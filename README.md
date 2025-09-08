# TerraCorder 🖖

*"Scanning Terraform test matrix... Dependencies detected, Captain!"*

A powerful Terraform test dependency scanner that helps identify all tests that need to be run when modifying Azure resources in the Terraform AzureRM provider. TerraCorder intelligently discovers test dependencies through both direct resource usage and template references, ensuring comprehensive test coverage analysis.

[![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Terraform](https://img.shields.io/badge/Terraform-623CE4?style=flat&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Azure](https://img.shields.io/badge/Azure-0089D0?style=flat&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/release/WodansSon/terraform-terracorder.svg)](https://github.com/WodansSon/terraform-terracorder/releases)

## 🎯 Features

- **Comprehensive Dependency Detection**: Finds tests using resources directly or via template references
- **Multiple Output Formats**: List, JSON, CSV, and summary formats
- **Smart Template Analysis**: Analyzes template functions to discover indirect dependencies
- **Progress Visualization**: Beautiful progress bars with file-by-file scanning feedback
- **Flexible Filtering**: Focus on specific files, test names, or test prefixes
- **Cross-Platform**: Works on Windows, Linux, and macOS with PowerShell Core

## 🚀 Quick Start

### Download and Run
```powershell
# Download TerraCorder
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/WodansSon/terraform-terracorder/main/scripts/terracorder.ps1" -OutFile "terracorder.ps1"

# Find all tests using azurerm_subnet
.\terracorder.ps1 -ResourceName "azurerm_subnet" -Summary
```

### Clone and Use
```powershell
# Clone the repository
git clone https://github.com/WodansSon/terraform-terracorder.git
cd terraform-terracorder

# Run TerraCorder
.\scripts\terracorder.ps1 -ResourceName "azurerm_virtual_network" -ShowDetails
```

## 📋 Usage Examples

### Basic Resource Scanning
```powershell
# Find all tests that use azurerm_subnet
.\terracorder.ps1 -ResourceName "azurerm_subnet"

# Get a summary view with just file names and test functions
.\terracorder.ps1 -ResourceName "azurerm_subnet" -Summary

# Show detailed output with line numbers and context
.\terracorder.ps1 -ResourceName "azurerm_subnet" -ShowDetails
```

### Output Formats
```powershell
# JSON output for programmatic processing
.\terracorder.ps1 -ResourceName "azurerm_subnet" -OutputFormat json

# CSV output for spreadsheet analysis
.\terracorder.ps1 -ResourceName "azurerm_subnet" -OutputFormat csv

# Get only test names (one per line) for CI/CD pipelines
.\terracorder.ps1 -ResourceName "azurerm_subnet" -TestNamesOnly

# Get unique test prefixes for batch execution
.\terracorder.ps1 -ResourceName "azurerm_subnet" -TestPrefixes
```

### Targeted Analysis
```powershell
# Test a specific file
.\terracorder.ps1 -ResourceName "azurerm_subnet" -TestFile "internal/services/network/subnet_test.go"

# Find tests for multiple resources (run separately and combine)
@("azurerm_subnet", "azurerm_virtual_network") | ForEach-Object {
    .\terracorder.ps1 -ResourceName $_ -TestNamesOnly
} | Sort-Object -Unique
```

## 🏗️ How It Works

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

## 🎯 Use Cases

### Development Workflow
- **Before making changes**: Identify which tests to run locally
- **Code review**: Understand the impact scope of resource modifications
- **CI/CD optimization**: Run only affected tests in pull requests

### Team Collaboration
- **Impact analysis**: Share comprehensive test coverage reports
- **Documentation**: Generate dependency maps for complex resources
- **Quality assurance**: Ensure no tests are missed during resource updates

## 📊 Sample Output

### Summary Format (`-Summary`)
```
Found 12 tests using azurerm_subnet:

📁 internal/services/network/subnet_test.go
  └── TestAccSubnet_basic
  └── TestAccSubnet_disappears
  └── TestAccSubnet_requiresImport

📁 internal/services/network/virtual_network_test.go
  └── TestAccVirtualNetwork_withSubnet
  └── TestAccVirtualNetwork_multipleSubnets
```

### JSON Format (`-OutputFormat json`)
```json
{
  "resource_name": "azurerm_subnet",
  "scan_summary": {
    "files_scanned": 847,
    "tests_found": 12,
    "template_functions_analyzed": 23
  },
  "results": [
    {
      "file": "internal/services/network/subnet_test.go",
      "test_function": "TestAccSubnet_basic",
      "line_number": 15,
      "match_type": "direct"
    }
  ]
}
```

## ⚙️ Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-ResourceName` | Azure resource to search for | `"azurerm_subnet"` |
| `-ShowDetails` | Include line numbers and context | Switch parameter |
| `-OutputFormat` | Output format: list, json, csv | `"json"` |
| `-TestFile` | Analyze specific file only | `"subnet_test.go"` |
| `-TestNamesOnly` | Output only test names | Switch parameter |
| `-TestPrefixes` | Output test prefixes only | Switch parameter |
| `-Summary` | Concise summary format | Switch parameter |

## 🔧 Requirements

- **PowerShell**: 5.1 or PowerShell Core 6.0+
- **Operating System**: Windows, Linux, or macOS
- **Terraform AzureRM Provider**: Source code (for scanning)

## 📦 Installation

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

## 🤝 Contributing

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

## 🐛 Issues and Support

- **Bug Reports**: [GitHub Issues](https://github.com/WodansSon/terraform-terracorder/issues)
- **Feature Requests**: [GitHub Discussions](https://github.com/WodansSon/terraform-terracorder/discussions)
- **Documentation**: [Wiki](https://github.com/WodansSon/terraform-terracorder/wiki)

## 📈 Roadmap

- [ ] **v2.0**: Multi-provider support (AWS, GCP)
- [ ] **v2.1**: Integration with GitHub Actions
- [ ] **v2.2**: Visual dependency graphs
- [ ] **v2.3**: Test execution time estimation
- [ ] **v2.4**: PowerShell Gallery publication

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🏆 Acknowledgments

- Inspired by the complexity of Terraform provider testing
- Built for the Terraform AzureRM provider community
- Special thanks to all contributors and testers

---

<div align="center">

**[⬆ Back to Top](#terracorder-)**

Made with ❤️ for the Terraform community

</div>
