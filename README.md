# TerraCorder

*"Analyzing Terraform test matrix... Building comprehensive dependency database!"*

A high-performance **AST-based semantic analysis tool** that identifies all tests needed when modifying Azure resources in the Terraform AzureRM provider. TerraCorder uses a Go AST (Abstract Syntax Tree) analyzer to perform deep syntactic parsing of test files, building a complete relational database of test dependencies with direct resource usage, template references, and sequential test patterns tracked through full foreign key relationships.

**Two powerful modes:** Discovery Mode for initial AST analysis and database building, and Database Mode for fast querying of previously analyzed data!

[![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Terraform](https://img.shields.io/badge/Terraform-623CE4?style=flat&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Azure](https://img.shields.io/badge/Azure-0089D0?style=flat&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/release/WodansSon/terraform-terracorder.svg)](https://github.com/WodansSon/terraform-terracorder/releases)

## Features

### Discovery Mode (Initial Analysis)
- **AST Semantic Analysis**: Go-based Abstract Syntax Tree parser performs deep syntactic analysis (not regex pattern matching)
- **Relational Database Architecture**: Full normalized database with foreign key relationships tracking all test dependencies
- **Single-Pass AST Processing**: Efficient AST analyzer extracts all metadata in one pass per file
- **Comprehensive Dependency Detection**: Tracks direct resource usage, template references, and sequential test patterns through AST call graph analysis
- **Database Export**: Complete CSV exports of all 12 database tables for advanced analysis
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
  - Template function call chains with multi-level indirection
  - Color-coded output with automatic VS Code theme detection
  - Professional box-drawing characters for clear hierarchy visualization
- **Data Exploration**: Perfect for analysis, reporting, and understanding test relationships
- **Syntax Highlighting**: Color-coded output with VS Code theme detection for enhanced readability (requires terminal ANSI support)
- **Cross-Platform**: Works on Windows, Linux, and macOS with PowerShell Core 7.0+

## Quick Start

### Clone and Use (Recommended)
TerraCorder requires the modules directory to function properly. The easiest way to get started is to clone the repository:
```powershell
# Clone the repository
git clone https://github.com/WodansSon/terraform-terracorder.git
cd terraform-terracorder

# Run Discovery Mode (initial analysis)
.\scripts\terracorder.ps1 -ResourceName "azurerm_virtual_network" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"

# Run Database Mode (query existing data)
.\scripts\terracorder.ps1 -DatabaseDirectory "output" -ShowDirectReferences

# Run Database Mode (view available options)
.\scripts\terracorder.ps1 -DatabaseDirectory "output"

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

# Download main script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/WodansSon/terraform-terracorder/main/scripts/terracorder.ps1" -OutFile "terracorder\scripts\terracorder.ps1"

# Download required modules
$modules = @(
    "Database.psm1",
    "DatabaseMode.psm1",
    "FileDiscovery.psm1",
    "ASTImport.psm1",
    "ProcessingCore.psm1",
    "RelationalQueries.psm1",
    "UI.psm1"
)

foreach ($module in $modules) {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/WodansSon/terraform-terracorder/main/modules/$module" -OutFile "terracorder\modules\$module"
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

# Show all reference types combined (complete blast radius analysis)
.\scripts\terracorder.ps1 -DatabaseDirectory "output" -ShowAllReferences

# Use custom database location
.\scripts\terracorder.ps1 -DatabaseDirectory "C:\analysis\subnet" -ShowAllReferences
```

### Visual Blast Radius Trees
Database Mode includes **rich visual tree diagrams** that map complete dependency chains:
- **Unicode box-drawing**: Professional tree structure with proper connectors (│, ├, └, ┬, ►, ─)
- **Color-coded output**: Automatic VS Code theme detection for enhanced readability
- **Sequential test visualization**: Shows entry points, groups, keys, and referenced functions
- **Template dependency mapping**: Displays indirect configuration chains across files

### Database Exports
```powershell
# TerraCorder automatically exports 12 CSV tables to the output directory:
# - Resources.csv                  : Master resource table (Azure resource being analyzed)
# - Services.csv                   : All Azure services discovered
# - Files.csv                      : All test files analyzed
# - Structs.csv                    : All test resource structs found
# - TestFunctions.csv              : All test functions discovered
# - TestFunctionSteps.csv          : Individual test steps and configurations
# - TemplateFunctions.csv          : Template/configuration methods
# - TemplateReferences.csv         : Template method calls in tests
# - DirectResourceReferences.csv   : Direct resource usage
# - IndirectConfigReferences.csv   : Indirect template dependencies
# - SequentialReferences.csv       : Sequential test relationships
# - ReferenceTypes.csv             : Reference type lookup table

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
Phase 1: File Discovery               : 2,695 files found, 1,277 relevant in 4,826 ms
Phase 2: AST Analysis & DB Import      : 8,473 functions, 26,771 refs in 47,927 ms
Phase 3: CSV Export                    : 12 tables exported in 489 ms

Total Execution Time                  : 53.2 seconds
```

### Database Size: `azurerm_kubernetes_cluster`
```
Services Table                        : 5 services
Files Table                           : 22 files
Structs Table                         : 16 structs
TestFunctions Table                   : 322 test functions
TestFunctionSteps Table               : 502 test steps
TemplateFunctions Table               : 333 template functions
TemplateReferences Table              : 501 template calls
DirectResourceReferences Table        : 910 direct references
IndirectConfigReferences Table        : 238 indirect references
SequentialReferences Table            : 0 sequential links
ReferenceTypes Table                  : 13 reference types
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
- **Go AST analyzer** performs deep syntactic parsing of all discovered files
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
- Exports all 12 database tables to CSV files
- Maintains proper column headers even for empty tables
- Provides comprehensive dataset for analysis and reporting
- Exports `go_test_commands.txt` file for CI/CD integration

### Database Mode - Fast Query Operations

Database Mode loads previously exported CSV files for instant analysis:

#### Database Initialization
- Imports all 12 CSV tables into in-memory database
- Rebuilds indexes and foreign key relationships
- Displays comprehensive statistics (typically 5-10 seconds)

#### Query Operations (All Optional)
- **No flags (default)**: Display available analysis options with examples
- **ShowDirectReferences**: Display all direct resource usage and attribute references
- **ShowIndirectReferences**: Display template dependencies and sequential test chains with **visual tree diagrams**
  - Sequential test entry points organized by groups and keys
  - Template function call chains showing multi-level dependencies
  - Color-coded tree structure with professional Unicode box-drawing
  - External reference markers for cross-resource dependencies
- **ShowAllReferences**: Display complete blast radius analysis (Direct + Indirect) with full visual output

#### Benefits
- **Speed**: Query operations complete in seconds vs minutes for Discovery Mode
- **Portability**: Share CSV database without needing the source repository
- **Analysis**: Multiple queries without re-scanning files
- **Reporting**: Generate reports from structured data
- **Progressive Discovery**: View options first, then choose your analysis

### AST Analyzer - Go-Based Semantic Parser

TerraCorder uses a **Go AST (Abstract Syntax Tree) analyzer** for accurate semantic analysis:

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
- Pre-built binary: `tools/ast-analyzer/ast-analyzer` (Linux/macOS) or `ast-analyzer.exe` (Windows)
- Source code: `tools/ast-analyzer/*.go`
- Build instructions: `tools/ast-analyzer/README.md`

**Note**: The AST analyzer is automatically invoked by TerraCorder during Discovery Mode Phase 2. You don't need to run it manually unless you're debugging or developing.

## Database Schema

TerraCorder uses a **normalized relational database** with 12 tables:

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `Resources` | Master resource table | ResourceRefId (PK), ResourceName |
| `Services` | Azure services | ServiceRefId (PK), Name, ResourceRefId (FK) |
| `Files` | Test files | FileRefId (PK), FilePath, ServiceRefId (FK) |
| `Structs` | Test resource structs | StructRefId (PK), StructName, FileRefId (FK), ResourceRefId (FK) |
| `TestFunctions` | Test functions | TestFunctionRefId (PK), FunctionName, FileRefId (FK), StructRefId (FK), ResourceRefId (FK) |
| `TestFunctionSteps` | Test steps/configs | TestFunctionStepRefId (PK), TestFunctionRefId (FK), ReferenceTypeId (FK) |
| `TemplateFunctions` | Template methods | TemplateFunctionRefId (PK), TemplateFunctionName, StructRefId (FK), ResourceRefId (FK) |
| `TemplateReferences` | Template calls | TemplateReferenceRefId (PK), TestFunctionRefId (FK), TemplateReference |
| `DirectResourceReferences` | Direct usage | DirectRefId (PK), FileRefId (FK), ReferenceTypeId (FK) |
| `IndirectConfigReferences` | Template deps | IndirectRefId (PK), TemplateReferenceRefId (FK), SourceTemplateFunctionRefId (FK) |
| `SequentialReferences` | Sequential links | SequentialRefId (PK), EntryPointFunctionRefId (FK), ReferencedFunctionRefId (FK) |
| `ReferenceTypes` | Reference lookup | ReferenceTypeId (PK), ReferenceTypeName |

**Note**: The `Resources` table is the master table containing the Azure resource being analyzed (e.g., "azurerm_virtual_network"). Four tables (Services, Structs, TestFunctions, TemplateFunctions) contain `ResourceRefId` foreign keys linking them to the resource under analysis.

## Sample Output

### Console Output
```
============================================================
 Terra-Corder - Database Initialization
============================================================
 [INFO] Creating Database Tables
 [INFO] Populating ReferenceTypes Table
Database Initialization: Completed in 15 ms

Phase 1: File Discovery and Filtering...
 [INFO] Discovered 3,421 Test Files
 [INFO] Filtered To 127 Relevant Files
 [INFO] Found 12 Additional Sequential Test Files
Phase 1: Completed in 245 ms

Phase 2: AST Analysis and Database Import...
 [INFO] Processing file 127 of 127 (100%) - Complete
 [INFO] Processed 127 Files Through AST Parser
 [INFO] Found 89 Direct Resource References
 [INFO] Found 234 Template References
 [INFO] Created 567 Indirect Configuration References
 [INFO] Linked 24 Sequential Test Relationships
 [INFO] Generated Test Commands For 1 Service
Phase 2: Completed in 2,456 ms

Phase 3: Exporting Database CSV Files...
 [INFO] Exported: 12 Tables
 [INFO] Exported: go_test_commands.txt
Phase 3: Completed in 61 ms

============================================================
 Required Acceptance Test Execution:
============================================================

  Service Name: resourcegroup
    go test -timeout 30000s -v ./internal/services/resourcegroup -run "TestAccResourceGroup_"

Total Execution Time: 2762 ms (2.8 seconds)
```

### Visual Blast Radius Analysis (Database Mode)

Database Mode provides **rich visual tree diagrams** for dependency analysis:

#### Sequential Test Chain Visualization
```
============================================================
  Sequential Call Chain:
============================================================
 Entry Point: 650: TestAccKeyVaultManagedHardwareSecurityModule
  │
  ├──┬─► Sequential Group: dataSource
  │  │
  │  └─┬─► Key     : basic
  │    └─► Function: External Reference: testAccDataSourceKeyVaultManagedHardwareSecurityModule_basic
  │
  ├──┬─► Sequential Group: keys
  │  │
  │  ├─┬─► Key     : basic
  │  │ └─► Function: External Reference: testAccKeyVaultMHSMKey_basic
  │  │
  │  ├─┬─► Key     : complete
  │  │ └─► Function: External Reference: testAccKeyVaultMHSMKey_complete
  │  │
  │  ├─┬─► Key     : data_source
  │  │ └─► Function: External Reference: testAccKeyVaultMHSMKeyDataSource_basic
  │  │
  │  ├─┬─► Key     : purge
  │  │ └─► Function: External Reference: testAccKeyVaultHSMKey_purge
  │  │
  │  ├─┬─► Key     : rotationPolicy
  │  │ └─► Function: External Reference: testAccMHSMKeyRotationPolicy_all
  │  │
  │  └─┬─► Key     : softDeleteRecovery
  │    └─► Function: External Reference: testAccKeyVaultHSMKey_softDeleteRecovery
  │
  ├──┬─► Sequential Group: resource
  │  │
  │  ├─┬─► Key     : basic
  │  │ └─► Function: 2276: testAccKeyVaultManagedHardwareSecurityModule_basic
  │  │
  │  ├─┬─► Key     : complete
  │  │ └─► Function: 4453: testAccKeyVaultManagedHardwareSecurityModule_complete
  │  │
  │  ├─┬─► Key     : download
  │  │ └─► Function: 2739: testAccKeyVaultManagedHardwareSecurityModule_download
  │  │
  │  └─┬─► Key     : update
  │    └─► Function: 3751: testAccKeyVaultManagedHardwareSecurityModule_updateAndRequiresImport
  │
  ├──┬─► Sequential Group: roleAssignments
  │  │
  │  ├─┬─► Key     : builtInRole
  │  │ └─► Function: External Reference: testAccKeyVaultManagedHardwareSecurityModuleRoleAssignment_builtInRole
  │  │
  │  └─┬─► Key     : customRole
  │    └─► Function: External Reference: testAccKeyVaultManagedHardwareSecurityModuleRoleAssignment_customRole
  │
  ├──┬─► Sequential Group: roleDefinitionDataSource
  │  │
  │  └─┬─► Key     : basic
  │    └─► Function: External Reference: testAccDataSourceKeyVaultManagedHardwareSecurityModuleRoleDefinition_basic
  │
  └──┬─► Sequential Group: roleDefinitions
     │
     └─┬─► Key     : basic
       └─► Function: External Reference: testAccKeyVaultManagedHardwareSecurityModuleRoleDefinition_basic
```

#### Template Function Dependency Chain
```
============================================================
  Template Function Call Chain:
============================================================
 Entry Point: 664: TestAccSiteRecoveryFabric_basic
  │
  └──► Template: 1405: (r SiteRecoveryFabricResource).basic
       │
       └──► Template: 1413: (r SiteRecoveryFabricResource).template
            │
            └──► Function: 1499: testAccSiteRecoveryFabric_basicConfig
```

#### Tree Symbols Explained
- `│` Vertical pipe: Continues the tree structure downward
- `├` Tee connector: Branches to a sibling (more items follow)
- `└` Corner connector: Last item in a group (no more siblings)
- `┬` Tee-down connector: Parent with children below
- `►` Right arrow: Points to the referenced item
- `─` Horizontal line: Connects items at the same level

#### Color Coding (Terminal ANSI Support Required)
- **Entry Points**: Highlighted function names
- **Sequential Groups**: Colored group names (e.g., "dataSource", "keys", "resource")
- **Line Numbers**: Distinct color for quick reference
- **External References**: Marked to show cross-resource dependencies
- **Theme Detection**: Automatically adapts to VS Code light/dark themes

**Note**: Visual tree diagrams require terminal ANSI color support. Works best in:
- Windows Terminal
- VS Code integrated terminal
- PowerShell Core 7.0+ on Linux/macOS

### CSV Export Files (in output directory)
```
Resources.csv                        - Master resource table (e.g., azurerm_virtual_network)
Services.csv                         - All Azure services
Files.csv                            - All test files
Structs.csv                          - Test resource structs
TestFunctions.csv                    - Test function records
TestFunctionSteps.csv                - Individual test steps
TemplateFunctions.csv                - Template methods
TemplateReferences.csv               - Template method calls
DirectResourceReferences.csv         - Direct resource usage
IndirectConfigReferences.csv         - Template dependencies
SequentialReferences.csv             - Sequential test links
ReferenceTypes.csv                   - Reference type lookup
go_test_commands.txt                 - Generated test commands
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
| `-ShowAllReferences` | No | Display all reference types (complete analysis) | Shows available options | Switch parameter |

**Note**: If no Show parameter is specified, Database Mode displays available analysis options and examples.

## Troubleshooting

### PowerShell Version Issues

TerraCorder requires **PowerShell Core 7.0 or later**. You'll see a clear error if your version is unsupported:

```
ERROR: PowerShell Core 7.0 or later required.

Current environment:
  Edition: Desktop
  Version: 5.1.19041.5247

Required:
  Edition: Core
  Version: 7.0 or later
```

**Solution**: Install PowerShell Core 7.x from https://github.com/PowerShell/PowerShell

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
- **AST parsing** performs single-pass semantic analysis per file
- **Memory usage** peaks during Phase 2 (AST analysis) and Phase 4 (database population)
- **Disk I/O** is highest during Phase 8 (CSV export)

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
- **Go**: Go 1.16+ (for building AST analyzer from source, pre-built binary included)
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

## Troubleshooting
