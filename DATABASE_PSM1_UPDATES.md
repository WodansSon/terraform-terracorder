# Database.psm1 Updates for AST Integration

## Status: IN PROGRESS

## Summary
Update Database.psm1 to support the new AST-optimized schema while maintaining backward compatibility during transition.

---

## NEW Functions to ADD

### 1. Add-TemplateCallChainRecord
**Purpose**: Store template → template call chains (replaces TemplateCalls + IndirectConfigReferences)

```powershell
function Add-TemplateCallChainRecord {
    param(
        [int]$SourceTemplateFunctionRefId,
        [int]$TargetTemplateFunctionRefId,
        [int]$SourceServiceRefId,
        [int]$TargetServiceRefId,
        [int]$ChainDepth,
        [int]$CrossesServiceBoundary,  # 1 = true, 0 = false
        [int]$ReferenceTypeId,
        [bool]$IsLocalCall
    )

    $query = @"
INSERT INTO TemplateCallChain (
    SourceTemplateFunctionRefId,
    TargetTemplateFunctionRefId,
    SourceServiceRefId,
    TargetServiceRefId,
    ChainDepth,
    CrossesServiceBoundary,
    ReferenceTypeId,
    IsLocalCall
) VALUES (
    @sourceTemplateFunctionRefId,
    @targetTemplateFunctionRefId,
    @sourceServiceRefId,
    @targetServiceRefId,
    @chainDepth,
    @crossesServiceBoundary,
    @referenceTypeId,
    @isLocalCall
)
"@

    $params = @{
        sourceTemplateFunctionRefId = $SourceTemplateFunctionRefId
        targetTemplateFunctionRefId = $TargetTemplateFunctionRefId
        sourceServiceRefId = $SourceServiceRefId
        targetServiceRefId = $TargetServiceRefId
        chainDepth = $ChainDepth
        crossesServiceBoundary = $CrossesServiceBoundary
        referenceTypeId = $ReferenceTypeId
        isLocalCall = if ($IsLocalCall) { 1 } else { 0 }
    }

    Invoke-SqliteQuery -Query $query -SqlParameters $params | Out-Null
    return Invoke-SqliteQuery -Query "SELECT last_insert_rowid() as ChainRefId" | Select-Object -ExpandProperty ChainRefId
}
```

### 2. Add-TemplateChainResourceRecord
**Purpose**: Junction table for template chain → ultimate resource references

```powershell
function Add-TemplateChainResourceRecord {
    param(
        [int]$ChainRefId,
        [int]$ResourceRefId
    )

    $query = @"
INSERT INTO TemplateChainResources (
    ChainRefId,
    ResourceRefId
) VALUES (
    @chainRefId,
    @resourceRefId
)
"@

    $params = @{
        chainRefId = $ChainRefId
        resourceRefId = $ResourceRefId
    }

    Invoke-SqliteQuery -Query $query -SqlParameters $params | Out-Null
    return Invoke-SqliteQuery -Query "SELECT last_insert_rowid() as ChainResourceRefId" | Select-Object -ExpandProperty ChainResourceRefId
}
```

### 3. Initialize-TemplateCallChainTable
**Purpose**: Create TemplateCallChain table

```powershell
function Initialize-TemplateCallChainTable {
    $createTableQuery = @"
CREATE TABLE IF NOT EXISTS TemplateCallChain (
    ChainRefId INTEGER PRIMARY KEY AUTOINCREMENT,
    SourceTemplateFunctionRefId INTEGER NOT NULL,
    TargetTemplateFunctionRefId INTEGER NOT NULL,
    SourceServiceRefId INTEGER NOT NULL,
    TargetServiceRefId INTEGER NOT NULL,
    ChainDepth INTEGER NOT NULL,
    CrossesServiceBoundary INTEGER NOT NULL,
    ReferenceTypeId INTEGER NOT NULL,
    IsLocalCall INTEGER NOT NULL,
    FOREIGN KEY (SourceTemplateFunctionRefId) REFERENCES TemplateFunctions(TemplateFunctionRefId),
    FOREIGN KEY (TargetTemplateFunctionRefId) REFERENCES TemplateFunctions(TemplateFunctionRefId),
    FOREIGN KEY (SourceServiceRefId) REFERENCES Services(ServiceRefId),
    FOREIGN KEY (TargetServiceRefId) REFERENCES Services(ServiceRefId),
    FOREIGN KEY (ReferenceTypeId) REFERENCES ReferenceTypes(ReferenceTypeId)
);
"@

    Invoke-SqliteQuery -Query $createTableQuery | Out-Null
    Write-Verbose "TemplateCallChain table initialized"
}
```

### 4. Initialize-TemplateChainResourcesTable
**Purpose**: Create TemplateChainResources junction table

```powershell
function Initialize-TemplateChainResourcesTable {
    $createTableQuery = @"
CREATE TABLE IF NOT EXISTS TemplateChainResources (
    ChainResourceRefId INTEGER PRIMARY KEY AUTOINCREMENT,
    ChainRefId INTEGER NOT NULL,
    ResourceRefId INTEGER NOT NULL,
    FOREIGN KEY (ChainRefId) REFERENCES TemplateCallChain(ChainRefId),
    FOREIGN KEY (ResourceRefId) REFERENCES Resources(ResourceRefId)
);
"@

    Invoke-SqliteQuery -Query $createTableQuery | Out-Null
    Write-Verbose "TemplateChainResources table initialized"
}
```

---

## EXISTING Functions to UPDATE

### 1. Add-TemplateFunctionRecord
**Current**: Stores FunctionBody (huge!)
**New**: No FunctionBody, add ReturnsString field

```powershell
function Add-TemplateFunctionRecord {
    param(
        [int]$FileRefId,
        [int]$StructRefId,
        [string]$FunctionName,
        [string]$ReceiverType,  # "pointer" or "value"
        [int]$Line,
        [int]$ReturnsString  # 1 = true, 0 = false
    )

    $query = @"
INSERT INTO TemplateFunctions (
    FileRefId,
    StructRefId,
    FunctionName,
    ReceiverType,
    Line,
    ReturnsString
) VALUES (
    @fileRefId,
    @structRefId,
    @functionName,
    @receiverType,
    @line,
    @returnsString
)
"@

    # REMOVED: FunctionBody parameter and field
    # ADDED: ReturnsString parameter and field

    $params = @{
        fileRefId = $FileRefId
        structRefId = $StructRefId
        functionName = $FunctionName
        receiverType = $ReceiverType
        line = $Line
        returnsString = $ReturnsString
    }

    Invoke-SqliteQuery -Query $query -SqlParameters $params | Out-Null
    return Invoke-SqliteQuery -Query "SELECT last_insert_rowid() as TemplateFunctionRefId" | Select-Object -ExpandProperty TemplateFunctionRefId
}
```

### 2. Add-TestStepRecord (rename from Add-TestFunctionStepRecord)
**Current**: Uses ConfigTemplate string, TargetServiceName string
**New**: Uses TemplateFunctionRefId FK, TargetServiceRefId FK

```powershell
function Add-TestStepRecord {
    param(
        [int]$TestFunctionRefId,
        [int]$TemplateFunctionRefId,  # NEW: Direct FK to template
        [int]$StepIndex,
        [int]$TargetStructRefId,
        [int]$TargetServiceRefId,  # NEW: FK to Services
        [int]$ReferenceTypeId,
        [int]$Line
    )

    $query = @"
INSERT INTO TestSteps (
    TestFunctionRefId,
    TemplateFunctionRefId,
    StepIndex,
    TargetStructRefId,
    TargetServiceRefId,
    ReferenceTypeId,
    Line
) VALUES (
    @testFunctionRefId,
    @templateFunctionRefId,
    @stepIndex,
    @targetStructRefId,
    @targetServiceRefId,
    @referenceTypeId,
    @line
)
"@

    # REMOVED: ConfigTemplate, TargetServiceName, StepBody
    # ADDED: TemplateFunctionRefId, TargetServiceRefId

    $params = @{
        testFunctionRefId = $TestFunctionRefId
        templateFunctionRefId = $TemplateFunctionRefId
        stepIndex = $StepIndex
        targetStructRefId = $TargetStructRefId
        targetServiceRefId = $TargetServiceRefId
        referenceTypeId = $ReferenceTypeId
        line = $Line
    }

    Invoke-SqliteQuery -Query $query -SqlParameters $params | Out-Null
    return Invoke-SqliteQuery -Query "SELECT last_insert_rowid() as TestStepRefId" | Select-Object -ExpandProperty TestStepRefId
}

# Add alias for backward compatibility
Set-Alias -Name Add-TestFunctionStepRecord -Value Add-TestStepRecord
```

### 3. Add-DirectResourceReference (alias for Add-DirectResourceReferenceRecord)
**Current**: Uses FileRefId, ResourceName string, ServiceName string
**New**: Uses TemplateFunctionRefId FK, ResourceRefId FK

```powershell
function Add-DirectResourceReference {
    param(
        [int]$TemplateFunctionRefId,  # NEW: FK to template containing reference
        [int]$ResourceRefId,  # NEW: FK to Resources table
        [int]$ReferenceTypeId,
        [string]$Context,
        [int]$Line
    )

    $query = @"
INSERT INTO DirectResourceReferences (
    TemplateFunctionRefId,
    ResourceRefId,
    ReferenceTypeId,
    Context,
    Line
) VALUES (
    @templateFunctionRefId,
    @resourceRefId,
    @referenceTypeId,
    @context,
    @line
)
"@

    # REMOVED: FileRefId (get via TemplateFunctionRefId), ResourceName, ServiceName
    # ADDED: TemplateFunctionRefId, ResourceRefId FKs

    $params = @{
        templateFunctionRefId = $TemplateFunctionRefId
        resourceRefId = $ResourceRefId
        referenceTypeId = $ReferenceTypeId
        context = $Context
        line = $Line
    }

    Invoke-SqliteQuery -Query $query -SqlParameters $params | Out-Null
    return Invoke-SqliteQuery -Query "SELECT last_insert_rowid() as DirectRefId" | Select-Object -ExpandProperty DirectRefId
}

# Keep old function name as alias
Set-Alias -Name Add-DirectResourceReferenceRecord -Value Add-DirectResourceReference
```

### 4. Initialize-TerraDatabase
**Update**: Add calls to new table initialization functions

```powershell
function Initialize-TerraDatabase {
    # ... existing code ...

    # Initialize new tables
    Initialize-TemplateCallChainTable
    Initialize-TemplateChainResourcesTable

    # ... existing code ...
}
```

---

## Functions to KEEP AS-IS

- ✅ `Add-ServiceRecord` - No changes needed
- ✅ `Add-FileRecord` - No changes needed (already has ServiceRefId FK)
- ✅ `Add-StructRecord` - No changes needed
- ✅ `Add-TestFunctionRecord` - No changes needed
- ✅ `Get-ReferenceTypeId` - No changes needed
- ✅ `Get-ReferenceTypeName` - No changes needed
- ✅ `Export-DatabaseToCSV` - Will need to add new tables to export
- ✅ `Import-DatabaseFromCSV` - Will need to add new tables to import

---

## Functions to DEPRECATE (Phase 2)

These functions support old regex-based schema, can be removed after full migration:

- ❌ `Add-IndirectConfigReferenceRecord` - Replaced by TemplateCallChain
- ❌ `Add-TemplateCallRecord` - Replaced by TemplateCallChain
- ❌ `Add-TemplateReferenceRecord` - Merged into TestSteps
- ❌ `Add-SequentialReferenceRecord` - Sequential not in Phase 1 scope

---

## Table Schema Changes

### TemplateFunctions Table
```sql
-- OLD:
CREATE TABLE TemplateFunctions (
    TemplateFunctionRefId INTEGER PRIMARY KEY,
    FileRefId INTEGER,
    StructRefId INTEGER,
    FunctionName TEXT,
    FunctionBody TEXT,  -- REMOVE THIS (304K rows!)
    ReceiverVariable TEXT,
    ReceiverType TEXT,
    Line INTEGER
);

-- NEW:
CREATE TABLE TemplateFunctions (
    TemplateFunctionRefId INTEGER PRIMARY KEY AUTOINCREMENT,
    FileRefId INTEGER NOT NULL,
    StructRefId INTEGER NOT NULL,
    FunctionName TEXT NOT NULL,
    ReceiverType TEXT NOT NULL,  -- "pointer" or "value"
    Line INTEGER NOT NULL,
    ReturnsString INTEGER NOT NULL,  -- 1 = true, 0 = false
    FOREIGN KEY (FileRefId) REFERENCES Files(FileRefId),
    FOREIGN KEY (StructRefId) REFERENCES Structs(StructRefId)
);
```

### TestSteps Table (renamed from TestFunctionSteps)
```sql
-- OLD:
CREATE TABLE TestFunctionSteps (
    TestFunctionStepRefId INTEGER PRIMARY KEY,
    TestFunctionRefId INTEGER,
    StepIndex INTEGER,
    ConfigTemplate TEXT,
    StepBody TEXT,
    Line INTEGER,
    TargetStructRefId INTEGER,
    TargetServiceName TEXT,
    ReferenceTypeId INTEGER,
    StructVisibilityTypeId INTEGER
);

-- NEW:
CREATE TABLE TestSteps (
    TestStepRefId INTEGER PRIMARY KEY AUTOINCREMENT,
    TestFunctionRefId INTEGER NOT NULL,
    TemplateFunctionRefId INTEGER NOT NULL,  -- Direct FK to template
    StepIndex INTEGER NOT NULL,
    TargetStructRefId INTEGER NOT NULL,
    TargetServiceRefId INTEGER NOT NULL,  -- FK to Services
    ReferenceTypeId INTEGER NOT NULL,
    Line INTEGER NOT NULL,
    FOREIGN KEY (TestFunctionRefId) REFERENCES TestFunctions(TestFunctionRefId),
    FOREIGN KEY (TemplateFunctionRefId) REFERENCES TemplateFunctions(TemplateFunctionRefId),
    FOREIGN KEY (TargetStructRefId) REFERENCES Structs(StructRefId),
    FOREIGN KEY (TargetServiceRefId) REFERENCES Services(ServiceRefId),
    FOREIGN KEY (ReferenceTypeId) REFERENCES ReferenceTypes(ReferenceTypeId)
);
```

### DirectResourceReferences Table
```sql
-- OLD:
CREATE TABLE DirectResourceReferences (
    DirectRefId INTEGER PRIMARY KEY,
    FileRefId INTEGER,
    ResourceName TEXT,
    ReferenceTypeId INTEGER,
    Context TEXT,
    Line INTEGER,
    ServiceName TEXT
);

-- NEW:
CREATE TABLE DirectResourceReferences (
    DirectRefId INTEGER PRIMARY KEY AUTOINCREMENT,
    TemplateFunctionRefId INTEGER NOT NULL,  -- Which template contains reference
    ResourceRefId INTEGER NOT NULL,  -- FK to Resources
    ReferenceTypeId INTEGER NOT NULL,
    Context TEXT NOT NULL,
    Line INTEGER NOT NULL,
    FOREIGN KEY (TemplateFunctionRefId) REFERENCES TemplateFunctions(TemplateFunctionRefId),
    FOREIGN KEY (ResourceRefId) REFERENCES Resources(ResourceRefId),
    FOREIGN KEY (ReferenceTypeId) REFERENCES ReferenceTypes(ReferenceTypeId)
);
```

---

## Next Steps

1. ✅ Create new functions: Add-TemplateCallChainRecord, Add-TemplateChainResourceRecord
2. ✅ Create table initialization functions
3. ✅ Update existing Add-* functions for new schema
4. ✅ Update Initialize-TerraDatabase to call new table init functions
5. ✅ Test with ASTImport.psm1
6. ⏭️ Update Export/Import CSV functions for new tables
7. ⏭️ Update query functions in RelationalQueries.psm1 and DatabaseMode.psm1

---

## Implementation Status

- [ ] Add-TemplateCallChainRecord - NOT STARTED
- [ ] Add-TemplateChainResourceRecord - NOT STARTED
- [ ] Initialize-TemplateCallChainTable - NOT STARTED
- [ ] Initialize-TemplateChainResourcesTable - NOT STARTED
- [ ] Update Add-TemplateFunctionRecord - NOT STARTED
- [ ] Create Add-TestStepRecord (rename) - NOT STARTED
- [ ] Create Add-DirectResourceReference (alias) - NOT STARTED
- [ ] Update Initialize-TerraDatabase - NOT STARTED
