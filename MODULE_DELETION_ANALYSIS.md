# PowerShell Module Deletion Analysis - AST Integration

## Current State: 126 Functions Across 13 Modules

### Module Deletion Summary

| Module | Functions | Status | Reason |
|--------|-----------|--------|--------|
| **PatternAnalysis.psm1** | 5 | ❌ **DELETE** | AST does pattern analysis |
| **TestFunctionProcessing.psm1** | 2 | ❌ **DELETE** | AST extracts test functions |
| **TestFunctionStepsProcessing.psm1** | 21 | ❌ **DELETE** | AST extracts test steps |
| **ProcessingCore.psm1** | 3 | ❌ **DELETE** | AST does all processing |
| **TemplateProcessing.psm1** | 2 | ❌ **DELETE** | AST extracts templates |
| **TemplateProcessingStrategies.psm1** | 0 | ❌ **DELETE** | Empty module |
| **ReferencesProcessing.psm1** | 2 | ❌ **DELETE** | AST resolves references |
| **SequentialProcessing.psm1** | 3 | ❌ **DELETE** | AST handles sequential |
| **FileDiscovery.psm1** | 2 | ⚠️ **SIMPLIFY** | Reduce to 1 function (just list files) |
| **RelationalQueries.psm1** | 3 | ⚠️ **UPDATE** | Update queries for new schema |
| **Database.psm1** | 55 | ⚠️ **UPDATE** | Update for new schema (reduce ~30 functions) |
| **DatabaseMode.psm1** | 7 | ⚠️ **UPDATE** | Update queries for new schema |
| **UI.psm1** | 21 | ✅ **KEEP** | Display functions still needed |

### Total Function Reduction
- **Current**: 126 functions
- **After AST**: ~40 functions
- **Reduction**: ~86 functions (68% code reduction!)

---

## Detailed Module Analysis

### ❌ DELETE: PatternAnalysis.psm1 (5 functions)
**Why**: AST does all pattern analysis via semantic parsing

**Functions to Delete**:
1. `Get-TestFunctionPattern` - AST extracts test functions
2. `Get-TemplateFunctionPattern` - AST extracts template functions
3. `Get-StructPattern` - AST extracts struct info
4. `Get-ConfigCallPattern` - AST extracts Config() calls
5. `Get-SequentialPattern` - AST extracts sequential patterns

**AST Replacement**: AST outputs `test_functions`, `template_functions`, `test_steps` in JSON

---

### ❌ DELETE: TestFunctionProcessing.psm1 (2 functions)
**Why**: AST extracts all test function metadata

**Functions to Delete**:
1. `Extract-TestFunctions` - AST outputs `test_functions` array
2. `Process-TestFunctionBody` - AST parses function bodies

**AST Replacement**:
```json
{
  "test_functions": [
    {
      "name": "TestAccNetworkManager_basic",
      "struct_name": "ManagerResource",
      "line": 45
    }
  ]
}
```

---

### ❌ DELETE: TestFunctionStepsProcessing.psm1 (21 functions!)
**Why**: AST extracts test steps and resolves references

**Functions to Delete**:
1. `Extract-TestSteps` - AST outputs `test_steps`
2. `Get-ConfigTemplate` - AST resolves template calls
3. `Resolve-StructReference` - AST resolves structs
4. `Determine-ReferenceType` - AST determines reference types
5. `Find-TemplateFunction` - AST knows which template
6. `Get-StructVisibility` - AST knows Go visibility
7. ... (15 more functions)

**AST Replacement**:
```json
{
  "test_steps": [
    {
      "test_function": "TestAccNetworkManager_basic",
      "step_index": 1,
      "calls_template": "basic",
      "target_struct": "ManagerResource",
      "target_service": "network",
      "reference_type": "SELF_CONTAINED"
    }
  ]
}
```

---

### ❌ DELETE: ProcessingCore.psm1 (3 functions)
**Why**: AST does all processing upfront

**Functions to Delete**:
1. `Process-TestFiles` - Replaced by AST batch processing
2. `Process-FileContent` - AST parses files
3. `Extract-Metadata` - AST extracts all metadata

**AST Replacement**: Single call to `ast-analyzer.exe` on each file

---

### ❌ DELETE: TemplateProcessing.psm1 (2 functions)
**Why**: AST extracts template functions

**Functions to Delete**:
1. `Extract-TemplateFunctions` - AST outputs `template_functions`
2. `Parse-TemplateBody` - AST parses template bodies

**AST Replacement**:
```json
{
  "template_functions": [
    {
      "name": "basic",
      "struct_name": "ManagerResource",
      "returns_string": true,
      "line": 123
    }
  ]
}
```

---

### ❌ DELETE: TemplateProcessingStrategies.psm1 (0 functions)
**Why**: Empty module, no functions

---

### ❌ DELETE: ReferencesProcessing.psm1 (2 functions)
**Why**: AST resolves all references upfront

**Functions to Delete**:
1. `Resolve-TemplateReferences` - AST outputs `template_calls`
2. `Build-ReferenceChain` - AST walks call graph

**AST Replacement**:
```json
{
  "template_calls": [
    {
      "source_function": "basic",
      "target_method": "template",
      "target_struct": "ManagerResource",
      "is_local_call": true
    }
  ]
}
```

---

### ❌ DELETE: SequentialProcessing.psm1 (3 functions)
**Why**: Sequential tests not in AST scope (Phase 2+)

**Functions to Delete**:
1. `Extract-SequentialTests` - Not in current scope
2. `Process-SequentialChain` - Not in current scope
3. `Resolve-SequentialReferences` - Not in current scope

**Note**: Sequential tests are a separate feature (Phase 2), not needed for basic resource discovery

---

### ⚠️ SIMPLIFY: FileDiscovery.psm1 (2 → 1 function)
**Current Functions**:
1. `Get-TestFilesContainingResource` (261 lines!) - Complex regex filtering
2. `Get-AdditionalSequentialFiles` - Sequential-specific

**New Function**:
```powershell
function Get-TestFiles {
    param(
        [string]$RepositoryDirectory,
        [string]$ServiceFilter = "*"
    )

    # Simple file listing - AST does the filtering
    Get-ChildItem -Path $RepositoryDirectory -Recurse -Filter "*_test.go" |
        Where-Object { $_.FullName -match 'internal/services/[^/]+/.*_test\.go$' }
}

Export-ModuleMember -Function Get-TestFiles
```

**Reduction**: 369 lines → ~15 lines (96% reduction!)

---

### ⚠️ UPDATE: RelationalQueries.psm1 (3 functions - update queries)
**Current Functions**:
1. `Get-TestFilesByResource` - Update for new schema
2. `Get-TemplateCallChain` - Update for TemplateCallChain table
3. `Get-ResourceReferences` - Update for new FKs

**Changes Needed**: Update SQL queries to use FKs instead of strings

Example:
```powershell
# OLD:
$query = "SELECT * FROM TestSteps WHERE ConfigTemplate = 'basic'"

# NEW:
$query = @"
SELECT ts.*, tf.FunctionName AS TemplateName
FROM TestSteps ts
JOIN TemplateFunctions tf ON ts.TemplateFunctionRefId = tf.TemplateFunctionRefId
WHERE tf.FunctionName = 'basic'
"@
```

---

### ⚠️ UPDATE: Database.psm1 (55 → ~25 functions)
**Functions to KEEP** (update for new schema):
1. `Initialize-TerraDatabase` - Update table definitions
2. `Get-ReferenceTypeId` - Keep
3. `Add-ServiceRecord` - Keep
4. `Add-FileRecord` - Keep (update ServiceRefId FK)
5. `Add-StructRecord` - Keep
6. `Add-TestFunctionRecord` - Update (add ServiceRefId FK, remove FunctionBody)
7. `Add-TemplateFunctionRecord` - Update (add ServiceRefId FK, ReturnsString, remove FunctionBody)
8. `Add-TestStepRecord` - Update (add TemplateFunctionRefId FK, remove ConfigTemplate string)
9. `Add-DirectResourceReference` - Update (add TemplateFunctionRefId, ResourceRefId FKs)
10. `Export-DatabaseToCSV` - Update for new tables
11. `Import-DatabaseFromCSV` - Update for new tables

**Functions to ADD**:
1. `Add-TemplateCallChainRecord` - New table
2. `Add-TemplateChainResourceRecord` - New table

**Functions to DELETE** (~30 functions):
- All `Get-*ByPattern` functions (AST does pattern matching)
- All `Resolve-*` functions (AST does resolution)
- All `Parse-*` functions (AST does parsing)
- All `Extract-*` functions (AST does extraction)

---

### ⚠️ UPDATE: DatabaseMode.psm1 (7 functions - update queries)
**Functions to UPDATE**:
1. `Show-DatabaseStatistics` - Update for new table names/counts
2. `Show-DirectReferences` - Update query for new schema
3. `Show-TemplateFunctionDependencies` - Update for TemplateCallChain
4. `Show-SequentialCallChain` - Remove (sequential not in Phase 1)
5. `Show-IndirectReferences` - Update for TemplateCallChain
6. `Show-SequentialReferences` - Remove (sequential not in Phase 1)
7. `Show-CrossFileReferences` - Update for new schema

**Reduction**: 7 → 5 functions (remove sequential)

---

### ✅ KEEP: UI.psm1 (21 functions - no changes)
**Why**: Display functions still needed for output formatting

**Functions** (examples):
- `Write-Phase`
- `Write-InfoMessage`
- `Write-SuccessMessage`
- `Write-ErrorMessage`
- `Format-Table`
- Color/theme functions

---

## NEW Module to CREATE

### ASTImport.psm1 (~5 functions)
**Purpose**: Import AST JSON output and populate database

**Functions**:
1. `Import-ASTOutput` - Main entry point
2. `Import-TestFunctionsFromAST` - Import test_functions array
3. `Import-TemplateFunctionsFromAST` - Import template_functions array
4. `Import-TestStepsFromAST` - Import test_steps array
5. `Import-TemplateCallsFromAST` - Import template_calls array
6. `Import-DirectReferencesFromAST` - Import config_info array

**Total**: ~200 lines (vs 2000+ lines of regex code!)

---

## Summary

### Code Reduction
| Category | Before | After | Reduction |
|----------|--------|-------|-----------|
| **Modules** | 13 | 5 | 62% |
| **Functions** | 126 | ~40 | 68% |
| **Lines of Code** | ~8,000 | ~2,000 | 75% |

### Modules After AST Integration
1. ✅ **UI.psm1** (21 functions) - Display/formatting
2. ✅ **Database.psm1** (~25 functions) - Database operations
3. ✅ **DatabaseMode.psm1** (5 functions) - Query mode
4. ✅ **RelationalQueries.psm1** (3 functions) - Query helpers
5. ✅ **FileDiscovery.psm1** (1 function) - File listing
6. ✅ **ASTImport.psm1** (6 functions) - AST import **NEW**

### Deleted Modules (8 modules, 38 functions)
1. ❌ PatternAnalysis.psm1
2. ❌ TestFunctionProcessing.psm1
3. ❌ TestFunctionStepsProcessing.psm1
4. ❌ ProcessingCore.psm1
5. ❌ TemplateProcessing.psm1
6. ❌ TemplateProcessingStrategies.psm1
7. ❌ ReferencesProcessing.psm1
8. ❌ SequentialProcessing.psm1

---

## Implementation Order

1. ✅ **Create ASTImport.psm1** (foundation for everything)
2. ✅ **Update Database.psm1** (new schema support)
3. ✅ **Simplify FileDiscovery.psm1** (just file listing)
4. ✅ **Update terracorder.ps1** (remove old imports, add AST processing)
5. ✅ **Update RelationalQueries.psm1** (new schema queries)
6. ✅ **Update DatabaseMode.psm1** (new schema queries)
7. ✅ **Delete 8 regex modules** (PatternAnalysis, TestFunctionProcessing, etc.)
8. ✅ **Test end-to-end** (verify everything works)

**Result**: Simple, clean, maintainable codebase with 75% less code! 🎯
