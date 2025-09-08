# TerraCorder Usage Examples

This directory contains practical examples of how to use TerraCorder in various scenarios.

## Common Use Cases

### 1. Basic Resource Scanning

```powershell
# Find all tests that use azurerm_subnet (with explicit repository path)
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm"

# Get a clean summary view
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm" -Summary

# Show detailed output with line numbers
.\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm" -ShowDetails

# Auto-detect repository path when running from within the provider repo
cd C:\path\to\terraform-provider-azurerm
.\terracorder.ps1 -ResourceName "azurerm_subnet" -ShowDetails
```

### 2. CI/CD Pipeline Integration

```powershell
# Get clean test names for automated test runs (no progress bars in output)
$repoPath = "C:\path\to\terraform-provider-azurerm"
$testNames = .\terracorder.ps1 -ResourceName "azurerm_virtual_network" -RepositoryPath $repoPath -TestNamesOnly

# Example: Run each test individually
foreach ($test in $testNames) {
    Write-Host "Running: go test -run ^$test`$ -timeout 30m ./internal/services/..." -ForegroundColor Green
    # go test -run "^$test$" -timeout 30m ./internal/services/...
}

# Example: GitHub Actions integration
Write-Host "GitHub Actions matrix strategy:"
$testNames | ForEach-Object { "        - test-name: `"$_`"" }

# Get test prefixes for batch execution
$prefixes = .\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath $repoPath -TestPrefixes
foreach ($prefix in $prefixes) {
    Write-Host "Batch run: go test -run $prefix -timeout 60m ./internal/services/..." -ForegroundColor Cyan
}
```

### 3. JSON Output for Automation

```powershell
# Generate comprehensive JSON report for further processing
$repoPath = "C:\path\to\terraform-provider-azurerm"
$jsonOutput = .\terracorder.ps1 -ResourceName "azurerm_storage_account" -RepositoryPath $repoPath -OutputFormat json | ConvertFrom-Json

# Display summary statistics
Write-Host "=== Analysis Results ===" -ForegroundColor Yellow
Write-Host "Repository: $($jsonOutput.repository_path)" -ForegroundColor Gray
Write-Host "Resource: $($jsonOutput.resource_name)" -ForegroundColor Cyan
Write-Host "Files with matches: $($jsonOutput.summary.files_with_matches)" -ForegroundColor Green
Write-Host "Total test functions: $($jsonOutput.summary.total_test_functions)" -ForegroundColor Green
Write-Host "Services affected: $($jsonOutput.summary.services_affected)" -ForegroundColor Magenta

# Process each result file
Write-Host "`n=== Top 5 Files by Test Count ===" -ForegroundColor Yellow
foreach ($result in $jsonOutput.results) {
    Write-Host "$($result.file): $($result.test_function) (line $($result.line_number))"
}
```

### 4. Multiple Resource Analysis

```powershell
# Analyze multiple related resources
$repoPath = "C:\terraform-provider-azurerm"
$resources = @("azurerm_subnet", "azurerm_virtual_network", "azurerm_network_security_group")
$allTests = @()

foreach ($resource in $resources) {
    Write-Host "Analyzing $resource..." -ForegroundColor Yellow
    $tests = .\terracorder.ps1 -ResourceName $resource -RepositoryPath $repoPath -TestNamesOnly
    $allTests += $tests
}

# Get unique test names
$uniqueTests = $allTests | Sort-Object -Unique
Write-Host "`nUnique tests to run: $($uniqueTests.Count)" -ForegroundColor Green
$uniqueTests | ForEach-Object { Write-Host "  $_" }
```

### 5. Impact Analysis Reporting

```powershell
# Generate comprehensive impact report
function New-ImpactReport {
    param(
        [string]$ResourceName,
        [string]$RepositoryPath = "C:\terraform-provider-azurerm"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $reportPath = "impact-report-$ResourceName-$timestamp.html"

    # Get data
    $jsonData = .\terracorder.ps1 -ResourceName $ResourceName -RepositoryPath $RepositoryPath -OutputFormat json | ConvertFrom-Json    # Generate HTML report
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Impact Report: $ResourceName</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #f0f8ff; padding: 20px; border-radius: 5px; }
        .summary { background: #f9f9f9; padding: 15px; margin: 20px 0; }
        .test-list { margin: 20px 0; }
        .test-item { margin: 5px 0; padding: 8px; background: #fff; border-left: 3px solid #007acc; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Impact Analysis: $ResourceName</h1>
        <p>Generated on: $(Get-Date)</p>
    </div>

    <div class="summary">
        <h2>Summary</h2>
        <ul>
            <li><strong>Files Scanned:</strong> $($jsonData.scan_summary.files_scanned)</li>
            <li><strong>Tests Found:</strong> $($jsonData.scan_summary.tests_found)</li>
            <li><strong>Template Functions:</strong> $($jsonData.scan_summary.template_functions_analyzed)</li>
        </ul>
    </div>

    <div class="test-list">
        <h2>Affected Tests</h2>
"@

    foreach ($result in $jsonData.results) {
        $html += "<div class='test-item'><strong>$($result.test_function)</strong><br/>File: $($result.file)<br/>Line: $($result.line_number) ($($result.match_type))</div>`n"
    }

    $html += @"
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "Report saved to: $reportPath" -ForegroundColor Green

    # Open report in default browser
    Start-Process $reportPath
}

# Usage
New-ImpactReport -ResourceName "azurerm_subnet"
```

## Advanced Scenarios

### Cross-Platform Usage

```bash
# Linux/macOS with PowerShell Core
pwsh -c "./terracorder.ps1 -ResourceName 'azurerm_subnet' -Summary"

# Windows PowerShell
powershell.exe -Command "./terracorder.ps1 -ResourceName 'azurerm_subnet' -Summary"
```

### Performance Optimization

```powershell
# For large codebases, use specific file targeting
.\terracorder.ps1 -ResourceName "azurerm_subnet" -TestFile "internal/services/network/subnet_test.go"

# Use summary mode for quick overview
.\terracorder.ps1 -ResourceName "azurerm_subnet" -Summary
```

### Integration with Git Hooks

```powershell
# Example pre-push hook
# Save as .git/hooks/pre-push

$changedFiles = git diff --name-only HEAD~1 HEAD | Where-Object { $_ -like "*.go" -and $_ -like "*resource_*" }

foreach ($file in $changedFiles) {
    # Extract resource name from filename
    if ($file -match "resource_azurerm_(.+)\.go") {
        $resourceName = "azurerm_" + $Matches[1]
        Write-Host "Analyzing impact of changes to $resourceName..." -ForegroundColor Yellow

        $tests = .\terracorder.ps1 -ResourceName $resourceName -TestNamesOnly
        if ($tests.Count -gt 0) {
            Write-Host "WARNING: The following tests should be run:" -ForegroundColor Red
            $tests | ForEach-Object { Write-Host "  go test -run $_" }
        }
    }
}
```

## Output Format Examples

### List Format (Default)
```
Found 5 tests using azurerm_subnet:

internal/services/network/subnet_test.go:
  TestAccSubnet_basic (line 15)
  TestAccSubnet_disappears (line 45)

internal/services/network/virtual_network_test.go:
  TestAccVirtualNetwork_withSubnet (line 123)
```

### JSON Format
```json
{
  "resource_name": "azurerm_subnet",
  "scan_summary": {
    "files_scanned": 247,
    "tests_found": 5,
    "template_functions_analyzed": 12
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

### CSV Format
```csv
File,TestFunction,LineNumber,MatchType
internal/services/network/subnet_test.go,TestAccSubnet_basic,15,direct
internal/services/network/subnet_test.go,TestAccSubnet_disappears,45,direct
```

## Mock Testing Environment

For testing TerraCorder itself:

```powershell
# Test with narrow console
.\terracorder.ps1 -ResourceName "azurerm_subnet" -TestConsoleWidth 40

# Test with wide console
.\terracorder.ps1 -ResourceName "azurerm_subnet" -TestConsoleWidth 120

# Test error conditions
.\terracorder.ps1 -ResourceName "nonexistent_resource" -Summary
```

## Tips and Best Practices

1. **Use Summary Mode**: For quick overviews, always use `-Summary`
2. **JSON for Automation**: Use `-OutputFormat json` for scripted processing
3. **Combine with Git**: Integrate with git hooks for automatic impact analysis
4. **Test Prefixes**: Use `-TestPrefixes` for batch test execution
5. **Regular Scanning**: Run periodically to understand test dependencies
6. **Documentation**: Save reports for team sharing and documentation

## Integration Examples

### With GitHub Actions
```yaml
- name: Analyze Test Impact
  run: |
    $tests = .\terracorder.ps1 -ResourceName "azurerm_subnet" -TestNamesOnly
    echo "::set-output name=tests::$($tests -join ',')"
```

### With Azure DevOps
```yaml
- powershell: |
    $impact = .\terracorder.ps1 -ResourceName "$(ResourceName)" -Summary
    Write-Host "##vso[task.setvariable variable=TestImpact]$impact"
```

### With Jenkins
```groovy
script {
    def tests = powershell(returnStdout: true, script: '.\\terracorder.ps1 -ResourceName "azurerm_subnet" -TestNamesOnly')
    env.AFFECTED_TESTS = tests.trim()
}
```
