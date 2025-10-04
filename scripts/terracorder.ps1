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

.PARAMETER ResourceName
    [Discovery Mode] The Azure resource name to search for (e.g., azurerm_subnet)

.PARAMETER RepositoryDirectory
    [Discovery Mode] Path to terraform-provider-azurerm repository root

.PARAMETER DatabaseDirectory
    [Database Mode] Path to existing CSV database directory (mutually exclusive with Discovery Mode)

.PARAMETER ExportDirectory
    Directory path where CSV export files will be stored (defaults to ../output)

.PARAMETER ShowDirectReferences
    [Database Mode] Display all direct resource references

.PARAMETER ShowIndirectReferences
    [Database Mode] Display all indirect/template-based references

.PARAMETER ShowSequentialReferences
    [Database Mode] Display sequential test dependencies

.PARAMETER ShowCrossFileReferences
    [Database Mode] Display cross-file struct references

.PARAMETER ShowAllReferences
    [Database Mode] Display all reference types (equivalent to all Show* flags)

.EXAMPLE
    # Discovery Mode: Full scan
    .\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryDirectory "C:\path\to\terraform-provider-azurerm"

.EXAMPLE
    # Database Mode: Show direct references
    .\terracorder.ps1 -DatabaseDirectory "C:\output" -ShowDirectReferences

.EXAMPLE
    # Database Mode: Show all reference types
    .\terracorder.ps1 -DatabaseDirectory "C:\output" -ShowAllReferences
#>

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
    [string]$ExportDirectory = (Join-Path $PSScriptRoot "..\output"),

    # Database Mode query options
    [Parameter(Mandatory = $false, ParameterSetName = "DatabaseMode")]
    [switch]$ShowDirectReferences,

    [Parameter(Mandatory = $false, ParameterSetName = "DatabaseMode")]
    [switch]$ShowIndirectReferences,

    [Parameter(Mandatory = $false, ParameterSetName = "DatabaseMode")]
    [switch]$ShowSequentialReferences,

    [Parameter(Mandatory = $false, ParameterSetName = "DatabaseMode")]
    [switch]$ShowCrossFileReferences,

    [Parameter(Mandatory = $false, ParameterSetName = "DatabaseMode")]
    [switch]$ShowAllReferences
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

    # Validate at least one query option is specified
    if (-not ($ShowDirectReferences -or $ShowIndirectReferences -or $ShowSequentialReferences -or
              $ShowCrossFileReferences -or $ShowAllReferences)) {
        Write-Host ""
        Write-Host "ERROR: " -ForegroundColor Red -NoNewline
        Write-Host "Database Mode requires at least one query option." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Available options:" -ForegroundColor Cyan
        Write-Host "  -ShowDirectReferences      : Display direct resource references" -ForegroundColor Gray
        Write-Host "  -ShowIndirectReferences    : Display indirect/template references" -ForegroundColor Gray
        Write-Host "  -ShowSequentialReferences  : Display sequential test dependencies" -ForegroundColor Gray
        Write-Host "  -ShowCrossFileReferences   : Display cross-file struct references" -ForegroundColor Gray
        Write-Host "  -ShowAllReferences         : Display all reference types" -ForegroundColor Gray
        Write-Host ""
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

        #region Database and Pattern Initialization
        # Initialize database first, then regex patterns
        Show-PhaseHeaderGeneric -Title "Database Initialization" -Description "Terra-Corder"
        Initialize-TerraDatabase -ExportDirectory $ExportDirectoryAbsolute -RepositoryDirectory $RepositoryDirectory -ResourceName $ResourceName -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -ElapsedColor $Script:ElapsedColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor

        # Initialize regex patterns after database is ready and set as global
        $Global:RegexPatterns = Initialize-RegexPatterns

        # Get reference to the ReferenceTypes from Database module after initialization and set as global
        $Global:ReferenceTypes = & (Get-Module Database) { $script:ReferenceTypes }
        #endregion
        #region Phase 1: File Discovery and Filtering
        # Phase 1: File discovery and filtering
        Show-PhaseHeader -PhaseNumber 1 -PhaseDescription "File Discovery and Filtering"
        $phase1Start = Get-Date

        $discoveryResult = Get-TestFilesContainingResource -RepositoryDirectory $RepositoryDirectory -ResourceName $ResourceName -UseParallel $true -ThreadCount $Global:ThreadCount -NumberColor $Script:NumberColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor
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
            Show-PhaseMessageHighlight -Message "No Tests Found For Resource '$ResourceName'" -HighlightText $($ResourceName) -HighlightColor "Magenta" -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
            exit 0
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

        $databaseResult = Invoke-DatabasePopulation -AllRelevantFiles $allRelevantFiles -FileContents $fileContents -RepositoryDirectory $RepositoryDirectory -RegexPatterns $Global:RegexPatterns -ThreadCount $Global:ThreadCount -ResourceName $ResourceName -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor
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

        $templateResult = Invoke-TemplateFunctionProcessing -AllRelevantFiles $allRelevantFiles -FileContents $fileContents -RepositoryDirectory $RepositoryDirectory -ResourceName $ResourceName -RegexPatterns $Global:RegexPatterns -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor

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
        Invoke-RelationalReferencesPopulation -AllRelevantFiles $allRelevantFiles -ResourceName $ResourceName -RepositoryDirectory $RepositoryDirectory -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor | Out-Null

        # Phase 5.5: Classify ServiceImpactTypeId for template dependencies
        Update-ServiceImpactReferentialIntegrity -ResourceName $ResourceName -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -InfoColor $Script:InfoColor -BaseColor $Script:BaseColor

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

        #region Phase 7: Generate Go Test Commands
        # Phase 7: Group by service and create test command
        Show-PhaseHeader -PhaseNumber 7 -PhaseDescription "Generating go test commands"
        $phase7Start = Get-Date

        $serviceResult = Get-ServiceTestResults -AllTestResults $allTestResults -AllSequentialTests $allSequentialTests -ResourceFunctions $resourceFunctions
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

        #region Phase 8: Output Results
        # Phase 8: Output results
        $phase8Start = Get-Date
        Show-PhaseHeader -PhaseNumber 8 -PhaseDescription "Exporting Database CSV Files"

        Export-DatabaseToCSV -ItemColor $ItemColor -NumberColor $NumberColor -BaseColor $BaseColor -InfoColor $InfoColor

        $phase8Elapsed = (Get-Date) - $phase8Start
        Show-PhaseCompletion -PhaseNumber 8 -DurationMs ([math]::Round($phase8Elapsed.TotalMilliseconds, 0))

        # Ensure variables are still properly initialized for Phase 8
        if ($null -eq $allSequentialTests -or $allSequentialTests -isnot [array]) { $allSequentialTests = @() }
        if ($null -eq $resourceFunctions -or $resourceFunctions -isnot [array]) { $resourceFunctions = @() }

        # Convert to arrays explicitly to ensure proper type and force PowerShell to treat them as collections
        $allSequentialTests = [array]@($allSequentialTests)
        $resourceFunctions = [array]@($resourceFunctions)
        #endregion

        #region Display Results and Completion
        # Display console output using the new UI function
        # TODO: Implement full Show-FinalSummary with complete AnalysisData structure
        #       This should include:
        #       1. Repository Summary (Files With Matches, Direct/Template/Cross-File References, etc.)
        #       2. Unique Test Prefixes section (list of all TestAcc prefixes found)
        #       3. Required Acceptance Test Execution (current go test commands - implemented)
        Show-RunTestsByService -ServiceGroups $serviceGroups -CommandsResult $commandsResult -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor

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

        # Execute requested query operations
        if ($ShowAllReferences) {
            Show-AllReferences -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
        } else {
            # Show individual reference types if requested
            if ($ShowDirectReferences) {
                Show-DirectReferences -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
            }

            if ($ShowIndirectReferences) {
                Show-IndirectReferences -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
            }

            if ($ShowSequentialReferences) {
                Show-SequentialReferences -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
            }

            if ($ShowCrossFileReferences) {
                Show-CrossFileReferences -NumberColor $Script:NumberColor -ItemColor $Script:ItemColor -BaseColor $Script:BaseColor -InfoColor $Script:InfoColor
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
