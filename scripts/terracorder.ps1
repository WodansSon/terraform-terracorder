#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Find all tests that use a specific Azure resource directly or via template references.

.DESCRIPTION
    This script searches through all test files in the internal/services directory
    of a Terraform provider repository to find tests that use a specified Azure resource
    name (e.g., azurerm_subnet). It finds tests that use the resource either:
    1. Directly in the test configurations
    2. Via template references by calling template functions that contain the resource

    The script can automatically detect the Terraform provider repository location or
    you can specify it explicitly using the -RepositoryPath parameter.

    This ensures comprehensive test coverage identification when a resource is modified.

.PARAMETER ResourceName
    The Azure resource name to search for (e.g., azurerm_subnet, azurerm_virtual_network)

.PARAMETER ShowDetails
    Show detailed output including line numbers and context

.PARAMETER OutputFormat
    Output format: 'list' (default), 'json', or 'csv'

.PARAMETER TestFile
    Optional: Test a specific file instead of scanning all files

.PARAMETER TestNamesOnly
    Output only the test names that need to be executed to test for PR impact (one per line)

.PARAMETER TestPrefixes
    Output unique test prefixes (e.g., TestAccChaosStudioCapability_) instead of full test names

.PARAMETER Summary
    Show a concise summary output with just file names and test functions

.PARAMETER RepositoryPath
    Path to the Terraform provider repository root directory (containing internal/services)
    If not specified, will try to auto-detect from current directory

.EXAMPLE
    .\terracorder.ps1 -ResourceName "azurerm_subnet"

.EXAMPLE
    .\terracorder.ps1 -ResourceName "azurerm_subnet" -Summary

.EXAMPLE
    .\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\terraform-provider-azurerm"
#>

[CmdletBinding()]
param(
    [string]$ResourceName,
    [switch]$ShowDetails,
    [ValidateSet('list', 'json', 'csv')]
    [string]$OutputFormat = 'list',
    [string]$TestFile,
    [switch]$TestNamesOnly,
    [switch]$TestPrefixes,
    [switch]$Summary,
    [string]$RepositoryPath,
    [int]$TestConsoleWidth = 0  # For testing progress bar/spinner at different widths
)

# Global variable for testing console width
$Global:TestConsoleWidth = $TestConsoleWidth

#region Core Functions

function Set-AdequateConsoleWidth {
    param(
        [int]$MinimumWidth = 50
    )

    $currentWidth = if ($Global:TestConsoleWidth -gt 0) {
        $Global:TestConsoleWidth
    } else {
        try {
            $Host.UI.RawUI.WindowSize.Width
        } catch {
            80
        }
    }

    if ($currentWidth -lt $MinimumWidth) {
        try {
            $bufferSize = $Host.UI.RawUI.BufferSize
            $windowSize = $Host.UI.RawUI.WindowSize

            if ($bufferSize.Width -lt $MinimumWidth) {
                $bufferSize.Width = $MinimumWidth
                $Host.UI.RawUI.BufferSize = $bufferSize
            }

            if ($windowSize.Width -lt $MinimumWidth) {
                $windowSize.Width = [math]::Min($MinimumWidth, $bufferSize.Width)
                $Host.UI.RawUI.WindowSize = $windowSize
            }

            Write-Host "Console width expanded to $MinimumWidth characters for better progress display." -ForegroundColor Green
        } catch {
            Write-Host ""
            Write-Host "Warning: " -ForegroundColor Yellow -NoNewline
            Write-Host "Console width is $currentWidth characters. For optimal progress display, please expand to at least $MinimumWidth characters." -ForegroundColor Yellow
            Write-Host ""
        }
    }
}

function Test-ResourceNameValid {
    param([string]$ResourceName)

    if ([string]::IsNullOrWhiteSpace($ResourceName)) {
        Write-Host ""
        Write-Host "Error: " -ForegroundColor Red -NoNewline
        Write-Host "ResourceName " -ForegroundColor Yellow -NoNewline
        Write-Host "parameter is required." -ForegroundColor Red
        Write-Host ""
        return $false
    }

    if ($ResourceName -eq "azurerm") {
        Write-Host ""
        Write-Host "Error: ResourceName cannot be just " -ForegroundColor Red -NoNewline
        Write-Host "'azurerm'" -ForegroundColor Red -NoNewline
        Write-Host ". Please specify a complete Azure resource name like 'azurerm_subnet', 'azurerm_virtual_network', etc." -ForegroundColor Red
        Write-Host ""
        return $false
    }

    if ($ResourceName -notmatch '^azurerm_[a-z_]+$') {
        Write-Host ""
        Write-Host "Warning: ResourceName " -ForegroundColor Yellow -NoNewline
        Write-Host "'$ResourceName' " -ForegroundColor Red -NoNewline
        Write-Host "does not follow the expected pattern " -ForegroundColor Yellow -NoNewline
        Write-Host "'azurerm_resourcetype'" -ForegroundColor Cyan -NoNewline
        Write-Host ". This may not return expected results." -ForegroundColor Yellow
    }

    return $true
}

function Initialize-Environment {
    param(
        [string]$ScriptRoot,
        [string]$RepositoryPath
    )

    $rootDir = $null

    if ($RepositoryPath) {
        # Use the provided repository path
        if (-not (Test-Path $RepositoryPath)) {
            throw "Repository path '$RepositoryPath' does not exist."
        }

        $rootDir = Resolve-Path $RepositoryPath

        if (-not (Test-Path "$rootDir\internal\services")) {
            throw "Could not find internal/services directory in '$RepositoryPath'. Make sure this is the terraform-provider-azurerm root directory."
        }
    } else {
        # Try to auto-detect from current directory and script location
        $searchPaths = @(
            (Get-Location).Path,
            $ScriptRoot,
            (Split-Path -Parent $ScriptRoot)
        )

        foreach ($searchPath in $searchPaths) {
            $testPath = Join-Path $searchPath "internal\services"
            if (Test-Path $testPath) {
                $rootDir = $searchPath
                break
            }

            # Also check parent directories up to 3 levels
            $currentPath = $searchPath
            for ($i = 0; $i -lt 3; $i++) {
                $parentPath = Split-Path -Parent $currentPath
                if ($parentPath -eq $currentPath) { break }  # Reached root

                $testPath = Join-Path $parentPath "internal\services"
                if (Test-Path $testPath) {
                    $rootDir = $parentPath
                    break
                }
                $currentPath = $parentPath
            }

            if ($rootDir) { break }
        }

        if (-not $rootDir) {
            $errorMessage = @"
Could not find terraform-provider-azurerm repository root directory.

Please specify the repository path using the -RepositoryPath parameter:
    .\terracorder.ps1 -ResourceName "azurerm_subnet" -RepositoryPath "C:\path\to\terraform-provider-azurerm"

Or run this script from within the terraform-provider-azurerm directory structure.

Searched in:
"@ + ($searchPaths | ForEach-Object { "`n  - $_" })

            throw $errorMessage
        }
    }

    return $rootDir
}

function Get-SearchPatterns {
    param([string]$ResourceName)

    return @(
        "resource\s+`"$ResourceName`"",
        "data\s+`"$ResourceName`"",
        "$ResourceName\.\w+",
        "terraform\s+import\s+$ResourceName",
        "`"$ResourceName`""
    )
}

function Show-ProgressBar {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Activity = "Processing"
    )

    if ($Total -eq 0) { return }

    [Console]::CursorVisible = $false

    $consoleWidth = if ($Global:TestConsoleWidth -gt 0) {
        $Global:TestConsoleWidth
    } else {
        try {
            $Host.UI.RawUI.WindowSize.Width
        } catch {
            80
        }
    }

    $percentage = [math]::Round(($Current / $Total) * 100)
    $spinnerChars = @("|", "/", "-", "\")

    $spinnerIndex = [math]::Floor($Current / 12) % 4
    $spinnerChar = $spinnerChars[$spinnerIndex]

    if ($Current -eq $Total) {
        $spinnerDisplay = "Complete"
    } else {
        $spinnerDisplay = $spinnerChar
    }

    $maxStatusText = "100% ($Total/$Total)"
    $barFixedChars = $Activity.Length + 4 + $maxStatusText.Length
    $margin = 2
    $availableWidth = $consoleWidth - $barFixedChars - $margin

    if ($availableWidth -ge 10) {
        $barWidth = $availableWidth
        $completed = [math]::Round(($Current / $Total) * $barWidth)
        $remaining = $barWidth - $completed

        Write-Host "`r" -NoNewline
        Write-Host "$Activity " -ForegroundColor Cyan -NoNewline
        Write-Host "[" -ForegroundColor Cyan -NoNewline
        Write-Host ("#" * $completed) -ForegroundColor Green -NoNewline
        Write-Host ("-" * $remaining) -ForegroundColor Cyan -NoNewline
        Write-Host "] " -ForegroundColor Cyan -NoNewline
        Write-Host "$percentage%" -ForegroundColor Green -NoNewline
        Write-Host " (" -ForegroundColor Cyan -NoNewline
        Write-Host "$Current" -ForegroundColor Green -NoNewline
        Write-Host "/" -ForegroundColor Cyan -NoNewline
        Write-Host "$Total" -ForegroundColor Green -NoNewline
        Write-Host ")" -ForegroundColor Cyan -NoNewline
    } else {
        Write-Host "`r$Activity" -ForegroundColor Cyan -NoNewline
        Write-Host " $spinnerDisplay " -ForegroundColor Green -NoNewline
        Write-Host "(" -ForegroundColor Cyan -NoNewline
        Write-Host "$Current" -ForegroundColor Green -NoNewline
        Write-Host "/" -ForegroundColor Cyan -NoNewline
        Write-Host "$Total" -ForegroundColor Green -NoNewline
        Write-Host ")" -ForegroundColor Cyan -NoNewline
    }

    if ($Current -eq $Total) {
        Write-Host ""
        [Console]::CursorVisible = $true
    }
}

function Get-TestFiles {
    param(
        [string]$RootDir,
        [string]$TestFile
    )

    if ($TestFile) {
        return Get-Item $TestFile -ErrorAction Stop
    } else {
        return Get-ChildItem -Path "$RootDir\internal\services" -Recurse -Filter "*_test.go"
    }
}

function Test-FileContainsResource {
    param(
        [string]$FilePath,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if (Select-String -Path $FilePath -Pattern $pattern -Quiet) {
            return $true
        }
    }
    return $false
}

function Get-RelativePath {
    param(
        [string]$FullPath,
        [string]$RootDir
    )

    return $FullPath.Replace("$RootDir\", "").Replace("\", "/")
}

#endregion

#region Template Function Analysis

function Find-TemplateFunctions {
    param([string]$Content)

    return [regex]::Matches($Content, 'func\s+(?:\([^)]+\)\s+)?(\w+)\s*\([^)]*(?:acceptance\.TestData|TestData)[^)]*\)\s+string')
}

function Get-FunctionBody {
    param(
        [string]$Content,
        [System.Text.RegularExpressions.Match]$FunctionMatch
    )

    $funcStart = $FunctionMatch.Index
    $remaining = $Content.Substring($funcStart)

    # Find the opening brace of the function
    $openBraceIndex = $remaining.IndexOf('{')
    if ($openBraceIndex -eq -1) {
        return ""
    }

    # Count braces to find the end of the function
    $braceCount = 0
    $inString = $false
    $inChar = $false
    $inComment = $false
    $inLineComment = $false
    $funcBodyEnd = $remaining.Length

    for ($i = $openBraceIndex; $i -lt $remaining.Length; $i++) {
        $char = $remaining[$i]
        $prevChar = if ($i -gt 0) { $remaining[$i-1] } else { '' }
        $nextChar = if ($i -lt $remaining.Length - 1) { $remaining[$i+1] } else { '' }

        # Handle line comments
        if (-not $inString -and -not $inChar -and $char -eq '/' -and $nextChar -eq '/') {
            $inLineComment = $true
            continue
        }
        if ($inLineComment -and ($char -eq "`n" -or $char -eq "`r")) {
            $inLineComment = $false
            continue
        }
        if ($inLineComment) { continue }

        # Handle block comments
        if (-not $inString -and -not $inChar -and $char -eq '/' -and $nextChar -eq '*') {
            $inComment = $true
            continue
        }
        if ($inComment -and $char -eq '*' -and $nextChar -eq '/') {
            $inComment = $false
            $i++ # Skip the '/' character
            continue
        }
        if ($inComment) { continue }

        # Handle string literals
        if (-not $inChar -and $char -eq '"' -and $prevChar -ne '\') {
            $inString = -not $inString
            continue
        }
        if (-not $inString -and $char -eq "'" -and $prevChar -ne '\') {
            $inChar = -not $inChar
            continue
        }

        # Skip if we're inside a string or char literal
        if ($inString -or $inChar) { continue }

        # Count braces
        if ($char -eq '{') {
            $braceCount++
        } elseif ($char -eq '}') {
            $braceCount--
            if ($braceCount -eq 0) {
                $funcBodyEnd = $i + 1
                break
            }
        }
    }

    return $remaining.Substring(0, [Math]::Min($funcBodyEnd, $remaining.Length))
}

function Test-FunctionContainsResource {
    param(
        [string]$FunctionBody,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($FunctionBody -match $pattern) {
            return $true
        }
    }
    return $false
}

function Find-AllTemplateFunctionsWithResource {
    param(
        [System.IO.FileInfo[]]$TestFiles,
        [string[]]$Patterns,
        [string]$RootDir,
        [bool]$ShowProgress,
        [bool]$ShowVerbose = $true
    )

    $allTemplateFunctionsWithResource = @{}

    if ($ShowVerbose) {
        Write-Host "Phase 1: Finding template functions containing resource..." -ForegroundColor Yellow
    }

    $currentIndex = 0
    $totalFiles = $TestFiles.Count

    foreach ($file in $TestFiles) {
        $currentIndex++

        if (-not $ShowProgress) {
            Show-ProgressBar -Current $currentIndex -Total $totalFiles -Activity "Scanning Template Functions:"
        }

        if (-not (Test-FileContainsResource -FilePath $file.FullName -Patterns $Patterns)) {
            continue
        }

        $relativePath = Get-RelativePath -FullPath $file.FullName -RootDir $RootDir
        $content = Get-Content -Path $file.FullName -Raw
        $templateFunctions = Find-TemplateFunctions -Content $content

        foreach ($match in $templateFunctions) {
            $funcName = $match.Groups[1].Value
            $funcBody = Get-FunctionBody -Content $content -FunctionMatch $match

            if (Test-FunctionContainsResource -FunctionBody $funcBody -Patterns $Patterns) {
                if (-not $allTemplateFunctionsWithResource.ContainsKey($funcName)) {
                    $allTemplateFunctionsWithResource[$funcName] = @()
                }
                $allTemplateFunctionsWithResource[$funcName] += $relativePath

                if ($ShowVerbose) {
                    Write-Host "  Found Template: " -ForegroundColor Cyan -NoNewline
                    Write-Host "'$funcName' " -ForegroundColor Magenta -NoNewline
                    Write-Host "containing resource in " -ForegroundColor Gray -NoNewline
                    Write-Host "./$relativePath" -ForegroundColor Cyan
                }
            }
        }
    }

    if ($ShowVerbose) {
        $color = if ($allTemplateFunctionsWithResource.Count -eq 0) { "Red" } else { "Yellow" }
        Write-Host "Found $($allTemplateFunctionsWithResource.Count) template/test functions containing the resource" -ForegroundColor $color
        Write-Host ""
    }

    # Universal check: Exit if no template functions found
    if ($allTemplateFunctionsWithResource.Count -eq 0) {
        Write-Host "No template/test functions found containing " -ForegroundColor Red -NoNewline
        Write-Host "'$ResourceName'" -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }

    return $allTemplateFunctionsWithResource
}

#endregion

#region Direct Resource Usage Analysis

function Find-DirectResourceMatches {
    param(
        [string]$FilePath,
        [string[]]$Patterns
    )

    $matchResults = @()
    $lines = Get-Content -Path $FilePath
    $lineNumber = 0

    foreach ($line in $lines) {
        $lineNumber++

        foreach ($pattern in $Patterns) {
            if ($line -match $pattern) {
                $matchResults += [PSCustomObject]@{
                    Line = $lineNumber
                    Content = $line.Trim()
                    Pattern = $pattern
                    Type = "Direct"
                }
                break
            }
        }
    }

    return $matchResults
}

function Find-TemplateReferenceMatches {
    param(
        [string]$Content,
        [string]$FilePath,
        [hashtable]$AllTemplateFunctionsWithResource,
        [string]$ResourceName
    )

    $matchResults = @()
    $relevantTemplateFunctions = @()

    foreach ($templateFunc in $AllTemplateFunctionsWithResource.Keys) {
        $templateFiles = $AllTemplateFunctionsWithResource[$templateFunc]
        $relevantToResource = $false

        foreach ($templateFile in $templateFiles) {
            if ($templateFile -match $ResourceName.Replace("azurerm_", "")) {
                $relevantToResource = $true
                break
            }
        }

        if ($relevantToResource -and $Content -match "\b$templateFunc\s*\(") {
            $lines = Get-Content -Path $FilePath
            $lineNumber = 0

            foreach ($line in $lines) {
                $lineNumber++
                if ($line -match "\b$templateFunc\s*\(") {
                    $matchResults += [PSCustomObject]@{
                        Line = $lineNumber
                        Content = $line.Trim()
                        Pattern = "Template function call: $templateFunc"
                        Type = "Template Reference"
                        TemplateFunction = $templateFunc
                    }
                }
            }

            $relevantTemplateFunctions += $templateFunc
        }
    }

    return @{
        Matches = $matchResults
        RelevantTemplateFunctions = $relevantTemplateFunctions
    }
}

#endregion

#region Test Function Analysis

function Find-TestFunctions {
    param([string]$Content)

    return [regex]::Matches($Content, 'func\s+(Test\w+)\s*\(')
}

function Test-TestFunctionUsesResource {
    param(
        [string]$Content,
        [string]$TestFuncName,
        [string[]]$Patterns,
        [hashtable]$AllTemplateFunctionsWithResource,
        [string]$ResourceName
    )

    $funcStart = $Content.IndexOf("func $TestFuncName")
    if ($funcStart -lt 0) {
        return $false
    }

    $funcChunk = $Content.Substring($funcStart, [Math]::Min(2000, $Content.Length - $funcStart))

    foreach ($pattern in $Patterns) {
        if ($funcChunk -match $pattern) {
            return $true
        }
    }

    foreach ($templateFunc in $AllTemplateFunctionsWithResource.Keys) {
        $templateFiles = $AllTemplateFunctionsWithResource[$templateFunc]
        $relevantToResource = $false

        foreach ($templateFile in $templateFiles) {
            if ($templateFile -match $ResourceName.Replace("azurerm_", "")) {
                $relevantToResource = $true
                break
            }
        }

        if ($relevantToResource -and ($funcChunk -match "\b$templateFunc\s*\(" -or $funcChunk -match "\b$templateFunc\b")) {
            return $true
        }
    }

    return $false
}

function Find-RelevantTestFunctions {
    param(
        [string]$Content,
        [string[]]$Patterns,
        [hashtable]$AllTemplateFunctionsWithResource,
        [string]$ResourceName
    )

    $relevantTestFunctions = @()
    $testFunctions = Find-TestFunctions -Content $Content

    foreach ($match in $testFunctions) {
        $testFuncName = $match.Groups[1].Value

        if (Test-TestFunctionUsesResource -Content $Content -TestFuncName $testFuncName -Patterns $Patterns -AllTemplateFunctionsWithResource $AllTemplateFunctionsWithResource -ResourceName $ResourceName) {
            $relevantTestFunctions += $testFuncName
        }
    }

    return $relevantTestFunctions
}

#endregion

#region File Processing

function Invoke-TestFile {
    param(
        [System.IO.FileInfo]$File,
        [string[]]$Patterns,
        [hashtable]$AllTemplateFunctionsWithResource,
        [string]$ResourceName,
        [string]$RootDir
    )

    if (-not (Test-FileContainsResource -FilePath $File.FullName -Patterns $Patterns)) {
        return $null
    }

    $content = Get-Content -Path $File.FullName -Raw
    $relativePath = Get-RelativePath -FullPath $File.FullName -RootDir $RootDir

    $directMatches = Find-DirectResourceMatches -FilePath $File.FullName -Patterns $Patterns
    $templateResult = Find-TemplateReferenceMatches -Content $content -FilePath $File.FullName -AllTemplateFunctionsWithResource $AllTemplateFunctionsWithResource -ResourceName $ResourceName
    $relevantTestFunctions = Find-RelevantTestFunctions -Content $content -Patterns $Patterns -AllTemplateFunctionsWithResource $AllTemplateFunctionsWithResource -ResourceName $ResourceName

    $allMatches = @()
    if ($directMatches) {
        $allMatches += $directMatches
    }
    if ($templateResult.Matches) {
        $allMatches += $templateResult.Matches
    }

    if ($allMatches.Count -eq 0 -and $relevantTestFunctions.Count -eq 0) {
        return $null
    }

    return [PSCustomObject]@{
        File = $relativePath
        FullPath = $File.FullName
        MatchCount = $allMatches.Count
        DirectMatches = $directMatches.Count
        TemplateReferenceMatches = $templateResult.Matches.Count
        TestFunctions = $relevantTestFunctions
        TemplateFunctions = $templateResult.RelevantTemplateFunctions
        Matches = $allMatches
    }
}

function Invoke-AllTestFiles {
    param(
        [System.IO.FileInfo[]]$TestFiles,
        [string[]]$Patterns,
        [hashtable]$AllTemplateFunctionsWithResource,
        [string]$ResourceName,
        [string]$RootDir,
        [bool]$ShowProgress,
        [bool]$ShowVerbose = $true
    )

    $results = @()

    if ($ShowVerbose) {
        Write-Host "Phase 2: Finding test functions that use the resource..." -ForegroundColor Yellow
    }

    $currentIndex = 0
    $totalFiles = $TestFiles.Count

    foreach ($file in $TestFiles) {
        $currentIndex++

        if (-not $ShowProgress) {
            Show-ProgressBar -Current $currentIndex -Total $totalFiles -Activity "Analyzing Test Files       :"
        }

        $result = Invoke-TestFile -File $file -Patterns $Patterns -AllTemplateFunctionsWithResource $AllTemplateFunctionsWithResource -ResourceName $ResourceName -RootDir $RootDir

        if ($result) {
            $results += $result

            if ($ShowVerbose) {
                $usageType = if ($result.DirectMatches -gt 0 -and $result.TemplateReferenceMatches -gt 0) { "Direct + Template Reference" }
                             elseif ($result.DirectMatches -gt 0) { "Direct" }
                             else { "Template Reference" }

                Write-Host "  Found File: " -ForegroundColor Green -NoNewline
                Write-Host "./$($result.File) " -ForegroundColor Cyan -NoNewline
                Write-Host "($usageType usage)" -ForegroundColor Magenta
            }
        }
    }

    if ($ShowVerbose) {
        Write-Host ""
    }

    return $results
}

#endregion

#region Output Functions

function Write-TestNamesOnly {
    param([PSCustomObject[]]$Results)

    $allTestNames = @()
    foreach ($result in $Results) {
        foreach ($testFunc in $result.TestFunctions) {
            $allTestNames += $testFunc
        }
    }

    $uniqueTestNames = $allTestNames | Sort-Object | Get-Unique
    foreach ($testName in $uniqueTestNames) {
        Write-Output $testName
    }
}

function Get-TestPrefixFromName {
    param([string]$TestFunctionName)

    # Extract prefix - handle both standard pattern (TestAccResource_) and sequential pattern (TestAccResourceSequential)
    if ($TestFunctionName -match '^(TestAcc[^_]+_)') {
        # Standard pattern: TestAccResourceName_scenario
        return $matches[1]
    } elseif ($TestFunctionName -match '^(TestAcc.+Sequential)$') {
        # Sequential pattern: TestAccResourceNameSequential - use the full name as prefix
        return $matches[1]
    } elseif ($TestFunctionName -match '^(TestAcc.+)$') {
        # Other patterns without underscore: use the whole function name as prefix
        return $matches[1]
    }

    return ""
}

function Group-TestsByService {
    param([PSCustomObject[]]$Results)

    $serviceTestPrefixes = @{}

    foreach ($result in $Results) {
        $pathParts = $result.File -split '[/\\]'
        $serviceName = "other"
        if ($pathParts.Length -ge 3 -and $pathParts[0] -eq "internal" -and $pathParts[1] -eq "services") {
            $serviceName = $pathParts[2]
        }

        foreach ($testFunc in $result.TestFunctions) {
            $prefix = Get-TestPrefixFromName -TestFunctionName $testFunc

            if ($prefix -ne "") {
                if (-not $serviceTestPrefixes.ContainsKey($serviceName)) {
                    $serviceTestPrefixes[$serviceName] = @()
                }
                $serviceTestPrefixes[$serviceName] += $prefix
            }
        }
    }

    return $serviceTestPrefixes
}

function Write-TestPrefixes {
    param(
        [PSCustomObject[]]$Results,
        [hashtable]$AllTemplateFunctionsWithResource
    )

    # Show repository summary first
    Write-RepositorySummary -Results $Results -AllTemplateFunctionsWithResource $AllTemplateFunctionsWithResource

    $serviceTestPrefixes = Group-TestsByService -Results $Results

    Write-Host "Test Prefixes (for running test groups):" -ForegroundColor Cyan
    $allTestPrefixes = @()
    foreach ($service in $serviceTestPrefixes.Keys) {
        foreach ($prefix in $serviceTestPrefixes[$service]) {
            $allTestPrefixes += $prefix
        }
    }
    $uniqueTestPrefixes = $allTestPrefixes | Sort-Object | Get-Unique
    foreach ($prefix in $uniqueTestPrefixes) {
        Write-Host "  $prefix" -ForegroundColor Magenta
    }

    Write-Host ""
    Write-Host "Run Tests by Service:" -ForegroundColor Cyan
    $sortedServices = $serviceTestPrefixes.Keys | Sort-Object
    foreach ($serviceName in $sortedServices) {
        $serviceUniquePrefixes = $serviceTestPrefixes[$serviceName] | Sort-Object | Get-Unique
        $serviceConcatenated = $serviceUniquePrefixes -join '|'
        Write-Host ""
        Write-Host "  Service Name: " -ForegroundColor Cyan -NoNewline
        Write-Host "$serviceName" -ForegroundColor Magenta

        if ($serviceConcatenated -match '\|') {
            Write-Host "    go test -timeout 30000s -v ./internal/services/$serviceName -run `"$serviceConcatenated`"" -ForegroundColor Gray
        } else {
            Write-Host "    go test -timeout 30000s -v ./internal/services/$serviceName -run $serviceConcatenated" -ForegroundColor Gray
        }
    }
    Write-Host ""
}

function Convert-ToJson {
    param(
        [PSCustomObject[]]$Results,
        [hashtable]$AllTemplateFunctionsWithResource,
        [string]$ResourceName,
        [bool]$ShowDetails
    )

    $totalMatches = ($Results | Measure-Object -Property MatchCount -Sum).Sum

    $jsonOutput = @{
        ResourceName = $ResourceName
        TotalFiles = $Results.Count
        TotalMatches = $totalMatches
        TemplateFunctionsWithResource = $AllTemplateFunctionsWithResource
        Files = $Results | ForEach-Object {
            @{
                File = $_.File
                MatchCount = $_.MatchCount
                DirectMatches = $_.DirectMatches
                TemplateReferenceMatches = $_.TemplateReferenceMatches
                TestFunctions = $_.TestFunctions
                TemplateFunctions = $_.TemplateFunctions
                Matches = if ($ShowDetails) { $_.Matches } else { $null }
            }
        }
    }
    $jsonOutput | ConvertTo-Json -Depth 6
}

function Convert-ToCsv {
    param(
        [PSCustomObject[]]$Results,
        [string]$ResourceName
    )

    $csvData = @()
    foreach ($result in $Results) {
        foreach ($testFunc in $result.TestFunctions) {
            $csvData += [PSCustomObject]@{
                ResourceName = $ResourceName
                File = $result.File
                TestFunction = $testFunc
                UsageType = if ($result.DirectMatches -gt 0 -and $result.TemplateReferenceMatches -gt 0) { "Direct+TemplateReference" }
                           elseif ($result.DirectMatches -gt 0) { "Direct" }
                           else { "TemplateReference" }
                TemplateFunctions = ($result.TemplateFunctions -join '; ')
                TotalMatches = $result.MatchCount
                DirectMatches = $result.DirectMatches
                TemplateReferenceMatches = $result.TemplateReferenceMatches
            }
        }
    }
    $csvData | ConvertTo-Csv -NoTypeInformation
}

function Write-Summary {
    param([PSCustomObject[]]$Results)

    Write-Host "Found $($Results.Count) test files using resource '$ResourceName':" -ForegroundColor Green
    Write-Host ""

    foreach ($result in $Results | Sort-Object File) {
        Write-Host "File: " -ForegroundColor Cyan -NoNewline
        Write-Host "./$($result.File)" -ForegroundColor DarkGreen
        if ($result.TestFunctions.Count -gt 0) {
            Write-Host "   Test Functions:" -ForegroundColor Cyan
            foreach ($func in $result.TestFunctions | Sort-Object) {
                Write-Host "     $func" -ForegroundColor Magenta
            }
        }
        Write-Host ""
    }
}

function Write-Detailed {
    param(
        [PSCustomObject[]]$Results,
        [bool]$ShowDetails
    )

    Write-Host "Found $($Results.Count) test files using resource '$ResourceName':" -ForegroundColor Green
    Write-Host ""

    foreach ($result in $Results | Sort-Object File) {
        $usageType = if ($result.DirectMatches -gt 0 -and $result.TemplateReferenceMatches -gt 0) { "Direct + Template Reference" }
                    elseif ($result.DirectMatches -gt 0) { "Direct" }
                    else { "Template Reference" }

        Write-Host "File: " -ForegroundColor Cyan -NoNewline
        Write-Host "./$($result.File)" -ForegroundColor Green
        Write-Host "   Usage: " -ForegroundColor Cyan -NoNewline
        Write-Host "$usageType ($($result.DirectMatches) direct, $($result.TemplateReferenceMatches) template reference matches)" -ForegroundColor Magenta

        if ($result.TestFunctions.Count -gt 0) {
            Write-Host ""
            Write-Host "   Resource Test Functions:" -ForegroundColor Cyan
            foreach ($func in $result.TestFunctions | Sort-Object) {
                Write-Host "     $func" -ForegroundColor Yellow
            }
        }

        if ($result.TemplateFunctions.Count -gt 0) {
            Write-Host ""
            Write-Host "   Test Configurations That Uses Template Functions:" -ForegroundColor Cyan
            foreach ($func in $result.TemplateFunctions | Sort-Object) {
                Write-Host "     $func (contains resource: $ResourceName)" -ForegroundColor Yellow
            }
        }

        if ($ShowDetails -and $result.Matches.Count -gt 0) {
            Write-Host "   Matches:" -ForegroundColor Gray
            foreach ($match in $result.Matches | Sort-Object Line) {
                $color = if ($match.Type -eq "Direct") { "White" } else { "Yellow" }
                Write-Host "     Line $($match.Line): $($match.Content)" -ForegroundColor $color
            }
        }
        Write-Host ""
    }
}

function Write-RepositorySummary {
    param(
        [PSCustomObject[]]$Results,
        [hashtable]$AllTemplateFunctionsWithResource
    )

    $totalMatches = ($Results | Measure-Object -Property MatchCount -Sum).Sum
    $totalDirectMatches = ($Results | Measure-Object -Property DirectMatches -Sum).Sum
    $totalTemplateMatches = ($Results | Measure-Object -Property TemplateReferenceMatches -Sum).Sum
    $allTestFunctions = $Results | ForEach-Object { $_.TestFunctions } | Sort-Object -Unique
    $serviceTestPrefixes = Group-TestsByService -Results $Results

    $allTestPrefixes = @()
    foreach ($result in $Results) {
        foreach ($testFunc in $result.TestFunctions) {
            $prefix = Get-TestPrefixFromName -TestFunctionName $testFunc
            if ($prefix -ne "") {
                $allTestPrefixes += $prefix
            }
        }
    }
    $uniqueTestPrefixes = $allTestPrefixes | Sort-Object | Get-Unique

    Write-Host ""
    Write-Host "Repository Summary:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Files With Matches                    : " -ForegroundColor Cyan -NoNewline
    Write-Host "$($Results.Count)" -ForegroundColor Green
    Write-Host "  Total Direct Reference Matches        : " -ForegroundColor Cyan -NoNewline
    Write-Host "$totalDirectMatches" -ForegroundColor Yellow
    Write-Host "  Total Template Reference Matches      : " -ForegroundColor Cyan -NoNewline
    Write-Host "$totalTemplateMatches" -ForegroundColor Yellow
    Write-Host "    - Total Matches Found               : " -ForegroundColor Cyan -NoNewline
    Write-Host "$totalMatches" -ForegroundColor Green
    Write-Host "  Total Test Functions                  : " -ForegroundColor Cyan -NoNewline
    Write-Host "$($allTestFunctions.Count)" -ForegroundColor Green
    Write-Host "  Template Functions Containing Resource: " -ForegroundColor Cyan -NoNewline
    Write-Host "$($AllTemplateFunctionsWithResource.Count)" -ForegroundColor Green
    Write-Host "  Unique Test Prefixes                  : " -ForegroundColor Cyan -NoNewline
    Write-Host "$($uniqueTestPrefixes.Count)" -ForegroundColor Green
    Write-Host "  Total Services                        : " -ForegroundColor Cyan -NoNewline
    Write-Host "$($serviceTestPrefixes.Count)" -ForegroundColor Green
    Write-Host ""
}

function Write-List {
    param(
        [PSCustomObject[]]$Results,
        [hashtable]$AllTemplateFunctionsWithResource,
        [bool]$Summary,
        [bool]$ShowDetails
    )

    if ($Results.Count -eq 0) {
        Write-Host "No test files found using resource: $ResourceName" -ForegroundColor Red
        return
    }

    if ($Summary) {
        Write-Summary -Results $Results
    } else {
        Write-Detailed -Results $Results -ShowDetails $ShowDetails
    }

    Write-RepositorySummary -Results $Results -AllTemplateFunctionsWithResource $AllTemplateFunctionsWithResource
}

#endregion

#region Main Execution

function Main {
    try {
        if (-not (Test-ResourceNameValid -ResourceName $ResourceName)) {
            exit 1
        }

        Set-AdequateConsoleWidth -MinimumWidth 50
        $rootDir = Initialize-Environment -ScriptRoot $PSScriptRoot -RepositoryPath $RepositoryPath

        Write-Host ""
        # Display initial message (suppress for TestNamesOnly)
        if (-not $TestNamesOnly) {
            if ($Summary) {
                Write-Host "Scanning for all test files using resource: '$ResourceName'..." -ForegroundColor Green
            } else {
                Write-Host "Searching for tests using resource: '$ResourceName'..." -ForegroundColor Green
            }

            Write-Host ""
        }

        $patterns = Get-SearchPatterns -ResourceName $ResourceName
        $testFiles = Get-TestFiles -RootDir $rootDir -TestFile $TestFile

        # Suppress progress output for TestNamesOnly or Summary modes
        $showProgress = (-not $Summary)
        $showVerbose = (-not $Summary) -and (-not $TestNamesOnly)
        $allTemplateFunctionsWithResource = Find-AllTemplateFunctionsWithResource -TestFiles $testFiles -Patterns $patterns -RootDir $rootDir -ShowProgress $showProgress -ShowVerbose $showVerbose
        $results = Invoke-AllTestFiles -TestFiles $testFiles -Patterns $patterns -AllTemplateFunctionsWithResource $allTemplateFunctionsWithResource -ResourceName $ResourceName -RootDir $rootDir -ShowProgress $showProgress -ShowVerbose $showVerbose

        switch ($true) {
            $TestNamesOnly {
                Write-TestNamesOnly -Results $results
                exit 0
            }
            ($TestPrefixes -or $Summary) {
                Write-TestPrefixes -Results $results -AllTemplateFunctionsWithResource $allTemplateFunctionsWithResource
                exit 0
            }
            ($OutputFormat -eq 'json') {
                Convert-ToJson -Results $results -AllTemplateFunctionsWithResource $allTemplateFunctionsWithResource -ResourceName $ResourceName -ShowDetails $ShowDetails
            }
            ($OutputFormat -eq 'csv') {
                Convert-ToCsv -Results $results -ResourceName $ResourceName
            }
            default {
                Write-List -Results $results -AllTemplateFunctionsWithResource $allTemplateFunctionsWithResource -Summary $Summary -ShowDetails $ShowDetails
            }
        }
    }
    catch {
        Write-Host "Error Occurred: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Line Number   : $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        Write-Host "Exception Type: $($_.Exception.GetType().Name)" -ForegroundColor Red
        exit 1
    }
}

#region Test Functions

function Test-ProgressBarAtDifferentWidths {
    param(
        [string]$Activity = "Testing Progress",
        [int]$Total = 100
    )

    $testWidths = @(15, 25, 35, 50, 80, 120)

    Write-Host ""
    Write-Host "Testing Progress Bar at Different Console Widths:" -ForegroundColor Cyan
    Write-Host "=" * 50 -ForegroundColor Gray

    foreach ($width in $testWidths) {
        Write-Host ""
        Write-Host "Console Width: $width characters" -ForegroundColor Yellow
        Write-Host "-" * $width -ForegroundColor Gray

        # Set global test width
        $Global:TestConsoleWidth = $width

        # Simulate progress at this width
        for ($i = 0; $i -le $Total; $i += 20) {
            Show-ProgressBar -Current $i -Total $Total -Activity $Activity
            Start-Sleep -Milliseconds 200
        }

        Write-Host ""  # Extra line for spacing
    }

    $Global:TestConsoleWidth = 0

    Write-Host ""
    Write-Host "Progress bar test completed!" -ForegroundColor Green
}

#endregion

if ($TestConsoleWidth -gt 0 -and [string]::IsNullOrWhiteSpace($ResourceName)) {
    Test-ProgressBarAtDifferentWidths -Activity "Sample Progress Test" -Total 50
    exit 0
}

if ($PSBoundParameters.ContainsKey('ResourceName') -and -not [string]::IsNullOrWhiteSpace($ResourceName)) {
    Main
} else {
    [void](Test-ResourceNameValid -ResourceName "")
    exit 1
}

#endregion
