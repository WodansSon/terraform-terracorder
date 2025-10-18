# TerraCorder

*"Analyzing Terraform test matrix... Building comprehensive dependency database!"*

A high-performance **AST-based semantic analysis tool** that identifies all tests needed when modifying Azure resources in the Terraform AzureRM provider. TerraCorder uses a Go AST (Abstract Syntax Tree) analyzer to perform deep syntactic parsing of test files, building a complete relational database of test dependencies with direct resource usage, template references, and sequential test patterns tracked through full foreign key relationships.

**Two powerful modes:** Discovery Mode for initial AST analysis and database building, and Database Mode for fast querying of previously analyzed data!

[![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Go](https://img.shields.io/badge/Go-00ADD8?style=flat&logo=go&logoColor=white)](https://go.dev/)
[![Terraform](https://img.shields.io/badge/Terraform-623CE4?style=flat&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Azure](https://img.shields.io/badge/Azure-0089D0?style=flat&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/release/WodansSon/terraform-terracorder.svg)](https://github.com/WodansSon/terraform-terracorder/releases)

## Features

### Discovery Mode (Initial Analysis)
- **AST Semantic Analysis**: Go-based Abstract Syntax Tree parser performs deep syntactic analysis (not regex pattern matching)
- **Relational Database Architecture**: Full normalized database with foreign key relationships tracking all test dependencies
- **Single-Pass AST Processing**: Efficient Replicode extracts all metadata in one pass per file
- **Comprehensive Dependency Detection**: Tracks direct resource usage, template references, and sequential test patterns through AST call graph analysis
- **Database Export**: Complete CSV exports of all 14 database tables for advanced analysis
- **Resource Ownership Tracking**: Master mapping of all Terraform resources to their owning Azure services
- **Visual Progress Tracking**: Real-time progress with file-by-file scanning feedback during sequential discovery
- **Smart Test Command Generation**: Automatically generates optimized `go test` commands by service
- **Sequential Test Support**: Detects and tracks `acceptance.RunTestsInSequence` patterns via AST parsing
- **Template Function Analysis**: Maps complete template dependency chains across files through AST call graph resolution

### Database Mode (Query Existing Data)
- **Fast Query Operations**: Analyze previously discovered data in seconds, not minutes
- **No File Scanning**: Load from CSV exports instantly without repository access
- **Default Statistics View**: Run without flags to see available analysis options
- **Multiple Query Types**: Direct references, indirect references (includes templates and sequential patterns), or all combined
- **Visual Blast Radius Trees**: Rich Unicode tree diagrams mapping complete dependency chains
  - Sequential test entry points with nested groups and keys
  - Color-coded output with automatic VS Code theme detection
  - Professional box-drawing characters for clear hierarchy visualization
- **Data Exploration**: Perfect for analysis, reporting, and understanding test relationships
- **Syntax Highlighting**: Color-coded output with VS Code theme detection for enhanced readability (requires terminal ANSI support)
- **Cross-Platform**: Works on Windows, Linux, and macOS with PowerShell Core 7.0+

## Quick Start

### Download Release Package (Recommended)
Download the latest release package which includes everything you need:

```powershell
# Download and extract (Windows)
Invoke-WebRequest -Uri "https://github.com/WodansSon/terraform-terracorder/releases/latest/download/terracorder-3.0.0-windows.zip" -OutFile "terracorder.zip"
Expand-Archive -Path "terracorder.zip" -DestinationPath "C:\TerraCorder"
cd C:\TerraCorder

# IMPORTANT: Unblock downloaded files (Windows only)
Get-ChildItem -Path . -Recurse | Unblock-File

# Run Discovery Mode (initial analysis)
.\scripts\terracorder.ps1 -ResourceName "azurerm_virtual_network" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"
```

**Linux/macOS:**
```bash
# Download and extract
curl -L -o terracorder.tar.gz https://github.com/WodansSon/terraform-terracorder/releases/latest/download/terracorder-3.0.0-linux.tar.gz
tar -xzf terracorder.tar.gz -C ~/terracorder
cd ~/terracorder

# Make Replicode executable
chmod +x tools/replicode/replicode

# Run Discovery Mode
pwsh ./scripts/terracorder.ps1 -ResourceName "azurerm_virtual_network" -RepositoryDirectory "/path/to/terraform-provider-azurerm"
```

### Clone from Git (Alternative)
If you prefer to clone the repository:
```powershell
# Clone the repository
git clone https://github.com/WodansSon/terraform-terracorder.git
cd terraform-terracorder

# Run Discovery Mode (initial analysis)
.\scripts\terracorder.ps1 -ResourceName "azurerm_virtual_network" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"

# Run Database Mode (query existing data)
.\scripts\terracorder.ps1 -DatabaseDirectory ".\output" -ShowDirectReferences

# Run Database Mode (view available options)
.\scripts\terracorder.ps1 -DatabaseDirectory ".\output"

# Specify custom export directory
.\scripts\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm" -ExportDirectory "C:\analysis\output"
```

### Manual Download
If you prefer not to clone, you can download the required files manually:
```powershell
# Create directory structure
New-Item -Path "terracorder" -ItemType Directory
New-Item -Path "terracorder\modules" -ItemType Directory
New-Item -Path "terracorder\scripts" -ItemType Directory
New-Item -Path "terracorder\tools" -ItemType Directory
New-Item -Path "terracorder\tools\replicode" -ItemType Directory

# Download main script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/WodansSon/terraform-terracorder/main/scripts/terracorder.ps1" -OutFile "terracorder\scripts\terracorder.ps1"

# Download required modules
$modules = @(
    "Database.psm1",
    "DatabaseMode.psm1",
    "FileDiscovery.psm1",
    "ASTImport.psm1",
    "Prerequisites.psm1",
    "UI.psm1"
)

foreach ($module in $modules) {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/WodansSon/terraform-terracorder/main/modules/$module" -OutFile "terracorder\modules\$module"
}

# Download Replicode AST analyzer (choose based on your OS)
# Windows
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/WodansSon/terraform-terracorder/main/tools/replicode/replicode.exe" -OutFile "terracorder\tools\replicode\replicode.exe"

# Linux/macOS (uncomment the line below and comment out Windows line above)
# Invoke-WebRequest -Uri "https://raw.githubusercontent.com/WodansSon/terraform-terracorder/main/tools/replicode/replicode" -OutFile "terracorder/tools/replicode/replicode"
# chmod +x terracorder/tools/replicode/replicode

# Download Replicode source files (optional - for building from source)
$replicodeFiles = @("main.go", "patterns.go", "go.mod", "GNUMakefile", "Build.ps1", "README.md")
foreach ($file in $replicodeFiles) {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/WodansSon/terraform-terracorder/main/tools/replicode/$file" -OutFile "terracorder\tools\replicode\$file"
}

# Run TerraCorder
cd terracorder
.\scripts\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"
```

## Usage Examples

### Discovery Mode - Initial Resource Analysis
```powershell
# Analyze all tests that use azurerm_subnet (creates CSV database)
.\scripts\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"

# Use custom export directory for database
.\scripts\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "C:\terraform-provider-azurerm" -ExportDirectory "C:\analysis\subnet"
```

### Database Mode - Query Existing Data with Visual Blast Radius Analysis
```powershell
# View available analysis options (default - no flags required)
.\scripts\terracorder.ps1 -DatabaseDirectory "output"

# Show direct resource references (fast, no file scanning)
.\scripts\terracorder.ps1 -DatabaseDirectory "output" -ShowDirectReferences

# Show indirect references with visual tree diagrams (includes templates and sequential patterns)
.\scripts\terracorder.ps1 -DatabaseDirectory "output" -ShowIndirectReferences

# Use custom database location
.\scripts\terracorder.ps1 -DatabaseDirectory "C:\analysis\subnet" -ShowIndirectReferences
```

### Visual Blast Radius Trees
Database Mode includes **rich visual tree diagrams** that map complete dependency chains:
- **Unicode box-drawing**: Professional tree structure with proper connectors (│, ├, └, ┬, ►, ─)
- **Color-coded output**: Automatic VS Code theme detection for enhanced readability
- **Sequential test visualization**: Shows entry points, groups, keys, and referenced functions
- **Template dependency mapping**: Displays indirect configuration chains across files

#### Understanding Reference Type Labels

When viewing indirect references, TerraCorder uses **visual notation and minimal suffixes** for intuitive understanding:

**Visual Indicators:**
- **Same file reference**: Shows line number only (e.g., `Config: r.basic`)
  - Line number indicates internal reference within the same test file
  - No arrow needed - simplest case

- **Cross-file reference**: Shows `calls` notation (e.g., `Config: r.method calls r.template`)
  - Indicates the template calls another template in a different file
  - Clear semantic meaning: one function calls another

- **Line numbers**: Function definitions show line numbers (e.g., `Function: 2276: testAccExample_basic`)
  - Helps locate the exact function in source files
  - Missing line numbers indicate external references

**Explicit Suffixes (Comment Style):**

Only architecturally significant information is shown as comment-style suffixes:

- **// EXTERNAL_REFERENCE**: Target function is **outside the current analysis scope**
  - Example: `Config: r.template calls // EXTERNAL_REFERENCE`
  - Common in sequential tests referencing functions from other resource test files
  - Marked as external since the full definition isn't in the current database
  - Indicates you may need to analyze additional resources

- **// CROSS_SERVICE**: Dependency crosses **Azure service boundaries**
  - Example: Config: r.basic // CROSS_SERVICE: \`monitor\` calls \`network\`
  - The test is in one service but references a resource owned by another service
  - Shows which service calls which for clear cross-team visibility
  - Important for understanding cross-team dependencies and coordination needs
  - Can appear with same-file or cross-file references
  - Gracefully shows "UNKNOWN" if service information unavailable

**Why This Design:**
- **Visual clarity**: `calls` notation and line numbers convey structure without redundant labels
- **Focus on what matters**: Only show explicit labels for architecturally significant information
- **Intuitive**: Comment-style `//` syntax is familiar to developers
- **Scannable**: Easy to quickly identify cross-service dependencies (highest risk)

**Impact Assessment:**
- Same-file references are **safest** to modify (isolated, single file impact)
- Cross-file references require **checking intermediate templates** (multi-file impact)
- Cross-service references may require **coordination with other teams** (cross-boundary impact)
- External references indicate you may need to **analyze additional resources** for complete picture

### Database Exports
```powershell
# TerraCorder automatically exports 14 CSV tables to the output directory:
# - DirectResourceReferences.csv   : Direct resource usage
# - Files.csv                      : All test files analyzed
# - IndirectConfigReferences.csv   : Indirect template dependencies
# - ReferenceTypes.csv             : Reference type lookup table
# - ResourceRegistrations.csv      : Master mapping of ALL resources to owning services (~1,038 resources)
# - Resources.csv                  : Terraform resources being analyzed (with FK to ResourceRegistrations)
# - SequentialReferences.csv       : Sequential test relationships
# - Services.csv                   : All Azure services discovered
# - Structs.csv                    : All test resource structs found
# - TemplateCallChain.csv          : Template-to-template function calls
# - TemplateFunctions.csv          : Template/configuration methods
# - TemplateReferences.csv         : Template method calls in tests
# - TestFunctions.csv              : All test functions discovered
# - TestFunctionSteps.csv          : Individual test steps and configurations

# Plus: go_test_commands.txt       : Generated test commands for CI/CD

# Default location: ./output/*.csv
# Access via: -ExportDirectory parameter
```

### CI/CD Pipeline Integration
```powershell
# Use the generated go_test_commands.txt for CI/CD
$testFile = "C:\terracorder\output\go_test_commands.txt"
Get-Content $testFile | Where-Object { $_ -match "^  go test" } | ForEach-Object {
    Invoke-Expression $_
}

# Or parse the CSV exports for custom test execution logic
$tests = Import-Csv "C:\terracorder\output\TestFunctions.csv"
$subnetTests = $tests | Where-Object { $_.FunctionName -like "*Subnet*" }
```

## Real-World Performance

TerraCorder uses AST semantic analysis for comprehensive dependency detection:

### Example: `azurerm_resource_group` Analysis
```
Database Initialization           : 1,045 resource registrations in 1,700 ms
Phase 1: File Discovery           : 2,672 files found, 1,262 relevant in 3,921 ms
Phase 2: AST Analysis & DB Import : 8,496 tests, 9,157 configs, 24,773 refs in 59,125 ms
Phase 3: CSV Export               : 14 tables exported in 3,599 ms
Phase 4: Test Command Generation  : 127 services in 1,983 ms

Total Execution Time              : 70.9 seconds
```

### Database Size: `azurerm_kubernetes_cluster`
```
Services                 : 5 services
Files                    : 22 files
Structs                  : 16 structs
TestFunctions            : 320 test functions
TestFunctionSteps        : 500 test steps
TemplateFunctions        : 332 template functions
TemplateReferences       : 500 template calls
DirectResourceReferences : 428 direct references
IndirectConfigReferences : 500 indirect references
SequentialReferences     : 0 sequential links
TemplateCallChain        : 102 template-to-template calls
ReferenceTypes           : 15 reference types
ResourceRegistrations    : 1,045 resource-to-service mappings
```

## How It Works

### Discovery Mode - 3-Phase AST-Driven Analysis

TerraCorder uses a **streamlined 3-phase approach** with AST (Abstract Syntax Tree) semantic analysis:

#### Phase 1: File Discovery and Filtering
- Discovers all `*_test.go` and `*_resource.go` files in `internal/services/`
- Filters to files containing the target resource name
- Uses fast string matching for initial filtering
- Identifies sequential test patterns and additional test files

#### Phase 2: AST Analysis and Database Import
- **Replicode** performs deep syntactic parsing of all discovered files
- Extracts complete metadata through semantic analysis (not regex pattern matching):
  - Test function signatures and structures
  - Resource struct declarations
  - Template function definitions
  - Function call graphs and dependencies
  - Direct and indirect resource references
  - Sequential test relationships
- Imports AST metadata into normalized database tables
- Creates all records: Services, Files, Structs, TestFunctions, TemplateReferences, etc.
- Establishes all foreign key relationships
- **Creates external stub records** for cross-resource sequential references
  - Maintains referential integrity when sequential tests reference functions from other resources
  - Stubs marked with `Line = 0`, `FunctionBody = "EXTERNAL_REFERENCE"`, and `ReferenceTypeId = 10`
  - Ensures complete sequential test structure is visible in blast radius analysis
- Generates optimized `go test` commands grouped by Azure service
- Single-pass processing with real-time progress tracking

#### Phase 3: CSV Export
- Exports all 14 database tables to CSV files
- Maintains proper column headers even for empty tables
- Provides comprehensive dataset for analysis and reporting
- Exports `go_test_commands.txt` file for CI/CD integration

### Database Mode - Fast Query Operations

Database Mode loads previously exported CSV files for instant analysis:

#### Database Initialization
- Imports all 14 CSV tables into in-memory database
- Rebuilds indexes and foreign key relationships
- Displays comprehensive statistics (typically 5-10 seconds)

#### Query Operations (All Optional)
- **No flags (default)**: Display available analysis options with examples
- **ShowDirectReferences**: Display all direct resource usage and attribute references
- **ShowIndirectReferences**: Display template dependencies and sequential test chains with **visual tree diagrams**
  - Sequential test entry points organized by groups and keys
  - Color-coded tree structure
  - External reference markers for cross-resource dependencies

#### Benefits
- **Speed**: Query operations complete in seconds vs minutes for Discovery Mode
- **Portability**: Share CSV database without needing the source repository
- **Analysis**: Multiple queries without re-scanning files
- **Reporting**: Generate reports from structured data
- **Progressive Discovery**: View options first, then choose your analysis

### Replicode - Go-Based Semantic Parser

TerraCorder uses **Replicode**, a Go AST (Abstract Syntax Tree) analyzer for accurate semantic analysis:

#### Why AST Over Regex?
- **100% Accuracy**: AST parsing understands Go syntax semantically, not just text patterns
- **No False Positives**: Distinguishes between function definitions, calls, and comments
- **Call Graph Resolution**: Tracks actual function call relationships through syntax trees
- **Single-Pass Efficiency**: Extracts all metadata in one pass per file
- **Reliable Detection**: Identifies test functions, structs, templates, and dependencies accurately

#### How It Works
1. **AST Parsing**: Go's `go/parser` package builds complete syntax trees
2. **Semantic Analysis**: Walks AST nodes to identify:
   - Function declarations (`func (r ResourceType) FunctionName()`)
   - Struct definitions (`type ResourceType struct`)
   - Function calls and call graphs
   - Test function patterns (`func TestAcc*`)
   - Template function relationships
3. **Metadata Export**: Outputs structured JSON with all discovered elements
4. **PowerShell Import**: ASTImport.psm1 loads JSON into normalized database

#### Location
- Pre-built binary: `tools/replicode/replicode` (Linux/macOS) or `replicode.exe` (Windows)
- Source code: `tools/replicode/*.go`
- Build instructions: `tools/replicode/README.md`

**Note**: Replicode is automatically invoked by TerraCorder during Discovery Mode Phase 2. You don't need to run it manually unless you're debugging or developing.

## Database Schema

TerraCorder uses a **normalized relational database** with 14 tables:

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `Resources` | Terraform resources being analyzed | ResourceRefId (PK), ResourceName, ResourceRegistrationRefId (FK) |
| `ResourceRegistrations` | Master mapping of ALL resources to owning services | ResourceRegistrationRefId (PK), ServiceRefId (FK), ResourceName |
| `Services` | Azure services | ServiceRefId (PK), Name |
| `Files` | Test files | FileRefId (PK), FilePath, ServiceRefId (FK) |
| `Structs` | Test resource structs | StructRefId (PK), StructName, FileRefId (FK) |
| `TestFunctions` | Test functions | TestFunctionRefId (PK), FunctionName, FileRefId (FK), StructRefId (FK) |
| `TestFunctionSteps` | Test steps/configs | TestFunctionStepRefId (PK), TestFunctionRefId (FK), ReferenceTypeId (FK) |
| `TemplateFunctions` | Template methods | TemplateFunctionRefId (PK), TemplateFunctionName, StructRefId (FK) |
| `TemplateReferences` | Template calls | TemplateReferenceRefId (PK), TestFunctionRefId (FK), TemplateReference |
| `DirectResourceReferences` | Direct usage | DirectRefId (PK), TemplateFunctionRefId (FK), ReferenceTypeId (FK) |
| `IndirectConfigReferences` | Template deps | IndirectRefId (PK), TemplateReferenceRefId (FK), SourceTemplateFunctionRefId (FK) |
| `SequentialReferences` | Sequential links | SequentialRefId (PK), EntryPointFunctionRefId (FK), ReferencedFunctionRefId (FK) |
| `TemplateCallChain` | Template→template calls | TemplateCallChainRefId (PK), SourceTemplateFunctionRefId (FK), TargetTemplateFunctionRefId (FK), ReferenceTypeId (FK) |
| `ReferenceTypes` | Reference lookup | ReferenceTypeId (PK), ReferenceTypeName |

**Note**: The `Resources` table contains the specific resources being analyzed in the current run (1-N rows), with a foreign key to `ResourceRegistrations` which contains the master mapping of ALL ~1,038 resources to their owning services. This separation enables resource ownership tracking for cross-service dependency analysis.

## Sample Output

### Console Output
```
============================================================
 Terra-Corder v3.0.0 - Database Initialization
============================================================
 [INFO] Creating Database Tables
 [INFO] Imported 1045 Resource Registrations
 [INFO] Populating ReferenceTypes Table
Database Initialization: Completed in 1700 ms

Phase 1: File Discovery and Filtering...
 [INFO] Found 2672 Test Files
 [INFO] Filtered 1008 Irrelevant Files, 1664 Test Files To Analyze
 [INFO] Processing 1664 Files With 8 Threads
 [INFO] Found 1262 Test Files Containing The Resource
Phase 1: Completed in 3921 ms

Phase 2: Replicode Analysis and Database Import...
 [INFO] Processing 1262 Test Files With Replicode...
 [INFO] Processing Files 1262 of 1262 (100%) - Complete
 [INFO] Importing Replicode Data Into Database...
 [INFO] Replicode Import Complete: 1262/1262 Files Processed Successfully
 [INFO] Scanning For Additional Sequential Test Entry Points...
 [INFO] Found 2 Additional Sequential Test Files
 [INFO] Replicode Analysis Summary:
 [INFO]   Registry  : 1045 Resource-to-Service Mappings
 [INFO]   Structure : 131 Services, 1264 Files, 1199 Structs
 [INFO]   Functions : 8496 Tests, 9157 Configuration
 [INFO]   References: 12561 Steps, 24773 Direct, 4097 Calls
Phase 2: Completed in 59125 ms

Phase 3: Exporting Database to CSV...
 [INFO] Exported: 14 Tables
Phase 3: Completed in 3599 ms

Phase 4: Generating Go Test Commands...
 [INFO] Generated Test Commands For 127 Services
 [INFO] Exported: go_test_commands.txt
Phase 4: Completed in 1983 ms

============================================================
 Required Acceptance Test Execution:
============================================================

  Service Name: resource
    go test -timeout 30000s -v ./internal/services/resource -run "TestAccDataSourceAzureRMResourceGroup_|TestAccResourceGroup_|..."

Total Execution Time: 70948 ms (70.9 seconds)
```

### Visual Blast Radius Analysis (Database Mode)

Database Mode provides **rich visual tree diagrams** for dependency analysis:

#### Indirect References with Visual Tree Diagrams
```
File: ./internal/services/cosmos/cosmosdb_cassandra_resource_test.go
   7 Sequential Key References

   ============================================================
     Sequential Call Chain:
   ============================================================

      Entry Point: 12: TestAccCassandraSequential
       │
       ├──┬─► Group: "cluster"
       │  ├─┬─► Key     : "basic"
       │  │ └─► Function: testAccCassandraCluster_basic : EXTERNAL_REFERENCE
       │  │
       │  ├─┬─► Key     : "complete"
       │  │ └─► Function: testAccCassandraCluster_complete : EXTERNAL_REFERENCE
       │  │
       │  ├─┬─► Key     : "requiresImport"
       │  │ └─► Function: testAccCassandraCluster_requiresImport : EXTERNAL_REFERENCE
       │  │
       │  └─┬─► Key     : "update"
       │    └─► Function: testAccCassandraCluster_update : EXTERNAL_REFERENCE
       │
       └──┬─► Group: "dataCenter"
          ├─┬─► Key     : "basic"
          │ └─► Function: 21: testAccCassandraDatacenter_basic
          │
          ├─┬─► Key     : "update"
          │ └─► Function: 38: testAccCassandraDatacenter_update
          │
          └─┬─► Key     : "updateSku"
            └─► Function: 60: testAccCassandraDatacenter_updateSku
```

#### Color Coding (Terminal ANSI Support Required)
- **Entry Points**: Highlighted function names
- **Sequential Groups**: Colored group names (e.g., "dataSource", "keys", "resource")
- **Line Numbers**: Distinct color for quick reference
- **External References**: Marked to show cross-resource dependencies
- **Color Theme**: Uses the VS Code dark theme+

**Note**: Visual tree diagrams require terminal ANSI color support. Works best in:
- Windows Terminal
- VS Code integrated terminal
- PowerShell Core 7.0+ on Linux/macOS

### CSV Export Files (in output directory)
```
Resources.csv                - Terraform resources being analyzed (with FK to ResourceRegistrations)
ResourceRegistrations.csv    - Master mapping of ALL resources to owning services (~1,038 resources)
Services.csv                 - All Azure services
Files.csv                    - All test files
Structs.csv                  - Test resource structs
TestFunctions.csv            - Test function records
TestFunctionSteps.csv        - Individual test steps
TemplateFunctions.csv        - Template methods
TemplateReferences.csv       - Template method calls
DirectResourceReferences.csv - Direct resource usage
IndirectConfigReferences.csv - Template dependencies
SequentialReferences.csv     - Sequential test links
TemplateCallChain.csv        - Template-to-template function calls
ReferenceTypes.csv           - Reference type lookup
go_test_commands.txt         - Generated test commands
```

## Parameters

### Discovery Mode Parameters
| Parameter | Required | Description | Default | Example |
|-----------|----------|-------------|---------|---------|
| `-ResourceName` | **Yes** | Azure resource name to analyze | - | `"azurerm_subnet"` |
| `-RepositoryDirectory` | **Yes** | Path to terraform-provider-azurerm repository root | - | `"C:\terraform-provider-azurerm"` |
| `-ExportDirectory` | No | Directory for CSV exports and output files | `./output` | `"C:\analysis\output"` |

### Database Mode Parameters
| Parameter | Required | Description | Default | Example |
|-----------|----------|-------------|---------|---------|
| `-DatabaseDirectory` | **Yes** | Directory containing CSV database files | - | `"output"` or `"C:\analysis\output"` |
| `-ShowDirectReferences` | No | Display direct resource references | Shows available options | Switch parameter |
| `-ShowIndirectReferences` | No | Display indirect references (templates + sequential) | Shows available options | Switch parameter |

**Note**: If no Show parameter is specified, Database Mode displays available analysis options and examples.

## Troubleshooting

### PowerShell Execution Policy (Windows)

If you download the release package and see this error:
```
File C:\TerraCorder\scripts\terracorder.ps1 cannot be loaded. The file is not digitally signed.
```

**Solution 1: Unblock the downloaded files (Recommended)**
```powershell
# Unblock all files in the TerraCorder directory
cd C:\TerraCorder
Get-ChildItem -Path . -Recurse | Unblock-File
```

**Solution 2: Temporarily bypass execution policy**
```powershell
# Run the script with bypass (one-time)
powershell -ExecutionPolicy Bypass -File .\scripts\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "C:\path\to\repo"
```

**Solution 3: Change your execution policy (Permanent)**
```powershell
# Allow running local unsigned scripts (requires Administrator)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Why this happens:** Windows blocks scripts downloaded from the internet for security. The `Unblock-File` command removes this restriction.

**Security Note:** This is standard practice for open-source PowerShell tools. If you don't trust the code, you can inspect the source code in the release package or on GitHub before running `Unblock-File`. All PowerShell modules (`.psm1`) and scripts (`.ps1`) are plain text and can be reviewed with any text editor.

### Prerequisites Validation

TerraCorder requires **PowerShell Core 7.0 or later** and **Go 1.21 or later**. Prerequisites are automatically validated on startup.

**Successful validation shows:**
```
Validating PowerShell Prerequisites:
 PowerShell Edition  : Core
 PowerShell Version  : 7.5.3
 Go Installation     : Go 1.24.5
 Status              : Supported
 Threading           : 8 threads
```

**If prerequisites are not met, you'll see a detailed error:**
```
Validating PowerShell Prerequisites:
 PowerShell Edition  : Desktop
 PowerShell Version  : 5.1.19041.5247
 Go Installation     : Not Found
 Status              : Unsupported

ERROR: Missing required dependencies.

Current environment:
  PowerShell Edition: Desktop
  PowerShell Version: 5.1.19041.5247
  Go Installation:    Not Found

Required:
  PowerShell Edition: Core
  PowerShell Version: 7.0 or later
  Go Installation:    1.21 or later

Go is required to run Replicode.
Install Go 1.21 or later from: https://go.dev/dl/

Install PowerShell Core 7.0 or later from: https://github.com/PowerShell/PowerShell
```

**Solutions:**
1. **PowerShell**: Install PowerShell Core 7.x from https://github.com/PowerShell/PowerShell
2. **Go**: Install Go 1.21+ from https://go.dev/dl/
3. Verify installations:
   - `pwsh --version` (should show 7.0 or higher)
   - `go version` (should show 1.21 or higher)
4. Ensure both are in your PATH
5. After installing, restart your terminal and try again

### Repository Path Issues

If the repository path is invalid, you'll see:

```
Error: The specified repository path does not exist or is not accessible:
  C:\invalid\path\terraform-provider-azurerm

Please verify:
  1. The path exists and is accessible
  2. You have read permissions for the directory
  3. The path points to the terraform-provider-azurerm repository root
```

**Solutions:**
1. Verify the path exists: `Test-Path "C:\path\to\terraform-provider-azurerm"`
2. Check for the `internal/services` directory structure
3. Use absolute paths, not relative paths

### Performance Optimization

For large repositories:
- **AST parsing** performs single-pass semantic analysis per file (Phase 2)
- **Memory usage** peaks during Phase 2 (AST analysis and database import)
- **Disk I/O** is highest during Phase 3 (CSV export)

To improve performance:
- Use SSD storage for the repository and export directory
- Ensure sufficient RAM (4GB+ recommended)
- Close other resource-intensive applications

## Installation

### Recommended: Git Clone
```powershell
git clone https://github.com/WodansSon/terraform-terracorder.git
cd terraform-terracorder
```

### Alternative: Manual Download
See the "Manual Download" section in [Quick Start](#quick-start) for detailed instructions on downloading all required files.

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

## Issues and Support

- **Bug Reports**: [GitHub Issues](https://github.com/WodansSon/terraform-terracorder/issues)
- **Feature Requests**: [GitHub Discussions](https://github.com/WodansSon/terraform-terracorder/discussions)
- **Documentation**: See database schema documentation in [DATABASE_SCHEMA.md](DATABASE_SCHEMA.md)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built for the Terraform AzureRM provider community
- Designed for comprehensive test dependency analysis through AST semantic analysis
- Uses Go AST parser for accurate syntactic analysis
- Optimized for efficient single-pass processing

---

<div align="center">

**[Back to Top](#terracorder)**

*Comprehensive test analysis through relational database intelligence*

</div>

## Requirements

- **PowerShell**: PowerShell Core 7.0 or later
- **Operating System**: Windows, Linux, or macOS
- **Memory**: Recommended 4GB+ for large repositories
- **Go**: Go 1.16+ (for building Replicode from source, pre-built binary included)
- **Terraform AzureRM Provider**: Source code for analysis
- **Terminal**: ANSI color support recommended for visual tree diagrams (Windows Terminal, VS Code integrated terminal, or modern Linux/macOS terminal)

## Use Cases

### Development Workflow
- **Pre-modification analysis**: Identify all tests to run before changing a resource
- **Impact assessment**: Understand the full scope of test coverage for any resource
- **Database exploration**: Query CSV exports to find patterns and relationships
- **Performance optimization**: Identify test bottlenecks through comprehensive data

### Data Analysis
- **Cross-service dependencies**: Analyze how tests span multiple Azure services
- **Template usage patterns**: Study how template functions are reused across tests
- **Sequential test chains**: Map complex test execution dependencies
- **Reference type distribution**: Understand direct vs. indirect test relationships

### CI/CD Integration
- **Test command generation**: Use generated `go_test_commands.txt` in pipelines
- **Selective test execution**: Run only tests affected by resource changes
- **Batch processing**: Group tests by service for parallel execution
- **Coverage validation**: Ensure all necessary tests are included
