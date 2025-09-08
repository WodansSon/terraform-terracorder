# TerraCorder

*"Scanning Terraform test matrix... Dependencies detected, Captain!"*

A powerful **standalone** Terraform test dependency scanner that helps identify all tests that need to be run when modifying Azure resources in the Terraform AzureRM provider. TerraCorder intelligently discovers test dependencies through both direct resource usage and template references, ensuring comprehensive test coverage analysis.

Works from anywhere - just point it to your terraform-provider-azurerm repository!

[![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Terraform](https://img.shields.io/badge/Terraform-623CE4?style=flat&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Azure](https://img.shields.io/badge/Azure-0089D0?style=flat&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/release/WodansSon/terraform-terracorder.svg)](https://github.com/WodansSon/terraform-terracorder/releases)

## Features

- **Comprehensive Dependency Detection**: Finds tests using resources directly or via template references
- **Standalone Tool**: Works from anywhere - just specify the repository path or run from within the repo
- **Repository Auto-Detection**: Intelligently finds terraform-provider-azurerm repositories
- **Clean CI/CD Output**: `-TestNamesOnly` mode produces pipeline-ready test function names
- **Multiple Output Formats**: List, JSON, CSV, and summary formats
- **Smart Template Analysis**: Analyzes template functions to discover indirect dependencies
- **Progress Visualization**: Beautiful progress bars with file-by-file scanning feedback
- **Flexible Filtering**: Focus on specific files, test names, or test prefixes
- **Cross-Platform**: Works on Windows, Linux, and macOS with PowerShell Core

## Quick Start

### Download and Run
```powershell
# Download TerraCorder
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/WodansSon/terraform-terracorder/main/scripts/terracorder.ps1" -OutFile "terracorder.ps1"

# Find all tests using azurerm_subnet (specify repository path)
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm" -Summary

# Or let TerraCorder auto-detect the repository if running from within it
cd C:\path\to\terraform-provider-azurerm
.\terracorder.ps1 -ResourceName "azurerm_subnet" -Summary
```

### Clone and Use
```powershell
# Clone the repository
git clone https://github.com/WodansSon/terraform-terracorder.git
cd terraform-terracorder

# Run TerraCorder with explicit repository path
.\scripts\terracorder.ps1 -ResourceName "azurerm_virtual_network" -RepositoryPath "C:\path\to\terraform-provider-azurerm" -ShowDetails

# Or run from within the terraform provider repository
cd C:\path\to\terraform-provider-azurerm
C:\path\to\terraform-terracorder\scripts\terracorder.ps1 -ResourceName "azurerm_virtual_network" -ShowDetails
```## Usage Examples

### Basic Resource Scanning
```powershell
# Find all tests that use azurerm_subnet (with explicit repository path)
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm"

# Get a summary view with just file names and test functions
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm" -Summary

# Show detailed output with line numbers and context
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm" -ShowDetails

# Auto-detect repository path (when running from within the provider repo)
cd C:\path\to\terraform-provider-azurerm
.\terracorder.ps1 -ResourceName "azurerm_subnet" -Summary
```

### CI/CD Pipeline Integration
```powershell
# Get clean test names for CI/CD systems (no progress bars in output)
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm" -TestNamesOnly

# Example output (one test name per line):
# TestAccSubnet_basic
# TestAccSubnet_complete
# TestAccVirtualNetwork_withSubnet

# Use in GitHub Actions or Azure DevOps pipelines
$tests = .\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "$env:REPO_PATH" -TestNamesOnly
foreach ($test in $tests) {
    go test -run "^$test$" -timeout 30m ./internal/services/...
}
```

### Output Formats
```powershell
# JSON output for programmatic processing
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm" -OutputFormat json

# CSV output for spreadsheet analysis
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm" -OutputFormat csv

# Get unique test prefixes for batch execution
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm" -TestPrefixes
```

### Targeted Analysis
```powershell
# Test a specific file within the repository
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm" -TestFile "internal/services/network/subnet_test.go"

# Find tests for multiple resources (run separately and combine)
@("azurerm_subnet", "azurerm_virtual_network") | ForEach-Object {
    .\terracorder.ps1 -ResourceName $_ -RepositoryPath "C:\path\to\terraform-provider-azurerm" -TestNamesOnly
} | Sort-Object -Unique

# Real-world example: Find all tests for subnet-related resources
$subnetResources = @("azurerm_subnet", "azurerm_subnet_nat_gateway_association", "azurerm_subnet_route_table_association")
$allTests = $subnetResources | ForEach-Object {
    .\terracorder.ps1 -ResourceName $_ -RepositoryPath "C:\terraform-provider-azurerm" -TestNamesOnly
} | Sort-Object -Unique
Write-Host "Found $($allTests.Count) unique tests across all subnet resources"
```

## Real-World Results

TerraCorder has been tested against the full terraform-provider-azurerm repository with impressive results:

### Example: `azurerm_subnet` Analysis
```
Files With Matches                    : 247 files
Total Matches Found                   : 5,721 matches
Total Test Functions                  : 1,457 test functions
Services Affected                     : 62 Azure services
Scan Time                            : ~15 seconds
```

### Example: `azurerm_virtual_network` Analysis
```
Template Functions Discovered        : 546 template functions
Test Functions Found                 : 800+ test functions
Cross-Service Dependencies           : 45+ services
Direct vs Template References        : Smart detection of both patterns
```

## How It Works

TerraCorder uses a two-phase approach to discover test dependencies:

### Phase 1: Direct Resource Detection
- Scans all `*_test.go` files in the `internal/services/` directory
- Identifies direct usage of the specified resource (e.g., `azurerm_subnet`)
- Extracts test function names and file locations

### Phase 2: Template Reference Analysis
- Discovers template functions that contain the target resource
- Finds all tests that call these template functions
- Maps indirect dependencies through template usage

### Smart Progress Tracking
- Real-time file scanning progress with visual indicators
- Automatic console width detection and adjustment
- Graceful handling of narrow terminal windows

## Use Cases

### Development Workflow
- **Before making changes**: Identify which tests to run locally for any resource modification
- **Code review**: Understand the comprehensive impact scope of resource modifications
- **CI/CD optimization**: Use `-TestNamesOnly` to run only affected tests in pull requests
- **Cross-repository analysis**: Run from any location by specifying the repository path

### Team Collaboration
- **Impact analysis**: Generate and share comprehensive test coverage reports across teams
- **Documentation**: Create dependency maps for complex resources and their test relationships
- **Quality assurance**: Ensure complete test coverage - no tests are missed during resource updates
- **Remote analysis**: Team members can analyze dependencies without cloning large repositories

## Sample Output

### Summary Format (`-Summary`)
```
Searching for tests using resource: 'azurerm_subnet'...

Repository Summary:

  Files With Matches                    : 247
  Total Direct Reference Matches        : 2558
  Total Template Reference Matches      : 3159
    - Total Matches Found               : 5721
  Total Test Functions                  : 1457
  Template Functions Containing Resource: 876
  Unique Test Prefixes                  : 199
  Total Services                        : 62
```

### CI/CD Format (`-TestNamesOnly`)
```
TestAccSubnet_basic
TestAccSubnet_complete
TestAccSubnet_delegation
TestAccSubnet_requiresImport
TestAccVirtualNetwork_withSubnet
TestAccVirtualNetwork_multipleSubnets
TestAccNetworkSecurityGroup_withSubnet
[... 1450+ more test names]
```

### JSON Format (`-OutputFormat json`)
```json
{
  "ResourceName": "azurerm_subnet",
  "TotalMatches": 5721,
  "TotalFiles": 247,
  "Files": [
    {
      "File": "internal/services/network/subnet_resource_test.go",
      "RelativePath": "./internal/services/network/subnet_resource_test.go",
      "DirectMatches": 45,
      "TemplateMatches": 12,
      "TestFunctions": ["TestAccSubnet_basic", "TestAccSubnet_complete"],
      "TemplateFunctions": ["basic", "complete", "requiresImport"]
    },
    {
      "File": "internal/services/network/virtual_network_resource_test.go",
      "RelativePath": "./internal/services/network/virtual_network_resource_test.go",
      "DirectMatches": 8,
      "TemplateMatches": 3,
      "TestFunctions": ["TestAccVirtualNetwork_withSubnet"],
      "TemplateFunctions": ["withSubnet"]
    }
  ],
  "TemplateFunctionsWithResource": {
    "basic": ["internal/services/network/subnet_resource_test.go"],
    "complete": ["internal/services/network/subnet_resource_test.go"],
    "withSubnet": ["internal/services/network/virtual_network_resource_test.go"]
  }
}
```

## Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-ResourceName` | **Required**. Azure resource to search for | `"azurerm_subnet"` |
| `-RepositoryPath` | **Optional**. Path to terraform-provider-azurerm repository root. Auto-detected if not specified. | `"C:\terraform-provider-azurerm"` |
| `-ShowDetails` | Include line numbers and context in output | Switch parameter |
| `-OutputFormat` | Output format: `list` (default), `json`, `csv` | `"json"` |
| `-TestFile` | Analyze specific file only (relative to repository root) | `"internal/services/network/subnet_test.go"` |
| `-TestNamesOnly` | **CI/CD Mode**. Output only clean test function names (one per line) | Switch parameter |
| `-TestPrefixes` | Output unique test prefixes for batch execution | Switch parameter |
| `-Summary` | Concise summary format with totals and statistics | Switch parameter |

## Requirements

- **PowerShell**: 5.1 or PowerShell Core 6.0+
- **Operating System**: Windows, Linux, or macOS
- **Terraform AzureRM Provider**: Source code (for scanning)

## Installation

### Option 1: Direct Download
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/WodansSon/terraform-terracorder/main/scripts/terracorder.ps1" -OutFile "terracorder.ps1"
```

### Option 2: Git Clone
```powershell
git clone https://github.com/WodansSon/terraform-terracorder.git
```

### Option 3: PowerShell Gallery (Coming Soon)
```powershell
Install-Script -Name TerraCorder
```

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Setup
```powershell
# Clone the repository
git clone https://github.com/WodansSon/terraform-terracorder.git
cd terraform-terracorder

# Run tests
.\tests\run-tests.ps1

# Run with test data
.\scripts\terracorder.ps1 -ResourceName "azurerm_subnet" -TestConsoleWidth 80
```

## Issues and Support

- **Bug Reports**: [GitHub Issues](https://github.com/WodansSon/terraform-terracorder/issues)
- **Feature Requests**: [GitHub Discussions](https://github.com/WodansSon/terraform-terracorder/discussions)
- **Documentation**: [Wiki](https://github.com/WodansSon/terraform-terracorder/wiki)

## Roadmap

- [ ] **v2.0**: Multi-provider support (AWS, GCP)
- [ ] **v2.1**: Integration with GitHub Actions
- [ ] **v2.2**: Visual dependency graphs
- [ ] **v2.3**: Test execution time estimation
- [ ] **v2.4**: PowerShell Gallery publication

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by the complexity of Terraform provider testing
- Built for the Terraform AzureRM provider community
- Special thanks to all contributors and testers

---

<div align="center">

**[Back to Top](#terracorder)**

Made with love for the Terraform community

</div>
