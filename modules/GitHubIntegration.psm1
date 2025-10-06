# GitHubIntegration.psm1
# GitHub Pull Request integration for automatic resource discovery

function Get-ResourcesFromPullRequest {
    <#
    .SYNOPSIS
    Discover affected Azure resources from a GitHub Pull Request

    .DESCRIPTION
    Analyzes changed files in a PR to identify which azurerm_* resources were modified.
    Looks for *_resource.go files and extracts resource type names.

    .PARAMETER PullRequest
    PR number or URL (e.g., 1234 or "https://github.com/hashicorp/terraform-provider-azurerm/pull/1234")

    .PARAMETER RepositoryDirectory
    Path to the local git repository

    .PARAMETER Owner
    GitHub repository owner (defaults to "hashicorp")

    .PARAMETER Repository
    GitHub repository name (defaults to "terraform-provider-azurerm")

    .RETURNS
    Array of resource names (e.g., @("azurerm_subnet", "azurerm_virtual_network"))
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PullRequest,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryDirectory,

        [Parameter(Mandatory = $false)]
        [string]$Owner = "hashicorp",

        [Parameter(Mandatory = $false)]
        [string]$Repository = "terraform-provider-azurerm",

        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    # Extract PR number from URL if provided
    $prNumber = $PullRequest
    if ($PullRequest -match '/pull/(\d+)') {
        $prNumber = $matches[1]
    }
    if ($PullRequest -match '#(\d+)') {
        $prNumber = $matches[1]
    }

    Write-Host ""
    Write-Separator
    Write-Host "  ANALYZING PULL REQUEST #$prNumber" -ForegroundColor $ItemColor
    Write-Separator
    Write-Host ""

    try {
        # Check if we're in a git repository
        Push-Location $RepositoryDirectory
        $isGitRepo = Test-Path (Join-Path $RepositoryDirectory ".git")

        if (-not $isGitRepo) {
            Pop-Location
            throw "Directory is not a git repository: $RepositoryDirectory"
        }

        # Try to fetch PR information using GitHub CLI if available
        $changedFiles = @()
        $useGitHubCLI = $false

        # Check if GitHub CLI is available
        try {
            $null = gh --version 2>$null
            if ($LASTEXITCODE -eq 0) {
                $useGitHubCLI = $true
            }
        } catch {
            $useGitHubCLI = $false
        }

        if ($useGitHubCLI) {
            Write-Host "  Using GitHub CLI to fetch PR changes..." -ForegroundColor $InfoColor

            # Get changed files from PR using GitHub CLI
            try {
                $prFiles = gh pr view $prNumber --json files --jq '.files[].path' 2>$null
                if ($LASTEXITCODE -eq 0 -and $prFiles) {
                    $changedFiles = $prFiles -split "`n" | Where-Object { $_ -ne "" }

                    Write-Host "  Found " -ForegroundColor $InfoColor -NoNewline
                    Write-Host "$($changedFiles.Count) " -ForegroundColor $NumberColor -NoNewline
                    Write-Host "changed files in PR #$prNumber" -ForegroundColor $InfoColor
                }
            } catch {
                Write-Host "  Warning: Could not fetch PR via GitHub CLI, falling back to git diff" -ForegroundColor Yellow
                $useGitHubCLI = $false
            }
        }

        # Fallback: Use git diff if GitHub CLI not available or failed
        if (-not $useGitHubCLI -or $changedFiles.Count -eq 0) {
            Write-Host "  Using git to analyze local PR branch..." -ForegroundColor $InfoColor

            # Try to find the PR branch locally
            # Common patterns: pr-1234, pull/1234, pr/1234, etc.
            $possibleBranches = @(
                "pr-$prNumber",
                "pull/$prNumber",
                "pr/$prNumber",
                "pull-$prNumber"
            )

            $prBranch = $null
            foreach ($branch in $possibleBranches) {
                $null = git rev-parse --verify $branch 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $prBranch = $branch
                    break
                }
            }

            if (-not $prBranch) {
                Pop-Location
                throw "Could not find PR branch locally. Please fetch the PR or use GitHub CLI (gh) for remote PR analysis."
            }

            Write-Host "  Found PR branch: " -ForegroundColor $InfoColor -NoNewline
            Write-Host "$prBranch" -ForegroundColor $ItemColor

            # Get the merge base (common ancestor with main/master)
            $defaultBranch = git symbolic-ref refs/remotes/origin/HEAD 2>$null | ForEach-Object { $_ -replace 'refs/remotes/origin/', '' }
            if (-not $defaultBranch) {
                $defaultBranch = "main"
            }

            $mergeBase = git merge-base $defaultBranch $prBranch 2>$null
            if ($LASTEXITCODE -ne 0) {
                Pop-Location
                throw "Could not determine merge base between $defaultBranch and $prBranch"
            }

            # Get changed files
            $gitDiff = git diff --name-only $mergeBase..$prBranch 2>$null
            if ($LASTEXITCODE -eq 0) {
                $changedFiles = $gitDiff -split "`n" | Where-Object { $_ -ne "" }

                Write-Host "  Found " -ForegroundColor $InfoColor -NoNewline
                Write-Host "$($changedFiles.Count) " -ForegroundColor $NumberColor -NoNewline
                Write-Host "changed files" -ForegroundColor $InfoColor
            }
        }

        Pop-Location

        if ($changedFiles.Count -eq 0) {
            Write-Host ""
            Write-Host "  No changed files found in PR #$prNumber" -ForegroundColor Yellow
            Write-Host ""
            return @()
        }

        # Filter for resource files and extract resource names
        # Pattern: internal/services/*/azurerm_*_resource.go or *_resource_test.go
        $resourceFiles = $changedFiles | Where-Object {
            $_ -match '_resource\.go$' -and $_ -notmatch '_test\.go$'
        }

        Write-Host ""
        Write-Host "  Resource Files Changed: " -ForegroundColor $InfoColor -NoNewline
        Write-Host "$($resourceFiles.Count)" -ForegroundColor $NumberColor
        Write-Host ""

        $discoveredResources = @()

        foreach ($file in $resourceFiles) {
            # Extract resource name from file path
            # Pattern: internal/services/network/virtual_network_resource.go -> azurerm_virtual_network
            if ($file -match '([a-z0-9_]+)_resource\.go$') {
                $resourcePart = $matches[1]
                $resourceName = "azurerm_$resourcePart"

                # Verify this resource actually exists in the file
                $fullPath = Join-Path $RepositoryDirectory $file
                if (Test-Path $fullPath) {
                    $content = Get-Content $fullPath -Raw -ErrorAction SilentlyContinue
                    if ($content -and $content -match [regex]::Escape($resourceName)) {
                        $discoveredResources += $resourceName

                        Write-Host "    ✓ " -ForegroundColor Green -NoNewline
                        Write-Host "$resourceName " -ForegroundColor $ItemColor -NoNewline
                        Write-Host "($file)" -ForegroundColor $BaseColor
                    }
                }
            }
        }

        # Remove duplicates and sort
        $discoveredResources = $discoveredResources | Select-Object -Unique | Sort-Object

        Write-Host ""
        if ($discoveredResources.Count -eq 0) {
            Write-Host "  No Azure resources detected in changed files" -ForegroundColor Yellow
        } else {
            Write-Host "  Discovered " -ForegroundColor $InfoColor -NoNewline
            Write-Host "$($discoveredResources.Count) " -ForegroundColor $NumberColor -NoNewline
            Write-Host "affected resource(s)" -ForegroundColor $InfoColor
        }
        Write-Host ""

        return $discoveredResources

    } catch {
        if ((Get-Location).Path -ne $PSScriptRoot) {
            Pop-Location
        }
        throw "Failed to analyze PR #${prNumber}: $_"
    }
}

function Show-PullRequestSummary {
    <#
    .SYNOPSIS
    Display summary of PR analysis

    .PARAMETER PullRequest
    PR number

    .PARAMETER Resources
    Array of discovered resources

    .PARAMETER NumberColor
    Color for numbers

    .PARAMETER ItemColor
    Color for items

    .PARAMETER InfoColor
    Color for info text

    .PARAMETER BaseColor
    Color for base text
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PullRequest,

        [Parameter(Mandatory = $true)]
        [array]$Resources,

        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    Write-Host ""
    Write-Separator
    Write-Host "  PR #$PullRequest ANALYSIS SUMMARY" -ForegroundColor $ItemColor
    Write-Separator
    Write-Host ""

    if ($Resources.Count -eq 0) {
        Write-Host "  No Azure resources found to analyze" -ForegroundColor Yellow
    } else {
        Write-Host "  Will analyze " -ForegroundColor $InfoColor -NoNewline
        Write-Host "$($Resources.Count) " -ForegroundColor $NumberColor -NoNewline
        Write-Host "resource(s):" -ForegroundColor $InfoColor
        Write-Host ""

        foreach ($resource in $Resources) {
            Write-Host "    • " -ForegroundColor $BaseColor -NoNewline
            Write-Host "$resource" -ForegroundColor $ItemColor
        }
    }

    Write-Host ""
}

Export-ModuleMember -Function Get-ResourcesFromPullRequest, Show-PullRequestSummary
