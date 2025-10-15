# TerraCorder Database Schema
## AST-Based Fully Normalized Relational Design

---

## Overview

TerraCorder uses AST (Abstract Syntax Tree) semantic analysis to extract test function relationships and resource references from Terraform provider Go test files. The database schema is fully normalized with foreign key relationships, storing metadata only (no source code).

### Core Principle
**AST does the heavy lifting (semantic resolution), PowerShell does the querying (presentation)**

### Key Benefits
- **Compact Storage**: Metadata-only design (~70K rows typical)
- **High Performance**: AST resolves relationships upfront, single-pass analysis
- **100% Accuracy**: Semantic syntax tree analysis eliminates pattern matching errors
- **Simple Queries**: Pre-resolved relationships enable straightforward SQL-like queries
- **Full Normalization**: All repeating strings normalized into lookup tables with FK references

---

## Operational Modes

TerraCorder operates in two distinct modes:

### Discovery Mode (Database Creation)
- **Purpose**: AST-based analysis of Terraform provider repository
- **Process**: AST analyzer processes Go test files, outputs resolved relationships
- **Output**: 12 CSV files representing normalized database tables
- **File**: `go_test_commands.txt` with generated test commands
- **Duration**: Seconds to minutes (depends on repository size)
- **Use Case**: First-time analysis, updating database with code changes
- **Method**: Single-pass semantic analysis, no iterative resolution

#### What Goes Into go_test_commands.txt

The `go_test_commands.txt` file contains **ALL test functions** discovered through three discovery mechanisms:

1. **Direct References** - Tests that explicitly use the resource in HCL code
   - Example: `resource "azurerm_kubernetes_cluster" "test"`
   - Source: DirectResourceReferences table
   - Query: `-ShowDirectReferences`

2. **Indirect References (Template Dependencies)** - Tests that call template functions which configure the resource
   - Example: Test calls `r.complete()` -> template creates the resource
   - Source: IndirectConfigReferences table
   - Query: `-ShowIndirectReferences` (shows both #2 and #3)

3. **Sequential References** - Tests pulled in via `acceptance.RunTestsInSequence()` patterns
   - Example: HDInsight Kafka test -> pulls in HBase, Hadoop, Spark cluster tests
   - Source: SequentialReferences table
   - Query: `-ShowIndirectReferences` (shows both #2 and #3)

**Important**:
- **`-ShowIndirectReferences`** displays template dependencies (#2) + sequential references (#3)
- **`-ShowDirectReferences`** displays direct resource usage (#1)
- **Complete blast radius** = Direct + Indirect + Sequential (shown in `go_test_commands.txt`)
- To see the **full impact**, you need to run BOTH `-ShowDirectReferences` AND `-ShowIndirectReferences`

### Database Mode (Query Operations)
- **Purpose**: Fast querying of previously analyzed data
- **Process**: Load CSV files into in-memory database, execute queries
- **Input**: CSV files from previous Discovery Mode run
- **Operations**: ShowDirectReferences, ShowIndirectReferences, ShowAllReferences, ShowTestSequence
- **Duration**: Seconds (database load + query execution)
- **Use Case**: Analysis, reporting, exploration without re-scanning repository
- **Note**: Database Mode is read-only, does not regenerate CSV files or `go_test_commands.txt`

---

## Design Principles

### 1. Full Normalization
Every repeating string value is stored once in a lookup table and referenced via foreign keys:
- **Resources**: Terraform resource types (e.g., "azurerm_kubernetes_cluster")
- **Services**: Azure service categories (e.g., "network", "compute")
- **Structs**: Go struct names (e.g., "ManagerResource", "VirtualNetworkResource")
- **ReferenceTypes**: Relationship classifications (e.g., RESOURCE_BLOCK, SAME_SERVICE)
- **Files**: Test file paths
- **TemplateFunctions**: Template function names (e.g., "basic", "template")

### 2. Metadata-Only Storage
- **Design**: Store function names, line numbers, and relationships only
- **Rationale**: Source code already exists in Git repository
- **Result**: Compact database, fast queries, no duplicate storage

### 3. Pre-Resolved Relationships
- **AST Analysis**: AST walks call graphs and resolves relationships during parsing
- **Database Storage**: Stores final resolved relationships with foreign key references
- **Query Simplicity**: Simple joins replace complex multi-pass resolution logic

### 4. Semantic Understanding
- **AST Parsing**: Parse Go syntax tree to understand code structure semantically
- **Capabilities**:
  - Determines if function returns string (template vs helper)
  - Tracks both pointer and value receivers
  - Understands service boundaries from package structure
  - Identifies sequential test patterns and references
  - Resolves template call chains and resource references

---

## Database Tables

### Current Schema (14 Tables Exported)

The database currently exports the following 14 tables to CSV:

**Normalization/Lookup Tables (6)**:
1. **Resources** - Terraform resource types being analyzed
2. **ResourceRegistrations** - Master mapping of all Terraform resources to owning services
3. **Services** - Azure service categories
4. **Files** - Test file paths
5. **Structs** - Go struct names
6. **ReferenceTypes** - Relationship type classifications

**Data Tables (8)**:
7. **TestFunctions** - Test function metadata
8. **TemplateFunctions** - Template function metadata
9. **TestFunctionSteps** (TestSteps) - Test step execution records
10. **DirectResourceReferences** - Direct HCL resource references
11. **SequentialReferences** - Sequential test execution references
12. **TemplateReferences** - Template function call references (legacy support)
13. **IndirectConfigReferences** - Indirect resource references via templates (legacy support)
14. **TemplateCallChain** - Template-to-template function calls for cross-file reference detection

### Entity Relationship Diagram

```mermaid
erDiagram
    %% Resources is the top-level entity - everything flows from here
    Resources ||--o{ Services : "has services for"
    Resources ||--o{ Structs : "defines test structs for"
    Resources ||--o{ TestFunctions : "tested by"
    Resources ||--o{ TemplateFunctions : "configured by"
    Resources ||--o{ DirectResourceReferences : "directly referenced in"
    Resources ||--o| ResourceRegistrations : "registered in"

    %% ResourceRegistrations maps all resources to owning services
    ResourceRegistrations }o--|| Services : "owned by service"

    %% Service hierarchy
    Services ||--o{ Files : "contains test files"
    Services ||--o{ Structs : "defines test structs"

    %% File relationships
    Files ||--o{ TestFunctions : "contains"
    Files ||--o{ TemplateFunctions : "contains"
    Files ||--o{ Structs : "defines"

    %% Struct relationships
    Structs ||--o{ TestFunctions : "receiver for"
    Structs ||--o{ TemplateFunctions : "receiver for"

    %% Test function execution flow
    TestFunctions ||--o{ TestFunctionSteps : "executes steps"
    TestFunctions ||--o{ SequentialReferences : "entry point for"
    TestFunctions ||--o{ SequentialReferences : "referenced in"
    TestFunctions ||--o{ TemplateReferences : "calls templates via"

    %% Template function relationships
    TemplateFunctions ||--o{ TestFunctionSteps : "called by step"
    TemplateFunctions ||--o{ DirectResourceReferences : "references resource"
    TemplateFunctions ||--o{ TemplateReferences : "is referenced"
    TemplateFunctions ||--o{ TemplateCallChain : "source of call"
    TemplateFunctions ||--o{ TemplateCallChain : "target of call"

    %% Reference flow
    TestFunctionSteps ||--o{ IndirectConfigReferences : "produces"
    TemplateReferences ||--o{ IndirectConfigReferences : "resolves to"

    %% Reference type classification
    ReferenceTypes ||--o{ TestFunctionSteps : "classifies"
    ReferenceTypes ||--o{ DirectResourceReferences : "classifies"
    ReferenceTypes ||--o{ IndirectConfigReferences : "classifies"
    ReferenceTypes ||--o{ TemplateCallChain : "classifies"

    Resources {
        int ResourceRefId PK
        string ResourceName UK
        int ResourceRegistrationRefId FK
    }

    ResourceRegistrations {
        int ResourceRegistrationRefId PK
        int ServiceRefId FK
        string ResourceName UK
    }

    Services {
        int ServiceRefId PK
        int ResourceRefId FK
        string Name UK
    }

    Files {
        int FileRefId PK
        string FilePath UK
        int ServiceRefId FK
    }

    Structs {
        int StructRefId PK
        int ResourceRefId FK
        int FileRefId FK
        int Line
        string StructName
    }

    TestFunctions {
        int TestFunctionRefId PK
        int ResourceRefId FK
        int FileRefId FK
        int StructRefId FK
        int Line
        string FunctionName
        string TestPrefix
        int ReferenceTypeRefId FK
        int SequentialEntryPointRefId FK
    }

    TemplateFunctions {
        int TemplateFunctionRefId PK
        int ResourceRefId FK
        string TemplateFunctionName
        int StructRefId FK
        int FileRefId FK
        int Line
        string ReceiverVariable
    }

    TestFunctionSteps {
        int TestStepRefId PK
        int TestFunctionRefId FK
        int TemplateFunctionRefId FK
        int StepIndex
        int TargetStructRefId FK
        int TargetServiceRefId FK
        int ReferenceTypeId FK
        int Line
    }

    DirectResourceReferences {
        int DirectRefId PK
        int TemplateFunctionRefId FK
        int ResourceRefId FK
        int ReferenceTypeId FK
        string Context
        int TemplateLine
        int ContextLine
    }

    SequentialReferences {
        int SequentialRefId PK
        int EntryPointFunctionRefId FK
        int ReferencedFunctionRefId FK
        string SequentialGroup
        string SequentialKey
    }

    TemplateReferences {
        int TemplateReferenceRefId PK
        int TestFunctionRefId FK
        int TestFunctionStepRefId FK
        int StructRefId FK
        string TemplateReference
        string TemplateVariable
        string TemplateMethod
    }

    IndirectConfigReferences {
        int IndirectRefId PK
        int TestFunctionStepRefId FK
        int TemplateReferenceRefId FK
        int SourceTemplateFunctionRefId FK
        int ReferenceTypeId FK
        int ServiceImpactTypeId FK
    }

    TemplateCallChain {
        int TemplateCallChainRefId PK
        int SourceTemplateFunctionRefId FK
        int TargetTemplateFunctionRefId FK
        int ReferenceTypeId FK
        int Line
    }

    ReferenceTypes {
        int ReferenceTypeId PK
        string ReferenceTypeName UK
    }
```

---

### Normalization/Lookup Tables (Store Unique Values Once)

#### 1. Resources
**Purpose**: Master list of Terraform resources we're searching for

```sql
CREATE TABLE Resources (
    ResourceRefId INTEGER PRIMARY KEY,
    ResourceName TEXT UNIQUE NOT NULL,
    ResourceRegistrationRefId INTEGER,
    FOREIGN KEY (ResourceRegistrationRefId) REFERENCES ResourceRegistrations(ResourceRegistrationRefId)
);
```

**Example Data**:
```
ResourceRefId | ResourceName                     | ResourceRegistrationRefId
1             | azurerm_resource_group           | 523
2             | azurerm_virtual_network          | 1523
3             | azurerm_subnet                   | 1286
4             | azurerm_kubernetes_cluster       | 765
5             | azurerm_recovery_services_vault  | 787
```

**Why Normalized**: Store "azurerm_resource_group" once, reference by ID in DirectResourceReferences and other tables

**Why Keep ResourceName**: While ResourceRegistrationRefId links to the master registration, keeping ResourceName in this table is a denormalization optimization because:
- Resources table may contain multiple rows (multi-resource analysis, PR-based discovery)
- ResourceName is accessed frequently in queries and display logic
- Avoiding a join to ResourceRegistrations for every query improves performance
- The redundancy is controlled (only resources being analyzed, not all 1038 possible resources)

**Foreign Key**: `ResourceRegistrationRefId` links to the master ResourceRegistrations table to determine which service owns this resource

---

#### 2. ResourceRegistrations
**Purpose**: Master mapping of ALL Terraform resources to their owning Azure services

```sql
CREATE TABLE ResourceRegistrations (
    ResourceRegistrationRefId INTEGER PRIMARY KEY,
    ServiceRefId INTEGER NOT NULL,
    ResourceName TEXT UNIQUE NOT NULL,
    FOREIGN KEY (ServiceRefId) REFERENCES Services(ServiceRefId)
);
```

**Example Data**:
```
ResourceRegistrationRefId | ServiceRefId | ResourceName
523                       | 45           | azurerm_resource_group
787                       | 103          | azurerm_recovery_services_vault
1523                      | 75           | azurerm_virtual_network
1286                      | 75           | azurerm_subnet
765                       | 24           | azurerm_kubernetes_cluster
```

**Purpose**: This table is the **source of truth** for which Azure service owns each Terraform resource. It's populated by parsing `internal/services/*/registration.go` files in the provider repository.

**Discovery Process**:
- Scans all `internal/services/*/registration.go` files
- Extracts service name from directory path (e.g., `internal/services/recoveryservices/`)
- Parses two registration styles:
  - **Old style**: Quoted strings in `SupportedResources()` map (e.g., `"azurerm_recovery_services_vault"`)
  - **New style**: Typed structs in `Resources()` array -> finds `ResourceType()` method in `*_resource.go` files

**Typical Size**: ~1,038 resource registrations from ~131 Azure services (azurerm provider)

**Performance**: Import optimized with single-pass file reading, regex matching, and struct->resource map caching (1.7 seconds for full import)

**Use Cases**:
1. **Cross-service dependency analysis**: Determine if a test uses resources owned by different services
2. **ServiceImpactTypeId calculation**: Compare test-service vs resource-owning-service (future enhancement)
3. **Resource ownership reporting**: Show which service maintains each resource's implementation

**Why Separate from Resources**: Resources table contains only the specific resources being analyzed in the current run (1-N rows), while ResourceRegistrations contains ALL possible resources in the provider (~1,038 rows). This separation:
- Keeps Resources table small and focused on current analysis
- Provides complete resource-to-service mapping for any resource
- Enables future multi-resource and PR-driven discovery features

---

#### 3. Services
**Purpose**: Azure service categories for service boundary analysis

```sql
CREATE TABLE Services (
    ServiceRefId INTEGER PRIMARY KEY,
    ServiceName TEXT UNIQUE NOT NULL
);
```

**Example Data**:
```
ServiceRefId | ServiceName
1            | network
2            | compute
3            | storage
4            | containerservice
5            | recoveryservices
```

**Why Normalized**: Store "network" once, reference by ID in Files, TestFunctions, TemplateFunctions, TestSteps, ResourceRegistrations

**AST Extraction**: AST extracts service name from file path:
```
internal/services/network/manager_test.go -> "network"
internal/services/compute/virtual_machine_test.go -> "compute"
```

**Relationship to ResourceRegistrations**: Services table is populated during AST analysis from test file paths. ResourceRegistrations table links ALL provider resources to their owning services by parsing registration.go files. The two work together to enable cross-service dependency analysis.

---

#### 4. Structs
**Purpose**: Go struct names used as test/template receivers

```sql
CREATE TABLE Structs (
    StructRefId INTEGER PRIMARY KEY,
    StructName TEXT UNIQUE NOT NULL
);
```

**Example Data**:
```
StructRefId | StructName
1           | ManagerResource
2           | VirtualNetworkResource
3           | SubnetResource
4           | KubernetesClusterResource
```

**Why Normalized**: Store "ManagerResource" once, reference by ID in TestFunctions, TemplateFunctions, TestSteps

**AST Extraction**: AST resolves struct names from function receivers:
```go
func (r ManagerResource) basic() string { ... }  // StructName = "ManagerResource"
func (r *VirtualNetworkResource) template() string { ... }  // StructName = "VirtualNetworkResource"
```

**Benefits**:
- Storage efficiency (store string once, reference by integer)
- Referential integrity (can't reference non-existent structs)
- No typos ("ManagerResource" vs "MangerResource")
- Faster joins (integer comparisons vs string comparisons)

---

#### 5. ReferenceTypes
**Purpose**: Classify relationship types across multiple dimensions

```sql
CREATE TABLE ReferenceTypes (
    ReferenceTypeId INTEGER PRIMARY KEY,
    ReferenceTypeName TEXT UNIQUE NOT NULL,
    Category TEXT NOT NULL,
    Description TEXT
);
```

**Master Data**:
```
ReferenceTypeId | ReferenceTypeName      | Category           | Description
1               | SELF_CONTAINED         | test-to-template   | Test step calls own struct's template method
2               | CROSS_FILE             | file-location      | Reference in different file within same service
3               | EMBEDDED_SELF          | file-location      | Reference in same file as definition
4               | ATTRIBUTE_REFERENCE    | reference-style    | HCL attribute reference (azurerm_xxx.test.name)
5               | RESOURCE_BLOCK         | reference-style    | HCL resource block (resource "azurerm_xxx" "test")
6               | DATA_SOURCE_REFERENCE  | reference-style    | HCL data source reference
7               | TEMPLATE_FUNCTION      | function-type      | Template function (returns string)
8               | SEQUENTIAL_REFERENCE   | test-pattern       | Sequential test execution pattern
9               | ANONYMOUS_FUNCTION     | function-type      | Anonymous function reference
10              | EXTERNAL_REFERENCE     | dependency         | External dependency outside codebase
11              | PRIVATE_REFERENCE      | visibility         | Go private struct (lowercase first letter)
12              | PUBLIC_REFERENCE       | visibility         | Go public struct (uppercase first letter)
13              | SEQUENTIAL_ENTRYPOINT  | test-pattern       | Entry point for sequential test pattern
14              | SAME_SERVICE           | service-boundary   | Within same Azure service
15              | CROSS_SERVICE          | service-boundary   | Crosses Azure service boundary
```

**Categories Explained**:
- **test-to-template**: How test step relates to template function
- **file-location**: Same file vs different file
- **reference-style**: How resource is referenced in HCL code
- **function-type**: Classification of function types
- **test-pattern**: Test execution patterns
- **dependency**: External vs internal dependencies
- **visibility**: Go language visibility rules
- **service-boundary**: Service impact analysis

**AST Advantage**: AST determines reference types during semantic analysis, not after-the-fact pattern matching

**Note**: ReferenceTypes are statically initialized in PowerShell at startup, not imported from CSV

---

#### 6. Files
**Purpose**: Track test files being analyzed

```sql
CREATE TABLE Files (
    FileRefId INTEGER PRIMARY KEY,
    FileName TEXT NOT NULL,
    FilePath TEXT UNIQUE NOT NULL,
    ServiceRefId INTEGER NOT NULL,
    FOREIGN KEY (ServiceRefId) REFERENCES Services(ServiceRefId)
);
```

**Example Data**:
```
FileRefId | FileName                          | FilePath                                                              | ServiceRefId
1         | network_manager_resource_test.go  | internal/services/network/network_manager_resource_test.go            | 1
2         | virtual_network_resource_test.go  | internal/services/network/virtual_network_resource_test.go            | 1
3         | kubernetes_cluster_resource_test.go| internal/services/containerservice/kubernetes_cluster_resource_test.go| 4
```

**Why Needed**: Link all other tables to source files and services

**AST Extraction**: AST receives file path, extracts service from path structure

---

### Data Tables (AST-Extracted Metadata)

#### 7. TestFunctions
**Purpose**: Test function metadata

```sql
CREATE TABLE TestFunctions (
    TestFunctionRefId INTEGER PRIMARY KEY,
    FileRefId INTEGER NOT NULL,
    StructRefId INTEGER,
    FunctionName TEXT NOT NULL,
    Line INTEGER NOT NULL,
    TestPrefix TEXT NOT NULL,
    ReferenceTypeRefId INTEGER,
    SequentialEntryPointRefId INTEGER DEFAULT 0,
    FOREIGN KEY (FileRefId) REFERENCES Files(FileRefId),
    FOREIGN KEY (StructRefId) REFERENCES Structs(StructRefId),
    FOREIGN KEY (ReferenceTypeRefId) REFERENCES ReferenceTypes(ReferenceTypeId)
);
```

**Example Data**:
```
TestFunctionRefId | FileRefId | StructRefId | FunctionName                       | Line | TestPrefix | ReferenceTypeRefId
1                 | 1         | 1           | TestAccNetworkManager_basic        | 45   | TestAcc_   | NULL
2                 | 1         | 1           | TestAccNetworkManager_requiresImport| 78   | TestAcc_   | NULL
3                 | 0         | NULL        | testAccSecurityCenterWorkspace_basic| 0    | testAcc_   | 10
```

**Column Details**:
- **TestPrefix**: Test prefix up to and including first underscore (e.g., "TestAcc_", "test_")
- **ReferenceTypeRefId**: Foreign key to ReferenceTypes (10 = EXTERNAL_REFERENCE for functions not in scanned files)
- **FileRefId = 0**: Indicates external reference (function exists but file wasn't scanned)
- **SequentialEntryPointRefId**: Foreign key to the entry point function for sequential test chains

**AST Extraction**:
```go
func TestAccNetworkManager_basic(t *testing.T) { ... }
// AST extracts: FunctionName="TestAccNetworkManager_basic", Line=45
```

**Queries**:
```sql
-- Get test function with file and service info
SELECT tf.FunctionName, f.FilePath, s.ServiceName
FROM TestFunctions tf
JOIN Files f ON tf.FileRefId = f.FileRefId
JOIN Services s ON f.ServiceRefId = s.ServiceRefId
WHERE tf.TestFunctionRefId = 1;
```

---

#### 8. TemplateFunctions
**Purpose**: Template function metadata (NO function bodies)

```sql
CREATE TABLE TemplateFunctions (
    TemplateFunctionRefId INTEGER PRIMARY KEY,
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

**Example Data**:
```
TemplateFunctionRefId | FileRefId | StructRefId | FunctionName | ReceiverType | Line | ReturnsString
1                     | 1         | 1           | basic        | value        | 123  | 1
2                     | 1         | 1           | template     | value        | 234  | 1
3                     | 1         | 1           | helper       | pointer      | 345  | 0
```

**AST Extraction**:
```go
func (r ManagerResource) basic() string { ... }
// AST extracts: FunctionName="basic", ReceiverType="value", ReturnsString=1

func (r *ManagerResource) helper() int { ... }
// AST extracts: FunctionName="helper", ReceiverType="pointer", ReturnsString=0
```

**Note**: Only template methods (return string) are tracked; infrastructure helpers are ignored

**Queries**:
```sql
-- Get all template functions for a struct
SELECT tf.FunctionName, f.FilePath, st.StructName
FROM TemplateFunctions tf
JOIN Files f ON tf.FileRefId = f.FileRefId
JOIN Structs st ON tf.StructRefId = st.StructRefId
WHERE st.StructName = 'ManagerResource'
  AND tf.ReturnsString = 1;
```

---

#### 9. TestSteps
**Purpose**: Test step -> template relationships (RESOLVED by AST)

```sql
CREATE TABLE TestSteps (
    TestStepRefId INTEGER PRIMARY KEY,
    TestFunctionRefId INTEGER NOT NULL,
    TemplateFunctionRefId INTEGER NOT NULL,  -- Direct FK to template being called
    StepIndex INTEGER NOT NULL,
    TargetStructRefId INTEGER NOT NULL,
    TargetServiceRefId INTEGER NOT NULL,
    ReferenceTypeId INTEGER NOT NULL,
    Line INTEGER NOT NULL,
    FOREIGN KEY (TestFunctionRefId) REFERENCES TestFunctions(TestFunctionRefId),
    FOREIGN KEY (TemplateFunctionRefId) REFERENCES TemplateFunctions(TemplateFunctionRefId),
    FOREIGN KEY (TargetStructRefId) REFERENCES Structs(StructRefId),
    FOREIGN KEY (TargetServiceRefId) REFERENCES Services(ServiceRefId),
    FOREIGN KEY (ReferenceTypeId) REFERENCES ReferenceTypes(ReferenceTypeId)
);
```

**Example Data**:
```
TestStepRefId | TestFunctionRefId | TemplateFunctionRefId | StepIndex | TargetStructRefId | TargetServiceRefId | ReferenceTypeId | Line
1             | 1                 | 1                     | 1         | 1                 | 1                  | 1               | 67
2             | 1                 | 2                     | 2         | 1                 | 1                  | 1               | 68
3             | 2                 | 1                     | 1         | 1                 | 1                  | 1               | 89
```

**AST Extraction**:
```go
func TestAccNetworkManager_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_network_manager", "test")
    r := ManagerResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),  // AST resolves: TemplateFunctionRefId=1, TargetStructRefId=1, ReferenceTypeId=1 (SELF_CONTAINED)
        },
    })
}
```

**Note**: AST resolves template function references, target struct, and service during parsing - all stored as foreign keys for efficient queries

**Queries**:
```sql
-- Get all test steps for a test function
SELECT
    tf.FunctionName AS Template,
    st.StructName AS TargetStruct,
    sv.ServiceName AS TargetService,
    rt.ReferenceTypeName AS ReferenceType
FROM TestSteps ts
JOIN TemplateFunctions tf ON ts.TemplateFunctionRefId = tf.TemplateFunctionRefId
JOIN Structs st ON ts.TargetStructRefId = st.StructRefId
JOIN Services sv ON ts.TargetServiceRefId = sv.ServiceRefId
JOIN ReferenceTypes rt ON ts.ReferenceTypeId = rt.ReferenceTypeId
WHERE ts.TestFunctionRefId = 1
ORDER BY ts.StepIndex;
```

---

#### 10. DirectResourceReferences
**Purpose**: Direct resource mentions in template function HCL code

```sql
CREATE TABLE DirectResourceReferences (
    DirectRefId INTEGER PRIMARY KEY,
    TemplateFunctionRefId INTEGER NOT NULL,
    ResourceRefId INTEGER NOT NULL,
    ReferenceTypeId INTEGER NOT NULL,  -- RESOURCE_BLOCK (5) or ATTRIBUTE_REFERENCE (4)
    Context TEXT NOT NULL,  -- Actual HCL line
    TemplateLine INTEGER NOT NULL,  -- Line number in source file where template function is defined
    ContextLine INTEGER NOT NULL,   -- Line number within HCL template string
    FOREIGN KEY (TemplateFunctionRefId) REFERENCES TemplateFunctions(TemplateFunctionRefId),
    FOREIGN KEY (ResourceRefId) REFERENCES Resources(ResourceRefId),
    FOREIGN KEY (ReferenceTypeId) REFERENCES ReferenceTypes(ReferenceTypeId)
);
```

**Example Data**:
```
DirectRefId | TemplateFunctionRefId | ResourceRefId | ReferenceTypeId | Context                                            | TemplateLine | ContextLine
1           | 2                     | 1             | 5               | resource "azurerm_resource_group" "test" {         | 200          | 6
2           | 2                     | 2             | 4               | resource_group_name = azurerm_resource_group.test.name | 200          | 15
3           | 3                     | 2             | 5               | resource "azurerm_virtual_network" "test" {        | 250          | 8
```

**Line Number Calculation**:
- `TemplateLine`: Line in source file where template function starts (from AST `template_line`)
- `ContextLine`: Line within the HCL template string (from AST `context_line`)
- Approximate source line: `TemplateLine + ContextLine` (may vary based on HCL string formatting)

**AST Extraction**:
AST walks template function body (already parsed), identifies:
- `resource "azurerm_xxx" "test" { ... }` -> RESOURCE_BLOCK (5)
- `azurerm_xxx.test.name` -> ATTRIBUTE_REFERENCE (4)

**Queries**:
```sql
-- Get all direct references to a resource
SELECT
    tf.FunctionName AS Template,
    f.FilePath,
    r.ResourceName,
    rt.ReferenceTypeName,
    dr.Context,
    dr.Line
FROM DirectResourceReferences dr
JOIN TemplateFunctions tf ON dr.TemplateFunctionRefId = tf.TemplateFunctionRefId
JOIN Files f ON tf.FileRefId = f.FileRefId
JOIN Resources r ON dr.ResourceRefId = r.ResourceRefId
JOIN ReferenceTypes rt ON dr.ReferenceTypeId = rt.ReferenceTypeId
WHERE r.ResourceName = 'azurerm_resource_group'
ORDER BY f.FilePath, dr.Line;

-- Distinguish between resource blocks and attribute references
SELECT
    COUNT(CASE WHEN rt.ReferenceTypeName = 'RESOURCE_BLOCK' THEN 1 END) AS ResourceBlocks,
    COUNT(CASE WHEN rt.ReferenceTypeName = 'ATTRIBUTE_REFERENCE' THEN 1 END) AS AttributeReferences
FROM DirectResourceReferences dr
JOIN ReferenceTypes rt ON dr.ReferenceTypeId = rt.ReferenceTypeId
JOIN Resources r ON dr.ResourceRefId = r.ResourceRefId
WHERE r.ResourceName = 'azurerm_resource_group';
```

---

#### 11. SequentialReferences
**Purpose**: Links sequential test entry points to their referenced test functions

Sequential references are the **DISCOVERY MECHANISM** that expands blast radius beyond direct file references. They capture `t.Run()` and `acceptance.RunTestsInSequence()` patterns that allow tests from completely different services to be included in the discovery.

```sql
CREATE TABLE SequentialReferences (
    SequentialRefId INTEGER PRIMARY KEY,
    EntryPointFunctionRefId INTEGER NOT NULL,
    ReferencedFunctionRefId INTEGER NOT NULL,
    SequentialGroup TEXT NOT NULL,
    SequentialKey TEXT NOT NULL,
    FOREIGN KEY (EntryPointFunctionRefId) REFERENCES TestFunctions(TestFunctionRefId),
    FOREIGN KEY (ReferencedFunctionRefId) REFERENCES TestFunctions(TestFunctionRefId)
);
```

**Example Data**:
```
SequentialRefId | EntryPointFunctionRefId | ReferencedFunctionRefId | SequentialGroup      | SequentialKey
1               | 1                       | 2                       | interactiveQuery     | securityProfile
2               | 1                       | 3                       | hadoop               | securityProfile
3               | 1                       | 4                       | hbase                | securityProfile
4               | 1                       | 5                       | kafka                | securityProfile
5               | 1                       | 6                       | spark                | securityProfile
```

**Foreign Keys**:
- `EntryPointFunctionRefId`: The main test function that orchestrates sequential execution
- `ReferencedFunctionRefId`: The actual test function being called sequentially

**Example Code Pattern**:
```go
// Entry point in hdinsight_cluster_resource_test.go
func TestAccHDInsightCluster_securityProfileSequential(t *testing.T) {
    acceptance.RunTestsInSequence(t, map[string]map[string]func(t *testing.T){
        "interactiveQuery": {"securityProfile": testAccHDInsightInteractiveQueryCluster_securityProfile},
        "hadoop":           {"securityProfile": testAccHDInsightHadoopCluster_securityProfile},
        "hbase":            {"securityProfile": testAccHDInsightHBaseCluster_securityProfile},
        "kafka":            {"securityProfile": testAccHDInsightKafkaCluster_securityProfile},
        "spark":            {"securityProfile": testAccHDInsightSparkCluster_securityProfile},
    })
}
```

**Why This Matters**:
Without SequentialReferences table, tests from different services would NEVER be discovered because:
- They're in different files
- They reference different resources
- The ONLY connection is the sequential test entry point

**AST Extraction**:
AST parses test function bodies looking for:
- `t.Run(name, func(t *testing.T) { ... })` patterns
- `acceptance.RunTestsInSequence(t, map[string]map[string]func(...))` patterns
- Extracts the nested map structure to get group/key pairs

**Queries**:
```sql
-- Find all sequential references for an entry point
SELECT
    tf_entry.FunctionName AS EntryPoint,
    tf_ref.FunctionName AS ReferencedFunction,
    sr.SequentialGroup,
    sr.SequentialKey
FROM SequentialReferences sr
JOIN TestFunctions tf_entry ON sr.EntryPointFunctionRefId = tf_entry.TestFunctionRefId
JOIN TestFunctions tf_ref ON sr.ReferencedFunctionRefId = tf_ref.TestFunctionRefId
WHERE sr.EntryPointFunctionRefId = 1
ORDER BY sr.SequentialGroup, sr.SequentialKey;
```

---

#### 12. TemplateReferences
**Purpose**: Track template function calls from test steps (legacy support for blast radius analysis)

```sql
CREATE TABLE TemplateReferences (
    TemplateReferenceRefId INTEGER PRIMARY KEY,
    TestFunctionRefId INTEGER NOT NULL,
    TestFunctionStepRefId INTEGER,
    StructRefId INTEGER NOT NULL,
    TemplateReference TEXT NOT NULL,
    TemplateVariable TEXT NOT NULL,
    TemplateMethod TEXT NOT NULL,
    FOREIGN KEY (TestFunctionRefId) REFERENCES TestFunctions(TestFunctionRefId),
    FOREIGN KEY (TestFunctionStepRefId) REFERENCES TestFunctionSteps(TestStepRefId),
    FOREIGN KEY (StructRefId) REFERENCES Structs(StructRefId)
);
```

**Example Data**:
```
TemplateReferenceRefId | TestFunctionRefId | TestFunctionStepRefId | StructRefId | TemplateReference | TemplateVariable | TemplateMethod
34                     | 1                 | 1                     | 1           | r.hadoop          | r                | hadoop
35                     | 1                 | 2                     | 1           | r.basic           | r                | basic
```

**Purpose**: This legacy table stores parsed template references in the format `variable.method` (e.g., `r.basic`, `r.template`). While TestFunctionSteps now stores direct FK references to TemplateFunctions, this table is maintained for backwards compatibility with existing blast radius analysis queries.

**Column Details**:
- **TemplateReference**: Full reference string (e.g., "r.hadoop", "r.basic")
- **TemplateVariable**: Variable name (e.g., "r")
- **TemplateMethod**: Method name (e.g., "hadoop", "basic")

---

#### 13. IndirectConfigReferences
**Purpose**: Track indirect resource references via template call chains (legacy support)

```sql
CREATE TABLE IndirectConfigReferences (
    IndirectRefId INTEGER PRIMARY KEY,
    TestFunctionStepRefId INTEGER NOT NULL,
    TemplateReferenceRefId INTEGER NOT NULL,
    SourceTemplateFunctionRefId INTEGER NOT NULL,
    ReferenceTypeId INTEGER,
    ServiceImpactTypeId INTEGER,
    FOREIGN KEY (TestFunctionStepRefId) REFERENCES TestFunctionSteps(TestStepRefId),
    FOREIGN KEY (TemplateReferenceRefId) REFERENCES TemplateReferences(TemplateReferenceRefId),
    FOREIGN KEY (SourceTemplateFunctionRefId) REFERENCES TemplateFunctions(TemplateFunctionRefId),
    FOREIGN KEY (ReferenceTypeId) REFERENCES ReferenceTypes(ReferenceTypeId)
);
```

**Example Data**:
```
IndirectRefId | TestFunctionStepRefId | TemplateReferenceRefId | SourceTemplateFunctionRefId | ReferenceTypeId | ServiceImpactTypeId
34            | 1                     | 34                     | 1                           | 3               | 15
35            | 2                     | 35                     | 2                           | 3               | 14
```

**Purpose**: This legacy table tracks when a test step calls a template function that references resources. While newer queries use TestFunctionSteps with TemplateFunctions directly, this table is maintained for backwards compatibility.

**Column Details**:
- **ServiceImpactTypeId**: Reference to ReferenceTypes (14 = SAME_SERVICE, 15 = CROSS_SERVICE)
- **ReferenceTypeId**: Type of reference (e.g., 3 = EMBEDDED_SELF)

---

#### 14. TemplateCallChain
**Purpose**: Track template-to-template function calls for cross-file reference detection

```sql
CREATE TABLE TemplateCallChain (
    TemplateCallChainRefId INTEGER PRIMARY KEY,
    SourceTemplateFunctionRefId INTEGER NOT NULL,
    TargetTemplateFunctionRefId INTEGER,
    ReferenceTypeId INTEGER NOT NULL,
    Line INTEGER NOT NULL,
    FOREIGN KEY (SourceTemplateFunctionRefId) REFERENCES TemplateFunctions(TemplateFunctionRefId),
    FOREIGN KEY (TargetTemplateFunctionRefId) REFERENCES TemplateFunctions(TemplateFunctionRefId),
    FOREIGN KEY (ReferenceTypeId) REFERENCES ReferenceTypes(ReferenceTypeId)
);
```

**Example Data**:
```
TemplateCallChainRefId | SourceTemplateFunctionRefId | TargetTemplateFunctionRefId | ReferenceTypeId | Line
1                      | 123                         | 456                         | 2               | 45
2                      | 124                         | 457                         | 2               | 67
3                      | 125                         | NULL                        | 10              | 89
```

**Purpose**: Tracks when template functions call other template functions (e.g., data source template calling resource template). This enables detection of cross-file references where templates bridge between test files.

**Example Use Case**:
- Data source test: `BackupProtectionPolicyFileShareDataSource.basic()`
- Calls resource template: `BackupProtectionPolicyFileShareResource.basicDaily()`
- Creates cross-file dependency chain for blast radius analysis

**Column Details**:
- **SourceTemplateFunctionRefId**: The template function making the call
- **TargetTemplateFunctionRefId**: The template function being called (NULL for EXTERNAL_REFERENCE)
- **ReferenceTypeId**: Type of call:
  - `1` (SELF_CONTAINED) - Same file, no external calls
  - `2` (CROSS_FILE) - Calls template in different file (both analyzed)
  - `3` (EMBEDDED_SELF) - Same file context
  - `10` (EXTERNAL_REFERENCE) - Calls unresolved/external target
- **Line**: Line number where the template call occurs

**AST Extraction**: Detected in `fmt.Sprintf()` arguments where template functions reference other template functions by name (e.g., `r.basicDaily()` within template code).

**Query Performance**: Pre-indexed lookup by `SourceTemplateFunctionRefId` enables O(1) retrieval during blast radius analysis.

---

## Database Modes - Query Patterns

### Direct Mode
**Purpose**: Find test files with DIRECT resource references in template code

**Query**:
```sql
SELECT DISTINCT
    f.FilePath,
    r.ResourceName,
    rt.ReferenceTypeName,
    dr.Line,
    dr.Context
FROM DirectResourceReferences dr
JOIN TemplateFunctions tf ON dr.TemplateFunctionRefId = tf.TemplateFunctionRefId
JOIN Files f ON tf.FileRefId = f.FileRefId
JOIN Resources r ON dr.ResourceRefId = r.ResourceRefId
JOIN ReferenceTypes rt ON dr.ReferenceTypeId = rt.ReferenceTypeId
WHERE r.ResourceName = 'azurerm_resource_group'
ORDER BY f.FilePath, dr.Line;
```

**Output Example**:
```
FilePath                                                      | ResourceName            | ReferenceTypeName      | Line | Context
internal/services/network/network_manager_resource_test.go    | azurerm_resource_group  | RESOURCE_BLOCK         | 245  | resource "azurerm_resource_group" "test" {
internal/services/network/virtual_network_resource_test.go    | azurerm_resource_group  | ATTRIBUTE_REFERENCE    | 267  | resource_group_name = azurerm_resource_group.test.name
```

---

### Indirect Mode
**Purpose**: Find test files that INDIRECTLY reference resources through template call chains

**Query**:
```sql
SELECT DISTINCT
    f.FilePath,
    tf_test.FunctionName AS TestFunction,
    r.ResourceName,
    tcc.ChainDepth,
    tf_template.FunctionName AS TemplateContainingResource
FROM TestSteps ts
JOIN TestFunctions tf_test ON ts.TestFunctionRefId = tf_test.TestFunctionRefId
JOIN Files f ON tf_test.FileRefId = f.FileRefId
JOIN TemplateCallChain tcc ON ts.TestStepRefId = tcc.TestStepRefId
JOIN TemplateChainResources tcr ON tcc.ChainRefId = tcr.ChainRefId
JOIN Resources r ON tcr.ResourceRefId = r.ResourceRefId
JOIN TemplateFunctions tf_template ON tcc.TargetTemplateFunctionRefId = tf_template.TemplateFunctionRefId
WHERE r.ResourceName = 'azurerm_resource_group'
ORDER BY f.FilePath, tcc.ChainDepth;
```

**Output Example**:
```
FilePath                                                      | TestFunction                        | ResourceName            | ChainDepth | TemplateContainingResource
internal/services/network/network_manager_resource_test.go    | TestAccNetworkManager_basic         | azurerm_resource_group  | 1          | template
internal/services/compute/virtual_machine_resource_test.go    | TestAccVirtualMachine_basic         | azurerm_resource_group  | 2          | commonInfra
```

---

### All References Mode (Combined)
**Purpose**: Find ALL test files (direct + indirect) that reference a resource

**Query**:
```sql
-- Direct references
SELECT DISTINCT f.FilePath, 'DIRECT' AS ReferenceMode, 0 AS ChainDepth
FROM DirectResourceReferences dr
JOIN TemplateFunctions tf ON dr.TemplateFunctionRefId = tf.TemplateFunctionRefId
JOIN Files f ON tf.FileRefId = f.FileRefId
JOIN Resources r ON dr.ResourceRefId = r.ResourceRefId
WHERE r.ResourceName = 'azurerm_resource_group'

UNION

-- Indirect references
SELECT DISTINCT f.FilePath, 'INDIRECT' AS ReferenceMode, tcc.ChainDepth
FROM TestSteps ts
JOIN TestFunctions tf_test ON ts.TestFunctionRefId = tf_test.TestFunctionRefId
JOIN Files f ON tf_test.FileRefId = f.FileRefId
JOIN TemplateCallChain tcc ON ts.TestStepRefId = tcc.TestStepRefId
JOIN TemplateChainResources tcr ON tcc.ChainRefId = tcr.ChainRefId
JOIN Resources r ON tcr.ResourceRefId = r.ResourceRefId
WHERE r.ResourceName = 'azurerm_resource_group'

ORDER BY FilePath, ChainDepth;
```

---

## Database Schema Statistics

### Typical Data Volume (azurerm provider)

| Table | Typical Row Count | Description |
|-------|------------------|-------------|
| Resources | 1-5 | Resources being analyzed (current run) |
| ResourceRegistrations | ~1,038 | Master mapping of ALL resources to services |
| Services | ~131 | Azure service categories |
| Files | ~2,700 | Test files analyzed |
| Structs | ~2,700 | Go struct definitions |
| ReferenceTypes | 15 | Relationship classifications (static) |
| TestFunctions | ~2,700 | Test function metadata |
| TemplateFunctions | ~5,000 | Template function metadata (no bodies) |
| TestFunctionSteps | ~3,500 | Test step execution records |
| DirectResourceReferences | ~50,000 | Direct HCL resource references |
| SequentialReferences | ~100 | Sequential test patterns |
| TemplateReferences | ~3,500 | Template call references (legacy) |
| IndirectConfigReferences | ~5,000 | Indirect references (legacy) |
| TemplateCallChain | ~18 | Template-to-template calls |
| **TOTAL** | **~71,000** | Complete database size |

**Storage Characteristics**:
- Compact: ~71K total rows for complete azurerm provider analysis
- Efficient: Metadata-only storage, no function bodies
- Fast: In-memory hashtable-based queries with O(1) lookups
- Normalized: All repeating strings stored once with FK references
- Optimized: ResourceRegistrations import ~1.7 seconds (12x faster than naive approach)

---

### Normalization Benefits

| Data Type | Storage Method | Benefit |
|-----------|---------------|---------|
| Service Names | ServiceRefId FK | Store "network" once, reference by integer thousands of times |
| Struct Names | StructRefId FK | Referential integrity prevents invalid struct references |
| Resource Names | ResourceRefId FK | Consistent resource identification across all tables |
| Resource Registrations | ResourceRegistrationRefId FK | Master mapping of resources to owning services |
| Template Names | TemplateFunctionRefId FK | Direct relationships, no string matching needed |
| Reference Types | ReferenceTypeId FK | Efficient classification with O(1) lookups |

**Advantages**:
- **Storage**: Integer FKs use less space than repeated strings
- **Integrity**: Can't reference non-existent entities
- **Performance**: Integer comparisons faster than string comparisons
- **Consistency**: Single source of truth for all lookup values
- **Cross-service analysis**: ResourceRegistrations enables true dependency tracking

---

### AST Analysis Capabilities

| Feature | Implementation |
|---------|---------------|
| **Function Detection** | Parse syntax tree, identify return types and receivers |
| **Call Resolution** | Recursive graph walk resolves complete call chains |
| **Service Boundaries** | Package structure analysis determines service relationships |
| **Template Tracking** | Semantic analysis tracks all template calls (same-file + cross-file) |
| **Reference Classification** | Determined during parsing (EMBEDDED_SELF, CROSS_FILE, etc.) |
| **Sequential Patterns** | Identifies `t.Run()` and `RunTestsInSequence()` patterns |
| **Resource References** | HCL parsing identifies resource blocks and attribute references |
| **Accuracy** | 100% semantic accuracy vs pattern matching |
| **Processing** | Single-pass analysis with pre-resolved relationships |

---

## Usage Examples

### Multi-Resource Analysis
```powershell
.\terracorder.ps1 -ResourceName "azurerm_virtual_network,azurerm_subnet,azurerm_network_security_group"
```

**Query**:
```sql
SELECT DISTINCT f.FilePath
FROM DirectResourceReferences dr
JOIN TemplateFunctions tf ON dr.TemplateFunctionRefId = tf.TemplateFunctionRefId
JOIN Files f ON tf.FileRefId = f.FileRefId
JOIN Resources r ON dr.ResourceRefId = r.ResourceRefId
WHERE r.ResourceName IN ('azurerm_virtual_network', 'azurerm_subnet', 'azurerm_network_security_group')
```

---

### PR-Driven Test Discovery
**Use Case**: GitHub PR modifies `azurerm_virtual_network` resource, need to know which tests to run

**Implementation**:
1. Parse PR diff -> extract changed resource names
2. Query database for all tests referencing those resources
3. Output test file list for CI/CD pipeline

**Query**:
```sql
-- Direct + Indirect references for changed resources
SELECT DISTINCT
    f.FilePath,
    r.ResourceName,
    CASE
        WHEN dr.DirectRefId IS NOT NULL THEN 'DIRECT'
        ELSE 'INDIRECT'
    END AS ImpactType
FROM Resources r
LEFT JOIN DirectResourceReferences dr ON r.ResourceRefId = dr.ResourceRefId
LEFT JOIN TemplateFunctions tf ON dr.TemplateFunctionRefId = tf.TemplateFunctionRefId
LEFT JOIN Files f ON tf.FileRefId = f.FileRefId
LEFT JOIN TemplateChainResources tcr ON r.ResourceRefId = tcr.ResourceRefId
LEFT JOIN TemplateCallChain tcc ON tcr.ChainRefId = tcc.ChainRefId
LEFT JOIN TestSteps ts ON tcc.TestStepRefId = ts.TestStepRefId
LEFT JOIN TestFunctions tft ON ts.TestFunctionRefId = tft.TestFunctionRefId
LEFT JOIN Files f2 ON tft.FileRefId = f2.FileRefId
WHERE r.ResourceName IN (
    SELECT ResourceName FROM @pr_changed_resources
)
ORDER BY ImpactType, FilePath;
```

---

### Impact Analysis
**Use Case**: Show all dependencies when changing a template function

**Query**:
```sql
-- Find all tests that use a template (direct or via chain)
SELECT DISTINCT
    tf_test.FunctionName AS TestFunction,
    f.FilePath,
    tcc.ChainDepth,
    CASE WHEN tcc.ChainDepth = 0 THEN 'DIRECT' ELSE 'INDIRECT' END AS UsageType
FROM TemplateFunctions tf_template
LEFT JOIN TestSteps ts ON tf_template.TemplateFunctionRefId = ts.TemplateFunctionRefId
LEFT JOIN TemplateCallChain tcc ON tf_template.TemplateFunctionRefId = tcc.TargetTemplateFunctionRefId
LEFT JOIN TestSteps ts2 ON tcc.TestStepRefId = ts2.TestStepRefId
LEFT JOIN TestFunctions tf_test ON COALESCE(ts.TestFunctionRefId, ts2.TestFunctionRefId) = tf_test.TestFunctionRefId
LEFT JOIN Files f ON tf_test.FileRefId = f.FileRefId
WHERE tf_template.FunctionName = 'commonInfra'
ORDER BY tcc.ChainDepth;
```

---

## Summary

TerraCorder's AST-based database schema provides:

**Architecture**:
- ✅ **Fully normalized design** - All repeating strings in lookup tables with FK references
- ✅ **Metadata-only storage** - No source code duplication (source already in Git)
- ✅ **Pre-resolved relationships** - AST semantic analysis resolves all relationships upfront
- ✅ **13 normalized tables** - 6 lookup tables + 7 data tables

**Performance**:
- ✅ **Compact database** - ~71K total rows for complete azurerm provider
- ✅ **Fast queries** - O(1) hashtable lookups with integer FK joins
- ✅ **Single-pass analysis** - No iterative resolution needed
- ✅ **100% semantic accuracy** - Syntax tree analysis eliminates pattern matching errors
- ✅ **Optimized imports** - ResourceRegistrations import in 1.7s (12x speedup)

**Capabilities**:
- ✅ **Direct references** - Resource blocks and attribute references in HCL templates
- ✅ **Indirect references** - Template call chains and transitive dependencies
- ✅ **Sequential tests** - Cross-service test discovery via `RunTestsInSequence` patterns
- ✅ **Service boundaries** - SAME_SERVICE vs CROSS_SERVICE impact analysis
- ✅ **Multi-resource support** - Analyze multiple resources in single run
- ✅ **Resource ownership** - Master mapping of all resources to owning services

**Modes**:
- ✅ **Discovery Mode** - AST analysis creates database from repository
- ✅ **Database Mode** - Fast read-only queries on pre-analyzed data

**New Additions**:
- ✅ **ResourceRegistrations table** - Maps all 1,038 resources to 131 owning services
- ✅ **Resources.ResourceRegistrationRefId** - FK linking analyzed resources to master registrations
- ✅ **Cross-service tracking** - Foundation for identifying when tests depend on resources from other services

**Status**: Production-ready implementation with complete AST-based semantic analysis and resource ownership tracking
