<#
.SYNOPSIS
    Comprehensive regression test for all Azure resources in the provider

.DESCRIPTION
    Tests terracorder.ps1 against every resource registration in the provider to ensure
    the AST migration didn't break any resource analysis. Generates detailed reports
    showing successes, failures, and statistics.

.PARAMETER RepositoryDirectory
    Path to terraform-provider-azurerm repository

.PARAMETER OutputDirectory
    Base directory for test outputs (creates subdirs per resource)

.PARAMETER MaxConcurrent
    Maximum number of concurrent tests (default: 4)

.PARAMETER ResourceFilter
    Optional regex filter for resource names (e.g., "azurerm_virtual_.*")

.PARAMETER ContinueOnError
    Continue testing even if failures occur (default: true)

.EXAMPLE
    .\Test-AllResources.ps1 -RepositoryDirectory "C:\github.com\hashicorp\terraform-provider-azurerm" -OutputDirectory ".\regression-test"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryDirectory,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = ".\regression-test",

    [Parameter(Mandatory = $false)]
    [int]$MaxConcurrent = 1,

    [Parameter(Mandatory = $false)]
    [string]$ResourceFilter = $null,

    [Parameter(Mandatory = $false)]
    [switch]$ContinueOnError = $true
)

$ErrorActionPreference = "Stop"

# Create output directories
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$testRunDir = Join-Path $OutputDirectory "run_$timestamp"
$logsDir = Join-Path $testRunDir "logs"
$resultsDir = Join-Path $testRunDir "results"
$reportPath = Join-Path $testRunDir "test-report.txt"

New-Item -ItemType Directory -Path $testRunDir -Force | Out-Null
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  TERRACORDER COMPREHENSIVE REGRESSION TEST" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Repository: $RepositoryDirectory" -ForegroundColor Gray
Write-Host "  Output Dir: $testRunDir" -ForegroundColor Gray
Write-Host "  Concurrent: $MaxConcurrent" -ForegroundColor Gray
Write-Host ""

# Get all resource registrations using existing Database module functionality
Write-Host "[INFO] Discovering resource registrations..." -ForegroundColor Cyan

    # Find all registration.go files
    $registrationFiles = Get-ChildItem -Path (Join-Path $RepositoryDirectory "internal\services") -Recurse -Filter "registration.go"

    # Extract resource names from registration.go files
    $allResources = @()
    foreach ($file in $registrationFiles) {
        $content = Get-Content $file.FullName -Raw

        # Match both old-style map entries: "azurerm_resource_name":
        # and new-style struct entries followed by ResourceType() methods
        $matches = [regex]::Matches($content, '"(azurerm_[^"]+)"')
        foreach ($match in $matches) {
            $allResources += $match.Groups[1].Value
        }
    }

    $allResources = $allResources | Sort-Object -Unique

    # Apply filter if specified
    if ($ResourceFilter) {
        $filteredResources = $allResources | Where-Object { $_ -match $ResourceFilter }
        Write-Host "[INFO] Filter applied: $ResourceFilter" -ForegroundColor Yellow
        Write-Host "[INFO] Filtered: $($allResources.Count) -> $($filteredResources.Count) resources" -ForegroundColor Yellow
        $allResources = @($filteredResources)  # Ensure it's an array
    }

    $totalResources = $allResources.Count
    Write-Host "[INFO] Found $totalResources resources to test" -ForegroundColor Green
    Write-Host ""

# Test results tracking
$results = @{
    Success = @()
    Failed = @()
    NoTests = @()
    Errors = @()
}

$startTime = Get-Date
$completedCount = 0

# Progress tracking
$progressParams = @{
    Activity = "Testing Resources"
    Status = "Starting..."
    PercentComplete = 0
}
Write-Progress @progressParams

# Process resources in batches for concurrent execution
$batchSize = $MaxConcurrent
$batches = [Math]::Ceiling($totalResources / $batchSize)

for ($batchNum = 0; $batchNum -lt $batches; $batchNum++) {
    $batchStart = $batchNum * $batchSize
    $batchEnd = [Math]::Min($batchStart + $batchSize - 1, $totalResources - 1)

    # Get batch resources and ensure it's always an array
    if ($batchStart -eq $batchEnd) {
        # Single resource - explicitly create array
        $batchResources = @($allResources[$batchStart])
    } else {
        $batchResources = @($allResources[$batchStart..$batchEnd])
    }

    # Run batch concurrently using background jobs
    $jobs = @()

    foreach ($resource in $batchResources) {
        $scriptBlock = {
            param($Resource, $RepoDir, $ResultsDir, $LogsDir, $ScriptPath)

            # Suppress console errors in background jobs
            $ErrorActionPreference = "Continue"

            $resourceOutputDir = Join-Path $ResultsDir $Resource
            $logFile = Join-Path $LogsDir "$Resource.log"

            try{
                # PHASE 1: Run Discovery Mode for this resource
                # Use Start-Transcript to capture Write-Host output
                Start-Transcript -Path $logFile -Force | Out-Null

                try {
                    & $ScriptPath `
                        -RepositoryDirectory $RepoDir `
                        -ResourceName $Resource `
                        -ExportDirectory $resourceOutputDir
                } finally {
                    Stop-Transcript | Out-Null
                }

                # Read the log file back for analysis
                $output = Get-Content -Path $logFile -Raw

                # Analyze output for success/failure
                $outputText = $output

                $result = @{
                    Resource = $Resource
                    Status = "Unknown"
                    Message = ""
                    TestsFound = 0
                    Functions = 0
                    References = 0
                    ExecutionTime = 0
                    DatabaseModeStatus = "NotTested"
                }

                # Check for errors
                if ($outputText -match "ERROR:|Exception" -and $outputText -notmatch "ERROR: A parameter cannot be found") {
                    $result.Status = "Error"
                    # Extract error message
                    if ($outputText -match "ERROR:\s*(.+?)(?:\r?\n|$)") {
                        $result.Message = $Matches[1].Trim()
                    } else {
                        $result.Message = "Unknown error occurred"
                    }
                }
                # Check if no tests found (AST format) - handle transcript line breaks
                elseif ($outputText -match "Generated Test Commands For\s+0\s+Services") {
                    $result.Status = "NoTests"
                    $result.Message = "No test files found for this resource"
                }
                # Success - extract statistics (AST format) - handle transcript line breaks
                elseif ($outputText -match "Generated Test Commands For\s+(\d+)\s+Services") {
                    $result.Status = "Success"
                    $result.TestsFound = [int]$Matches[1]

                    # Extract execution time
                    if ($outputText -match "Total Execution Time:\s*(\d+)\s*ms") {
                        $result.ExecutionTime = [int]$Matches[1]
                    }

                    $result.Message = "Discovery: $($result.TestsFound) service(s), $($result.ExecutionTime)ms"

                    # PHASE 2: Test Database Mode operations (only if Discovery succeeded)
                    if ($result.Status -eq "Success") {
                        $dbLogFile = Join-Path $LogsDir "$Resource-dbmode.log"
                        $dbTestsPassed = 0
                        $dbTestsFailed = 0

                        try {
                            # Test 1: ShowDirectReferences
                            Start-Transcript -Path $dbLogFile -Force | Out-Null
                            try {
                                & $ScriptPath -DatabaseDirectory $resourceOutputDir -ShowDirectReferences *>&1 | Out-Null
                                $dbTestsPassed++
                            } catch {
                                $dbTestsFailed++
                            }
                            Stop-Transcript | Out-Null

                            # Allow garbage collection between queries
                            Start-Sleep -Seconds 2

                            # Test 2: ShowIndirectReferences
                            Start-Transcript -Path $dbLogFile -Append | Out-Null
                            try {
                                & $ScriptPath -DatabaseDirectory $resourceOutputDir -ShowIndirectReferences *>&1 | Out-Null
                                $dbTestsPassed++
                            } catch {
                                $dbTestsFailed++
                            }
                            Stop-Transcript | Out-Null

                            if ($dbTestsFailed -eq 0) {
                                $result.DatabaseModeStatus = "Success"
                                $result.Message += " | DB Mode: Both queries passed"
                            } else {
                                $result.DatabaseModeStatus = "Failed"
                                $result.Message += " | DB Mode: $dbTestsFailed/2 queries failed"
                            }
                        }
                        catch {
                            $result.DatabaseModeStatus = "Error"
                            $result.Message += " | DB Mode: Error - $($_.Exception.Message)"
                        }
                    }
                    else {
                        # Skip Database Mode tests if Discovery Mode failed
                        $result.DatabaseModeStatus = "Skipped"
                        $result.Message += " | DB Mode: Skipped (Discovery failed)"
                    }
                }
                else {
                    $result.Status = "Error"
                    $result.Message = "Unexpected output format"
                }

                return $result
            }
            catch {
                return @{
                    Resource = $Resource
                    Status = "Error"
                    Message = $_.Exception.Message
                    TestsFound = 0
                    Functions = 0
                    References = 0
                    ExecutionTime = 0
                    DatabaseModeStatus = "NotTested"
                }
            }
        }

        $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts\terracorder.ps1"
        $arguments = [object[]]@($resource, $RepositoryDirectory, $resultsDir, $logsDir, $scriptPath)
        $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $arguments

        $jobs += @{
            Job = $job
            Resource = $resource
        }
    }

    # Wait for batch to complete
    foreach ($jobInfo in $jobs) {
        $job = $jobInfo.Job
        $resource = $jobInfo.Resource

        # Wait for job with timeout (5 minutes per resource)
        $timeout = 300
        $completed = Wait-Job -Job $job -Timeout $timeout

        if ($null -eq $completed) {
            # Timeout
            Stop-Job -Job $job
            $result = @{
                Resource = $resource
                Status = "Error"
                Message = "Timeout after $timeout seconds"
                TestsFound = 0
                Functions = 0
                References = 0
                ExecutionTime = 0
                DatabaseModeStatus = "NotTested"
            }
        }
        else {
            # Get result - take last object in case there was any other output
            $jobOutput = Receive-Job -Job $job
            $result = if ($jobOutput -is [array]) { $jobOutput[-1] } else { $jobOutput }
        }

        Remove-Job -Job $job -Force

        # Allow garbage collection between tests
        Start-Sleep -Seconds 2

        # Categorize result
        switch ($result.Status) {
            "Success" { $results.Success += $result }
            "NoTests" { $results.NoTests += $result }
            "Error" { $results.Failed += $result }
            default { $results.Errors += $result }
        }

        $completedCount++

        # Update progress
        $percentComplete = [Math]::Round(($completedCount / $totalResources) * 100, 1)
        $progressParams = @{
            Activity = "Testing Resources"
            Status = "Completed $completedCount of $totalResources - Current: $resource"
            PercentComplete = $percentComplete
        }
        Write-Progress @progressParams

        # Console output
        $statusColor = switch ($result.Status) {
            "Success" { "Green" }
            "NoTests" { "Yellow" }
            "Error" { "Red" }
            default { "Gray" }
        }

        $dbStatusColor = switch ($result.DatabaseModeStatus) {
            "Success" { "Green" }
            "Failed" { "Red" }
            "Error" { "Red" }
            "NotTested" { "Gray" }
            default { "Gray" }
        }

        Write-Host "[$completedCount/$totalResources] " -NoNewline -ForegroundColor Gray
        Write-Host $resource -NoNewline -ForegroundColor Cyan
        Write-Host " - Discovery: " -NoNewline
        Write-Host $result.Status -NoNewline -ForegroundColor $statusColor
        if ($result.DatabaseModeStatus -ne "NotTested") {
            Write-Host " | DB Mode: " -NoNewline
            Write-Host $result.DatabaseModeStatus -ForegroundColor $dbStatusColor
        } else {
            Write-Host ""
        }

        if ($result.Status -eq "Error" -and -not $ContinueOnError) {
            Write-Host ""
            Write-Host "[FATAL] Test failed and -ContinueOnError is false. Stopping." -ForegroundColor Red
            break
        }
    }

    if (-not $ContinueOnError -and $results.Failed.Count -gt 0) {
        break
    }
}

Write-Progress -Activity "Testing Resources" -Completed

$endTime = Get-Date
$totalDuration = $endTime - $startTime

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  DISCOVERY MODE" -ForegroundColor Yellow
Write-Host "  ---------------" -ForegroundColor Yellow
Write-Host "  Total Resources Tested: " -NoNewline -ForegroundColor Gray
Write-Host $completedCount -ForegroundColor White
Write-Host "  Successful: " -NoNewline -ForegroundColor Gray
Write-Host $results.Success.Count -ForegroundColor Green
Write-Host "  No Tests Found: " -NoNewline -ForegroundColor Gray
Write-Host $results.NoTests.Count -ForegroundColor Yellow
Write-Host "  Failed: " -NoNewline -ForegroundColor Gray
Write-Host $results.Failed.Count -ForegroundColor Red
Write-Host "  Errors: " -NoNewline -ForegroundColor Gray
Write-Host $results.Errors.Count -ForegroundColor Red
Write-Host ""
Write-Host "  DATABASE MODE" -ForegroundColor Yellow
Write-Host "  ---------------" -ForegroundColor Yellow
$dbSuccess = @($results.Success | Where-Object { $_.DatabaseModeStatus -eq "Success" }).Count
$dbFailed = @($results.Success | Where-Object { $_.DatabaseModeStatus -in @("Failed", "Error") }).Count
Write-Host "  Tested: " -NoNewline -ForegroundColor Gray
Write-Host $results.Success.Count -ForegroundColor White
Write-Host "  Successful: " -NoNewline -ForegroundColor Gray
Write-Host $dbSuccess -ForegroundColor Green
Write-Host "  Failed: " -NoNewline -ForegroundColor Gray
Write-Host $dbFailed -ForegroundColor Red
Write-Host ""
Write-Host "  OVERALL" -ForegroundColor Yellow
Write-Host "  ---------------" -ForegroundColor Yellow
Write-Host "  Discovery Success Rate: " -NoNewline -ForegroundColor Gray
$successRate = if ($completedCount -gt 0) { [Math]::Round((($results.Success.Count) / $completedCount) * 100, 1) } else { 0 }
Write-Host "$successRate%" -ForegroundColor $(if ($successRate -ge 95) { "Green" } elseif ($successRate -ge 80) { "Yellow" } else { "Red" })
Write-Host "  Database Mode Success Rate: " -NoNewline -ForegroundColor Gray
$dbSuccessRate = if ($results.Success.Count -gt 0) { [Math]::Round(($dbSuccess / $results.Success.Count) * 100, 1) } else { 0 }
Write-Host "$dbSuccessRate%" -ForegroundColor $(if ($dbSuccessRate -ge 95) { "Green" } elseif ($dbSuccessRate -ge 80) { "Yellow" } else { "Red" })
Write-Host ""
Write-Host "  Total Duration: $([Math]::Round($totalDuration.TotalMinutes, 1)) minutes" -ForegroundColor Gray
Write-Host ""

# Generate detailed report
Write-Host "[INFO] Generating detailed report..." -ForegroundColor Cyan

$reportContent = @"
============================================================
TERRACORDER COMPREHENSIVE REGRESSION TEST REPORT
============================================================

Test Run: $timestamp
Repository: $RepositoryDirectory
Total Resources: $completedCount
Duration: $([Math]::Round($totalDuration.TotalMinutes, 1)) minutes

DISCOVERY MODE SUMMARY
----------------------
Successful: $($results.Success.Count)
No Tests Found: $($results.NoTests.Count)
Failed: $($results.Failed.Count)
Errors: $($results.Errors.Count)
Success Rate: $successRate%

DATABASE MODE SUMMARY
---------------------
Tested: $($results.Success.Count)
Successful: $dbSuccess
Failed: $dbFailed
Success Rate: $dbSuccessRate%

"@

if ($results.Failed.Count -gt 0) {
    $reportContent += @"

============================================================
FAILED RESOURCES - DISCOVERY MODE ($($results.Failed.Count))
============================================================

"@
    foreach ($failure in ($results.Failed | Sort-Object Resource)) {
        $reportContent += "- $($failure.Resource)`n"
        $reportContent += "  Error: $($failure.Message)`n"
        $reportContent += "  Log: $logsDir\$($failure.Resource).log`n`n"
    }
}

if ($dbFailed -gt 0) {
    $dbFailures = $results.Success | Where-Object { $_.DatabaseModeStatus -in @("Failed", "Error") }
    $reportContent += @"

============================================================
FAILED RESOURCES - DATABASE MODE ($dbFailed)
============================================================

"@
    foreach ($failure in ($dbFailures | Sort-Object Resource)) {
        $reportContent += "- $($failure.Resource)`n"
        $reportContent += "  Status: $($failure.DatabaseModeStatus)`n"
        $reportContent += "  Message: $($failure.Message)`n"
        $reportContent += "  Log: $logsDir\$($failure.Resource)-dbmode.log`n`n"
    }
}

if ($results.Success.Count -gt 0) {
    $reportContent += @"

============================================================
SUCCESSFUL RESOURCES ($($results.Success.Count))
============================================================

"@

    # Summary statistics
    $totalTests = ($results.Success | Measure-Object -Property TestsFound -Sum).Sum
    $totalFunctions = ($results.Success | Measure-Object -Property Functions -Sum).Sum
    $totalReferences = ($results.Success | Measure-Object -Property References -Sum).Sum
    $avgTime = ($results.Success | Measure-Object -Property ExecutionTime -Average).Average

    $reportContent += @"
Total Test Files: $totalTests
Total Functions: $totalFunctions
Total References: $totalReferences
Average Execution Time: $([Math]::Round($avgTime, 0)) ms

Top 10 Resources by Test Coverage:
"@

    $top10 = $results.Success | Sort-Object TestsFound -Descending | Select-Object -First 10
    foreach ($item in $top10) {
        $reportContent += "`n  $($item.Resource): $($item.TestsFound) test files, $($item.Functions) functions"
    }
}

if ($results.NoTests.Count -gt 0) {
    $reportContent += @"


============================================================
RESOURCES WITH NO TESTS ($($results.NoTests.Count))
============================================================

"@
    foreach ($noTest in ($results.NoTests | Sort-Object Resource)) {
        $reportContent += "- $($noTest.Resource)`n"
    }
}

$reportContent | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host "[INFO] Report saved to: $reportPath" -ForegroundColor Green
Write-Host ""

# Exit with appropriate code
if ($results.Failed.Count -gt 0 -or $dbFailed -gt 0) {
    Write-Host "[WARNING] Some tests failed. Review the report for details." -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host "[SUCCESS] All tests completed successfully!" -ForegroundColor Green
    exit 0
}
