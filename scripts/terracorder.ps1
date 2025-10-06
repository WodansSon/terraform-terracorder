#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Find tests to run when modifying Azure resources with database tracking

.DESCRIPTION
    Enhanced tool that answers: "When I change a resource, what tests do I need to run?"

    DISCOVERY MODE (Default):
    Scans repository files, runs all 8 phases, populates database, exports CSVs, and generates go test commands.
    Finds tests that use the resource either:
    1. Directly in test configurations
    2. Via template references
    3. Via acceptance.RunTestsInSequence calls

    Supports multiple modes:
    - Single resource: -ResourceName "azurerm_subnet"
    - Multiple resources: -ResourceNames @("azurerm_subnet", "azurerm_virtual_network")
    - Pull Request: -PullRequest 1234 (auto-detects affected resources)

    DATABASE MODE (Query Only):
    Loads existing CSV database and provides deep analysis without re-scanning files.
    Use this mode for fast, repeatable queries and visualization of previously discovered data.

    If no Show* parameter is specified in Database Mode, displays database statistics only.

.PARAMETER ResourceName
    [Discovery Mode] Single Azure resource name to search for (e.g., azurerm_subnet)

.PARAMETER ResourceNames
    [Discovery Mode] Array of Azure resource names to search for (e.g., @("azurerm_subnet", "azurerm_virtual_network"))

.PARAMETER PullRequest
    [Discovery Mode] GitHub Pull Request number or URL to analyze for affected resources
    Example: 1234 or "https://github.com/hashicorp/terraform-provider-azurerm/pull/1234"

.PARAMETER RepositoryDirectory
    [Discovery Mode] Path to terraform-provider-azurerm repository root

.PARAMETER DatabaseDirectory
    [Database Mode] Path to existing CSV database directory (mutually exclusive with Discovery Mode)

.PARAMETER ExportDirectory
    Directory path where CSV export files will be stored (defaults to ../output)

.PARAMETER ShowDirectReferences
    [Database Mode] Display all direct resource references (optional)

.PARAMETER ShowIndirectReferences
    [Database Mode] Display all indirect/template-based references (optional)

.PARAMETER Help
    Display comprehensive formatted help message

.EXAMPLE
    # Discovery Mode: Single resource
    .\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"

.EXAMPLE
    # Discovery Mode: Multiple resources
    .\terracorder.ps1 -ResourceNames @("azurerm_subnet", "azurerm_virtual_network") -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"

.EXAMPLE
    # Discovery Mode: Analyze Pull Request
    .\terracorder.ps1 -PullRequest 1234 -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"

.EXAMPLE
    # Discovery Mode: Analyze Pull Request with URL
    .\terracorder.ps1 -PullRequest "https://github.com/hashicorp/terraform-provider-azurerm/pull/1234" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"

.EXAMPLE
    # Database Mode: Show direct references
    .\terracorder.ps1 -DatabaseDirectory "C:\output" -ShowDirectReferences

.EXAMPLE
    # Database Mode: Show indirect references only
    .\terracorder.ps1 -DatabaseDirectory "C:\output" -ShowIndirectReferences

.EXAMPLE
    # Show comprehensive help
    .\terracorder.ps1 -Help

.NOTES
    Version: 2.0
    Author: Terraform Test Discovery Tool

.LINK
    https://github.com/WodansSon/terraform-terracorder
#>

[CmdletBinding(DefaultParameterSetName = "DiscoveryMode")]
param(
    # Discovery Mode parameters - Single Resource (also used for Database Mode filtering)
    [Parameter(Mandatory = $false, ParameterSetName = "DiscoveryMode")]
    [Parameter(Mandatory = $false, ParameterSetName = "DatabaseMode")]
    [string]$ResourceName,

    # Discovery Mode parameters - Multiple Resources
    [Parameter(Mandatory = $false, ParameterSetName = "DiscoveryModeMultiple")]
    [string[]]$ResourceNames,

    # Discovery Mode parameters - Pull Request
    [Parameter(Mandatory = $false, ParameterSetName = "DiscoveryModePR")]
    [string]$PullRequest,

    [Parameter(Mandatory = $false, ParameterSetName = "DiscoveryMode")]
    [Parameter(Mandatory = $false, ParameterSetName = "DiscoveryModeMultiple")]
    [Parameter(Mandatory = $false, ParameterSetName = "DiscoveryModePR")]
    [string]$RepositoryDirectory,

    # Database Mode parameters
    [Parameter(Mandatory = $false, ParameterSetName = "DatabaseMode")]
    [string]$DatabaseDirectory,

    # Shared parameters
    [Parameter(Mandatory = $false)]
    [string]$ExportDirectory,

    # Database Mode query options
    [Parameter(Mandatory = $false, ParameterSetName = "DatabaseMode")]
    [switch]$ShowDirectReferences,

    [Parameter(Mandatory = $false, ParameterSetName = "DatabaseMode")]
    [switch]$ShowIndirectReferences,

    # Help parameter
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# Script-level color configuration - SINGLE SOURCE OF TRUTH for all color theming
$Script:ElapsedColor = "Yellow"    # For timing/duration displays
$Script:ItemColor = "Cyan"         # For item types (e.g., "sequential", "CROSS_FILE")
$Script:NumberColor = "Yellow"     # For counts and numbers
$Script:BaseColor = "Gray"         # For base/normal text
$Script:HighlightColor = "Cyan"    # For highlighted values
$Script:InfoColor = "Cyan"         # For [INFO] prefix

#region PowerShell Prerequisites Validation
# Validate PowerShell prerequisites before any module imports
Write-Host ""
Write-Host "Validating PowerShell Prerequisites:" -ForegroundColor Yellow

# Check PowerShell version
$currentVersion = $PSVersionTable.PSVersion
$currentEdition = $PSVersionTable.PSEdition
$fullVersion = $currentVersion.ToString()

Write-Host " PowerShell Edition  : " -ForegroundColor Cyan -NoNewline
$editionColor = if ($currentEdition -eq 'Core') { 'Green' } else { 'Yellow' }
Write-Host "$currentEdition" -ForegroundColor $editionColor

Write-Host " PowerShell Version  : " -ForegroundColor Cyan -NoNewline
$versionColor = if ($currentVersion.Major -ge 7) { 'Green' } else { 'Yellow' }
Write-Host "$fullVersion" -ForegroundColor $versionColor

# Calculate optimal thread count for parallel processing
$Global:ThreadCount = [Math]::Min(8, [Math]::Max(2, [Environment]::ProcessorCount))
$threadText = if ($Global:ThreadCount -eq 1) { "thread" } else { "threads" }


# Check if requirements are met
$meetsRequirements = ($currentEdition -eq 'Core') -and ($currentVersion.Major -ge 7)

if ($meetsRequirements) {
    Write-Host " Status              : " -ForegroundColor Cyan -NoNewline
    Write-Host "Supported" -ForegroundColor Green
    Write-Host " Threading           : " -ForegroundColor Cyan -NoNewline
    Write-Host "$($Global:ThreadCount) $threadText" -ForegroundColor Green
} else {
    Write-Host " Status              : " -ForegroundColor Cyan -NoNewline
    Write-Host "Unsupported" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "ERROR: " -ForegroundColor Cyan -NoNewline
    Write-Host "PowerShell Core 7.0 or later required." -ForegroundColor Magenta
    Write-Host ""
    Write-Host "Current environment:" -ForegroundColor Yellow
    Write-Host "  Edition: " -ForegroundColor Cyan -NoNewline
    Write-Host "$currentEdition" -ForegroundColor Yellow
    Write-Host "  Version: " -ForegroundColor Cyan -NoNewline
    Write-Host "$fullVersion" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Required:" -ForegroundColor Yellow
    Write-Host "  Edition: " -ForegroundColor Cyan -NoNewline
    Write-Host "Core" -ForegroundColor Green
    Write-Host "  Version: " -ForegroundColor Cyan -NoNewline
    Write-Host "7.0 or later" -ForegroundColor Green
    Write-Host ""
    Write-Host "Please install PowerShell version 7.0 or later from: " -ForegroundColor Cyan -NoNewline
    Write-Host "https://github.com/PowerShell/PowerShell" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
#endregion

#region Module Imports and Initialization
# TerraCorder Version
$Global:TerraCoderVersion = "2.0.6"

# Disable verbose output to reduce noise
$VerbosePreference = 'SilentlyContinue'

# Import required modules in correct dependency order
$ModulesPath = Join-Path $PSScriptRoot "..\modules"
Import-Module (Join-Path $ModulesPath "UI.psm1") -Force                          # Base UI functions (no dependencies)
Import-Module (Join-Path $ModulesPath "Database.psm1") -Force                    # Database functions (uses UI)
Import-Module (Join-Path $ModulesPath "PatternAnalysis.psm1") -Force             # Pattern analysis (no dependencies)
Import-Module (Join-Path $ModulesPath "GitHubIntegration.psm1") -Force           # GitHub PR integration (uses UI)
Import-Module (Join-Path $ModulesPath "TestFunctionProcessing.psm1") -Force      # Function extraction (uses PatternAnalysis, Database)
Import-Module (Join-Path $ModulesPath "TestFunctionStepsProcessing.psm1") -Force # Step-level analysis (uses Database, TestFunctionProcessing)
Import-Module (Join-Path $ModulesPath "RelationalQueries.psm1") -Force           # Relational queries (uses Database)
Import-Module (Join-Path $ModulesPath "FileDiscovery.psm1") -Force               # File discovery functions
Import-Module (Join-Path $ModulesPath "ProcessingCore.psm1") -Force              # Core processing (uses TestFunctionProcessing)
Import-Module (Join-Path $ModulesPath "TemplateProcessing.psm1") -Force          # Template processing
Import-Module (Join-Path $ModulesPath "ReferencesProcessing.psm1") -Force        # Reference processing
Import-Module (Join-Path $ModulesPath "SequentialProcessing.psm1") -Force        # Sequential processing
Import-Module (Join-Path $ModulesPath "DatabaseMode.psm1") -Force                # Database-only mode query functions
#endregion

# Display help if requested (after UI module is loaded)
if ($Help) {
    Show-ComprehensiveHelp
    exit 0
}

# Set default ExportDirectory if not provided (must be after param block for PS 5.1 compatibility)
if (-not $ExportDirectory) {
    $ExportDirectory = Join-Path $PSScriptRoot "..\output"
}

#region Mode Detection and Validation
# Determine operation mode: Discovery Mode or Database Mode
$IsDiscoveryMode = $false
$ResourcesToProcess = @()

if ($DatabaseDirectory) {
    # Database Mode
    # Validate mutually exclusive parameters (ResourceName is allowed for filtering)
    if ($ResourceNames -or $PullRequest -or $RepositoryDirectory) {
        Show-MutuallyExclusiveModesError
        exit 1
    }

    # Validate database directory exists
    if (-not (Test-Path $DatabaseDirectory -PathType Container)) {
        Show-DirectoryNotFoundError -DirectoryType "Database" -DirectoryPath $DatabaseDirectory
        exit 1
    }

    # If no query option specified, default to showing statistics only
    $ShowStatisticsOnly = -not ($ShowDirectReferences -or $ShowIndirectReferences)

} elseif ($PullRequest -and $RepositoryDirectory) {
    # Pull Request Discovery Mode
    $IsDiscoveryMode = $true

    # Validate repository directory exists
    if (-not (Test-Path $RepositoryDirectory)) {
        Show-DirectoryNotFoundError -DirectoryType "Repository" -DirectoryPath $RepositoryDirectory
        exit 1
    }

    # Discover resources from PR
    try {
        $ResourcesToProcess = Get-ResourcesFromPullRequest `
            -PullRequest $PullRequest `
            -RepositoryDirectory $RepositoryDirectory `
            -NumberColor $Script:NumberColor `
            -ItemColor $Script:ItemColor `
            -InfoColor $Script:InfoColor `
            -BaseColor $Script:BaseColor

        if ($ResourcesToProcess.Count -eq 0) {
            Write-Host ""
            Write-Host "  No resources found in PR #$PullRequest to analyze." -ForegroundColor Yellow
            Write-Host "  This could mean:" -ForegroundColor $Script:InfoColor
            Write-Host "    • No *_resource.go files were modified" -ForegroundColor $Script:BaseColor
            Write-Host "    • Only test files were modified" -ForegroundColor $Script:BaseColor
            Write-Host "    • Only documentation was changed" -ForegroundColor $Script:BaseColor
            Write-Host ""
            exit 0
        }

        Show-PullRequestSummary `
            -PullRequest $PullRequest `
            -Resources $ResourcesToProcess `
            -NumberColor $Script:NumberColor `
            -ItemColor $Script:ItemColor `
            -InfoColor $Script:InfoColor `
            -BaseColor $Script:BaseColor

    } catch {
        Write-Host ""
        Write-Host "  ERROR: Failed to analyze Pull Request #$PullRequest" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

} elseif ($ResourceNames -and $RepositoryDirectory) {
    # Multiple Resources Discovery Mode
    $IsDiscoveryMode = $true

    # Validate repository directory exists
    if (-not (Test-Path $RepositoryDirectory)) {
        Show-DirectoryNotFoundError -DirectoryType "Repository" -DirectoryPath $RepositoryDirectory
        exit 1
    }

    # Validate all resource name formats
    $invalidResources = @()
    foreach ($resource in $ResourceNames) {
        if (-not $resource.StartsWith("azurerm_")) {
            $invalidResources += $resource
        }
    }

    if ($invalidResources.Count -gt 0) {
        Write-Host ""
        Write-Host "  ERROR: Invalid resource name(s) detected" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Resource names must start with 'azurerm_'" -ForegroundColor $Script:InfoColor
        Write-Host ""
        Write-Host "  Invalid resources:" -ForegroundColor Yellow
        foreach ($resource in $invalidResources) {
            Write-Host "    • $resource" -ForegroundColor $Script:BaseColor
        }
        Write-Host ""
        exit 1
    }

    $ResourcesToProcess = $ResourceNames

} elseif ($ResourceName -and $RepositoryDirectory) {
    # Single Resource Discovery Mode
    $IsDiscoveryMode = $true

    # Validate repository directory exists
    if (-not (Test-Path $RepositoryDirectory)) {
        Show-DirectoryNotFoundError -DirectoryType "Repository" -DirectoryPath $RepositoryDirectory
        exit 1
    }

    # Validate resource name format
    if (-not $ResourceName.StartsWith("azurerm_")) {
        Show-InvalidResourceNameError -ResourceName $ResourceName
        exit 1
    }

    $ResourcesToProcess = @($ResourceName)

} else {
    # Neither mode properly specified
    Show-MissingParametersError
    exit 1
}
#endregion

#region Script Initialization and Validation
# Initialize script
$ExportDirectoryAbsolute = [System.IO.Path]::GetFullPath($ExportDirectory)

# Show appropriate banner based on mode
if ($IsDiscoveryMode) {
    $bannerParams = @{
        DiscoveryMode = $true
        RepositoryDirectory = $RepositoryDirectory
        ExportDirectory = $ExportDirectoryAbsolute
    }

    if ($PullRequest) {
        $bannerParams['PullRequest'] = $PullRequest
        $bannerParams['ResourceNames'] = $ResourcesToProcess
    } elseif ($ResourcesToProcess.Count -eq 1) {
        $bannerParams['ResourceName'] = $ResourcesToProcess[0]
    } else {
        $bannerParams['ResourceNames'] = $ResourcesToProcess
    }

    Show-InitialBanner @bannerParams
} else {
    Show-InitialBanner -DatabaseDirectory $DatabaseDirectory -ExportDirectory $ExportDirectoryAbsolute
}

Write-Separator
#endregion

#region Mode Execution
# Hide cursor to reduce flashing during progress updates
[Console]::CursorVisible = $false

# Initialize timing
$scriptStartTime = Get-Date
try {
    if ($IsDiscoveryMode) {
        #region DISCOVERY MODE

        # Validate test directory exists
        $testDirectory = Join-Path $RepositoryDirectory "internal\services"
        if (-not (Test-Path $testDirectory)) {
            Write-Error "Test directory not found: $testDirectory"
            exit 1
        }

        # Track overall results across all resources
        $currentResourceIndex = 0
        $totalResources = $ResourcesToProcess.Count

        #region Database and Pattern Initialization (One-Time Setup)
        # Initialize database ONCE before processing any resources
        Show-PhaseHeaderGeneric -Title "Database Initialization" -Description "Terra-Corder"
        Initialize-TerraDatabase -ExportDirectory $ExportDirectoryAbsolute -RepositoryDirectory $RepositoryDirectory -ResourceName $ResourcesToProcess[0] -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -ElapsedColor $Script:ElapsedColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        # Initialize regex patterns after database is ready and set as global
        $Global:RegexPatterns = Initialize-RegexPatterns

        # Get reference to the ReferenceTypes from Database module after initialization and set as global
        $Global:ReferenceTypes = & (Get-Module Database) { $script:ReferenceTypes }

        # Initialize accumulators for cross-resource data (used in Phase 7)
        $allTestResultsAccumulator = @()
        $allSequentialTestsAccumulator = @()
        $resourceFunctionsAccumulator = @()
        #endregion

        # Loop through each resource
        foreach ($CurrentResourceName in $ResourcesToProcess) {
            $currentResourceIndex++

            # Show resource processing header for multiple resources
            if ($totalResources -gt 1) {
                Write-Host ""
                Write-Separator
                Write-Host ""
                Write-Host "  PROCESSING RESOURCE " -ForegroundColor $Script:InfoColor -NoNewline
                Write-Host "$currentResourceIndex" -ForegroundColor $Script:NumberColor -NoNewline
                Write-Host " OF " -ForegroundColor $Script:InfoColor -NoNewline
                Write-Host "$totalResources" -ForegroundColor $Script:NumberColor
                Write-Host ""
                Write-Host "  Resource: " -ForegroundColor $Script:InfoColor -NoNewline
                Write-Host "$CurrentResourceName" -ForegroundColor Yellow
                Write-Host ""
                Write-Separator
                Write-Host ""
            }

            $resourceStartTime = Get-Date

        # Add current resource to the database (for resources after the first one)
        if ($currentResourceIndex -gt 1) {
            Add-ResourceToDatabase -ResourceName $CurrentResourceName
        }
        #region Phase 1: File Discovery and Filtering
        # Phase 1: File discovery and filtering
        Show-PhaseHeader -PhaseNumber 1 -PhaseDescription "File Discovery and Filtering"
        $phase1Start = Get-Date

        $discoveryResult = Get-TestFilesContainingResource -RepositoryDirectory $RepositoryDirectory -ResourceName $CurrentResourceName -UseParallel $true -ThreadCount $Global:ThreadCount -NumberColor $Script:NumberColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor
        $allTestFileNames = $discoveryResult.AllFiles
        $relevantFileNames = $discoveryResult.RelevantFiles
        $fileContents = $discoveryResult.FileContents


        $phase1Duration = (Get-Date) - $phase1Start
        Show-PhaseCompletion -PhaseNumber 1 -DurationMs ([math]::Round($phase1Duration.TotalMilliseconds, 0))
        #endregion

        #region Phase 2: Categorize Files and Extract Functions
        # Phase 2: Categorize files using cached content
        Show-PhaseHeader -PhaseNumber 2 -PhaseDescription "Reading and Categorizing Relevant Test Files"
        $phase2Start = Get-Date

        $processingResult = Invoke-FileProcessingPhase -RelevantFileNames $relevantFileNames -FileContents $fileContents -RepositoryDirectory $RepositoryDirectory -RegexPatterns $Global:RegexPatterns -ThreadCount $Global:ThreadCount -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor

        $resourceFiles = $processingResult.ResourceFiles
        $sequentialFiles = $processingResult.SequentialFiles
        $resourceFunctions = $processingResult.ResourceFunctions

        Show-PhaseMessageHighlight -Message "Found $($resourceFunctions.Count) Test Functions That Reference The Resource" -HighlightText "$($resourceFunctions.Count)" -HighlightColor $Script:NumberColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        Show-PhaseMessageMultiHighlight -Message "Found $($sequentialFiles.Count) Files With Sequential Test Patterns That Reference The Resource" -HighlightTexts @("$($sequentialFiles.Count)", "Sequential Test Patterns") -HighlightColors @($Script:NumberColor, $Script:ItemColor) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        $phase2Duration = (Get-Date) - $phase2Start
        Show-PhaseCompletion -PhaseNumber 2 -DurationMs ([math]::Round($phase2Duration.TotalMilliseconds, 0))
        #endregion

        #region Phase 3: Find Additional Sequential Patterns
        # Phase 3: Find additional sequential files that reference our resource functions
        Show-PhaseHeader -PhaseNumber 3 -PhaseDescription "Finding Additional Sequential Test Patterns"
        $phase3Start = Get-Date

        # Ensure resourceFunctions is not null and is proper array
        if ($null -eq $resourceFunctions -or $resourceFunctions -isnot [array]) {
            $resourceFunctions = @()
        }
        $resourceFunctions = [array]$resourceFunctions

        # Convert relative file names to full paths for consistency
        $allTestFileNamesFull = $allTestFileNames | ForEach-Object { "$RepositoryDirectory\internal\services\$_" }

        try {
            # Ensure we pass a proper array type to avoid parameter binding issues
            $resourceFunctionsArray = @($resourceFunctions)
            $additionalResult = Get-AdditionalSequentialFiles -RepositoryDirectory $RepositoryDirectory -CandidateFileNames $allTestFileNamesFull -ResourceFunctions $resourceFunctionsArray -FileContents $fileContents
        } catch {
            $additionalResult = @{
                AdditionalFiles = @()
                UpdatedFileContents = $fileContents
            }
        }

        $additionalSequentialFiles = $additionalResult.AdditionalFiles
        $fileContents = $additionalResult.UpdatedFileContents

        Show-PhaseMessageMultiHighlight -Message "Found $($additionalSequentialFiles.Count) Additional Sequential Test Patterns That Reference The Resource" -HighlightTexts @("$($additionalSequentialFiles.Count)", "Sequential Test Patterns") -HighlightColors @($Script:NumberColor, $Script:ItemColor) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        # Combine all relevant files
        $allRelevantFiles = @($resourceFiles) + @($additionalSequentialFiles) | Sort-Object FullName -Unique
        Show-PhaseMessageHighlight -Message "Found A Total Of $($allRelevantFiles.Count) Files To Analyze" -HighlightText $($allRelevantFiles.Count) -HighlightColor $Script:NumberColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        $phase3Duration = (Get-Date) - $phase3Start
        Show-PhaseCompletion -PhaseNumber 3 -DurationMs ([math]::Round($phase3Duration.TotalMilliseconds, 0))

        if ($allRelevantFiles.Count -eq 0) {
            Write-Host ""
            Show-PhaseMessageHighlight -Message "No Tests Found For Resource '$CurrentResourceName'" -HighlightText $($CurrentResourceName) -HighlightColor "Magenta" -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

            # Continue to next resource if processing multiple, otherwise exit
            if ($totalResources -gt 1) {
                Write-Host ""
                Write-Host "  Skipping to next resource..." -ForegroundColor Yellow
                Write-Host ""
                continue
            } else {
                exit 0
            }
        }
        #endregion

        #region Phase 4: Database Population and Cross-File Analysis
        # Phase 4: Populate database using cached file contents
        Show-PhaseHeader -PhaseNumber 4 -PhaseDescription "Populating Database Tables"
        $phase4Start = Get-Date

        # Ensure fileContents is not null - use proper null check for hashtables
        if ($null -eq $fileContents -or $fileContents.GetType().Name -ne "Hashtable") {
            $fileContents = @{}
        }

        $databaseResult = Invoke-DatabasePopulation -AllRelevantFiles $allRelevantFiles -FileContents $fileContents -RepositoryDirectory $RepositoryDirectory -RegexPatterns $Global:RegexPatterns -ThreadCount $Global:ThreadCount -ResourceName $CurrentResourceName -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor
        $allTestResults = $databaseResult.AllTestResults
        $allSequentialTests = $databaseResult.AllSequentialTests
        $functionDatabase = $databaseResult.FunctionDatabase

        # Process both regular and sequential test functions into unified TestFunctionSteps table
        $testFunctions = Get-TestFunctions

        # Use encapsulated business logic from TestFunctionStepsProcessing module
        Invoke-TestFunctionStepsProcessing -TestFunctions $testFunctions -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor | Out-Null

        # Phase 4a.5: Resolve cross-file struct references using JOIN-like operations
        Show-PhaseMessageHighlight -Message "Resolving CROSS_FILE Struct References" -HighlightText "CROSS_FILE" -HighlightColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        $crossFileUpdates = Update-CrossFileStructReferences
        Show-PhaseMessageMultiHighlight -Message "Updated $crossFileUpdates CROSS_FILE Records" -HighlightTexts @("$crossFileUpdates", "CROSS_FILE") -HighlightColors @($Script:NumberColor, $Script:ItemColor) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        # Phase 4a.6: Resolve cross-file struct references in TestFunctionSteps
        # Use optimized database-first implementation
        Update-CrossFileStructReferencesInSteps -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor

        # Phase 4a.7: Update referential integrity for unresolved struct visibility
        Update-TestFunctionStepReferentialIntegrity -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor
        $phase4aElapsed = (Get-Date) - $phase4Start

        # Phase 4b: Build template function database for indirect reference detection
        $phase4bStart = Get-Date

        $templateResult = Invoke-TemplateFunctionProcessing -AllRelevantFiles $allRelevantFiles -FileContents $fileContents -RepositoryDirectory $RepositoryDirectory -ResourceName $CurrentResourceName -RegexPatterns $Global:RegexPatterns -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor

        $allTemplateFunctionsWithResource = $templateResult.TemplateFunctions
        # Template database is used internally by the processing functions

        $phase4bElapsed = (Get-Date) - $phase4bStart
        Show-PhaseMessageMultiHighlight -Message "Found $($allTemplateFunctionsWithResource.Count) Test Configuration Functions Containing The Resource ($([math]::Round($phase4bElapsed.TotalMilliseconds, 0)) ms)" -HighlightTexts @("$($allTemplateFunctionsWithResource.Count)", "$([math]::Round($phase4bElapsed.TotalMilliseconds, 0)) ms") -HighlightColors @($Script:NumberColor, $Script:ElapsedColor) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        # Phase 4.5: Dynamic Template Dependency Discovery
        $phase4cStart = Get-Date

        # Ensure allTemplateFunctionsWithResource is not null
        if (-not $allTemplateFunctionsWithResource) {
            $allTemplateFunctionsWithResource = @{}
        }

        $dependencyResult = Invoke-DynamicTemplateDependencyDiscovery -AllTestFileNames $allTestFileNamesFull -RepositoryDirectory $RepositoryDirectory -AllTemplateFunctionsWithResource $allTemplateFunctionsWithResource -RegexPatterns $Global:RegexPatterns -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor

        $newFilesDiscovered = $dependencyResult.NewFilesDiscovered
        $iterationCount = $dependencyResult.IterationCount
        # Note: fileContents now retrieved from database, no longer maintained as hashtable

        $allTemplateFunctionsWithResource = $dependencyResult.UpdatedTemplateFunctions

        $phase4cElapsed = (Get-Date) - $phase4cStart
        # Ensure newFilesDiscovered is not null or empty for display
        if (-not $newFilesDiscovered) { $newFilesDiscovered = 0 }
        Show-PhaseMessageMultiHighlight -Message "Found $newFilesDiscovered New Test Configuration Dependencies In $iterationCount Iterations ($([math]::Round($phase4cElapsed.TotalMilliseconds, 0)) ms)" -HighlightTexts @("$newFilesDiscovered", "$iterationCount", "$([math]::Round($phase4cElapsed.TotalMilliseconds, 0)) ms") -HighlightColors @($Script:NumberColor, $Script:NumberColor, $Script:ElapsedColor) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        Show-PhaseMessageHighlight -Message "Database Population Complete ($([math]::Round($phase4aElapsed.TotalMilliseconds, 0)) ms)" -HighlightText "$([math]::Round($phase4aElapsed.TotalMilliseconds, 0)) ms" -HighlightColor $Script:ElapsedColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        Show-PhaseCompletion -PhaseNumber 4 -DurationMs ([math]::Round(($phase4aElapsed.TotalMilliseconds + $phase4bElapsed.TotalMilliseconds + $phase4cElapsed.TotalMilliseconds), 0))
        #endregion

        #region Phase 5: Resource and Configuration References
        # Phase 5: Populating Resource and Configuration References
        Show-PhaseHeader -PhaseNumber 5 -PhaseDescription "Populating Resource and Configuration References"
        $phase45Start = Get-Date

        # Globals are already set during initialization

        # Use relational approach - pre-load ALL database data ONCE, use O(1) hashtable lookups!
        Invoke-RelationalReferencesPopulation -AllRelevantFiles $allRelevantFiles -ResourceName $CurrentResourceName -RepositoryDirectory $RepositoryDirectory -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor | Out-Null

        # Phase 5.5: Classify ServiceImpactTypeId for template dependencies
        Update-ServiceImpactReferentialIntegrity -ResourceName $CurrentResourceName -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor

        # Note: Proper go test command generation moved to Phase 7 using database-driven approach

        $phase45Elapsed = (Get-Date) - $phase45Start
        Show-PhaseCompletion -PhaseNumber 5 -DurationMs ([math]::Round($phase45Elapsed.TotalMilliseconds, 0))
        #endregion

        #region Phase 6: Sequential References Population
        # Phase 6: Populate SequentialReferences table and update entry points
        Show-PhaseHeader -PhaseNumber 6 -PhaseDescription "Populating SequentialReferences table"
        $phase6Start = Get-Date

        # Ensure variables are not null
        if (-not $allSequentialTests) { $allSequentialTests = @() }
        if (-not $functionDatabase) { $functionDatabase = @{} }

        $sequentialResult = Invoke-SequentialReferencesPopulation -AllSequentialTests $allSequentialTests -FunctionDatabase $functionDatabase
        $sequentialReferencesAdded = $sequentialResult.SequentialReferencesAdded
        $externalStubsCreated = $sequentialResult.ExternalStubsCreated

        if ($sequentialReferencesAdded -gt 0) {
            Show-PhaseMessageMultiHighlight -Message "Inserted $($sequentialReferencesAdded) Sequential Reference Records" -HighlightTexts @("$($sequentialReferencesAdded)", "Sequential Reference Records") -HighlightColors @($Script:NumberColor, $Script:ItemColor) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        }

        if ($externalStubsCreated -gt 0) {
            Show-PhaseMessageMultiHighlight -Message "Created $($externalStubsCreated) External Function Stub Records" -HighlightTexts @("$($externalStubsCreated)", "External Function Stub Records") -HighlightColors @($Script:NumberColor, $Script:ItemColor) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

            # Update sequential entry point references if we have sequential data
            Show-PhaseMessageMultiHighlight -Message "Updating Sequential Entry Point References" -HighlightTexts @("Sequential Entry Point") -HighlightColors @($Script:ItemColor) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
            $entryPointUpdates = Update-SequentialEntryPointReferences
            Show-PhaseMessageMultiHighlight -Message "Updated $entryPointUpdates Sequential Entry Point References In TestFunctions" -HighlightTexts @("$entryPointUpdates", "Sequential Entry Point") -HighlightColors @($Script:NumberColor, $Script:ItemColor) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        } else {
            Show-PhaseMessageMultiHighlight -Message "No Sequential Test Functions Detected - Skipping Sequential Processing" -HighlightTexts @("Sequential Test Functions", "Skipping Sequential Processing") -HighlightColors @($Script:ItemColor, $Script:NumberColor) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        }

        $phase6Elapsed = (Get-Date) - $phase6Start
        Show-PhaseCompletion -PhaseNumber 6 -DurationMs ([math]::Round($phase6Elapsed.TotalMilliseconds, 0))
        #endregion

        #region Accumulate data for Phase 7 (cross-resource go test generation)
        # Accumulate test results and functions from this resource for final Phase 7 processing
        $allTestResultsAccumulator += $allTestResults
        $allSequentialTestsAccumulator += $allSequentialTests
        $resourceFunctionsAccumulator += $resourceFunctions
        #endregion

        #region Display Results Per Resource
        # Display console output using the new UI function
        # Note: Phase 7 (go test commands) moved to after all resources processed
        # TODO: Implement full Show-FinalSummary with complete AnalysisData structure
        #       This should include:
        #       1. Repository Summary (Files With Matches, Direct/Template/Cross-File References, etc.)
        #       2. Unique Test Prefixes section (list of all TestAcc prefixes found)
        #       3. Required Acceptance Test Execution (moved to Phase 7 after all resources)

        # For now, skip per-resource test command display when processing multiple resources
        # Full test commands will be shown after Phase 7 completes

        # Calculate total execution time for this resource
        $resourceElapsed = (Get-Date) - $resourceStartTime

        if ($totalResources -gt 1) {
            Write-Host ""
            Write-Host "  Resource Processing Time: " -ForegroundColor $Script:InfoColor -NoNewline
            $resourceMs = [math]::Round($resourceElapsed.TotalMilliseconds, 0)
            $resourceSeconds = [math]::Round($resourceElapsed.TotalSeconds, 1)
            Write-Host "$resourceMs ms ($resourceSeconds seconds)" -ForegroundColor $Script:ElapsedColor
            Write-Host ""
        }
        #endregion

        # End of resource processing loop
        } # End foreach $CurrentResourceName

        #region Phase 7: Generate Go Test Commands (After All Resources Processed)
        # Phase 7: Group by service and create test command - run once with all accumulated data
        Show-PhaseHeader -PhaseNumber 7 -PhaseDescription "Generating go test commands for all resources"
        $phase7Start = Get-Date

        $serviceResult = Get-ServiceTestResults -AllTestResults $allTestResultsAccumulator -AllSequentialTests $allSequentialTestsAccumulator -ResourceFunctions $resourceFunctionsAccumulator
        $serviceGroups = $serviceResult.ServiceGroups

        $commandsResult = Show-GoTestCommands -ServiceGroups $serviceGroups -ExportDirectory $ExportDirectoryAbsolute -WriteToFile

        $serviceCount = if ($serviceGroups) { $serviceGroups.Count } else { 0 }
        Show-PhaseMessageHighlight -Message "Generated Test Commands For $serviceCount Service$(if ($serviceCount -ne 1) { 's' })" -HighlightText $serviceCount -HighlightColor $Script:NumberColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        if ($commandsResult.OutputFile) {
            $fileName = Split-Path $commandsResult.OutputFile -Leaf
            Show-PhaseMessageHighlight -Message "Exported: $fileName" -HighlightText "$fileName" -HighlightColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        }

        $phase7Elapsed = (Get-Date) - $phase7Start
        Show-PhaseCompletion -PhaseNumber 7 -DurationMs ([math]::Round($phase7Elapsed.TotalMilliseconds, 0))
        #endregion

        #region Phase 8: CSV Export (After All Resources Processed)
        # Phase 8: Output results - Export database once after all resources processed
        $phase8Start = Get-Date
        Show-PhaseHeader -PhaseNumber 8 -PhaseDescription "Exporting Database CSV Files"

        Export-DatabaseToCSV -ItemColor $ItemColor -NumberColor $NumberColor -BaseColor $BaseColor -InfoColor $InfoColor

        $phase8Elapsed = (Get-Date) - $phase8Start
        Show-PhaseCompletion -PhaseNumber 8 -DurationMs ([math]::Round($phase8Elapsed.TotalMilliseconds, 0))
        #endregion

        #region Display Final Test Commands
        # Display console output with all test commands from all resources
        Show-RunTestsByService -ServiceGroups $serviceGroups -CommandsResult $commandsResult -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor
        #endregion

        # Final summary for multiple resources
        if ($totalResources -gt 1) {
            Write-Host ""
            Write-Separator
            Write-Host ""
            Write-Host "  ALL RESOURCES PROCESSED" -ForegroundColor Green
            Write-Host ""
            Write-Host "  Total Resources: " -ForegroundColor $Script:InfoColor -NoNewline
            Write-Host "$totalResources" -ForegroundColor $Script:NumberColor
            Write-Host ""
            Write-Separator
            Write-Host ""
        }

        # Calculate total execution time
        $totalElapsed = (Get-Date) - $scriptStartTime
        Write-Host ""
        $totalMs = [math]::Round($totalElapsed.TotalMilliseconds, 0)
        $totalSeconds = [math]::Round($totalElapsed.TotalSeconds, 1)
        Write-Host "Total Execution Time: $totalMs ms ($totalSeconds seconds)" -ForegroundColor Cyan
        Write-Host ""
        #endregion
        #endregion DISCOVERY MODE
    }

    if (-not $IsDiscoveryMode) {
        #region DATABASE MODE
        # Import database from CSV files
        $importedResources = Import-DatabaseFromCSV -DatabaseDirectory $DatabaseDirectory -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        # Set imported resources in DatabaseMode module for filtering
        Set-ImportedResourcesCache -Resources $importedResources

        # Execute requested query operations
        if ($ShowStatisticsOnly) {
            # Default behavior: Show database statistics and available options
            Show-DatabaseStatistics -Resources $importedResources -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        } else {
            # Show individual reference types if requested
            if ($ShowDirectReferences) {
                Show-DirectReferences -ResourceName $ResourceName -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
            }

            if ($ShowIndirectReferences) {
                Show-IndirectReferences -ResourceName $ResourceName -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
            }
        }

        # Calculate total execution time
        $totalElapsed = (Get-Date) - $scriptStartTime
        Write-Host ""
        $totalMs = [math]::Round($totalElapsed.TotalMilliseconds, 0)
        $totalSeconds = [math]::Round($totalElapsed.TotalSeconds, 1)
        Write-Host "Total Execution Time: $totalMs ms ($totalSeconds seconds)" -ForegroundColor Cyan
        Write-Host ""

        #endregion DATABASE MODE
    }

} catch {
    Write-Host ""
    Write-Host "ERROR: " -ForegroundColor Red -NoNewline
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Cyan
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    throw
} finally {
    # Always restore cursor visibility, even if script fails
    [Console]::CursorVisible = $true
}
#endregion
