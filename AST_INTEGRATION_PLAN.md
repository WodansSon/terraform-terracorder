# AST Integration Plan - PowerShell Refactoring

## Current State Analysis

### terracorder.ps1 Structure
- **Parameters**: ResourceName, RepositoryDirectory (Discovery Mode) | DatabaseDirectory (Database Mode)
- **Modules Imported** (12 modules):
  1. UI.psm1 - Base UI functions ✅ **KEEP**
  2. Database.psm1 - Database functions ⚠️ **NEEDS UPDATES** (new schema)
  3. PatternAnalysis.psm1 - Pattern analysis ❌ **REMOVE** (AST replaces)
  4. TestFunctionProcessing.psm1 - Function extraction ❌ **REMOVE** (AST replaces)
  5. TestFunctionStepsProcessing.psm1 - Step analysis ❌ **REMOVE** (AST replaces)
  6. RelationalQueries.psm1 - Relational queries ✅ **KEEP** (query layer)
  7. FileDiscovery.psm1 - File discovery ⚠️ **SIMPLIFY** (just file listing, no regex)
  8. ProcessingCore.psm1 - Core processing ❌ **REMOVE** (AST replaces)
  9. TemplateProcessing.psm1 - Template processing ❌ **REMOVE** (AST replaces)
  10. ReferencesProcessing.psm1 - Reference processing ❌ **REMOVE** (AST replaces)
  11. SequentialProcessing.psm1 - Sequential processing ❌ **REMOVE** (AST replaces)
  12. DatabaseMode.psm1 - Database query mode ✅ **KEEP**

### Modules to DELETE
- PatternAnalysis.psm1
- TestFunctionProcessing.psm1
- TestFunctionStepsProcessing.psm1
- ProcessingCore.psm1
- TemplateProcessing.psm1
- ReferencesProcessing.psm1
- SequentialProcessing.psm1

### Modules to KEEP
- UI.psm1
- Database.psm1 (with updates)
- RelationalQueries.psm1
- DatabaseMode.psm1

### Modules to CREATE
- ASTImport.psm1 - Import AST JSON output and populate database

### Modules to SIMPLIFY
- FileDiscovery.psm1 - Just Get-ChildItem for `*_test.go` files

---

## New Discovery Mode Workflow

### Current (Regex-Based)
```
1. FileDiscovery: Find all *_test.go files
2. PatternAnalysis: Extract patterns from files
3. TestFunctionProcessing: Process test functions
4. TestFunctionStepsProcessing: Analyze test steps
5. TemplateProcessing: Process templates
6. ReferencesProcessing: Build reference chains
7. SequentialProcessing: Handle sequential tests
8. Database Export: Write CSVs
```

### New (AST-Based)
```
1. FileDiscovery: Find all *_test.go files
2. AST Processing: Run ast-analyzer.exe on each file (parallel)
3. ASTImport: Import JSON output into database
4. Database Export: Write CSVs
```

**Result**: 8 phases → 4 steps, ~80% code reduction

---

## Implementation Steps

### Step 1: Create ASTImport.psm1
**Purpose**: Import AST JSON output and populate database tables

**Functions**:
```powershell
function Import-ASTOutput {
    param(
        [string]$ASTAnalyzerPath,
        [string[]]$TestFiles,
        [string]$RepoRoot
    )

    # Run AST analyzer on each file (parallel)
    # Parse JSON output
    # Call Add-* functions from Database.psm1
}

function Import-TestFunctionsFromAST {
    param([object]$ASTData)
    # Call Add-TestFunction for each test_function
}

function Import-TemplateFunctionsFromAST {
    param([object]$ASTData)
    # Call Add-TemplateFunction for each template_function
}

function Import-TestStepsFromAST {
    param([object]$ASTData)
    # Call Add-TestStep for each test_step
}

function Import-TemplateCallsFromAST {
    param([object]$ASTData)
    # Call Add-TemplateCall for each template_call
}

function Import-DirectReferencesFromAST {
    param([object]$ASTData)
    # Call Add-DirectResourceReference for each config_info
}
```

### Step 2: Update Database.psm1
**Changes Needed**:

1. **New Table Creation Functions**:
   ```powershell
   function Initialize-TemplateCallChainTable
   function Initialize-TemplateChainResourcesTable
   ```

2. **Update Existing Functions to Use FKs**:
   ```powershell
   function Add-TestFunction
   # Change: Add ServiceRefId FK (from FileRefId)
   # Remove: ServiceName string

   function Add-TemplateFunction
   # Change: Add ServiceRefId FK (from FileRefId)
   # Remove: ServiceName string, FunctionBody
   # Add: ReturnsString boolean

   function Add-TestStep
   # Change: Add TemplateFunctionRefId FK
   # Remove: ConfigTemplate string, TargetServiceName, TargetStructName
   # Add: TargetServiceRefId FK, TargetStructRefId FK

   function Add-DirectResourceReference
   # Change: Add TemplateFunctionRefId FK, ResourceRefId FK
   # Remove: FileRefId FK (redundant), ResourceName string, ServiceName string
   ```

3. **New Add-* Functions**:
   ```powershell
   function Add-TemplateCallChain
   function Add-TemplateChainResource
   ```

### Step 3: Simplify FileDiscovery.psm1
**Current**: Complex regex-based file processing
**New**: Simple file listing

```powershell
function Get-TestFiles {
    param(
        [string]$RepositoryDirectory,
        [string]$ServiceFilter = "*"
    )

    $pattern = "internal/services/$ServiceFilter/*_test.go"
    Get-ChildItem -Path $RepositoryDirectory -Filter "*_test.go" -Recurse |
        Where-Object { $_.FullName -match 'internal/services/.*_test\.go$' }
}
```

**Remove**: All regex pattern matching functions

### Step 4: Update terracorder.ps1
**Changes**:

1. **Remove Module Imports**:
   ```powershell
   # DELETE THESE:
   # Import-Module PatternAnalysis.psm1
   # Import-Module TestFunctionProcessing.psm1
   # Import-Module TestFunctionStepsProcessing.psm1
   # Import-Module ProcessingCore.psm1
   # Import-Module TemplateProcessing.psm1
   # Import-Module ReferencesProcessing.psm1
   # Import-Module SequentialProcessing.psm1
   ```

2. **Add New Module Import**:
   ```powershell
   Import-Module (Join-Path $ModulesPath "ASTImport.psm1") -Force
   ```

3. **Replace Discovery Mode Logic**:
   ```powershell
   # OLD: 8 phases of regex processing

   # NEW: Simple AST processing
   $testFiles = Get-TestFiles -RepositoryDirectory $RepositoryDirectory
   $astPath = Join-Path $PSScriptRoot "..\tools\ast-analyzer\ast-analyzer.exe"

   Import-ASTOutput -ASTAnalyzerPath $astPath `
                    -TestFiles $testFiles `
                    -RepoRoot $RepositoryDirectory

   Export-DatabaseToCSV -ExportDirectory $ExportDirectory
   ```

### Step 5: Update RelationalQueries.psm1
**Changes**: Update queries to use new schema (FKs instead of strings)

Example:
```powershell
# OLD: String-based query
$query = "SELECT * FROM TestSteps WHERE ConfigTemplate = 'basic'"

# NEW: FK-based query
$query = @"
SELECT ts.*, tf.FunctionName AS TemplateName
FROM TestSteps ts
JOIN TemplateFunctions tf ON ts.TemplateFunctionRefId = tf.TemplateFunctionRefId
WHERE tf.FunctionName = 'basic'
"@
```

---

## File Changes Summary

### Files to DELETE
- modules/PatternAnalysis.psm1
- modules/TestFunctionProcessing.psm1
- modules/TestFunctionStepsProcessing.psm1
- modules/ProcessingCore.psm1
- modules/TemplateProcessing.psm1
- modules/ReferencesProcessing.psm1
- modules/SequentialProcessing.psm1

### Files to CREATE
- modules/ASTImport.psm1

### Files to MODIFY
- scripts/terracorder.ps1 (remove regex processing, add AST processing)
- modules/Database.psm1 (new schema, FKs instead of strings)
- modules/FileDiscovery.psm1 (simplify to just file listing)
- modules/RelationalQueries.psm1 (update queries for new schema)

### Files to KEEP AS-IS
- modules/UI.psm1
- modules/DatabaseMode.psm1

---

## Testing Strategy

### Unit Tests
1. Test ASTImport.psm1 functions individually
2. Test Database.psm1 new functions
3. Test FileDiscovery.psm1 simplified functions

### Integration Tests
1. Run terracorder.ps1 on single file
2. Run terracorder.ps1 on azurerm_resource_group
3. Verify CSV output matches expected schema
4. Verify Database Mode queries work with new schema

### Volume Tests
1. Run on entire network service
2. Verify performance (should be 10x faster)
3. Verify data volume (should be 90% reduction)

---

## Rollback Plan

**Git Branch Strategy**:
1. Create branch: `feature/ast-integration`
2. Commit each phase separately
3. Tag milestones: `ast-phase-1`, `ast-phase-2`, etc.
4. Keep main branch stable until full integration tested

**Archive Strategy**:
- Keep old modules in `archive/regex-modules/` for reference
- Document migration in CHANGELOG.md
- Update README.md with new workflow

---

## Success Criteria

✅ **Functionality**: All Database Mode queries work with new schema
✅ **Performance**: Discovery Mode 10x faster than regex
✅ **Data Quality**: 100% accurate (semantic analysis vs pattern matching)
✅ **Code Reduction**: 80% less PowerShell code
✅ **Data Reduction**: 90% less storage (no function bodies)
✅ **Maintainability**: Simpler codebase, easier to understand
✅ **Documentation**: All docs updated (DATABASE_SCHEMA.md, CHANGELOG.md, README.md)

---

## Timeline

- **Phase 1**: AST same-file template tracking ✅ COMPLETE
- **Phase 2**: Create ASTImport.psm1 (4 hours)
- **Phase 3**: Update Database.psm1 (4 hours)
- **Phase 4**: Update terracorder.ps1 (2 hours)
- **Phase 5**: Update queries (2 hours)
- **Phase 6**: Testing (4 hours)
- **Phase 7**: Documentation (2 hours)

**Total**: ~18 hours of focused work

---

## Next Steps

1. ✅ Fix AST same-file template tracking
2. ✅ Rebuild AST analyzer
3. ✅ Test AST fixes
4. ⏭️ Create ASTImport.psm1 module
5. ⏭️ Update Database.psm1 for new schema
6. ⏭️ Update terracorder.ps1 to use AST
7. ⏭️ Remove regex modules
8. ⏭️ End-to-end testing
9. ⏭️ Documentation updates
