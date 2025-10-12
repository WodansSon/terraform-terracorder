# AST-Optimized TerraCorder Implementation Plan

## Implementation Phases

### Phase 1: Fix Current AST (Foundation) - THIS WEEK
**Goal**: Make AST track ALL template calls and resolve basic relationships

#### 1.1 Update AST to Track ALL Template Calls
- [x] AST currently skips same-file template calls
- [ ] Remove same-file filter in `extractTemplateCallsFromExpr`
- [ ] Mark same-file calls with `IsLocalCall = true`
- [ ] Populate `TargetService` for same-file calls
- [ ] Test: Verify network_manager basic→template call is captured

#### 1.2 Test Current AST with Full Tracking
- [ ] Run AST on 50 random files
- [ ] Verify TemplateCalls count increases (currently 65, expect ~200-300)
- [ ] Verify same-file calls have `IsLocalCall = true`
- [ ] Compare with regex TemplateCalls.csv

**Deliverable**: AST captures ALL template calls (same-file + cross-file)

---

### Phase 2: AST Enhanced Resolution (AST Does the Work) - NEXT WEEK
**Goal**: AST resolves complete call chains and determines reference types

#### 2.1 Add Call Chain Resolution to AST
- [ ] AST walks template call graph
- [ ] Resolves multi-hop chains: basic() → template() → commonInfra()
- [ ] Tracks chain depth
- [ ] Determines if chain crosses service boundaries

#### 2.2 Add Resource Reference Tracking
- [ ] AST scans template function bodies for resource references
- [ ] Extracts `resource "azurerm_xxx"` blocks
- [ ] Associates resources with template functions
- [ ] Walks chains to find ultimate resource references

#### 2.3 Determine Reference Types in AST
- [ ] AST determines SELF_CONTAINED vs EMBEDDED_SELF vs CROSS_FILE
- [ ] AST determines SAME_SERVICE vs CROSS_SERVICE
- [ ] AST outputs reference type IDs directly

**Deliverable**: AST outputs resolved call chains with ultimate resources

---

### Phase 3: New Database Schema (Optimized Storage) - WEEK 3
**Goal**: Create new simplified tables and migration scripts

#### 3.1 Define New Schema DDL
- [ ] TestFunctions (simplified - no function bodies)
- [ ] TemplateFunctions (simplified - no function bodies)
- [ ] TestSteps (new - replaces TestFunctionSteps)
- [ ] TemplateCallChain (new - replaces TemplateCalls + IndirectConfigReferences)
- [ ] DirectResourceReferences (enhanced with service tracking)
- [ ] Files, Services, Resources, ReferenceTypes (keep with minor updates)

#### 3.2 Create Migration Scripts
- [ ] Map old schema → new schema
- [ ] Data transformation logic
- [ ] Validation: ensure no data loss

#### 3.3 Update Database Module
- [ ] New Add-* functions for new tables
- [ ] Update Get-* functions
- [ ] Remove deprecated functions
- [ ] Update indexes for performance

**Deliverable**: New database schema with migration path

---

### Phase 4: PowerShell Simplification (Query Layer) - WEEK 4
**Goal**: Remove complex resolution logic, make PowerShell a simple query layer

#### 4.1 Remove Complex Resolution Logic
- [ ] Delete multi-pass template resolution
- [ ] Delete struct lookup logic
- [ ] Delete file comparison logic
- [ ] Delete service resolution logic

#### 4.2 Implement Simple Import Logic
- [ ] Import AST JSON directly into tables
- [ ] No transformation needed (AST already resolved)
- [ ] Simple validation only

#### 4.3 Update Query Functions
- [ ] Get-TestsForResource (simplified)
- [ ] Get-CrossServiceDependencies (new)
- [ ] Get-TemplateCallChain (new)
- [ ] Get-CoverageReport (new)

**Deliverable**: Simplified PowerShell with 80% less code

---

### Phase 5: Multi-Resource & PR Features (Future Features) - WEEK 5+
**Goal**: Implement advanced features enabled by new design

#### 5.1 Multi-Resource Support
- [ ] Parse comma-separated resource args
- [ ] Single AST scan, multiple queries
- [ ] Aggregate results
- [ ] Deduplicate test lists

#### 5.2 GitHub PR Integration
- [ ] Parse PR diffs (via GitHub API or git)
- [ ] Extract changed resource files
- [ ] Map files → resource names
- [ ] Query AST data for affected tests

#### 5.3 Impact Analysis
- [ ] Find all resources dependent on target resource
- [ ] Show cross-service impact
- [ ] Generate dependency graphs

**Deliverable**: Production-ready multi-resource and PR-driven test discovery

---

## Detailed Phase 1 Tasks (THIS WEEK)

### Task 1.1: Fix AST Template Call Tracking

**File**: `tools/ast-analyzer/main.go`

**Current Code** (lines 1173-1179):
```go
if _, existsInSameFile := methodToFunc[key]; existsInSameFile {
    // Same-file call - mark as embedded and don't track
    templateCall.IsLocalCall = true
    // DON'T append - we only track cross-file calls
    return  // ← REMOVE THIS LINE
}
```

**New Code**:
```go
if _, existsInSameFile := methodToFunc[key]; existsInSameFile {
    // Same-file call - mark as local and track it
    templateCall.IsLocalCall = true
    templateCall.TargetService = serviceName  // Same service as source
} else {
    // Cross-file call - look up target service
    templateCall.IsLocalCall = false
    // TargetService already set by lookup in functions array
}

// ALWAYS append - track ALL template calls
*templateCalls = append(*templateCalls, *templateCall)
```

**Test**:
```powershell
# Run on network_manager file
$result = & "C:\github.com\WodansSon\terraform-terracorder\tools\ast-analyzer\ast-analyzer.exe" `
    -file "C:\github.com\hashicorp\terraform-provider-azurerm\internal\services\network\network_manager_resource_test.go" `
    -reporoot "C:\github.com\hashicorp\terraform-provider-azurerm"

$json = $result | ConvertFrom-Json
Write-Host "Template Calls: $($json.TemplateCalls.Count)"

# Expect: basic() → template() call to appear
$basicToTemplate = $json.TemplateCalls | Where-Object {
    $_.SourceFunction -eq "basic" -and $_.TargetMethod -eq "template"
}
if ($basicToTemplate) {
    Write-Host "✓ Found basic→template call (same-file)"
    Write-Host "  IsLocalCall: $($basicToTemplate.IsLocalCall)"
    Write-Host "  SourceService: $($basicToTemplate.SourceService)"
    Write-Host "  TargetService: $($basicToTemplate.TargetService)"
} else {
    Write-Error "✗ Missing basic→template call!"
}
```

### Task 1.2: Rebuild and Test

```powershell
# Rebuild AST analyzer
cd C:\github.com\WodansSon\terraform-terracorder\tools\ast-analyzer
go build -o ast-analyzer.exe

# Test on 10 files
$repo = "C:\github.com\hashicorp\terraform-provider-azurerm"
$files = Get-ChildItem "$repo\internal\services" -Recurse -Filter "*_test.go" |
    Get-Random -Count 10

$totalTemplateCalls = 0
foreach ($file in $files) {
    $result = & ".\ast-analyzer.exe" -file $file.FullName -reporoot $repo
    $json = $result | ConvertFrom-Json
    $totalTemplateCalls += $json.TemplateCalls.Count
}

Write-Host "Average template calls per file: $($totalTemplateCalls / 10)"
# Expect: 3-5 per file (up from current ~1.3)
```

### Task 1.3: Volume Test

```powershell
# Run on 50 files and extrapolate
$sampleSize = 50
$files = Get-ChildItem "$repo\internal\services" -Recurse -Filter "*_test.go" |
    Get-Random -Count $sampleSize

$stats = @{
    Functions = 0
    Calls = 0
    TestSteps = 0
    TemplateCalls = 0
}

foreach ($file in $files) {
    $result = & ".\ast-analyzer.exe" -file $file.FullName -reporoot $repo
    $json = $result | ConvertFrom-Json
    $stats.Functions += $json.Functions.Count
    $stats.Calls += $json.Calls.Count
    $stats.TestSteps += $json.TestSteps.Count
    $stats.TemplateCalls += $json.TemplateCalls.Count
}

# Extrapolate to full provider
$totalFiles = 2672
$multiplier = $totalFiles / $sampleSize

Write-Host "Estimated total rows:"
Write-Host "  Functions: $($stats.Functions * $multiplier)"
Write-Host "  Calls: $($stats.Calls * $multiplier)"
Write-Host "  TestSteps: $($stats.TestSteps * $multiplier)"
Write-Host "  TemplateCalls: $($stats.TemplateCalls * $multiplier)"  # Expect: ~300-400 (up from 65)
Write-Host "  TOTAL: $(($stats.Functions + $stats.Calls + $stats.TestSteps + $stats.TemplateCalls) * $multiplier)"
```

---

## Success Criteria

### Phase 1 Complete When:
- [x] AST tracks ALL template calls (same-file + cross-file)
- [ ] TemplateCalls count increases from 65 → ~300-400
- [ ] Same-file calls marked with IsLocalCall=true
- [ ] Volume test shows ~60-70K total rows (not much increase from current)
- [ ] network_manager basic→template call verified

### Phase 2 Complete When:
- [ ] AST outputs complete call chains
- [ ] AST determines ultimate resource references
- [ ] AST outputs reference types (no PowerShell resolution needed)

### Phase 3 Complete When:
- [ ] New schema defined and documented
- [ ] Migration scripts created
- [ ] Database module updated

### Phase 4 Complete When:
- [ ] PowerShell complexity reduced by 80%
- [ ] Import logic simplified
- [ ] Query functions work with new schema

### Phase 5 Complete When:
- [ ] Multi-resource support implemented
- [ ] PR integration working
- [ ] Impact analysis features complete

---

## Timeline

| Phase | Duration | Target Completion |
|-------|----------|-------------------|
| Phase 1: Fix AST | 2-3 days | This week |
| Phase 2: AST Resolution | 5-7 days | Next week |
| Phase 3: New Schema | 3-5 days | Week 3 |
| Phase 4: PowerShell Simplify | 3-5 days | Week 4 |
| Phase 5: New Features | Ongoing | Week 5+ |

---

## Risk Mitigation

### Risk: Breaking existing functionality
**Mitigation**: Keep regex approach working in parallel during transition

### Risk: AST resolution is more complex than expected
**Mitigation**: Phase 1 keeps simple structure, Phase 2 adds complexity incrementally

### Risk: Data volume increases unexpectedly
**Mitigation**: Volume testing in Phase 1 before committing to design

### Risk: Migration loses data
**Mitigation**: Validation scripts, parallel run comparison

---

## Next Immediate Actions

1. **Update main.go** - Remove same-file filter (30 mins)
2. **Rebuild AST** - Test build (5 mins)
3. **Test network_manager** - Verify basic→template call (10 mins)
4. **Volume test** - Run on 50 files (15 mins)
5. **Analyze results** - Compare to expectations (30 mins)

**Total time to Phase 1**: ~2-3 hours of focused work

---

## Ready to Start?

Should I proceed with Task 1.1 (updating main.go to track all template calls)?
