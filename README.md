# TerraCorder 🖖

*"Scanning Terraform test matrix... Dependencies detected, Captain!"*

A powerful Terraform test dependency scanner that helps identify all tests that need to be run when modifying Azure resources in the Terraform AzureRM provider.

[![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Terraform](https://img.shields.io/badge/Terraform-623CE4?style=flat&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Azure](https://img.shields.io/badge/Azure-0089D0?style=flat&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com/)

## 🚀 Quick Start

```powershell
# Download TerraCorder
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/yourusername/terraform-terracorder/main/terracorder.ps1" -OutFile "terracorder.ps1"

# Find all tests using azurerm_subnet
.\terracorder.ps1 -ResourceName "azurerm_subnet" -Summary
