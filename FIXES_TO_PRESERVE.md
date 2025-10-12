# Fixes to Preserve When Resetting to Main

## Fix 1: Numbered Files Bug (CRITICAL)

**File**: `modules/FileDiscovery.psm1`
**Location**: Around line 113 in the parallel processing scriptblock

**Change**:
```powershell
# OLD (creates numbered files):
if ($content -cmatch $precisePattern) {
    $results.RelevantFiles += $fileInfo.FullName
}

# NEW (fixed):
# Explicitly capture -cmatch result to prevent boolean output to file descriptors
$matchResult = ($content -cmatch $precisePattern)
if ($matchResult) {
    $results.RelevantFiles += $fileInfo.FullName
}
```

**Verification**: Run script, confirm no numbered files created in local and target repository

---

## Fix 2: Struct Resolution from AST

**File**: `modules/Database.psm1`
**Location**: In the `Import-ASTData` function

### Part A: Add StructRefId parameter to Add-TestFunctionRecord
Search for: `function Add-TestFunctionRecord`
Add parameter: `[Nullable[int]]$StructRefId = $null,`

### Part B: Use StructRefId when creating TestFunction
In `Add-TestFunctionRecord`, update the TestFunction object creation to include:
```powershell
StructRefId = $StructRefId
```

### Part C: Add Phase 1 in Import-ASTData
After the function import loop and BEFORE "PHASE 2: Process Test Steps", add:

```powershell
# PHASE 1: Update existing TestFunctions with StructRefId from AST ReceiverType
# This enriches the regex-created function records with accurate AST-based struct resolution
foreach ($fileData in $ASTData) {
    foreach ($astFunc in $fileData.functions) {
        # Only process test functions that have ReceiverType from AST
        if ($astFunc.IsTestFunc -and $astFunc.ReceiverType -and $astFunc.ReceiverType -ne "") {
            # Find the existing TestFunction record created during regex processing
            $existingFunc = $script:TestFunctions.Values | Where-Object {
                $_.FunctionName -eq $astFunc.FunctionName
            }

            if ($existingFunc) {
                # Look up StructRefId from the ReceiverType
                $structRefId = $script:StructsByNameIndex[$astFunc.ReceiverType]

                if ($structRefId) {
                    # Update the in-memory TestFunction object
                    $existingFunc.StructRefId = $structRefId
                    $importStats.StructRefsUpdated++
                }
            }
        }
    }
}

Write-Verbose "Updated $($importStats.StructRefsUpdated) test functions with struct references from AST"
```

**Verification**: Run script, check that TestFunctions.csv has StructRefId populated for test functions

---

## Fix 3: Tools Directory (Already Safe)

**Directory**: `tools/ast-analyzer/`
**Status**: Untracked by git, will survive reset
**Contents**:
- main.go (with enrichTestFunctionsWithStructInfo)
- patterns.go
- GNUMakefile
- Makefile
- Build.ps1
- ast-analyzer.exe (binary)
- go.mod

**Action**: No action needed, directory is already safe

---

## Application Steps

1. **Save this file** outside the repository
2. **Reset to main**: `git reset --hard origin/main`
3. **Apply Fix 1**: Manually edit FileDiscovery.psm1
4. **Apply Fix 2**: Manually edit Database.psm1 (3 parts)
5. **Verify tools/**: Confirm directory still exists
6. **Test**: Run on azurerm_private_endpoint
7. **Commit**: "Fix numbered files bug and add struct resolution from AST"

---

## Testing Commands

```powershell
# Test numbered files fix
.\scripts\terracorder.ps1 -ResourceName "azurerm_private_endpoint" -RepositoryDirectory "C:\github.com\hashicorp\terraform-provider-azurerm"

# Verify no numbered files created in local repository
Get-ChildItem -Path . -File | Where-Object { $_.Name -match '^\d+$' } | Measure-Object

# Verify no numbered files created in target repository
Get-ChildItem -Path "C:\github.com\hashicorp\terraform-provider-azurerm" -File | Where-Object { $_.Name -match '^\d+$' } | Measure-Object

# Verify no AST CSV files created in target repository (old bug from previous AST version)
Get-ChildItem -Path "C:\github.com\hashicorp\terraform-provider-azurerm\output\ast" -File -Filter "*_ast.csv" -ErrorAction SilentlyContinue | Measure-Object
Get-ChildItem -Path "C:\github.com\hashicorp\terraform-provider-azurerm\json" -File -Filter "*_ast.csv" -ErrorAction SilentlyContinue | Measure-Object

# Verify struct resolution
Import-Csv .\output\TestFunctions.csv | Where-Object { $_.StructRefId -ne "" } | Measure-Object
```
