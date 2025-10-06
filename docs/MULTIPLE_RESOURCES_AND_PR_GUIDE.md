# Multiple Resources and Pull Request Analysis - Usage Guide

## Overview

TerraCorder now supports analyzing multiple Azure resources in a single run and can automatically detect affected resources from GitHub Pull Requests.

## New Features

### 1. Multiple Resource Analysis (`-ResourceNames`)

Analyze multiple Azure resources in a single execution. The tool will process each resource sequentially, maintaining separate databases and test results for each.

**Usage:**
```powershell
.\terracorder.ps1 -ResourceNames @("azurerm_subnet", "azurerm_virtual_network", "azurerm_network_interface") -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"
```

**Benefits:**
- Process multiple related resources together
- Consolidated execution with progress tracking
- Individual databases maintained for each resource
- Comprehensive summary at completion

### 2. Pull Request Auto-Detection (`-PullRequest`)

Automatically discover which Azure resources were modified in a GitHub Pull Request and analyze all affected resources.

**Usage (with PR number):**
```powershell
.\terracorder.ps1 -PullRequest 1234 -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"
```

**Usage (with PR URL):**
```powershell
.\terracorder.ps1 -PullRequest "https://github.com/hashicorp/terraform-provider-azurerm/pull/1234" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"
```

**How It Works:**
1. Analyzes changed files in the PR
2. Identifies modified `*_resource.go` files
3. Extracts resource names (e.g., `azurerm_subnet`)
4. Runs full discovery for each affected resource

**Requirements:**
- **Recommended:** GitHub CLI (`gh`) installed and authenticated
  - Install: `winget install GitHub.cli` or visit https://cli.github.com
  - Authenticate: `gh auth login`
- **Alternative:** Local git repository with PR branch checked out
  - Branch patterns supported: `pr-1234`, `pull/1234`, `pr/1234`, `pull-1234`

## Examples

### Example 1: Analyze Two Related Resources
```powershell
# Analyze subnet and virtual network resources together
.\terracorder.ps1 `
    -ResourceNames @("azurerm_subnet", "azurerm_virtual_network") `
    -RepositoryDirectory "C:\repos\terraform-provider-azurerm"
```

### Example 2: Analyze PR with GitHub CLI
```powershell
# Automatically detect and analyze all resources modified in PR #5678
.\terracorder.ps1 `
    -PullRequest 5678 `
    -RepositoryDirectory "C:\repos\terraform-provider-azurerm"
```

### Example 3: Analyze PR without GitHub CLI
```powershell
# Fetch the PR branch first
cd C:\repos\terraform-provider-azurerm
git fetch origin pull/5678/head:pr-5678
git checkout pr-5678

# Then run analysis
.\terracorder.ps1 `
    -PullRequest 5678 `
    -RepositoryDirectory "C:\repos\terraform-provider-azurerm"
```

### Example 4: Custom Export Directory for Multiple Resources
```powershell
.\terracorder.ps1 `
    -ResourceNames @("azurerm_kubernetes_cluster", "azurerm_kubernetes_cluster_node_pool") `
    -RepositoryDirectory "C:\repos\terraform-provider-azurerm" `
    -ExportDirectory "C:\terracorder-output\aks-resources"
```

## Output Structure

### Multiple Resources
When processing multiple resources, each resource gets its own database directory with timestamped results:

```
output/
├── azurerm_subnet_20251005_143022/
│   ├── Resources.csv
│   ├── Services.csv
│   ├── Files.csv
│   └── ...
├── azurerm_virtual_network_20251005_143156/
│   ├── Resources.csv
│   ├── Services.csv
│   ├── Files.csv
│   └── ...
└── summary.txt
```

### Pull Request Analysis
PR analysis creates a special directory structure:

```
output/
├── PR_1234_20251005_143022/
│   ├── detected_resources.txt
│   ├── azurerm_subnet/
│   │   ├── Resources.csv
│   │   └── ...
│   ├── azurerm_virtual_network/
│   │   ├── Resources.csv
│   │   └── ...
│   └── pr_summary.txt
```

## Progress Tracking

### Multiple Resources
```
================================================================================
  PROCESSING RESOURCE 2 OF 3

  Resource: azurerm_virtual_network

================================================================================

Phase 1: File Discovery and Filtering...
...
  Resource Processing Time: 45231 ms (45.2 seconds)
```

### Pull Request
```
================================================================================
  ANALYZING PULL REQUEST #1234
================================================================================

  Using GitHub CLI to fetch PR changes...
  Found 5 changed files in PR #1234

  Resource Files Changed: 2

    ✓ azurerm_subnet (internal/services/network/subnet_resource.go)
    ✓ azurerm_virtual_network (internal/services/network/virtual_network_resource.go)

  Discovered 2 affected resource(s)
```

## Advanced Scenarios

### Scenario 1: Review PR Changes Before Analysis
```powershell
# First, see what resources would be analyzed
.\terracorder.ps1 -PullRequest 1234 -RepositoryDirectory "C:\repos\terraform-provider-azurerm" -WhatIf

# Then run the actual analysis (WhatIf support coming in future update)
.\terracorder.ps1 -PullRequest 1234 -RepositoryDirectory "C:\repos\terraform-provider-azurerm"
```

### Scenario 2: Mixed Approach
```powershell
# Analyze PR resources plus additional resources
# First get PR resources, then add more manually
$prResources = @("azurerm_subnet", "azurerm_virtual_network")  # Detected from PR
$additionalResources = @("azurerm_route_table")  # Related resources to include
$allResources = $prResources + $additionalResources

.\terracorder.ps1 `
    -ResourceNames $allResources `
    -RepositoryDirectory "C:\repos\terraform-provider-azurerm"
```

## Troubleshooting

### GitHub CLI Not Found
If you see "Using git to analyze local PR branch..." but prefer GitHub CLI:
1. Install GitHub CLI: `winget install GitHub.cli`
2. Authenticate: `gh auth login`
3. Verify: `gh --version`

### PR Branch Not Found
If you see "Could not find PR branch locally":
1. Fetch the PR: `git fetch origin pull/1234/head:pr-1234`
2. Or install GitHub CLI for automatic remote access

### No Resources Detected from PR
If PR analysis finds no resources:
- PR may only modify test files
- PR may only update documentation
- Resource definition files may not follow `*_resource.go` pattern
- Try running with specific resource names instead

### Invalid Resource Names
All resource names must start with `azurerm_`. If you see validation errors:
```
ERROR: Invalid resource name(s) detected
  Invalid resources:
    • subnet (should be azurerm_subnet)
```

## Performance Considerations

- **Multiple Resources:** Each resource is processed sequentially. Total time = sum of individual processing times.
- **Pull Requests:** PR metadata fetching adds 1-5 seconds (with GitHub CLI) or requires local branch.
- **Recommendation:** For large PRs affecting many resources, consider running overnight or on a dedicated build machine.

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Terraform Test Discovery

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  discover-tests:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run TerraCorder
        shell: pwsh
        run: |
          .\scripts\terracorder.ps1 `
            -PullRequest ${{ github.event.pull_request.number }} `
            -RepositoryDirectory ${{ github.workspace }}
      - name: Upload Results
        uses: actions/upload-artifact@v3
        with:
          name: terracorder-results
          path: output/
```

### Azure DevOps Pipeline Example
```yaml
trigger:
  - main

pool:
  vmImage: 'windows-latest'

steps:
- task: PowerShell@2
  displayName: 'Discover Affected Tests'
  inputs:
    targetType: 'inline'
    script: |
      .\scripts\terracorder.ps1 `
        -PullRequest $(System.PullRequest.PullRequestNumber) `
        -RepositoryDirectory $(Build.SourcesDirectory)

- task: PublishBuildArtifacts@1
  inputs:
    pathToPublish: 'output'
    artifactName: 'terracorder-results'
```

## Version History

- **v2.0** - Added `-ResourceNames` array and `-PullRequest` support
- **v1.0** - Initial release with single `-ResourceName` support

## See Also

- [Main README](../README.md) - General usage and features
- [Database Schema](../DATABASE_SCHEMA.md) - Database structure documentation
- [Contributing Guide](../CONTRIBUTING.md) - How to contribute
