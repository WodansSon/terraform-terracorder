<#
.SYNOPSIS
    PowerShell and Go prerequisites validation module for Terracorder

.DESCRIPTION
    This module provides functions to validate that the required PowerShell version,
    edition, and Go installation are present before running Terracorder.

    Compatible with PowerShell 5.1+ but enforces PowerShell Core 7.0+ and Go 1.21+
    as runtime requirements.

.NOTES
    Version: 1.0
    Compatible: PowerShell 5.1+
    Required: PowerShell Core 7.0+, Go 1.21+
#>

#region Private Functions

<#
.SYNOPSIS
    Check if Go is installed and retrieve version information
#>
function Get-GoVersionInfo {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $result = @{
        Installed = $false
        Version = ""
        VersionMajor = 0
        VersionMinor = 0
        IsValid = $false
    }

    try {
        $goVersionOutput = go version 2>$null
        if ($LASTEXITCODE -eq 0 -and $goVersionOutput) {
            $result.Installed = $true

            # Extract version from output like "go version go1.21.0 windows/amd64"
            if ($goVersionOutput -match 'go version go([\d\.]+)') {
                $result.Version = $matches[1]

                # Parse major.minor version
                if ($result.Version -match '^(\d+)\.(\d+)') {
                    $result.VersionMajor = [int]$matches[1]
                    $result.VersionMinor = [int]$matches[2]
                }
            }

            # Check if version meets minimum requirement (1.21+)
            $result.IsValid = ($result.VersionMajor -gt 1) -or
                              ($result.VersionMajor -eq 1 -and $result.VersionMinor -ge 21)
        }
    } catch {
        $result.Installed = $false
    }

    return $result
}

<#
.SYNOPSIS
    Display prerequisite check results with color coding
#>
function Write-PrerequisiteStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PowerShellInfo,

        [Parameter(Mandatory = $true)]
        [hashtable]$GoInfo,

        [Parameter(Mandatory = $true)]
        [int]$ThreadCount
    )

    Write-Host ""
    Write-Host "Validating PowerShell Prerequisites:" -ForegroundColor Yellow

    # PowerShell Edition
    Write-Host " PowerShell Edition  : " -ForegroundColor Cyan -NoNewline
    $editionColor = if ($PowerShellInfo.Edition -eq 'Core') { 'Green' } else { 'Yellow' }
    Write-Host "$($PowerShellInfo.Edition)" -ForegroundColor $editionColor

    # PowerShell Version
    Write-Host " PowerShell Version  : " -ForegroundColor Cyan -NoNewline
    $versionColor = if ($PowerShellInfo.Version.Major -ge 7) { 'Green' } else { 'Yellow' }
    Write-Host "$($PowerShellInfo.VersionString)" -ForegroundColor $versionColor

    # Go Installation
    Write-Host " Go Installation     : " -ForegroundColor Cyan -NoNewline
    if ($GoInfo.Installed) {
        if ($GoInfo.IsValid) {
            Write-Host "Go $($GoInfo.Version)" -ForegroundColor Green
        } else {
            Write-Host "Go $($GoInfo.Version) (too old)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Not Found" -ForegroundColor Yellow
    }

    # Overall Status
    Write-Host " Status              : " -ForegroundColor Cyan -NoNewline
    if ($PowerShellInfo.MeetsRequirements -and $GoInfo.IsValid) {
        Write-Host "Supported" -ForegroundColor Green
        Write-Host " Threading           : " -ForegroundColor Cyan -NoNewline
        $threadText = if ($ThreadCount -eq 1) { "thread" } else { "threads" }
        Write-Host "$ThreadCount $threadText" -ForegroundColor Green
    } else {
        Write-Host "Unsupported" -ForegroundColor Yellow
    }
}

<#
.SYNOPSIS
    Display detailed error messages for unmet prerequisites
#>
function Write-PrerequisiteErrors {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PowerShellInfo,

        [Parameter(Mandatory = $true)]
        [hashtable]$GoInfo
    )

    Write-Host ""
    Write-Host "ERROR: " -ForegroundColor Red -NoNewline
    Write-Host "Missing required dependencies." -ForegroundColor Magenta
    Write-Host ""

    # Current environment
    Write-Host "Current environment:" -ForegroundColor Yellow
    Write-Host "  PowerShell Edition: " -ForegroundColor Cyan -NoNewline
    Write-Host "$($PowerShellInfo.Edition)" -ForegroundColor Yellow
    Write-Host "  PowerShell Version: " -ForegroundColor Cyan -NoNewline
    Write-Host "$($PowerShellInfo.VersionString)" -ForegroundColor Yellow
    Write-Host "  Go Installation:    " -ForegroundColor Cyan -NoNewline
    if ($GoInfo.Installed) {
        if ($GoInfo.IsValid) {
            Write-Host "Go $($GoInfo.Version)" -ForegroundColor Green
        } else {
            Write-Host "Go $($GoInfo.Version) (too old)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Not Found" -ForegroundColor Yellow
    }
    Write-Host ""

    # Requirements
    Write-Host "Required:" -ForegroundColor Yellow
    Write-Host "  PowerShell Edition: " -ForegroundColor Cyan -NoNewline
    Write-Host "Core" -ForegroundColor Green
    Write-Host "  PowerShell Version: " -ForegroundColor Cyan -NoNewline
    Write-Host "7.0 or later" -ForegroundColor Green
    Write-Host "  Go Installation:    " -ForegroundColor Cyan -NoNewline
    Write-Host "1.21 or later" -ForegroundColor Green
    Write-Host ""

    # Specific guidance
    if (-not $GoInfo.IsValid) {
        if (-not $GoInfo.Installed) {
            Write-Host "Go is required to run Replicode." -ForegroundColor Cyan
            Write-Host "Install Go 1.21 or later from: " -ForegroundColor Cyan -NoNewline
            Write-Host "https://go.dev/dl/" -ForegroundColor Yellow
        } else {
            Write-Host "Go version $($GoInfo.Version) is too old for Replicode." -ForegroundColor Cyan
            Write-Host "Upgrade to Go 1.21 or later from: " -ForegroundColor Cyan -NoNewline
            Write-Host "https://go.dev/dl/" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    if ($PowerShellInfo.Edition -ne 'Core' -or $PowerShellInfo.Version.Major -lt 7) {
        Write-Host "Install PowerShell Core 7.0 or later from: " -ForegroundColor Cyan -NoNewline
        Write-Host "https://github.com/PowerShell/PowerShell" -ForegroundColor Yellow
        Write-Host ""
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Test if all prerequisites are met for running Terracorder

.DESCRIPTION
    Validates that PowerShell Core 7.0+ and Go 1.21+ are installed.
    Displays colorful status output and detailed error messages if requirements are not met.
    Exits with code 1 if prerequisites are not satisfied.

.PARAMETER ExitOnFailure
    If specified, exits the script with code 1 when prerequisites are not met.
    If not specified, returns $false but allows the script to continue.

.OUTPUTS
    System.Boolean - $true if all prerequisites are met, $false otherwise

.EXAMPLE
    Test-Prerequisites -ExitOnFailure
    Validates prerequisites and exits if not met

.EXAMPLE
    if (-not (Test-Prerequisites)) {
        Write-Warning "Prerequisites not met, continuing anyway..."
    }
#>
function Test-Prerequisites {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ExitOnFailure
    )

    # Gather PowerShell information
    $psInfo = @{
        Version = $PSVersionTable.PSVersion
        VersionString = $PSVersionTable.PSVersion.ToString()
        Edition = $PSVersionTable.PSEdition
        MeetsRequirements = ($PSVersionTable.PSEdition -eq 'Core') -and
                           ($PSVersionTable.PSVersion.Major -ge 7)
    }

    # Gather Go information
    $goInfo = Get-GoVersionInfo

    # Calculate optimal thread count for parallel processing
    $threadCount = [Math]::Min(8, [Math]::Max(2, [Environment]::ProcessorCount))

    # Display status
    Write-PrerequisiteStatus -PowerShellInfo $psInfo -GoInfo $goInfo -ThreadCount $threadCount

    # Check if requirements are met
    $allRequirementsMet = $psInfo.MeetsRequirements -and $goInfo.IsValid

    if (-not $allRequirementsMet) {
        Write-PrerequisiteErrors -PowerShellInfo $psInfo -GoInfo $goInfo

        if ($ExitOnFailure) {
            exit 1
        }

        return $false
    }

    # Set global thread count for use by other modules
    $Global:ThreadCount = $threadCount

    return $true
}

#endregion

# Export public functions
Export-ModuleMember -Function Test-Prerequisites
