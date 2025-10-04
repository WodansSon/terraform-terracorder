#Requires -Version 7

<#
.SYNOPSIS
    PowerShell module for UI operations in Terraform test analysis.
.DESCRIPTION
    This module provides output formatting, display functions, and user interface
    operations for the Terraform test analysis script.

    All color values are provided by the main script - this module has no color defaults.
#>

function Show-InitialBanner {
    <#
    .SYNOPSIS
        Displays the initial banner with mode-specific information.

    .PARAMETER DiscoveryMode
        Switch to indicate Discovery Mode. If not specified, Database Mode is assumed.

    .PARAMETER ResourceName
        [Discovery Mode] The Azure resource name being searched for

    .PARAMETER RepositoryDirectory
        [Discovery Mode] Path to terraform-provider-azurerm repository root

    .PARAMETER DatabaseDirectory
        [Database Mode] Path to existing CSV database directory

    .PARAMETER ExportDirectory
        Directory path where CSV export files will be stored
    #>
    param(
        [Parameter(Mandatory = $false)]
        [switch]$DiscoveryMode,

        [Parameter(Mandatory = $false)]
        [string]$ResourceName = "",

        [Parameter(Mandatory = $false)]
        [string]$RepositoryDirectory = "",

        [Parameter(Mandatory = $false)]
        [string]$DatabaseDirectory = "",

        [Parameter(Mandatory = $false)]
        [string]$ExportDirectory = ""
    )

    # Discovery Mode Banner
    Write-Host ""
    Write-Separator
    Write-Host "`e]0;Terra-Corder v$Global:TerraCoderVersion`a" -NoNewline  # Set window title
    $banner = @"
  _____                     ____              _
 |_   _|__ _ __ _ __ __ _  / ___|___  _ __ __| | ___ _ __
   | |/ _ \ '__| '__/ _`` || |   / _ \| '__/ _`` |/ _ \ '__|
   | |  __/ |  | | | (_| || |__| (_) | | | (_| |  __/ |
   |_|\___|_|  |_|  \__,_| \____\___/|_|  \__,_|\___|_|
"@
    # Split banner into lines and apply rainbow colors
    $bannerLines = $banner -split "`n"
    $rainbowColors = @("Red", "Yellow", "Green", "Cyan", "Blue")

    for ($i = 0; $i -lt $bannerLines.Count; $i++) {
        $colorIndex = $i % $rainbowColors.Count
        Write-Host $bannerLines[$i] -ForegroundColor $rainbowColors[$colorIndex]
    }

    Write-Host "`e[0m" -NoNewline  # Reset formatting
    Write-Host ""
    Write-Host "   Terraform AzureRM Provider Test Usage Discovery Tool" -ForegroundColor Cyan
    Write-Host "   Version: $Global:TerraCoderVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Separator
    Write-Host ""

    if ($DiscoveryMode) {
        Write-Host " Resource Name       : " -ForegroundColor Cyan -NoNewline
        Write-Host "$ResourceName" -ForegroundColor Yellow
        Write-Host " Repository Directory: " -ForegroundColor Cyan -NoNewline
        Write-Host "$RepositoryDirectory" -ForegroundColor Green
        Write-Host " Export Directory    : " -ForegroundColor Cyan -NoNewline
        Write-Host "$ExportDirectory" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "  DATABASE MODE (Query Only)" -ForegroundColor Yellow
        Write-Host "  Database Directory: " -ForegroundColor Cyan -NoNewline
        Write-Host "$DatabaseDirectory" -ForegroundColor Green
        Write-Host ""
    }
}

function Show-PhaseHeader {
    <#
    .SYNOPSIS
        Displays a phase header with consistent formatting.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$PhaseNumber,
        [Parameter(Mandatory = $true)]
        [string]$PhaseDescription
    )

    Write-Host ""
    Write-Host "Phase $PhaseNumber`: " -ForegroundColor Yellow -NoNewline
    Write-Host "$PhaseDescription..." -ForegroundColor Green
}

function Show-PhaseHeaderGeneric {
    <#
    .SYNOPSIS
        Displays a generic phase header with consistent formatting (no phase number).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    Write-Host ""
    Write-Host "$Title`: " -ForegroundColor Yellow -NoNewline
    Write-Host "$Description..." -ForegroundColor Green
}

function Show-PhaseMessage {
    <#
    .SYNOPSIS
        Displays a phase message with consistent formatting.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    Write-Host " " -NoNewline
    Write-Host "[INFO]" -ForegroundColor $InfoColor -NoNewline
    Write-Host " $Message" -ForegroundColor $BaseColor
}

function Show-PhaseMessageHighlight {
    <#
    .SYNOPSIS
        Displays a phase message with highlighted text for emphasis.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [string]$HighlightText,
        [Parameter(Mandatory = $false)]
        [string]$HighlightColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    # Replace the highlight text with a placeholder, split the message, then rebuild with colors
    $placeholder = "###HIGHLIGHT###"
    $parts = $Message -replace [regex]::Escape($HighlightText), $placeholder -split $placeholder

    Write-Host " " -NoNewline
    Write-Host "[INFO]" -ForegroundColor $InfoColor -NoNewline
    Write-Host " " -NoNewline
    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($i -gt 0) {
            # Write the highlight text
            Write-Host $HighlightText -ForegroundColor $HighlightColor -NoNewline
        }
        # Write the regular text part
        Write-Host $parts[$i] -ForegroundColor $BaseColor -NoNewline
    }
    Write-Host "" # New line at the end
}

function Show-PhaseMessageMultiHighlight {
    <#
    .SYNOPSIS
        Displays a phase message with multiple highlighted text elements for emphasis.
    .DESCRIPTION
        This function allows highlighting multiple different text elements in a single message,
        each with their own color. Useful for messages that need to emphasize multiple values.
    .PARAMETER Message
        The complete message text containing all the highlight text elements
    .PARAMETER HighlightTexts
        Array of text strings to be highlighted in the message
    .PARAMETER HighlightColors
        Array of colors corresponding to each highlight text. If fewer colors than texts are provided,
        the last color will be reused for remaining texts.
    .EXAMPLE
        Show-PhaseMessageMultiHighlight -Message "Found: Reduced to 1664 files (excluded 1008 irrelevant files)" -HighlightTexts @("1664", "1008") -HighlightColors @("Yellow", "Red")
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [array]$HighlightTexts,
        [Parameter(Mandatory = $false)]
        [array]$HighlightColors = @("Cyan"),
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    # Ensure we have at least one color
    if ($HighlightColors.Count -eq 0) {
        $HighlightColors = @("Cyan")
    }

    # Create a working copy of the message
    $workingMessage = $Message

    # Find all highlight positions with their colors
    $highlights = @()

    for ($i = 0; $i -lt $HighlightTexts.Count; $i++) {
        $text = [string]$HighlightTexts[$i]
        $colorIndex = [Math]::Min($i, $HighlightColors.Count - 1)
        $color = $HighlightColors[$colorIndex]

        # Find all occurrences of this text
        $searchPos = 0
        while (($index = $workingMessage.IndexOf($text, $searchPos)) -ge 0) {
            $highlights += @{
                Start = $index
                End = $index + $text.Length - 1
                Text = $text
                Color = $color
                Length = $text.Length
                Order = $i
            }
            $searchPos = $index + 1  # Move past this occurrence
        }
    }

    # Sort highlights by start position, then by order if same position
    $highlights = $highlights | Sort-Object Start, Order

    # Remove overlapping highlights, keeping the first one at each position
    $filteredHighlights = @()
    $lastEnd = -1

    foreach ($highlight in $highlights) {
        if ($highlight.Start -gt $lastEnd) {
            $filteredHighlights += $highlight
            $lastEnd = $highlight.End
        }
    }

    # Output the message with highlights
    Write-Host " " -NoNewline
    Write-Host "[INFO]" -NoNewline -ForegroundColor $InfoColor
    Write-Host " " -NoNewline

    $currentPos = 0
    foreach ($highlight in $filteredHighlights) {
        # Write text before highlight
        if ($highlight.Start -gt $currentPos) {
            $beforeText = $Message.Substring($currentPos, $highlight.Start - $currentPos)
            Write-Host $beforeText -ForegroundColor $BaseColor -NoNewline
        }

        # Write highlighted text
        Write-Host $highlight.Text -ForegroundColor $highlight.Color -NoNewline

        $currentPos = $highlight.End + 1
    }

    # Write remaining text
    if ($currentPos -lt $Message.Length) {
        $remainingText = $Message.Substring($currentPos)
        Write-Host $remainingText -ForegroundColor $BaseColor -NoNewline
    }

    Write-Host "" # New line
}

function Show-PhaseCompletion {
    <#
    .SYNOPSIS
        Displays a phase completion message with timing information.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$PhaseNumber,
        [Parameter(Mandatory = $true)]
        [int]$DurationMs
    )

    Write-Host "Phase $PhaseNumber`: " -ForegroundColor Yellow -NoNewline
    Write-Host "Completed in $DurationMs ms" -ForegroundColor Green
}

function Show-PhaseCompletionGeneric {
    <#
    .SYNOPSIS
        Displays a generic phase completion message with timing information (no phase number).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [int]$DurationMs
    )

    Write-Host "$Description`: " -ForegroundColor Yellow -NoNewline
    Write-Host "Completed in $DurationMs ms" -ForegroundColor Green
}

function Show-InlineProgress {
    <#
    .SYNOPSIS
        Displays inline progress that overwrites the previous line for dynamic updates.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$Current,
        [Parameter(Mandatory = $true)]
        [int]$Total,
        [Parameter(Mandatory = $false)]
        [string]$Activity = "Processing file",
        [Parameter(Mandatory = $false)]
        [switch]$Completed,
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Green",
        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    if ($Completed) {
        # Final completion message - use Green for completion (matches phase completion messages)
        # Use \r to overwrite the progress line
        Write-Host "`r " -NoNewline
        Write-Host "[INFO]" -NoNewline -ForegroundColor $InfoColor
        Write-Host " $Activity " -NoNewline -ForegroundColor $BaseColor
        Write-Host "$Total" -NoNewline -ForegroundColor $NumberColor
        Write-Host " of " -NoNewline -ForegroundColor $BaseColor
        Write-Host "$Total" -NoNewline -ForegroundColor $NumberColor
        Write-Host " (" -NoNewline -ForegroundColor $BaseColor
        Write-Host "100%" -NoNewline -ForegroundColor Green
        Write-Host ") - " -NoNewline -ForegroundColor $BaseColor
        Write-Host "Complete" -ForegroundColor Green
        # No extra newline - let the calling code handle spacing
    } else {
        # Calculate percentage as whole number
        $percentage = [math]::Round(($Current / $Total) * 100, 0)

        # Use multi-highlight for progress updates
        Write-Host "`r " -NoNewline
        Write-Host "[INFO]" -NoNewline -ForegroundColor $InfoColor
        Write-Host " $Activity " -NoNewline -ForegroundColor $BaseColor
        Write-Host "$Current" -NoNewline -ForegroundColor $NumberColor
        Write-Host " of " -NoNewline -ForegroundColor $BaseColor
        Write-Host "$Total" -NoNewline -ForegroundColor $NumberColor
        Write-Host " (" -NoNewline -ForegroundColor $BaseColor
        Write-Host "$percentage%" -NoNewline -ForegroundColor $NumberColor
        Write-Host ")" -NoNewline -ForegroundColor $BaseColor
    }
}

function Show-RunTestsByService {
    <#
    .SYNOPSIS
        Shows the "Required Acceptance Test Execution" section with go test commands grouped by service.
    .DESCRIPTION
        Displays go test commands for each service, organized by service name with all
        test prefixes for that service joined with pipe separators.
    .PARAMETER ServiceGroups
        Array of service group objects containing Name and test data
    .PARAMETER CommandsResult
        Result object from Show-GoTestCommands containing ConsoleData with test prefixes
    .PARAMETER NumberColor
        Color for numbers in output messages
    .PARAMETER ItemColor
        Color for item types in output messages
    .PARAMETER BaseColor
        Color for base text
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$ServiceGroups,

        [Parameter(Mandatory = $true)]
        [hashtable]$CommandsResult,

        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Green",

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    Write-Host ""
    Write-Separator
    Write-Host " Required Acceptance Test Execution:" -ForegroundColor $ItemColor
    Write-Separator
    Write-Host ""

    # ConsoleData is already pre-filtered, sorted, and contains only services with TestAcc prefixes
    # No need to re-filter or re-sort - just display the data
    $serviceCount = $CommandsResult.ConsoleData.Count

    for ($i = 0; $i -lt $serviceCount; $i++) {
        $serviceData = $CommandsResult.ConsoleData[$i]

        Write-ColoredText @(
            @{ Text = "  Service Name: "; Color = $ItemColor },
            @{ Text = $serviceData.ServiceName; Color = "Magenta" }
        )

        # Build console command from test prefixes (Command property has 2-space indent for file output)
        $testPrefixes = $serviceData.TestPrefixes
        if ($testPrefixes.Count -gt 1) {
            $testPattern = $testPrefixes -join "|"
            $goTestCommand = "go test -timeout 30000s -v ./internal/services/$($serviceData.ServiceName) -run `"$testPattern`""
        } else {
            $goTestCommand = "go test -timeout 30000s -v ./internal/services/$($serviceData.ServiceName) -run $testPrefixes"
        }

        Write-ColoredText @(
            @{ Text = "    "; Color = $BaseColor },
            @{ Text = $goTestCommand; Color = $BaseColor }
        )

        # Only add newline between services (not after the last one)
        if ($i -lt ($serviceCount - 1)) {
            Write-Host ""
        }
    }
}

function Write-Separator {
    <#
    .SYNOPSIS
        Writes a separator line of 60 equal sign characters.
    .DESCRIPTION
        Outputs a line of 60 equal sign characters to create a visual separator.
    #>
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Write-ColoredText {
    <#
    .SYNOPSIS
        Writes text segments with different colors in a single line.
    .DESCRIPTION
        Takes an array of text segments with their colors and writes them consecutively
        without line breaks, making multi-colored output clean and readable.
    .PARAMETER TextSegments
        Array of hashtables with 'Text' and 'Color' properties
    .PARAMETER NewLine
        Whether to add a newline at the end (default: true)
    .EXAMPLE
        Write-ColoredText @(
            @{ Text = "Found "; Color = "Green" },
            @{ Text = "42"; Color = "Yellow" },
            @{ Text = " total test files"; Color = "Green" }
        )
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$TextSegments,

        [Parameter(Mandatory = $false)]
        [bool]$NewLine = $true
    )

    foreach ($segment in $TextSegments) {
        if ($segment -eq $TextSegments[-1] -and $NewLine) {
            # Last segment and we want a newline
            Write-Host $segment.Text -ForegroundColor $segment.Color
        } else {
            # Not the last segment or we don't want a newline
            Write-Host $segment.Text -ForegroundColor $segment.Color -NoNewline
        }
    }

    # If we don't want a newline and we're at the last segment, we still need to handle it
    if (-not $NewLine -and $TextSegments.Count -gt 0) {
        # The loop above already handled it correctly with -NoNewline
    }
}

function Show-GoTestCommands {
    <#
    .SYNOPSIS
        Generate proper go test commands based on database test prefixes
    .DESCRIPTION
        Creates both file output and console display data for go test commands
        using actual test function prefixes from the database
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$ServiceGroups,
        [Parameter(Mandatory = $false)]
        [string]$ExportDirectory = "",
        [Parameter(Mandatory = $false)]
        [switch]$WriteToFile
    )

    $testCommands = @()
    $consoleOutput = @()

    if ($ServiceGroups.Count -gt 0) {
        # PERFORMANCE FIX: Query database ONCE and create lookup tables
        # Instead of 381 database queries (3 queries x 127 services), do 3 queries total
        $allServices = Get-Services
        $allFiles = Get-Files
        $allTestFunctions = Get-TestFunctions

        # Create hashtables for O(1) lookups
        $serviceById = @{}
        $allServices | ForEach-Object { $serviceById[$_.ServiceRefId] = $_ }

        $serviceByName = @{}
        $allServices | ForEach-Object { $serviceByName[$_.Name] = $_ }

        $filesByServiceId = @{}
        $allFiles | ForEach-Object {
            $serviceId = $_.ServiceRefId
            if (-not $filesByServiceId.ContainsKey($serviceId)) {
                $filesByServiceId[$serviceId] = @()
            }
            $filesByServiceId[$serviceId] += $_
        }

        $testFunctionsByFileId = @{}
        $allTestFunctions | Where-Object { $_.FunctionName -match '^Test' } | ForEach-Object {
            $fileId = $_.FileRefId
            if (-not $testFunctionsByFileId.ContainsKey($fileId)) {
                $testFunctionsByFileId[$fileId] = @()
            }
            $testFunctionsByFileId[$fileId] += $_
        }

        for ($i = 0; $i -lt $ServiceGroups.Count; $i++) {
            $serviceGroup = $ServiceGroups[$i]
            $serviceName = $serviceGroup.Name

            # O(1) lookup instead of filtering entire arrays
            $currentService = $serviceByName[$serviceName]

            if ($currentService) {
                $serviceFiles = $filesByServiceId[$currentService.ServiceRefId]
                if (-not $serviceFiles) { $serviceFiles = @() }

                $testPrefixes = @()
                foreach ($file in $serviceFiles) {
                    $fileFunctions = $testFunctionsByFileId[$file.FileRefId]
                    if ($fileFunctions) {
                        $testPrefixes += $fileFunctions | Select-Object -ExpandProperty TestPrefix
                    }
                }
                # Filter to only include test prefixes starting with uppercase letter (Go convention)
                # This includes Test*, Benchmark*, Example*, Fuzz*, etc.
                $testPrefixes = $testPrefixes | Where-Object { $_ -cmatch '^[A-Z]' } | Sort-Object -Unique
            } else {
                $testPrefixes = @()
            }

            if ($testPrefixes.Count -gt 0) {
                # Generate command for file output
                if ($testPrefixes.Count -gt 1) {
                    $pattern = ($testPrefixes -join "|")
                    $fileCommand = "  go test -timeout 30000s -v ./internal/services/$serviceName -run `"$pattern`""
                } else {
                    $singlePrefix = $testPrefixes | Select-Object -First 1
                    $fileCommand = "  go test -timeout 30000s -v ./internal/services/$serviceName -run $singlePrefix"
                }

                # Add to file output
                $testCommands += "# Service: $serviceName ($($testPrefixes.Count) test prefixes)"
                $testCommands += $fileCommand
                $testCommands += ""

                # Add to console output data
                $consoleOutput += @{
                    ServiceName = $serviceName
                    TestPrefixes = $testPrefixes
                    Command = $fileCommand
                }
            }
        }
    }

    $result = @{
        FileCommands = $testCommands
        ConsoleData = $consoleOutput
    }

    # Write to file if requested
    if ($WriteToFile -and $ExportDirectory) {
        $commandsFile = Join-Path $ExportDirectory "go_test_commands.txt"
        $testCommands | Out-File -FilePath $commandsFile -Encoding UTF8
        $result.OutputFile = $commandsFile
    }

    return $result
}

#region Error Display Functions

<#
.SYNOPSIS
    Display a generic error message with consistent formatting

.PARAMETER ErrorTitle
    The error title/type to display

.PARAMETER ErrorMessage
    The main error message

.PARAMETER ShowSeparators
    Whether to show blank lines before and after the error
#>
function Show-ErrorMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ErrorTitle,

        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,

        [Parameter(Mandatory = $false)]
        [switch]$NoSeparators
    )

    if (-not $NoSeparators) {
        Write-Host ""
    }
    Write-Host "$ErrorTitle " -ForegroundColor Red -NoNewline
    Write-Host $ErrorMessage -ForegroundColor Yellow
    if (-not $NoSeparators) {
        Write-Host ""
    }
}

<#
.SYNOPSIS
    Display error message for mutually exclusive mode parameters
#>
function Show-MutuallyExclusiveModesError {
    Show-ErrorMessage -ErrorTitle "ERROR:" -ErrorMessage "Cannot use -DatabaseDirectory with -ResourceName or -RepositoryDirectory"
    Write-Host "TerraCorder operates in two mutually exclusive modes:" -ForegroundColor Cyan
    Write-Host "  1. " -ForegroundColor Cyan -NoNewline
    Write-Host "DISCOVERY MODE" -ForegroundColor Yellow -NoNewline
    Write-Host " - Scan repository files (requires -ResourceName and -RepositoryDirectory)" -ForegroundColor Cyan
    Write-Host "  2. " -ForegroundColor Cyan -NoNewline
    Write-Host "DATABASE MODE" -ForegroundColor Yellow -NoNewline
    Write-Host " - Query existing database (requires -DatabaseDirectory)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  Discovery: " -ForegroundColor Cyan -NoNewline
    Write-Host ".\terracorder.ps1 -ResourceName 'azurerm_subnet' -RepositoryDirectory 'C:\repo'" -ForegroundColor White
    Write-Host "  Database:  " -ForegroundColor Cyan -NoNewline
    Write-Host ".\terracorder.ps1 -DatabaseDirectory 'C:\output' -ShowAllReferences" -ForegroundColor White
    Write-Host ""
}

<#
.SYNOPSIS
    Display error message for directory not found
#>
function Show-DirectoryNotFoundError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryType,

        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )

    Show-ErrorMessage -ErrorTitle "ERROR:" -ErrorMessage "$DirectoryType directory not found: $DirectoryPath"
}

<#
.SYNOPSIS
    Display error message for invalid resource name
#>
function Show-InvalidResourceNameError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceName
    )

    Show-ErrorMessage -ErrorTitle "ERROR:" -ErrorMessage "Invalid resource name: '$ResourceName'. Must start with 'azurerm_'"
}

<#
.SYNOPSIS
    Display error message for missing required parameters
#>
function Show-MissingParametersError {
    Show-ErrorMessage -ErrorTitle "ERROR:" -ErrorMessage "Missing required parameters"
    Write-Host "TerraCorder operates in two modes:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. " -ForegroundColor Cyan -NoNewline
    Write-Host "DISCOVERY MODE" -ForegroundColor Yellow -NoNewline
    Write-Host " - Scan repository and discover test dependencies" -ForegroundColor Cyan
    Write-Host "     Required: " -ForegroundColor Cyan -NoNewline
    Write-Host "-ResourceName <name> -RepositoryDirectory <path>" -ForegroundColor White
    Write-Host ""
    Write-Host "  2. " -ForegroundColor Cyan -NoNewline
    Write-Host "DATABASE MODE" -ForegroundColor Yellow -NoNewline
    Write-Host " - Query existing database without scanning" -ForegroundColor Cyan
    Write-Host "     Required: " -ForegroundColor Cyan -NoNewline
    Write-Host "-DatabaseDirectory <path>" -ForegroundColor White
    Write-Host "     Options:  " -ForegroundColor Cyan -NoNewline
    Write-Host "-ShowDirectReferences, -ShowIndirectReferences, -ShowAllReferences, etc." -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\terracorder.ps1 -ResourceName 'azurerm_subnet' -RepositoryDirectory 'C:\terraform-provider-azurerm'" -ForegroundColor White
    Write-Host "  .\terracorder.ps1 -DatabaseDirectory 'C:\output' -ShowAllReferences" -ForegroundColor White
    Write-Host ""
}

#endregion Error Display Functions

# Export functions
Export-ModuleMember -Function @(
    'Show-InitialBanner',
    'Show-PhaseHeader',
    'Show-PhaseHeaderGeneric',
    'Show-PhaseMessage',
    'Show-PhaseMessageHighlight',
    'Show-PhaseMessageMultiHighlight',
    'Show-PhaseCompletion',
    'Show-PhaseCompletionGeneric',
    'Show-InlineProgress',
    'Show-RunTestsByService',
    'Write-Separator',
    'Write-ColoredText',
    'Show-GoTestCommands',
    'Show-ErrorMessage',
    'Show-MutuallyExclusiveModesError',
    'Show-DirectoryNotFoundError',
    'Show-InvalidResourceNameError',
    'Show-MissingParametersError'
)
