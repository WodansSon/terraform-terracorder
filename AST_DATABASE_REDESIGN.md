# AST-Optimized Database Schema Redesign

## Goal
Keep TerraCorder's rich functionality while making it smarter and faster by leveraging AST's semantic understanding instead of regex pattern matching.

## Core Principle
**AST does the heavy lifting (resolution), PowerShell does the querying (presentation)**

---

## Tables to KEEP (Core Reference Data)

### 1. Resources
**Purpose**: Target resources we're searching for
**Schema**: No changes needed
```
ResourceRefId (PK)
ResourceName (e.g., "azurerm_kubernetes_cluster")
```
**Why Keep**: Core entity - what we're searching for

### 2. Services
**Purpose**: Azure service categories
**Schema**: No changes needed
```
ServiceRefId (PK)
ServiceName (e.g., "network", "compute", "storage")
```
**Why Keep**: Critical for service boundary tracking and cross-service analysis

### 3. Files
**Purpose**: Test file tracking
**Schema**: No changes needed
```
FileRefId (PK)
FileName
FilePath
ServiceRefId (FK) - derived from file path
```
**Why Keep**: Need to track which files contain which tests

### 4. ReferenceTypes
**Purpose**: Classify relationship types
**Schema**: REFACTOR (see below)
```
ReferenceTypeId (PK)
ReferenceTypeName
Category (new)
Description
```
**Why Keep**: Essential for both database modes (direct/indirect)
**Changes Needed**: Consolidate duplicates, add category field

---

## Tables to REFACTOR (AST-Optimized)

### 5. TestFunctions (SIMPLIFIED)
**Current**: Stores full function body (304KB of source code!)
**New**: Just metadata - AST extracts this cleanly

```
TestFunctionRefId (PK)
FileRefId (FK)
StructRefId (FK) - normalized struct reference
FunctionName
Line
ServiceRefId (FK) - normalized service reference (from file path - AST extracts)
```

**REMOVED**:
- ✗ FunctionBody (redundant - already in Git)
- ✗ TestPrefix (can derive if needed)
- ✗ SequentialEntryPointRefId (handle in separate table)

**NORMALIZED**:
- ✓ ServiceRefId FK replaces ServiceName string (already normalized via Files table!)

**Why**: AST gives us clean function metadata without needing full source

---

### 6. TemplateFunctions (MASSIVELY SIMPLIFIED)
**Current**: Stores 304,255 rows with full function bodies (11MB!)
**New**: Just metadata

```
TemplateFunctionRefId (PK)
FileRefId (FK)
StructRefId (FK) - normalized struct reference
FunctionName
ReceiverType (pointer vs value)
ServiceRefId (FK) - normalized service reference (AST extracts from path)
Line
ReturnsString (boolean - AST knows return type)
```

**REMOVED**:
- ✗ FunctionBody (304K rows of source code - biggest win!)
- ✗ ReceiverVariable (don't need it)

**NORMALIZED**:
- ✓ ServiceRefId FK replaces ServiceName string (already normalized via Files table!)

**Why**: AST semantic analysis eliminates need for source storage

---

### 7. TestSteps (NEW - Replaces TestFunctionSteps)
**Purpose**: Test step → template relationships (RESOLVED by AST)

```
TestStepRefId (PK)
TestFunctionRefId (FK)
TemplateFunctionRefId (FK) - direct FK to the template function being called
StepIndex
TargetStructRefId (FK) - normalized struct reference
TargetServiceRefId (FK) - normalized service reference (AST determines)
ReferenceTypeId (FK) - AST determines (SELF_CONTAINED, EMBEDDED_SELF, CROSS_FILE)
Line
```

**REMOVED**:
- ✗ StepBody (don't need full source)
- ✗ StructVisibilityTypeId (AST handles this differently)
- ✗ ConfigTemplate string (use TemplateFunctionRefId FK instead!)

**NORMALIZED**:
- ✓ TemplateFunctionRefId FK replaces ConfigTemplate string
- ✓ TargetServiceRefId FK replaces TargetServiceName string

**AST Advantage**: AST knows EXACTLY which template a step calls and what service it's in

---

### 8. TemplateCallChain (NEW - Replaces TemplateCalls + IndirectConfigReferences)
**Purpose**: Complete template → template → resource chain (RESOLVED by AST)

```
ChainRefId (PK)
TestStepRefId (FK) - which test step started this chain
SourceTemplateFunctionRefId (FK) - normalized template reference
TargetTemplateFunctionRefId (FK) - normalized template reference
SourceServiceRefId (FK) - normalized service reference
TargetServiceRefId (FK) - normalized service reference
ChainDepth (1, 2, 3... - AST can walk the chain)
CrossesServiceBoundary (boolean - AST determines)
ReferenceTypeId (FK) - SAME_SERVICE or CROSS_SERVICE
```

**REMOVED**:
- ✗ SourceTemplate string (use SourceTemplateFunctionRefId FK)
- ✗ TargetTemplate string (use TargetTemplateFunctionRefId FK)
- ✗ SourceService string (use SourceServiceRefId FK)
- ✗ TargetService string (use TargetServiceRefId FK)
- ✗ UltimateResourceRefs JSON array (create separate TemplateChainResources junction table!)

**NORMALIZED**:
- ✓ SourceTemplateFunctionRefId FK replaces SourceTemplate string
- ✓ TargetTemplateFunctionRefId FK replaces TargetTemplate string
- ✓ SourceServiceRefId FK replaces SourceService string
- ✓ TargetServiceRefId FK replaces TargetService string
- ✓ Separate junction table for ultimate resource references

**AST Advantage**:
- AST walks the call graph and resolves the ENTIRE chain
- No more multi-pass PowerShell resolution
- AST knows if it crosses services
- AST knows what resources are ultimately referenced

---

### 9. TemplateChainResources (NEW - Junction Table)
**Purpose**: Track which resources are referenced at the end of each template call chain
**Schema**:
```
ChainResourceRefId (PK)
ChainRefId (FK) - which call chain
ResourceRefId (FK) - normalized resource reference (from Resources table)
```

**Why**: Proper junction table instead of JSON array
- Maintains referential integrity
- Can't reference non-existent resources
- Enables efficient JOINs
- Standard relational design

**Example Query**:
```sql
-- Find all test steps that ultimately reference azurerm_resource_group
SELECT DISTINCT ts.TestStepRefId, tcc.ChainDepth
FROM TestSteps ts
JOIN TemplateCallChain tcc ON ts.TestStepRefId = tcc.TestStepRefId
JOIN TemplateChainResources tcr ON tcc.ChainRefId = tcr.ChainRefId
JOIN Resources r ON tcr.ResourceRefId = r.ResourceRefId
WHERE r.ResourceName = 'azurerm_resource_group'
```

---

### 10. DirectResourceReferences (KEEP BUT ENHANCE)
**Purpose**: Direct resource mentions in HCL
**Schema**: Enhanced with normalization

```
DirectRefId (PK)
TemplateFunctionRefId (FK) - which template contains this reference
ResourceRefId (FK) - normalized resource reference (from Resources table)
ReferenceTypeId (FK)
Context (the actual HCL line)
Line
```

**REMOVED**:
- ✗ FileRefId FK (get file via TemplateFunctionRefId → FileRefId)
- ✗ ResourceName string (use ResourceRefId FK)
- ✗ ServiceName string (get service via TemplateFunctionRefId → ServiceRefId)

**NORMALIZED**:
- ✓ TemplateFunctionRefId FK provides file and service context
- ✓ ResourceRefId FK replaces ResourceName string

**Why**: Still need to track direct resource references in templates, but properly normalized

---

### 11. Structs
**Purpose**: Normalized struct names (e.g., "ManagerResource", "VirtualNetworkResource")
**Schema**: No changes needed
```
StructRefId (PK)
StructName
```
**Why Keep**: Classic denormalization table
- Store unique struct names once
- FK references more efficient than string comparisons
- Maintains referential integrity
- Prevents typos/inconsistencies

---

## Summary of Normalization Improvements

### Normalization Lookup Tables (Store unique values once):
1. **Resources** - azurerm resource types (already normalized ✓)
2. **Services** - Azure service names (already normalized ✓)
3. **Structs** - Go struct names (already normalized ✓)
4. **ReferenceTypes** - Relationship classifications (already normalized ✓)
5. **Files** - Test file paths (already normalized ✓)

### Tables Using Proper FKs Instead of Strings:

#### TestFunctions:
- ❌ ~~ServiceName string~~
- ✅ ServiceRefId FK (via Files table)

#### TemplateFunctions:
- ❌ ~~ServiceName string~~
- ✅ ServiceRefId FK (via Files table)

#### TestSteps:
- ❌ ~~ConfigTemplate string~~ (e.g., "basic")
- ❌ ~~TargetServiceName string~~
- ❌ ~~TargetStructName string~~
- ✅ TemplateFunctionRefId FK (direct reference to template)
- ✅ TargetServiceRefId FK
- ✅ TargetStructRefId FK

#### TemplateCallChain:
- ❌ ~~SourceTemplate string~~
- ❌ ~~TargetTemplate string~~
- ❌ ~~SourceService string~~
- ❌ ~~TargetService string~~
- ❌ ~~UltimateResourceRefs JSON array~~
- ✅ SourceTemplateFunctionRefId FK
- ✅ TargetTemplateFunctionRefId FK
- ✅ SourceServiceRefId FK
- ✅ TargetServiceRefId FK
- ✅ TemplateChainResources junction table with ResourceRefId FK

#### DirectResourceReferences:
- ❌ ~~ResourceName string~~
- ❌ ~~ServiceName string~~
- ❌ ~~FileRefId FK~~ (redundant - get via template)
- ✅ TemplateFunctionRefId FK (provides file and service context)
- ✅ ResourceRefId FK

### Benefits of Full Normalization:
1. **Storage Efficiency**: "azurerm_resource_group" stored once, referenced by integer
2. **Referential Integrity**: Can't reference non-existent resources/services/structs
3. **No Typos**: Can't have "basic" vs "baisc" vs "Basic"
4. **Faster Joins**: Integer FK joins faster than string comparisons
5. **Data Consistency**: Single source of truth for all lookup values
6. **Standard Patterns**: Same normalization approach across entire schema

---

## Tables to REMOVE

### ❌ IndirectConfigReferences
**Why Remove**:
- Replaced by TemplateCallChain
- AST resolves entire chain, not just one hop
- New table is more powerful

### ❌ TemplateReferences
**Why Remove**:
- Merged into TestSteps (test → template relationship)
- AST resolves this directly

### ❌ TemplateCalls
**Why Remove**:
- Merged into TemplateCallChain
- AST gives us complete chains, not individual calls

### ❌ SequentialReferences
**Why Keep Separate**: Actually, we might need a separate SequentialTests table
- Different concept than template calls
- Test → Test relationships (sequential patterns)

---

## ReferenceTypes Table REFACTOR

### Current Problems:
- Duplicates: SAME_SERVICE (14) = EMBEDDED_SELF (3)?
- Duplicates: CROSS_SERVICE (15) = CROSS_FILE (2)?
- Mix of concepts: file location, service location, visibility

### New Structure:

```
ReferenceTypeId | ReferenceTypeName      | Category           | Description
----------------|------------------------|--------------------|--------------------------
1               | SELF_CONTAINED         | test-to-template   | Test step calls own struct's template
2               | CROSS_FILE             | file-location      | Reference in different file
3               | EMBEDDED_SELF          | file-location      | Reference in same file
4               | ATTRIBUTE_REFERENCE    | reference-style    | name/id attribute reference
5               | RESOURCE_BLOCK         | reference-style    | Full resource block
...
14              | SAME_SERVICE           | service-boundary   | Within same Azure service
15              | CROSS_SERVICE          | service-boundary   | Crosses Azure service boundary
```

**Categories**:
- `test-to-template`: How test relates to template
- `file-location`: Same file vs different file
- `service-boundary`: Same service vs cross-service
- `reference-style`: How resource is referenced (block, attribute, etc.)

**AST determines all of these UPFRONT**

---

## AST Output Format (What AST Should Return)

Instead of raw data that PowerShell has to resolve, AST returns **resolved relationships**:

```json
{
  "file_path": "internal/services/network/manager_test.go",
  "service_name": "network",

  "test_functions": [
    {
      "name": "TestAccNetworkManager_basic",
      "struct_name": "ManagerResource",
      "line": 45,
      "is_test": true
    }
  ],

  "template_functions": [
    {
      "name": "basic",
      "struct_name": "ManagerResource",
      "returns_string": true,
      "line": 123,
      "is_template": true
    },
    {
      "name": "template",
      "struct_name": "ManagerResource",
      "returns_string": true,
      "line": 234,
      "is_template": true
    }
  ],

  "test_steps": [
    {
      "test_function": "TestAccNetworkManager_basic",
      "step_index": 1,
      "calls_template": "basic",
      "target_struct": "ManagerResource",
      "target_service": "network",
      "reference_type": "SELF_CONTAINED",
      "line": 67
    }
  ],

  "template_call_chains": [
    {
      "source_template": "basic",
      "target_template": "template",
      "source_service": "network",
      "target_service": "network",
      "chain_depth": 1,
      "crosses_service_boundary": false,
      "reference_type": "SAME_SERVICE"
    }
  ],

  "direct_resource_references": [
    {
      "template_function": "template",
      "resource_name": "azurerm_resource_group",
      "reference_type": "RESOURCE_BLOCK",
      "context": "resource \"azurerm_resource_group\" \"test\" {",
      "line": 245
    }
  ]
}
```

**PowerShell just imports this and stores it - NO complex resolution needed!**

---

## Migration Strategy

### Phase 1: Fix Current AST (Quick Win)
1. ✅ Track ALL template calls (same-file + cross-file)
2. ✅ Populate service names
3. ✅ Test that it works with current database

### Phase 2: Enhance AST Resolution (AST Does the Work)
1. AST walks call chains and resolves ultimate resources
2. AST determines reference types upfront
3. AST outputs resolved relationships

### Phase 3: New Database Schema (Simplified Storage)
1. Remove source code storage (304K rows → metadata only)
2. Merge fragmented tables (TemplateReferences, TemplateCalls, IndirectConfigReferences → TemplateCallChain)
3. Let AST-resolved data flow directly into tables

### Phase 4: Simplify PowerShell (Query Layer Only)
1. Remove complex resolution logic
2. Simple JOINs for reporting
3. Fast lookups by resource name

---

## Expected Benefits

### Data Volume:
- **Current**: 611K rows (with 304K function bodies)
- **New**: ~60K rows (metadata only)
- **Reduction**: 90% less data, 95% less storage

### Performance:
- **Current**: Multi-pass PowerShell resolution
- **New**: AST resolves everything upfront
- **Speed**: 10x faster (estimate)

### Accuracy:
- **Current**: Regex pattern matching (can miss edge cases)
- **New**: AST semantic analysis (exact)
- **Quality**: 100% accurate relationships

### Maintainability:
- **Current**: Complex PowerShell JOINs and lookups
- **New**: Simple storage and queries
- **Complexity**: 80% reduction in code

---

## Questions to Validate

1. **Do we still need separate Structs table?**
   - Probably not - AST resolves struct names directly
   - Simpler to use struct name strings in joins

2. **How to handle sequential tests?**
   - Keep separate SequentialTests table
   - Different concept than template chains

3. **What about database mode?**
   - DatabaseMode still works - just queries different tables
   - Direct mode: DirectResourceReferences
   - Indirect mode: TemplateCallChain

4. **Backward compatibility?**
   - Don't need it - this is internal tool
   - Can migrate existing data if needed

---

## Next Steps

1. **Validate with you**: Does this architecture make sense?
2. **Document new schema**: Complete DDL for new tables
3. **Update AST analyzer**: Output resolved relationships
4. **Create migration script**: Old schema → new schema
5. **Update PowerShell**: Simplified import/query logic
6. **Test end-to-end**: Verify we can still find all tests for a resource

**Do you want me to proceed with Phase 1 (fix current AST) while we finalize the new schema design?**
