# Indirect Call Chain Analysis: Regex vs AST

## The Problem: AST is Missing Same-File Template Calls

### Example from network_manager_resource_test.go

```go
func (r ManagerResource) basic(data acceptance.TestData) string {
    return fmt.Sprintf(`
%s
resource "azurerm_network_manager" "test" {
  name                = "acctest-networkmanager-%d"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  scope {
    subscription_ids = [data.azurerm_subscription.current.id]
  }
}
`, r.template(data), data.RandomInteger)  // ← r.template(data) is a template-to-template call!
}

func (r ManagerResource) template(data acceptance.TestData) string {
    return fmt.Sprintf(`
provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "test" {
  name     = "acctestRG-network-%d"
  location = "%s"
}

data "azurerm_subscription" "current" {}
`, data.RandomInteger, data.Locations.Primary)
}
```

### Call Chain
1. Test function calls: `r.basic(data)`
2. `basic()` calls: `r.template(data)`
3. `template()` returns HCL with `azurerm_resource_group`

**This is exactly the type of indirect reference chain that TerraCorder needs to discover!**

## Current AST Behavior (WRONG)

From `main.go` lines 1173-1179:

```go
// CROSS-FILE FILTER: Check if the target method exists in the same file
// If it's a same-file call, mark as embedded and SKIP tracking
if templateCall.TargetStruct != "" && templateCall.TargetMethod != "" {
    key := templateCall.TargetStruct + "." + templateCall.TargetMethod
    if _, existsInSameFile := methodToFunc[key]; existsInSameFile {
        // Same-file call - mark as embedded and don't track
        // These are internal template compositions, not cross-service dependencies
        templateCall.IsLocalCall = true
        // DON'T append - we only track cross-file calls
        return  // ← THIS IS WRONG!
```

**Current Logic**: Skip same-file template calls
**Result**: Missing `basic()` → `template()` relationship
**Impact**: Can't build complete indirect reference chain

## What Regex Approach Does (CORRECT)

The regex approach in `TemplateProcessing.psm1` (lines 400-460) does:

```powershell
# Extract struct references (e.g., "SomeStruct{")
$structMatches = [regex]::Matches($funcBody, '\b([A-Z][a-zA-Z0-9_]*)\s*\{')
foreach ($structMatch in $structMatches) {
    $structName = $structMatch.Groups[1].Value
    $referencedStructRefId = Get-StructRefIdByName -StructName $structName
    if ($referencedStructRefId) {
        Add-TemplateReferenceRecord -TemplateFunctionRefId $templateFunctionRefId -StructRefId $referencedStructRefId | Out-Null
    }
}
```

It also tracks function calls within template bodies:

```powershell
if (-not [string]::IsNullOrEmpty($receiverVariable)) {
    $funcCallMatches = [regex]::Matches($funcBody, "\b$([regex]::Escape($receiverVariable))\.(\w+)\(")
    foreach ($funcCallMatch in $funcCallMatches) {
        $calledFuncName = $funcCallMatch.Groups[1].Value
        Add-TemplateCallRecord -CallerTemplateFunctionRefId $templateFunctionRefId -CalledName $calledFuncName -CallType "function"
    }
}
```

**Regex Logic**: Track ALL template calls (same-file AND cross-file)
**Result**: Captures `basic()` → `template()` → `azurerm_resource_group`
**Impact**: Complete indirect reference chain

## Why Same-File Calls Matter

### Use Case: Finding All Tests for azurerm_resource_group

Without same-file template call tracking:
```
Test: TestAccNetworkManager_basic
  → Step: r.basic(data)
  → ??? (missing link)

Template: basic()
  → ??? (missing link)

Template: template()
  → Contains: azurerm_resource_group
```

**Problem**: Can't connect the test to azurerm_resource_group!

With same-file template call tracking:
```
Test: TestAccNetworkManager_basic
  → Step: r.basic(data)
  → Template: basic() [TemplateReferences table]

Template: basic()
  → Calls: r.template(data) [TemplateCalls/IndirectConfigReferences]

Template: template()
  → Contains: azurerm_resource_group [DirectResourceReferences]
```

**Solution**: Complete chain from test → basic → template → resource

## What Regex Actually Does

The regex approach has a **TemplateCalls** table that stores ALL template-to-template calls:

```powershell
$script:TemplateCalls[$templateCallRefId] = [PSCustomObject]@{
    TemplateCallRefId = $templateCallRefId
    CallerTemplateFunctionRefId = $CallerTemplateFunctionRefId  # basic()
    CalledName = $CalledName                                     # "template"
    CallType = $CallType                                         # "function"
    LineNumber = $LineNumber
}
```

This tracks:
- `basic()` calls `template()` (same-file)
- `basic()` calls `commonConfig()` (same-file)
- `basic()` calls `NetworkResource.helper()` (cross-struct, maybe cross-file)

**Regex tracks ALL calls, not just cross-file!**

## What AST Should Do

### Track ALL Template Calls (Match Regex Behavior)

Remove the same-file filter and track everything:

```go
// BEFORE (wrong):
if _, existsInSameFile := methodToFunc[key]; existsInSameFile {
    templateCall.IsLocalCall = true
    return  // ← WRONG: Skip same-file calls
}

// AFTER (correct):
if _, existsInSameFile := methodToFunc[key]; existsInSameFile {
    templateCall.IsLocalCall = true      // Mark as same-file
    templateCall.TargetService = serviceName  // Same service
} else {
    templateCall.IsLocalCall = false     // Cross-file call
    // TargetService will be looked up in functions array
}
// ALWAYS append - track ALL template calls (same-file AND cross-file)
*templateCalls = append(*templateCalls, *templateCall)
```

**Why track same-file calls:**
1. **Complete dependency chain**: `test → basic() → template() → resource`
2. **PowerShell needs it**: Uses TemplateCalls to resolve indirect references
3. **Service impact analysis**: Even same-file calls matter for dependency depth
4. **Matches regex**: Enables 1:1 replacement of regex with AST

**Let PowerShell decide** what to do with the calls based on:
- Service boundaries (SourceService vs TargetService)
- Ultimate resource references (does chain lead to a resource?)
- Cross-service impact (does chain cross service boundaries?)

## Impact on Data Volume

Current AST (cross-file only): 65 template calls (from 50 file sample)
Expected AST (all calls): ~200-300 template calls (estimate)

This is still FAR less than regex because:
1. AST filters out infrastructure functions
2. AST filters out Check block calls
3. AST doesn't store full function bodies

The extra template calls are **essential data**, not noise.

## Implementation Plan

1. **Update extractTemplateCallsFromExpr** in main.go:
   - Remove the `return` statement on line 1179
   - Keep `IsLocalCall = true` for same-file tracking
   - Set `TargetService` for same-file calls
   - ALWAYS append to templateCalls

2. **Update TemplateCalls data structure**:
   - Ensure `IsLocalCall` bool field exists
   - Ensure `TargetService` is populated for all calls

3. **Test the fix**:
   - Run on network_manager_resource_test.go
   - Verify `basic() → template()` call is captured
   - Verify TemplateCalls count increases

4. **Verify complete chain resolution**:
   - Import AST data into PowerShell
   - Query: "Find all tests for azurerm_resource_group"
   - Verify: Network manager test appears in results

## Questions to Answer

1. **Does regex track same-file template calls?**
   - Need to examine TemplateReferences.csv
   - Count same-file vs cross-file references

2. **How does PowerShell use this data?**
   - Check RelationalQueries.psm1
   - Understand IndirectConfigReferences resolution

3. **Can we replace ALL regex with AST?**
   - Must capture same data as regex
   - Must enable same queries
   - Must be faster/more reliable

## Next Steps

Before proceeding with AST integration, we MUST:

1. ✅ Understand regex template call tracking (done - it tracks ALL calls)
2. ⏸️ Fix AST to track ALL template calls (same-file + cross-file)
3. ⏸️ Verify AST captures same relationships as regex
4. ⏸️ Test end-to-end: query for resource, get correct test list
5. ⏸️ Then integrate into TerraCorder

**DO NOT integrate until we verify AST can replace ALL regex functionality.**
