# FileDiscovery.psm1
# File discovery and filtering operations for TerraCorder

function Get-TestFilesContainingResource {
    <#
    .SYNOPSIS
        Discovers test files in repository and filters to those containing the target resource

    .PARAMETER RepositoryDirectory
        Root directory of the terraform-provider-azurerm repository

    .PARAMETER ResourceName
        Target Azure resource name to search for (e.g., "azurerm_kubernetes_cluster")

    .PARAMETER UseParallel
        Whether to use parallel processing for file discovery

    .RETURNS
        Hashtable with AllFiles, RelevantFiles, and FileContents
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryDirectory,
        [Parameter(Mandatory = $true)]
        [string]$ResourceName,
        [Parameter(Mandatory = $false)]
        [bool]$UseParallel = $true,
        [Parameter(Mandatory = $false)]
        [int]$ThreadCount = 8,
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    # Get total count of all test files first
    $allTestFiles = Get-ChildItem -Path "$RepositoryDirectory\internal\services" -Name "*_test.go" -Recurse
    Show-PhaseMessageHighlight -Message "Found $($allTestFiles.Count) Test Files" -HighlightText $($allTestFiles.Count) -HighlightColor $NumberColor -BaseColor $BaseColor -InfoColor $InfoColor

    # Now filter to exclude validate and parse directories
    $allTestFileNames = $allTestFiles | Where-Object {
        # Exclude validate directories - these contain validation logic, not actual tests
        # Exclude parse directories - these contain parsing logic, not resource tests
        $fullPath = "$RepositoryDirectory\internal\services\$_"
        $fullPath -notlike "*\validate\*" -and $fullPath -notlike "*\parse\*"
    }

    if ($allTestFileNames.Count -eq 0) {
        Write-Error "No test files found in '$RepositoryDirectory\internal\services'. Please verify the RepositoryDirectory path is correct."
        exit 1
    }

    $excludedCount = $allTestFiles.Count - $allTestFileNames.Count
    Show-PhaseMessageMultiHighlight -Message "Filtered $excludedCount Irrelevant Files, $($allTestFileNames.Count) Test Files To Analyze" -Highlights @(
        @{ Text = "$excludedCount"; Color = $NumberColor }
        @{ Text = "$($allTestFileNames.Count)"; Color = $NumberColor }
    ) -BaseColor $BaseColor -InfoColor $InfoColor

    $relevantFileNames = @()
    $fileContents = @{}  # Store file contents in memory: FullPath -> Content

    # Use all non-validate test files as candidates - ensures we don't miss any dependencies
    $candidateFileNames = $allTestFileNames

    if ($UseParallel) {
        # Use runspace pool for optimal parallel processing performance
        $totalFiles = $candidateFileNames.Count
        $filesPerThread = [Math]::Ceiling($totalFiles / $ThreadCount)

        $threadText = if ($ThreadCount -eq 1) { "Thread" } else { "Threads" }
        Show-PhaseMessageMultiHighlight -Message "Processing $totalFiles Files With $ThreadCount $threadText" -Highlights @(
            @{ Text = "$totalFiles"; Color = $NumberColor }
            @{ Text = "$ThreadCount"; Color = $NumberColor }
        ) -BaseColor $BaseColor -InfoColor $InfoColor

        # Create runspace pool for optimal performance
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount)
        $runspacePool.Open()

        # Split files into chunks for parallel processing
        $fileChunks = @()
        for ($i = 0; $i -lt $ThreadCount; $i++) {
            $startIndex = $i * $filesPerThread
            $endIndex = [Math]::Min($startIndex + $filesPerThread - 1, $totalFiles - 1)

            if ($startIndex -lt $totalFiles) {
                $fileChunks += ,@($candidateFileNames[$startIndex..$endIndex])
            }
        }

        # Parallel processing script block
        $processFileChunk = {
            param($FileChunk, $RepositoryDirectory, $ResourceName, $ThreadId)

            $results = @{
                ThreadId = $ThreadId
                ProcessedCount = 0
                RelevantFiles = @()
                FileContents = @{}
            }

            foreach ($fileName in $FileChunk) {
                try {
                    $fullPath = "$RepositoryDirectory\internal\services\$fileName"
                    $content = Get-Content $fullPath -Raw -ErrorAction Stop

                    # Get FileInfo object to ensure consistent FullName formatting
                    $fileInfo = Get-Item $fullPath -ErrorAction Stop
                    $results.FileContents[$fileInfo.FullName] = $content

                    # Content-based filtering - use precise regex to match complete resource names only
                    # Match resource name surrounded by word boundaries or quotes
                    $escapedResourceName = [regex]::Escape($ResourceName)
                    $precisePattern = "(?<!\w)$escapedResourceName(?!\w)"

                    # Explicitly capture -cmatch result to prevent boolean output to file descriptors
                    $matchResult = ($content -cmatch $precisePattern)
                    if ($matchResult) {
                        $results.RelevantFiles += $fileInfo.FullName
                    }

                    $results.ProcessedCount++
                }
                catch {
                    Write-Warning "Thread ${ThreadId}: Failed to process file $fileName - $($_.Exception.Message)"
                }
            }

            return $results
        }

        $jobs = @()
        try {
            # Start parallel processing jobs
            for ($i = 0; $i -lt $fileChunks.Count; $i++) {
                $chunk = $fileChunks[$i]
                if ($chunk.Count -gt 0) {
                    $powerShell = [powershell]::Create()
                    $powerShell.RunspacePool = $runspacePool

                    [void]$powerShell.AddScript($processFileChunk)
                    [void]$powerShell.AddArgument($chunk)
                    [void]$powerShell.AddArgument($RepositoryDirectory)
                    [void]$powerShell.AddArgument($ResourceName)
                    [void]$powerShell.AddArgument($i + 1)

                    $job = @{
                        PowerShell = $powerShell
                        Handle = $powerShell.BeginInvoke()
                        ThreadId = $i + 1
                    }
                    $jobs += $job
                }
            }

            # Wait for completion and collect results with animated progress
            $totalProcessed = 0
            $completedJobs = 0
            $totalJobs = $jobs.Count
            $dotCount = 0

            Write-Host " " -NoNewline
            Write-Host "[INFO]" -NoNewline -ForegroundColor $InfoColor
            Write-Host " Waiting For Threads To Return [" -NoNewline -ForegroundColor $BaseColor
            Write-Host $completedJobs -NoNewline -ForegroundColor $NumberColor
            Write-Host "/" -NoNewline -ForegroundColor $BaseColor
            Write-Host $totalJobs -NoNewline -ForegroundColor $NumberColor
            Write-Host "]" -NoNewline -ForegroundColor $BaseColor

            while ($completedJobs -lt $totalJobs) {
                foreach ($job in $jobs) {
                    if ($job.Handle.IsCompleted -and -not $job.Processed) {
                        try {
                            $result = $job.PowerShell.EndInvoke($job.Handle)

                            # Merge results (no verbose output per thread)
                            $totalProcessed += $result.ProcessedCount
                            # Only add non-empty results to avoid adding empty arrays as elements
                            if ($result.RelevantFiles -and $result.RelevantFiles.Count -gt 0) {
                                $relevantFileNames += $result.RelevantFiles
                            }
                            foreach ($key in $result.FileContents.Keys) {
                                $fileContents[$key] = $result.FileContents[$key]
                            }
                        } catch {
                            Write-Warning "Error in thread $($job.ThreadId): $($_.Exception.Message)"
                        } finally {
                            $job.PowerShell.Dispose()
                            $job.Processed = $true
                        }

                        $completedJobs++
                        Write-Host "`r " -NoNewline
                        Write-Host "[INFO]" -NoNewline -ForegroundColor $InfoColor
                        Write-Host " Waiting For Threads To Return [" -NoNewline -ForegroundColor $BaseColor
                        Write-Host $completedJobs -NoNewline -ForegroundColor $NumberColor
                        Write-Host "/" -NoNewline -ForegroundColor $BaseColor
                        Write-Host $totalJobs -NoNewline -ForegroundColor $NumberColor
                        Write-Host "]" -NoNewline -ForegroundColor $BaseColor
                    }
                }

                if ($completedJobs -lt $totalJobs) {
                    Start-Sleep -Milliseconds 300
                    $dotCount = ($dotCount + 1) % 4
                    $dots = "." * $dotCount
                    Write-Host "`r " -NoNewline
                    Write-Host "[INFO]" -NoNewline -ForegroundColor $InfoColor
                    Write-Host " Waiting For Threads To Return [" -NoNewline -ForegroundColor $BaseColor
                    Write-Host $completedJobs -NoNewline -ForegroundColor $NumberColor
                    Write-Host "/" -NoNewline -ForegroundColor $BaseColor
                    Write-Host $totalJobs -NoNewline -ForegroundColor $NumberColor
                    Write-Host "]$dots" -NoNewline -ForegroundColor $BaseColor
                }
            }

            Write-Host "`r " -NoNewline
            Write-Host "[INFO]" -NoNewline -ForegroundColor $InfoColor
            Write-Host " Waiting For Threads To Return [" -NoNewline -ForegroundColor $BaseColor
            Write-Host $completedJobs -NoNewline -ForegroundColor $NumberColor
            Write-Host "/" -NoNewline -ForegroundColor $BaseColor
            Write-Host $totalJobs -NoNewline -ForegroundColor $NumberColor
            Write-Host "] - " -NoNewline -ForegroundColor $BaseColor
            Write-Host "Complete" -ForegroundColor Green
        } finally {
            $runspacePool.Close()
            $runspacePool.Dispose()
        }
    } else {
        # Sequential processing (original method)
        foreach ($fileName in $candidateFileNames) {
            $fullPath = "$RepositoryDirectory\internal\services\$fileName"
            $content = Get-Content $fullPath -Raw

            # Get FileInfo object to ensure consistent FullName formatting
            $fileInfo = Get-Item $fullPath
            $fileContents[$fileInfo.FullName] = $content

            # Content-based filtering - use precise regex to match complete resource names only
            # Match resource name surrounded by word boundaries or quotes
            $escapedResourceName = [regex]::Escape($ResourceName)
            $precisePattern = "(?<!\w)$escapedResourceName(?!\w)"

            if ($content -cmatch $precisePattern) {
                $relevantFileNames += $fileInfo.FullName
            }
        }
    }

    if ($relevantFileNames.Count -eq 0) {
        Show-PhaseMessageMultiHighlight -Message "Error: No Test Files Found Containing '$ResourceName'" -Highlights @(
            @{ Text = "Error:"; Color = "Red" }
            @{ Text = "$ResourceName"; Color = "Magenta" }
        ) -BaseColor $BaseColor -InfoColor $InfoColor
        Show-PhaseMessageHighlight -Message "Please Verify The -ResourceName Is Correct And Exists In The Repository." -HighlightText "-ResourceName" -HighlightColor "Magenta" -BaseColor "Yellow" -InfoColor $InfoColor
        Write-Host ""
        exit 1
    }

    # Return results (message will be shown by caller in proper phase context)
    return @{
        AllFiles = $allTestFileNames
        RelevantFiles = $relevantFileNames
        FileContents = $fileContents
    }
}

function Get-AdditionalSequentialFiles {
    <#
    .SYNOPSIS
        Finds additional files with sequential test patterns that reference resource functions

    .PARAMETER RepositoryDirectory
        Root directory of the terraform-provider-azurerm repository

    .PARAMETER CandidateFileNames
        Array of candidate file names to search through

    .PARAMETER ResourceFunctions
        Array of resource function names to look for

    .PARAMETER FileContents
        Hashtable of already loaded file contents

    .RETURNS
        Array of additional sequential files and updated file contents
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryDirectory,
        [Parameter(Mandatory = $true)]
        [array]$CandidateFileNames,
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        $ResourceFunctions,
        [Parameter(Mandatory = $true)]
        [hashtable]$FileContents
    )

    # Ensure ResourceFunctions is treated as an array for processing
    if ($null -eq $ResourceFunctions) {
        $ResourceFunctions = @()
    } else {
        $ResourceFunctions = @($ResourceFunctions)
    }



    $additionalSequentialFiles = @()

    # PERFORMANCE OPTIMIZATION: Two-pass approach
    # Pass 1: Check cached files from Phase 1 for sequential patterns
    foreach ($fullPath in $CandidateFileNames) {
        # Skip if not already processed
        if ($FileContents.ContainsKey($fullPath)) {
            $content = $FileContents[$fullPath]
        } else {
            continue
        }

        # Check if this file has sequential patterns AND references our functions
        if ($content -match 'acceptance\.RunTestsInSequence') {
            $hasRelevantReference = $false
            foreach ($funcName in $ResourceFunctions) {
                if ($content -match [regex]::Escape($funcName)) {
                    $hasRelevantReference = $true
                    break
                }
            }
            if ($hasRelevantReference) {
                $fileInfo = Get-Item $fullPath
                $additionalSequentialFiles += $fileInfo
            }
        }
    }

    # Pass 2: Only if no sequential files found, do a targeted search for files with RunTestsInSequence
    if ($additionalSequentialFiles.Count -eq 0) {
        # Use grep-like search to quickly find files containing RunTestsInSequence
        $testDirectory = Join-Path $RepositoryDirectory "internal\services"

        # Get candidate files first
        $candidateFiles = Get-ChildItem -Path $testDirectory -Recurse -Filter "*_test.go" |
            Where-Object {
                $_.FullName -notlike "*validate*" -and
                -not $FileContents.ContainsKey($_.FullName)
            }

        $totalCandidates = $candidateFiles.Count
        $currentFile = 0
        $sequentialTestFiles = @()

        foreach ($file in $candidateFiles) {
            $currentFile++

            # Show progress every 100 files
            if ($currentFile % 100 -eq 0 -or $currentFile -eq $totalCandidates) {
                Show-InlineProgress -Current $currentFile -Total $totalCandidates -Activity "Scanning Test Files"
            }

            # Quick check: does this file contain RunTestsInSequence at all?
            $quickContent = Select-String -Path $file.FullName -Pattern "RunTestsInSequence" -Quiet
            if ($quickContent) {
                $sequentialTestFiles += $file
            }
        }

        # Show completion
        if ($totalCandidates -gt 0) {
            Show-InlineProgress -Current $totalCandidates -Total $totalCandidates -Activity "Scanning Test Files" -Completed
        }

        foreach ($file in $sequentialTestFiles) {
            $content = Get-Content $file.FullName -Raw

            # Check if this file references our functions
            $hasRelevantReference = $false
            foreach ($funcName in $ResourceFunctions) {
                if ($content -match [regex]::Escape($funcName)) {
                    $hasRelevantReference = $true
                    break
                }
            }
            if ($hasRelevantReference) {
                $additionalSequentialFiles += $file
                $FileContents[$file.FullName] = $content
            }
        }
    }



    return @{
        AdditionalFiles = $additionalSequentialFiles
        UpdatedFileContents = $FileContents
    }
}

Export-ModuleMember -Function Get-TestFilesContainingResource, Get-AdditionalSequentialFiles
