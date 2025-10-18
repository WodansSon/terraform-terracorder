#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Find tests to run when modifying a specific Azure resource with database tracking

.DESCRIPTION
    Enhanced tool that answers: "When I change a resource, what tests do I need to run?"

    DISCOVERY MODE (Default):
    Scans repository files, runs all 8 phases, populates database, exports CSVs, and generates go test commands.
    Finds tests that use the resource either:
    1. Directly in test configurations
    2. Via template references
    3. Via acceptance.RunTestsInSequence calls

    DATABASE MODE (Query Only):
    Loads existing CSV database and provides deep analysis without re-scanning files.
    Use this mode for fast, repeatable queries and visualization of previously discovered data.

    If no Show* parameter is specified in Database Mode, displays database statistics only.

.PARAMETER ResourceName
    [Discovery Mode] The Azure resource name to search for (e.g., azurerm_subnet)

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
    # Discovery Mode: Full scan
    .\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"

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
    Version: 1.0
    Author: Terraform Test Discovery Tool

.LINK
    https://github.com/WodansSon/terraform-terracorder
#>

[CmdletBinding(DefaultParameterSetName = "DiscoveryMode")]
param(
    # Discovery Mode parameters
    [Parameter(Mandatory = $false, ParameterSetName = "DiscoveryMode")]
    [string]$ResourceName,

    [Parameter(Mandatory = $false, ParameterSetName = "DiscoveryMode")]
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
# Import and run prerequisites check
$ModulesPath = Join-Path $PSScriptRoot "..\modules"
Import-Module (Join-Path $ModulesPath "Prerequisites.psm1") -Force
Test-Prerequisites -ExitOnFailure | Out-Null
#endregion

#region Module Imports and Initialization
# TerraCorder Version
$Global:TerraCoderVersion = "3.0.0"

# Disable verbose output to reduce noise
$VerbosePreference = 'SilentlyContinue'

# Import required modules in correct dependency order
# Note: Prerequisites.psm1 already imported above
Import-Module (Join-Path $ModulesPath "UI.psm1") -Force                          # Base UI functions (no dependencies)
Import-Module (Join-Path $ModulesPath "Database.psm1") -Force                    # Database functions (uses UI)
Import-Module (Join-Path $ModulesPath "ASTImport.psm1") -Force                   # AST-based import (Phase 1 integration)
Import-Module (Join-Path $ModulesPath "FileDiscovery.psm1") -Force               # File discovery functions
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

if ($DatabaseDirectory) {
    # Database Mode
    # Validate mutually exclusive parameters
    if ($ResourceName -or $RepositoryDirectory) {
        Show-MutuallyExclusiveModesError
        exit 1
    }

    # Validate database directory exists
    if (-not (Test-Path $DatabaseDirectory -PathType Container)) {
        Show-DirectoryNotFoundError -DirectoryType "Database" -DirectoryPath $DatabaseDirectory
        exit 1
    }

} elseif ($ResourceName -and $RepositoryDirectory) {
    # Discovery Mode
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
    Show-InitialBanner -DiscoveryMode -ResourceName $ResourceName -RepositoryDirectory $RepositoryDirectory -ExportDirectory $ExportDirectoryAbsolute
} else {
    Show-InitialBanner -DatabaseDirectory $DatabaseDirectory -ExportDirectory $ExportDirectoryAbsolute
}

Write-Separator
#endregion

#region Mode Execution
# Hide cursor to reduce flashing during progress updates (skip if in background job)
try {
    [Console]::CursorVisible = $false
} catch {
    # Ignore - likely running in background job where console is not available
}

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

        #region Database and Pattern Initialization
        # Initialize database first
        Show-PhaseHeaderGeneric -Title "Database Initialization" -Description "Terra-Corder"
        Initialize-TerraDatabase -ExportDirectory $ExportDirectoryAbsolute -RepositoryDirectory $RepositoryDirectory -ResourceName $ResourceName -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        # Get reference to the ReferenceTypes from Database module after initialization and set as global
        $Global:ReferenceTypes = & (Get-Module Database) { $script:ReferenceTypes }
        #endregion
        #region AST-Based Discovery and Import (v3.0.0 - Replaces Phases 1-6)
        # Phase 1: File Discovery
        Show-PhaseHeader -PhaseNumber 1 -PhaseDescription "File Discovery and Filtering"
        $phase1Start = Get-Date

        $discoveryResult = Get-TestFilesContainingResource -RepositoryDirectory $RepositoryDirectory -ResourceName $ResourceName -UseParallel $true -ThreadCount $Global:ThreadCount -NumberColor $Script:NumberColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor
        $relevantFileNames = $discoveryResult.RelevantFiles

        # Convert relative paths to full paths for Replicode
        $testFiles = $relevantFileNames

        Show-PhaseMessageHighlight -Message "Found $($testFiles.Count) Test Files Containing The Resource" -HighlightText "$($testFiles.Count)" -HighlightColor $Script:NumberColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        $phase1Duration = (Get-Date) - $phase1Start
        Show-PhaseCompletion -PhaseNumber 1 -DurationMs ([math]::Round($phase1Duration.TotalMilliseconds, 0))
        #endregion

        #region Phase 2: AST Analysis and Database Import
        Show-PhaseHeader -PhaseNumber 2 -PhaseDescription "Replicode Analysis and Database Import"
        $phase2Start = Get-Date

        # Verify Replicode exists
        $replicodePath = Join-Path $PSScriptRoot "..\tools\replicode\replicode.exe"
        if (-not (Test-Path $replicodePath)) {
            Write-Host ""
            Show-PhaseMessageHighlight -Message "ERROR: Replicode not found at $replicodePath" -HighlightText "ERROR" -HighlightColor "Red" -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
            exit 1
        }

        # Run Replicode in parallel and import to database
        Import-ASTOutput -ASTAnalyzerPath $replicodePath -TestFiles $testFiles -RepoRoot $RepositoryDirectory -ResourceName $ResourceName -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        # Phase 2.5: Discover Additional Sequential Test Files
        # After initial import, find files with RunTestsInSequence that reference functions we just imported
        Show-PhaseMessageHighlight -Message "Scanning For Additional Sequential Test Entry Points..." -HighlightText "Sequential" -HighlightColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        # Get all test function names from the database - direct property access without looping
        # Don't filter by naming convention - developers can name sequential functions anything!
        $resourceFunctionNames = (Get-TestFunctions).FunctionName

        if ($resourceFunctionNames.Count -gt 0) {
            # Get all test files in the repository to search
            $allTestFiles = Get-ChildItem -Path (Join-Path $RepositoryDirectory "internal\services") -Recurse -Filter "*_test.go" | Select-Object -ExpandProperty FullName

            # Find additional files that have sequential patterns referencing our functions
            $additionalResult = Get-AdditionalSequentialFiles `
                -RepositoryDirectory $RepositoryDirectory `
                -CandidateFileNames $allTestFiles `
                -ResourceFunctions $resourceFunctionNames `
                -FileContents @{}

            $additionalFiles = $additionalResult.AdditionalFiles

            if ($additionalFiles.Count -gt 0) {
                # Filter out files that were already processed in Phase 2 (prevent duplicates!)
                $additionalFilePaths = $additionalFiles | Select-Object -ExpandProperty FullName
                $newFilePaths = $additionalFilePaths | Where-Object { $_ -notin $testFiles }

                if ($newFilePaths.Count -gt 0) {
                    Show-PhaseMessageMultiHighlight -Message "Found $($newFilePaths.Count) Additional Sequential Test Files" -Highlights @(
                        @{ Text = "$($newFilePaths.Count)"; Color = $Script:NumberColor }
                        @{ Text = "Sequential"; Color = $Script:ItemColor }
                    ) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

                    # Import only the NEW files (deduplicated)
                    Import-ASTOutput -ASTAnalyzerPath $replicodePath -TestFiles $newFilePaths -RepoRoot $RepositoryDirectory -ResourceName $ResourceName -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
                } else {
                    Show-PhaseMessageMultiHighlight -Message "All Sequential Test Files Were Already Processed" -Highlights @(
                        @{ Text = "All"; Color = "Yellow" }
                        @{ Text = "Sequential"; Color = $Script:ItemColor }
                    ) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
                }
            } else {
                Show-PhaseMessageMultiHighlight -Message "No Additional Sequential Test Files Found" -Highlights @(
                    @{ Text = "No"; Color = "Yellow" }
                    @{ Text = "Sequential"; Color = $Script:ItemColor }
                ) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
            }
        }

        # Show database statistics
        $stats = Get-DatabaseStats
        $resourceRegCount = $stats.ResourceRegistrations
        $serviceCount = $stats.Services
        $fileCount = $stats.Files
        $structCount = $stats.Structs
        $testFuncCount = $stats.TestFunctions
        $templateFuncCount = $stats.TemplateFunctions
        $testStepCount = $stats.TestFunctionSteps
        $directRefCount = $stats.DirectResourceReferences
        $templateCallCount = $stats.TemplateCallChain

        # Display formatted summary block
        Show-PhaseMessageMultiHighlight -Message "Replicode Analysis Summary:" -Highlights @(
            @{ Text = "Replicode"; Color = $Script:ItemColor }
        ) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        Show-PhaseMessageMultiHighlight -Message "  Registry  : $resourceRegCount Resource-to-Service Mappings" -Highlights @(
            @{ Text = "$resourceRegCount"; Color = $Script:NumberColor }
        ) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        Show-PhaseMessageMultiHighlight -Message "  Structure : $serviceCount Services, $fileCount Files, $structCount Structs" -Highlights @(
            @{ Text = "$serviceCount"; Color = $Script:NumberColor }
            @{ Text = "$fileCount"; Color = $Script:NumberColor }
            @{ Text = "$structCount"; Color = $Script:NumberColor }
        ) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        Show-PhaseMessageMultiHighlight -Message "  Functions : $testFuncCount Tests, $templateFuncCount Configuration" -Highlights @(
            @{ Text = "$testFuncCount"; Color = $Script:NumberColor }
            @{ Text = "$templateFuncCount"; Color = $Script:NumberColor }
        ) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        Show-PhaseMessageMultiHighlight -Message "  References: $testStepCount Steps, $directRefCount Direct, $templateCallCount Calls" -Highlights @(
            @{ Text = "$testStepCount"; Color = $Script:NumberColor }
            @{ Text = "$directRefCount"; Color = $Script:NumberColor }
            @{ Text = "$templateCallCount"; Color = $Script:NumberColor }
        ) -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        $phase2Duration = (Get-Date) - $phase2Start
        Show-PhaseCompletion -PhaseNumber 2 -DurationMs ([math]::Round($phase2Duration.TotalMilliseconds, 0))
        #endregion

        #region Phase 3: CSV Export
        # Phase 3: Export database to CSV files
        Show-PhaseHeader -PhaseNumber 3 -PhaseDescription "Exporting Database to CSV"
        $phase3Start = Get-Date

        Export-DatabaseToCSV -NumberColor $Script:NumberColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        $phase3Duration = (Get-Date) - $phase3Start
        Show-PhaseCompletion -PhaseNumber 3 -DurationMs ([math]::Round($phase3Duration.TotalMilliseconds, 0))
        #endregion

        #region Phase 4: Generate Go Test Commands
        Show-PhaseHeader -PhaseNumber 4 -PhaseDescription "Generating Go Test Commands"
        $phase4Start = Get-Date

        # Get all services that have test files in the database
        $allServices = Get-Services
        $allFiles = Get-Files

        # Group files by service to create service groups
        $serviceGroups = @()
        foreach ($service in $allServices) {
            $serviceFiles = $allFiles | Where-Object { $_.ServiceRefId -eq $service.ServiceRefId }
            if ($serviceFiles) {
                $serviceGroups += @{
                    Name = $service.Name
                    ServiceRefId = $service.ServiceRefId
                }
            }
        }

        # Sort service groups alphabetically by name
        $serviceGroups = $serviceGroups | Sort-Object -Property Name

        if ($serviceGroups.Count -gt 0) {
            $commandsResult = Show-GoTestCommands -ServiceGroups $serviceGroups -ExportDirectory $ExportDirectoryAbsolute -WriteToFile
            # Report actual count of services with test commands, not all services with files
            $actualServiceCount = $commandsResult.ConsoleData.Count
            Show-PhaseMessageHighlight -Message "Generated Test Commands For $actualServiceCount Services" -HighlightText "$actualServiceCount" -HighlightColor $Script:NumberColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
            Show-PhaseMessageHighlight -Message "Exported: go_test_commands.txt" -HighlightText "go_test_commands.txt" -HighlightColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

            $phase4Duration = (Get-Date) - $phase4Start
            Show-PhaseCompletion -PhaseNumber 4 -DurationMs ([math]::Round($phase4Duration.TotalMilliseconds, 0))

            # Display test commands to console
            Show-RunTestsByService -CommandsResult $commandsResult -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor
        } else {
            Show-PhaseMessageHighlight -Message "No Services Found To Generate Test Commands" -HighlightText "No" -HighlightColor "Yellow" -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

            $phase4Duration = (Get-Date) - $phase4Start
            Show-PhaseCompletion -PhaseNumber 4 -DurationMs ([math]::Round($phase4Duration.TotalMilliseconds, 0))
        }

        #endregion

        #region Display Results and Completion
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
        Import-DatabaseFromCSV -DatabaseDirectory $DatabaseDirectory -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor | Out-Null

        # Execute requested query operations (or show statistics if no flags specified)
        if ($ShowDirectReferences) {
            Show-DirectReferences -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        }

        if ($ShowIndirectReferences) {
            Show-IndirectReferences -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
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
    # Always restore cursor visibility, even if script fails (skip if in background job)
    try {
        [Console]::CursorVisible = $true
    } catch {
        # Ignore - likely running in background job where console is not available
    }
}
#endregion
