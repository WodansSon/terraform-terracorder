# TerraCorder v3.0.0 Usage Examples

This document provides practical examples for using TerraCorder v3.0.0.

## Two Modes of Operation

TerraCorder v3.0.0 has two modes:
- **Discovery Mode**: Analyzes a single resource and builds a database
- **Database Mode**: Queries previously analyzed data

---

## Discovery Mode

Discovery Mode analyzes all tests for a single Terraform resource.

### Basic Usage

```powershell
# Analyze azurerm_subnet (outputs to ./output directory)
.\scripts\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"

# Use custom output directory
.\scripts\terracorder.ps1 -ResourceName "azurerm_virtual_network" -RepositoryDirectory "C:\terraform-provider-azurerm" -ExportDirectory "C:\analysis"
```

### What Discovery Mode Does

1. Scans test files for the resource
2. Uses Replicode (AST analyzer) to parse Go code
3. Builds a relational database of all test dependencies
4. Exports 14 CSV tables to the output directory
5. Generates go_test_commands.txt for running tests

### Output Files

After running Discovery Mode, you will have:
- 14 CSV files with complete test metadata
- go_test_commands.txt with ready-to-run test commands

---

## Database Mode

Database Mode queries previously analyzed data without re-scanning files.

### View Statistics

```powershell
# Show what data is available
.\scripts\terracorder.ps1 -DatabaseDirectory ".\output"
```

### Query Direct References

```powershell
# Show all direct resource usage
.\scripts\terracorder.ps1 -DatabaseDirectory ".\output" -ShowDirectReferences
```

### Query Indirect References

```powershell
# Show template dependencies and sequential tests with visual trees
.\scripts\terracorder.ps1 -DatabaseDirectory ".\output" -ShowIndirectReferences
```

---

## CI/CD Integration

### Using Generated Test Commands

```powershell
# TerraCorder generates go_test_commands.txt
# Run all tests for the analyzed resource
Get-Content ".\output\go_test_commands.txt" | Where-Object { $_ -match "^  go test" } | ForEach-Object {
    Write-Host "Running: $_" -ForegroundColor Yellow
    Invoke-Expression $_
}
```

### GitHub Actions Example

```yaml
- name: Run TerraCorder
  shell: pwsh
  run: |
    ./scripts/terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "./terraform-provider-azurerm"

- name: Run Tests
  shell: bash
  run: |
    grep "^  go test" ./output/go_test_commands.txt | bash
```

---

## Cross-Platform Usage

### Windows

```powershell
.\scripts\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "C:\terraform-provider-azurerm"
```

### Linux / macOS

```bash
pwsh ./scripts/terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "/home/user/terraform-provider-azurerm"
```

---

## Working with CSV Exports

### Analyze Services

```powershell
$services = Import-Csv ".\output\Services.csv"
Write-Host "Services affected: $($services.Count)"
$services | Format-Table
```

### Analyze Test Functions

```powershell
$tests = Import-Csv ".\output\TestFunctions.csv"
Write-Host "Total tests: $($tests.Count)"
$tests | Select-Object FunctionName, Line | Format-Table
```

### Analyze Direct References

```powershell
$directRefs = Import-Csv ".\output\DirectResourceReferences.csv"
Write-Host "Direct resource references: $($directRefs.Count)"
$directRefs | Format-Table
```

---

## Tips

1. **One Resource at a Time**: v3.0.0 analyzes one resource per run
2. **Reuse Database Mode**: Run Discovery once, query many times with Database Mode
3. **Custom Directories**: Use -ExportDirectory to organize different analyses
4. **Visual Trees**: Database Mode with -ShowIndirectReferences shows dependency trees
5. **CSV Exports**: All data is in CSV format for custom analysis

---

## Need Help?

- **Main Documentation**: [README.md](../README.md)
- **Database Schema**: [DATABASE_SCHEMA.md](../DATABASE_SCHEMA.md)
- **Issues**: [GitHub Issues](https://github.com/WodansSon/terraform-terracorder/issues)
