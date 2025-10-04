# TerraCorder

*"Analyzing Terraform test matrix... Building comprehensive dependency database!"*

A high-performance **database-driven** Terraform test analysis tool that identifies all tests needed when modifying Azure resources in the Terraform AzureRM provider. TerraCorder builds a complete relational database of test dependencies, tracking direct resource usage, template references, and sequential test patterns with full foreign key relationships.

**Two powerful modes:** Discovery Mode for initial analysis with multi-threaded processing, and Database Mode for fast querying of previously analyzed data!

[![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Terraform](https://img.shields.io/badge/Terraform-623CE4?style=flat&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Azure](https://img.shields.io/badge/Azure-0089D0?style=flat&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/release/WodansSon/terraform-terracorder.svg)](https://github.com/WodansSon/terraform-terracorder/releases)

## Features

### Discovery Mode (Initial Analysis)
- **Relational Database Architecture**: Full normalized database with foreign key relationships tracking all test dependencies
- **Multi-Threaded Processing**: Parallel file processing with up to 8 threads for maximum performance
- **Comprehensive Dependency Detection**: Tracks direct resource usage, template references, and sequential test patterns
- **Database Export**: Complete CSV exports of all 12 database tables for advanced analysis
- **Visual Progress Tracking**: Real-time multi-threaded progress with file-by-file scanning feedback
- **Smart Test Command Generation**: Automatically generates optimized `go test` commands by service
- **Sequential Test Support**: Detects and tracks `acceptance.RunTestsInSequence` patterns
- **Template Function Analysis**: Maps complete template dependency chains across files

### Database Mode (Query Existing Data)
- **Fast Query Operations**: Analyze previously discovered data in seconds, not minutes
- **No File Scanning**: Load from CSV exports instantly without repository access
- **Multiple Query Types**: Direct references, indirect references, sequential patterns, cross-file dependencies, or all combined
- **Data Exploration**: Perfect for analysis, reporting, and understanding test relationships
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
    "FileDiscovery.psm1",
    "PatternAnalysis.psm1",
    "ProcessingCore.psm1",
    "ReferencesProcessing.psm1",
    "RelationalQueries.psm1",
    "SequentialProcessing.psm1",
    "TemplateProcessing.psm1",
    "TemplateProcessingStrategies.psm1",
    "TestFunctionProcessing.psm1",
    "TestFunctionStepsProcessing.psm1",
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

### Database Mode - Query Existing Data
```powershell
# Show direct resource references (fast, no file scanning)
.\scripts\terracorder.ps1 -DatabaseDirectory "output" -ShowDirectReferences

# Show indirect/template references
.\scripts\terracorder.ps1 -DatabaseDirectory "output" -ShowIndirectReferences

# Show sequential test patterns
.\scripts\terracorder.ps1 -DatabaseDirectory "output" -ShowSequentialReferences

# Show cross-file struct dependencies
.\scripts\terracorder.ps1 -DatabaseDirectory "output" -ShowCrossFileReferences

# Show all reference types combined
.\scripts\terracorder.ps1 -DatabaseDirectory "output" -ShowAllReferences

# Use custom database location
.\scripts\terracorder.ps1 -DatabaseDirectory "C:\analysis\subnet" -ShowAllReferences
```

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

TerraCorder uses multi-threaded processing for maximum performance:

### Example: `azurerm_resource_group` Analysis
```
Phase 1: File Discovery               : 2,695 files found, 1,277 relevant in 4,826 ms
Phase 2: Multi-Threaded File Reading  : 8 threads, 8,473 functions found in 2,406 ms
Phase 3: Sequential Pattern Detection : 24 additional patterns in 1,621 ms
Phase 4: Database Population          : 1,282 files, 8,591 steps in 35,584 ms
Phase 5: Reference Processing         : 26,771 direct, 12,700 config refs in 8,468 ms
Phase 6: Sequential References        : 273 sequential links in 60 ms
Phase 7: Test Command Generation      : 127 services in 533 ms
Phase 8: Database Export              : 12 tables in 489 ms

Total Execution Time                  : 54.3 seconds
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

### Discovery Mode - 8-Phase Database-Driven Analysis

TerraCorder uses an **8-phase approach** to build the complete test dependency database:

#### Phase 1: File Discovery and Filtering
- Discovers all `*_test.go` and `*_resource.go` files in `internal/services/`
- Filters to files containing the target resource name
- Uses fast string matching for initial filtering

#### Phase 2: Multi-Threaded File Reading and Categorization
- Parallel processing with up to 8 threads
- Reads and categorizes files based on test patterns
- Real-time progress tracking with thread-safe updates

#### Phase 3: Sequential Test Pattern Detection
- Identifies `acceptance.RunTestsInSequence` patterns
- Discovers additional test files through sequential relationships

#### Phase 4: Database Population
- Multi-threaded population of core database tables
- Creates Services, Files, Structs, TestFunctions records
- Establishes foreign key relationships

#### Phase 5: Resource and Configuration Reference Processing
- Tracks direct resource usage (DirectResourceReferences)
- Analyzes template functions (TemplateFunctions)
- Maps template calls (TemplateReferences)
- Resolves indirect dependencies (IndirectConfigReferences)

#### Phase 6: Sequential References Population
- Links sequential test entry points to referenced functions
- Updates TestFunctions with entry point relationships
- Builds SequentialReferences table
- **Creates external stub records** for cross-resource sequential references
  - Maintains referential integrity when sequential tests reference functions from other resources
  - Stubs marked with `Line = 0`, `FunctionBody = "EXTERNAL_REFERENCE"`, and `ReferenceTypeId = 10`
  - Ensures complete sequential test structure is visible in blast radius analysis

#### Phase 7: Go Test Command Generation
- Groups tests by Azure service
- Generates optimized `go test` commands
- Exports `go_test_commands.txt` file

#### Phase 8: Database CSV Export
- Exports all 12 database tables to CSV
- Maintains proper column headers even for empty tables
- Provides comprehensive dataset for analysis

### Database Mode - Fast Query Operations

Database Mode loads previously exported CSV files for instant analysis:

#### Database Initialization
- Imports all 12 CSV tables into in-memory database
- Rebuilds indexes and foreign key relationships
- Displays comprehensive statistics (typically 5-10 seconds)

#### Query Operations
- **ShowDirectReferences**: Display all direct resource usage
- **ShowIndirectReferences**: Display template/configuration references
- **ShowSequentialReferences**: Display sequential test patterns
- **ShowCrossFileReferences**: Display cross-file struct dependencies
- **ShowAllReferences**: Display all reference types in categorized view

#### Benefits
- **Speed**: Query operations complete in seconds vs minutes for Discovery Mode
- **Portability**: Share CSV database without needing the source repository
- **Analysis**: Multiple queries without re-scanning files
- **Reporting**: Generate reports from structured data

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
Phase 1: Completed in 245 ms

Phase 2: Reading and Categorizing Relevant Test Files...
 [INFO] Processing file 127 of 127 (100%) - Complete
 [INFO] Processed 127 Files Using 8 Threads
Phase 2: Completed in 1,234 ms

Phase 3: Finding Additional Sequential Test Patterns...
 [INFO] Found 12 Additional Sequential Test Files
Phase 3: Completed in 15 ms

Phase 4: Populating Database Tables...
 [INFO] Populating database 139 of 139 (100%) - Complete
 [INFO] Populated 139 Files Using 8 Threads
Phase 4: Completed in 456 ms

Phase 5: Populating Resource and Configuration References...
 [INFO] Found 89 Direct Resource References
 [INFO] Found 234 Test Configuration References
 [INFO] Processing Test Configuration Indirect References
 [INFO] Created 567 Indirect Configuration References
Phase 5: Completed in 789 ms

Phase 6: Populating SequentialReferences table...
 [INFO] No Sequential Test Functions Detected - Skipping Sequential Processing
Phase 6: Completed in 3 ms

Phase 7: Generating go test commands...
 [INFO] Generated Test Commands For 1 Service
 [INFO] Exported: go_test_commands.txt
Phase 7: Completed in 46 ms

Phase 8: Exporting Database CSV Files...
 [INFO] Exported: 12 Tables
Phase 8: Completed in 61 ms

============================================================
 Required Acceptance Test Execution:
============================================================

  Service Name: resourcegroup
    go test -timeout 30000s -v ./internal/services/resourcegroup -run "TestAccResourceGroup_"

Total Execution Time: 3705 ms (3.7 seconds)
```

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
| `-ShowDirectReferences` | No* | Display direct resource references | - | Switch parameter |
| `-ShowIndirectReferences` | No* | Display indirect/template references | - | Switch parameter |
| `-ShowSequentialReferences` | No* | Display sequential test patterns | - | Switch parameter |
| `-ShowCrossFileReferences` | No* | Display cross-file struct dependencies | - | Switch parameter |
| `-ShowAllReferences` | No* | Display all reference types combined | - | Switch parameter |

*At least one Show parameter must be specified in Database Mode

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
- **Thread count** is automatically optimized (2-8 threads based on CPU cores)
- **Memory usage** peaks during Phase 2 (file reading) and Phase 4 (database population)
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
- Designed for comprehensive test dependency analysis
- Optimized for multi-threaded performance on modern hardware

---

<div align="center">

**[Back to Top](#terracorder)**

*Comprehensive test analysis through relational database intelligence*

</div>

## Requirements

- **PowerShell**: PowerShell Core 7.0 or later (required for multi-threading)
- **Operating System**: Windows, Linux, or macOS
- **Memory**: Recommended 4GB+ for large repositories
- **Terraform AzureRM Provider**: Source code for analysis

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
