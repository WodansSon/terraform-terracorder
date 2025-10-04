# ProcessingCore.psm1
# Core processing functions for TerraCorder

# Dependencies: TestFunctionProcessing.psm1 (loaded by main script)

function Invoke-FileProcessingPhase {
    <#
    .SYNOPSIS
        Process files and categorize them into resource files and sequential files using parallel processing
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$RelevantFileNames,
        [Parameter(Mandatory = $true)]
        [hashtable]$FileContents,
        [Parameter(Mandatory = $true)]
        [string]$RepositoryDirectory,
        [Parameter(Mandatory = $true)]
        [hashtable]$RegexPatterns,
        [Parameter(Mandatory = $true)]
        [int]$ThreadCount,
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    $totalFiles = $RelevantFileNames.Count
    if ($totalFiles -eq 0) {
        return @{
            ResourceFiles = @()
            SequentialFiles = @()
            ResourceFunctions = @()
        }
    }

    # Use provided thread count
    $threadText = if ($ThreadCount -eq 1) { "Thread" } else { "Threads" }

    Show-PhaseMessageMultiHighlight -Message "Processing $totalFiles Files With $ThreadCount $threadText" -HighlightTexts @("$totalFiles", "$ThreadCount") -HighlightColors @($NumberColor, $NumberColor) -BaseColor $BaseColor -InfoColor $InfoColor
    $filesPerThread = [Math]::Ceiling($totalFiles / $ThreadCount)

    # Split files into chunks for parallel processing
    $fileChunks = @()
    for ($i = 0; $i -lt $ThreadCount; $i++) {
        $startIndex = $i * $filesPerThread
        $endIndex = [Math]::Min($startIndex + $filesPerThread - 1, $totalFiles - 1)

        if ($startIndex -lt $totalFiles) {
            $fileChunks += ,@($RelevantFileNames[$startIndex..$endIndex])
        }
    }

    # Parallel processing script block
    $processFileChunk = {
        param($FileChunk, $FileContents, $RegexPatterns, $ThreadId)

        $results = @{
            ThreadId = $ThreadId
            ResourceFiles = @()
            SequentialFiles = @()
            ResourceFunctions = @()
        }

        foreach ($fullPath in $FileChunk) {
            try {
                # Get FileInfo object first to ensure consistent FullName formatting
                $fileInfo = Get-Item $fullPath
                $content = $FileContents[$fileInfo.FullName]

                # Skip files with empty or null content
                if ([string]::IsNullOrWhiteSpace($content)) {
                    continue
                }

                # This file contains our resource (since it came from Phase 1 filtering)
                $results.ResourceFiles += $fileInfo

                # Extract function names from resource files
                $testMatches = $RegexPatterns.TestFunction.Matches($content) | ForEach-Object { $_.Groups[1].Value }
                $lowerTestMatches = $RegexPatterns.LowerTestFunction.Matches($content) | ForEach-Object { $_.Groups[1].Value }
                $results.ResourceFunctions += $testMatches + $lowerTestMatches

                # Check if this file has sequential patterns (either RunTestsInSequence or map-based)
                if ($RegexPatterns.RunTestsInSequence.IsMatch($content) -or $RegexPatterns.MapBasedSequential.IsMatch($content)) {
                    $results.SequentialFiles += $fileInfo
                }
            } catch {
                Write-Warning "Thread ${ThreadId}: Error processing file $fullPath : $($_.Exception.Message)"
            }
        }

        return $results
    }

    # Create runspace pool for optimal performance
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount)
    $runspacePool.Open()

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
                [void]$powerShell.AddArgument($FileContents)
                [void]$powerShell.AddArgument($RegexPatterns)
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
        $resourceFiles = @()
        $sequentialFiles = @()
        $resourceFunctions = @()

        $completedJobs = 0
        $totalJobs = $jobs.Count
        $dotCount = 0

        Write-Host " " -NoNewline
        Write-Host "[INFO]" -NoNewline -ForegroundColor $InfoColor
        Write-Host " Waiting For Threads To Return [" -NoNewline -ForegroundColor Gray
        Write-Host $completedJobs -NoNewline -ForegroundColor $NumberColor
        Write-Host "/" -NoNewline -ForegroundColor Gray
        Write-Host $totalJobs -NoNewline -ForegroundColor $NumberColor
        Write-Host "]" -NoNewline -ForegroundColor Gray

        while ($completedJobs -lt $totalJobs) {
            foreach ($job in $jobs) {
                if ($job.Handle.IsCompleted -and -not $job.Processed) {
                    try {
                        $result = $job.PowerShell.EndInvoke($job.Handle)

                        # Merge results from this thread
                        $resourceFiles += $result.ResourceFiles
                        $sequentialFiles += $result.SequentialFiles
                        $resourceFunctions += $result.ResourceFunctions
                    } catch {
                        Write-Warning "Error in thread $($job.ThreadId): $($_.Exception.Message)"
                    } finally {
                        $job.PowerShell.Dispose()
                        $job.Processed = $true
                    }

                    $completedJobs++
                    Write-Host "`r " -NoNewline
                    Write-Host "[INFO]" -NoNewline -ForegroundColor $InfoColor
                    Write-Host " Waiting For Threads To Return [" -NoNewline -ForegroundColor Gray
                    Write-Host $completedJobs -NoNewline -ForegroundColor $NumberColor
                    Write-Host "/" -NoNewline -ForegroundColor Gray
                    Write-Host $totalJobs -NoNewline -ForegroundColor $NumberColor
                    Write-Host "]" -NoNewline -ForegroundColor Gray
                }
            }

            if ($completedJobs -lt $totalJobs) {
                Start-Sleep -Milliseconds 300
                $dotCount = ($dotCount + 1) % 4
                $dots = "." * $dotCount
                Write-Host "`r " -NoNewline
                Write-Host "[INFO]" -NoNewline -ForegroundColor $InfoColor
                Write-Host " Waiting For Threads To Return [" -NoNewline -ForegroundColor Gray
                Write-Host $completedJobs -NoNewline -ForegroundColor $NumberColor
                Write-Host "/" -NoNewline -ForegroundColor Gray
                Write-Host $totalJobs -NoNewline -ForegroundColor $NumberColor
                Write-Host "]$dots" -NoNewline -ForegroundColor Gray
            }
        }

        Write-Host "`r " -NoNewline
        Write-Host "[INFO]" -NoNewline -ForegroundColor $InfoColor
        Write-Host " Waiting For Threads To Return [" -NoNewline -ForegroundColor Gray
        Write-Host $completedJobs -NoNewline -ForegroundColor $NumberColor
        Write-Host "/" -NoNewline -ForegroundColor Gray
        Write-Host $totalJobs -NoNewline -ForegroundColor $NumberColor
        Write-Host "] - " -NoNewline -ForegroundColor Gray
        Write-Host "Complete" -ForegroundColor Green
    } finally {
        $runspacePool.Close()
        $runspacePool.Dispose()
    }

    return @{
        ResourceFiles = $resourceFiles
        SequentialFiles = $sequentialFiles
        ResourceFunctions = $resourceFunctions
    }
}

# Old sequential function removed - now always use optimized parallel processing

function Invoke-SequentialTestParsing {
    <#
    .SYNOPSIS
        Parse RunTestsInSequence patterns from file content
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        [Parameter(Mandatory = $true)]
        [hashtable]$RegexPatterns
    )

    # Return empty array if content is null or empty
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return @()
    }

    $sequentialTests = @()
    $lines = $Content -split "`n"
    $inRunTestsInSequence = $false
    $inMapBasedSequential = $false
    $currentMainFunction = $null
    $currentSequentialGroup = $null

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()

        # Detect function start (both uppercase Test* and lowercase test*)
        $mainTestMatch = $Global:RegexPatterns.MainTestFunction.Match($line)
        $mainLowerTestMatch = $Global:RegexPatterns.MainLowerTestFunction.Match($line)
        if ($mainTestMatch.Success -or $mainLowerTestMatch.Success) {
            $currentMainFunction = if ($mainTestMatch.Success) { $mainTestMatch.Groups[1].Value } else { $mainLowerTestMatch.Groups[1].Value }
            $inRunTestsInSequence = $false
        }

        # Detect RunTestsInSequence start
        if ($Global:RegexPatterns.RunTestsInSequenceCall.IsMatch($line)) {
            $inRunTestsInSequence = $true
            if ($currentMainFunction) {
                $sequentialTests += [PSCustomObject]@{
                    MainFunction = $currentMainFunction
                    ReferencedFunctions = @()
                    SequentialMappings = @()  # Track group/key mappings
                    File = $RelativePath
                    Service = $ServiceName
                }
            }
        }

        # Detect map-based sequential start
        if ($Global:RegexPatterns.MapBasedSequential.IsMatch($line)) {
            $inMapBasedSequential = $true
            if ($currentMainFunction) {
                $sequentialTests += [PSCustomObject]@{
                    MainFunction = $currentMainFunction
                    ReferencedFunctions = @()
                    SequentialMappings = @()  # Track group/key mappings
                    File = $RelativePath
                    Service = $ServiceName
                }
            }
        }

        # Parse sequential group start (e.g., "ipv4": {) - works for both patterns
        $sequentialGroupMatch = $Global:RegexPatterns.SequentialGroup.Match($line)
        if (($inRunTestsInSequence -or $inMapBasedSequential) -and $sequentialGroupMatch.Success) {
            $currentSequentialGroup = $sequentialGroupMatch.Groups[1].Value
        }

        # Parse function references inside sequential patterns (both RunTestsInSequence and map-based)
        if (($inRunTestsInSequence -or $inMapBasedSequential) -and $currentSequentialGroup) {
            # Look for function references like: "key": functionName,
            $sequentialFunctionMatch = $Global:RegexPatterns.SequentialFunction.Match($line)
            if ($sequentialFunctionMatch.Success) {
                $sequentialKey = $sequentialFunctionMatch.Groups[1].Value
                $functionName = $sequentialFunctionMatch.Groups[2].Value
                $lastSeqTest = $sequentialTests | Select-Object -Last 1
                if ($lastSeqTest) {
                    $lastSeqTest.ReferencedFunctions += $functionName
                    $lastSeqTest.SequentialMappings += [PSCustomObject]@{
                        Group = $currentSequentialGroup
                        Key = $sequentialKey
                        Function = $functionName
                    }
                }
            }
        }

        # Detect end of sequential group
        if (($inRunTestsInSequence -or $inMapBasedSequential) -and $Global:RegexPatterns.SequentialGroupEnd.IsMatch($line)) {
            $currentSequentialGroup = $null
        }

        # Detect end of RunTestsInSequence - look for }) pattern
        if ($Global:RegexPatterns.SequentialEnd.IsMatch($line)) {
            $inRunTestsInSequence = $false
            $inMapBasedSequential = $false
            $currentSequentialGroup = $null
        }
    }

    return $sequentialTests
}

function Invoke-DatabasePopulation {
    <#
    .SYNOPSIS
        Hybrid parallel/sequential approach for optimal performance:
        - Phase 1: Multiple threads process files in parallel, building thread-safe data structures
        - Phase 2: Single main thread performs all database writes from collected data
        This eliminates database contention while maximizing CPU utilization.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$AllRelevantFiles,
        [Parameter(Mandatory = $true)]
        [hashtable]$FileContents,
        [Parameter(Mandatory = $true)]
        [string]$RepositoryDirectory,
        [Parameter(Mandatory = $true)]
        [hashtable]$RegexPatterns,
        [Parameter(Mandatory = $true)]
        [int]$ThreadCount,
        [Parameter(Mandatory = $false)]
        [string]$ResourceName,
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    # Thread-safe collections for parallel processing
    $Global:ProcessedData = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
    $Global:AllTestResultsCollection = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
    $Global:AllSequentialTestsCollection = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

    # Use provided thread count
    $filesPerThread = [Math]::Ceiling($AllRelevantFiles.Count / $ThreadCount)
    $threadText = if ($ThreadCount -eq 1) { "Thread" } else { "Threads" }

    Show-PhaseMessageMultiHighlight -Message "Processing $($AllRelevantFiles.Count) Files With $ThreadCount $threadText" -HighlightTexts @("$($AllRelevantFiles.Count)", "$ThreadCount") -HighlightColors @($NumberColor, $NumberColor) -BaseColor $BaseColor -InfoColor $InfoColor

    # Create runspace pool for parallel processing
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount)
    $runspacePool.Open()

    # Chunk files across threads
    $jobs = @()
    for ($i = 0; $i -lt $ThreadCount; $i++) {
        $startIndex = $i * $filesPerThread
        $endIndex = [Math]::Min($startIndex + $filesPerThread - 1, $AllRelevantFiles.Count - 1)

        if ($startIndex -le $endIndex) {
            $fileChunk = $AllRelevantFiles[$startIndex..$endIndex]

            # Create a thread-local copy of file contents for just this chunk
            $chunkFileContents = @{}

            foreach ($fileItem in $fileChunk) {
                # Handle both FileInfo objects and strings
                $filePath = if ($fileItem -is [System.IO.FileInfo]) { $fileItem.FullName } else { $fileItem }

                if ($FileContents.ContainsKey($filePath)) {
                    $chunkFileContents[$filePath] = $FileContents[$filePath]
                }
            }

            $powerShell = [powershell]::Create()
            $powerShell.RunspacePool = $runspacePool

            # Parallel file processing script
            $scriptBlock = {
                param($FileChunk, $FileContents, $RepositoryDirectory, $RegexPatterns, $ThreadId, $ResourceName)

                # Precompile regex patterns for performance (can't access module patterns in parallel threads)
                $structInstantiationPattern = [regex]::new('(?:^|\s)(?:\w+)\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{\}')
                $structMethodCallPattern = [regex]::new('([A-Z][A-Za-z0-9_]*)\{\}\.')

                # Inline essential functions directly in thread context
                function Get-StructDefinitions {
                    param([string]$FileContent, [hashtable]$Patterns)
                    $structs = @()
                    $lines = $FileContent -split "`n"
                    for ($i = 0; $i -lt $lines.Count; $i++) {
                        $line = $lines[$i].Trim()
                        $match = $Patterns.StructDefinition.Match($line)
                        if ($match.Success) {
                            $structs += [PSCustomObject]@{
                                StructName = $match.Groups[1].Value
                                Line = $i + 1
                            }
                        }
                    }
                    return $structs
                }

                function Invoke-SequentialTestParsing {
                    param([string]$Content, [string]$RelativePath, [string]$ServiceName, [hashtable]$RegexPatterns)

                    $sequentialTests = @()

                    # Check if file contains sequential patterns
                    if (-not ($RegexPatterns.RunTestsInSequence.IsMatch($Content) -or $RegexPatterns.MapBasedSequential.IsMatch($Content))) {
                        return $sequentialTests
                    }

                    $lines = $Content -split "`n"
                    $currentMainFunction = $null
                    $inRunTestsInSequence = $false
                    $inMapBasedSequential = $false
                    $currentSequentialGroup = $null
                    $currentSequentialMappings = @()

                    for ($i = 0; $i -lt $lines.Count; $i++) {
                        $line = $lines[$i]
                        $trimmedLine = $line.Trim()

                        # Detect main test function
                        $mainTestMatch = $RegexPatterns.MainTestFunction.Match($line)
                        $mainLowerTestMatch = $RegexPatterns.MainLowerTestFunction.Match($line)
                        if ($mainTestMatch.Success -or $mainLowerTestMatch.Success) {
                            # Complete previous sequential test if we were processing one
                            if ($currentMainFunction -and $currentSequentialMappings.Count -gt 0) {
                                $sequentialTests += [PSCustomObject]@{
                                    MainFunction = $currentMainFunction
                                    SequentialMappings = $currentSequentialMappings
                                    RelativePath = $RelativePath
                                    Service = $ServiceName
                                }
                                $currentSequentialMappings = @()
                            }

                            $currentMainFunction = if ($mainTestMatch.Success) { $mainTestMatch.Groups[1].Value } else { $mainLowerTestMatch.Groups[1].Value }
                            $inRunTestsInSequence = $false
                            $inMapBasedSequential = $false
                            continue
                        }

                        # Detect RunTestsInSequence start
                        if ($RegexPatterns.RunTestsInSequenceCall.IsMatch($line)) {
                            $inRunTestsInSequence = $true
                            $inMapBasedSequential = $false
                            continue
                        }

                        # Detect map-based sequential pattern
                        if ($RegexPatterns.MapBasedSequential.IsMatch($line)) {
                            $inMapBasedSequential = $true
                            $inRunTestsInSequence = $false
                            continue
                        }

                        # Process sequential groups and functions
                        if (($inRunTestsInSequence -or $inMapBasedSequential) -and $currentMainFunction) {
                            # Detect sequential group start
                            $sequentialGroupMatch = $RegexPatterns.SequentialGroup.Match($trimmedLine)
                            if ($sequentialGroupMatch.Success) {
                                $currentSequentialGroup = $sequentialGroupMatch.Groups[1].Value
                                continue
                            }

                            # Parse function references inside sequential patterns
                            if ($currentSequentialGroup) {
                                $sequentialFunctionMatch = $RegexPatterns.SequentialFunction.Match($trimmedLine)
                                if ($sequentialFunctionMatch.Success) {
                                    $currentSequentialMappings += [PSCustomObject]@{
                                        Group = $currentSequentialGroup
                                        Key = $sequentialFunctionMatch.Groups[1].Value
                                        Function = $sequentialFunctionMatch.Groups[2].Value
                                    }
                                    continue
                                }
                            }

                            # Detect group end
                            if ($RegexPatterns.SequentialGroupEnd.IsMatch($trimmedLine)) {
                                $currentSequentialGroup = $null
                                continue
                            }

                            # Detect end of RunTestsInSequence - look for }) pattern
                            if ($inRunTestsInSequence -and $RegexPatterns.SequentialEnd.IsMatch($trimmedLine)) {
                                $inRunTestsInSequence = $false
                                continue
                            }

                            # Detect end of map-based sequential - look for }) or }; patterns
                            if ($inMapBasedSequential -and ($RegexPatterns.SequentialEnd.IsMatch($trimmedLine) -or $trimmedLine -match '^\s*\}\s*;?\s*$')) {
                                $inMapBasedSequential = $false
                                continue
                            }
                        }
                    }

                    # Handle final sequential test if we ended while processing one
                    if ($currentMainFunction -and $currentSequentialMappings.Count -gt 0) {
                        $sequentialTests += [PSCustomObject]@{
                            MainFunction = $currentMainFunction
                            SequentialMappings = $currentSequentialMappings
                            RelativePath = $RelativePath
                            Service = $ServiceName
                        }
                    }

                    return $sequentialTests
                }

                $threadResults = @()
                $threadTestResults = @()
                $threadSequentialTests = @()
                $debugMessages = @()

                $debugMessages += "Thread ${ThreadId}: Starting processing of $($FileChunk.Count) files"

                foreach ($fileItem in $FileChunk) {
                    try {
                        # Handle both FileInfo objects and strings
                        $filePath = if ($fileItem -is [System.IO.FileInfo]) { $fileItem.FullName } else { $fileItem }

                        # Skip null or empty paths
                        if ([string]::IsNullOrWhiteSpace($filePath)) {
                            $debugMessages += "Thread ${ThreadId}: Skipping null or empty file path"
                            continue
                        }

                        # Get cached content - FileContents keys should match this path format
                        if ($FileContents.ContainsKey($filePath)) {
                            $content = $FileContents[$filePath]
                        } else {
                            $debugMessages += "Thread ${ThreadId}: Key not found: $filePath"
                            continue
                        }

                        # MATCH SEQUENTIAL LOGIC: Skip files with empty or null content
                        if ([string]::IsNullOrWhiteSpace($content)) {
                            continue
                        }

                        # Extract service name and relative path
                        $pathParts = $filePath.Split([IO.Path]::DirectorySeparatorChar)
                        $servicesIndex = $pathParts.IndexOf("services")
                        if ($servicesIndex -eq -1 -or $servicesIndex + 1 -ge $pathParts.Count) {
                            # Skip files not in services directory structure
                            continue
                        }
                        $serviceName = $pathParts[$servicesIndex + 1]
                        $relativePath = $filePath.Replace($RepositoryDirectory, "").TrimStart('\').Replace("\", "/")

                        # MATCH SEQUENTIAL LOGIC: Parse actual struct definitions from the file content FIRST
                        $structDefinitions = Get-StructDefinitions -FileContent $content -Patterns $RegexPatterns

                        # MATCH SEQUENTIAL LOGIC: Create struct database for this file (local struct resolution)
                        $structDatabase = @{}
                        foreach ($struct in $structDefinitions) {
                            $structDatabase[$struct.StructName] = $struct.Line  # Use line as temporary ID - will be converted in main thread
                        }

                        # MATCH SEQUENTIAL LOGIC: Check if this file contains test functions using the same regex patterns
                        $hasTestFunctions = ($RegexPatterns.TestFunction.IsMatch($content) -or $RegexPatterns.LowerTestFunction.IsMatch($content))

                        $testFunctions = @()
                        if ($hasTestFunctions) {
                            # MATCH SEQUENTIAL LOGIC: Use the EXACT same logic as Get-TestFunctionsFromFile

                            # Extract standard test functions: func TestAccXxx_xxx(t *testing.T)
                            $testFunctionMatches = @()
                            $testFunctionMatches += $RegexPatterns.TestFunction.Matches($content)
                            $testFunctionMatches += $RegexPatterns.LowerTestFunction.Matches($content)

                            foreach ($match in $testFunctionMatches) {
                                $funcName = $match.Groups[1].Value

                                # PROPER inline function body extraction with string/comment/character handling
                                $funcStart = $match.Index
                                $remaining = $content.Substring($funcStart)
                                $openBraceIndex = $remaining.IndexOf('{')

                                if ($openBraceIndex -ne -1) {
                                    # Proper brace counting with string/comment/character literal handling
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

                                    $funcBody = $remaining.Substring(0, [Math]::Min($funcBodyEnd, $remaining.Length))

                                    if (-not [string]::IsNullOrWhiteSpace($funcBody)) {
                                        # MATCH SEQUENTIAL LOGIC: Calculate test prefix exactly like Get-TestFunctionsFromFile
                                        $testPrefix = if ($funcName -match '_') {
                                            ($funcName -split '_')[0] + '_'
                                        } else {
                                            $funcName
                                        }

                                        # MATCH SEQUENTIAL LOGIC: Extract struct name for local resolution using precompiled patterns
                                        $structName = $null
                                        $structMatches = $structInstantiationPattern.Matches($funcBody)
                                        if ($structMatches.Count -gt 0) {
                                            $structName = $structMatches[0].Groups[1].Value
                                        } else {
                                            $methodCallMatches = $structMethodCallPattern.Matches($funcBody)
                                            if ($methodCallMatches.Count -gt 0) {
                                                $structName = $methodCallMatches[0].Groups[1].Value
                                            }
                                        }

                                        # MATCH SEQUENTIAL LOGIC: Try to resolve StructRefId from local file first
                                        $localStructResolved = ($structName -and $structDatabase.ContainsKey($structName))

                                        $testFunctions += @{
                                            FunctionName = $funcName
                                            Line = $match.Index
                                            FunctionBody = $funcBody
                                            TestPrefix = $testPrefix
                                            StructName = $structName
                                            LocalStructResolved = $localStructResolved
                                        }
                                    }
                                }
                            }
                        }
                        # MATCH SEQUENTIAL LOGIC: If not a test file, testFunctions stays empty array

                        # Process sequential tests using the proper parsing function
                        $sequentialTests = Invoke-SequentialTestParsing -Content $content -RelativePath $relativePath -ServiceName $serviceName -RegexPatterns $RegexPatterns

                        # Add to thread results
                        $threadResults += [PSCustomObject]@{
                            ServiceName = $serviceName
                            RelativePath = $relativePath
                            FileContent = if ($hasTestFunctions) { "" } else { $content }
                            StructDefinitions = $structDefinitions
                            TestFunctions = $testFunctions
                            HasTestFunctions = $hasTestFunctions
                        }

                        # Test results for compatibility
                        $threadTestResults += [PSCustomObject]@{
                            File = $relativePath
                            Service = $serviceName
                            TestFunctions = $testFunctions | ForEach-Object { $_.FunctionName }
                            DirectMatches = ([regex]::Matches($content, [regex]::Escape($ResourceName))).Count
                            HasResource = $content -match [regex]::Escape($ResourceName)
                        }

                        $threadSequentialTests += $sequentialTests

                    } catch {
                        $debugMessages += "Thread ${ThreadId} error processing ${filePath}: $($_.Exception.Message)"
                    }
                }

                return @{
                    ThreadId = $ThreadId
                    ProcessedData = $threadResults
                    TestResults = $threadTestResults
                    SequentialTests = $threadSequentialTests
                    FilesProcessed = $FileChunk.Count
                    DebugMessages = $debugMessages
                }
            }

            $null = $powerShell.AddScript($scriptBlock)
            $null = $powerShell.AddArgument($fileChunk)
            $null = $powerShell.AddArgument($chunkFileContents)  # Pass thread-local copy
            $null = $powerShell.AddArgument($RepositoryDirectory)
            $null = $powerShell.AddArgument($RegexPatterns)
            $null = $powerShell.AddArgument($i + 1)
            $null = $powerShell.AddArgument($ResourceName)

            $jobs += @{
                PowerShell = $powerShell
                Handle = $powerShell.BeginInvoke()
                ThreadId = $i + 1
            }
        }
    }

    # Collect results from all threads with immediate termination on failure
    $allProcessedData = @()
    $allTestResults = @()
    $allSequentialTests = @()
    $functionDatabase = @{}

    $totalThreads = $jobs.Count
    $completedThreads = 0
    $dotCount = 0

    # Initial message
    Write-Host "`r [INFO] " -NoNewline -ForegroundColor Cyan
    Write-Host "Waiting For Threads To Return [" -NoNewline -ForegroundColor Gray
    Write-Host "$completedThreads" -NoNewline -ForegroundColor $NumberColor
    Write-Host "/" -NoNewline -ForegroundColor Gray
    Write-Host "$totalThreads" -NoNewline -ForegroundColor $NumberColor
    Write-Host "]" -NoNewline -ForegroundColor Gray

    try {
        foreach ($job in $jobs) {
            try {
                # Animate dots while waiting for this thread
                $asyncResult = $job.Handle
                while (-not $asyncResult.IsCompleted) {
                    $dotCount = ($dotCount % 3) + 1
                    $dots = "." * $dotCount + (" " * (3 - $dotCount))
                    Write-Host "`r [INFO] " -NoNewline -ForegroundColor Cyan
                    Write-Host "Waiting For Threads To Return [" -NoNewline -ForegroundColor Gray
                    Write-Host "$completedThreads" -NoNewline -ForegroundColor $NumberColor
                    Write-Host "/" -NoNewline -ForegroundColor Gray
                    Write-Host "$totalThreads" -NoNewline -ForegroundColor $NumberColor
                    Write-Host "]$dots" -NoNewline -ForegroundColor Gray
                    Start-Sleep -Milliseconds 300
                }

                $result = $job.PowerShell.EndInvoke($job.Handle)
                $completedThreads++

                # Update counter after thread completes
                Write-Host "`r [INFO] " -NoNewline -ForegroundColor Cyan
                Write-Host "Waiting For Threads To Return [" -NoNewline -ForegroundColor Gray
                Write-Host "$completedThreads" -NoNewline -ForegroundColor $NumberColor
                Write-Host "/" -NoNewline -ForegroundColor Gray
                Write-Host "$totalThreads" -NoNewline -ForegroundColor $NumberColor
                Write-Host "]   " -NoNewline -ForegroundColor Gray

                # Check for error in result - ANY thread failure triggers immediate termination
                if ($result.Error) {
                    Write-Host "Thread $($job.ThreadId): CRITICAL ERROR - $($result.Error)" -ForegroundColor Red
                    Write-Host "FATAL: Thread failure detected. Terminating ALL threads immediately..." -ForegroundColor Red

                    # BRUTAL CLEANUP: Stop all running threads immediately
                    foreach ($killJob in $jobs) {
                        try {
                            if ($killJob.PowerShell.InvocationStateInfo.State -eq 'Running') {
                                Write-Host "  Killing thread $($killJob.ThreadId)..." -ForegroundColor Yellow
                                $killJob.PowerShell.Stop()
                            }
                        } catch {
                            # Ignore errors during forced termination
                        }
                    }

                    # Dispose all PowerShell objects
                    foreach ($disposeJob in $jobs) {
                        try {
                            $disposeJob.PowerShell.Dispose()
                        } catch {
                            # Ignore disposal errors
                        }
                    }

                    # Close runspace pool immediately
                    try {
                        $runspacePool.Close()
                        $runspacePool.Dispose()
                    } catch {
                    # Ignore cleanup errors
                }

                # TODO: UX IMPROVEMENT NEEDED - PowerShell exceptions are not user-friendly
                # Replace this with a custom error message using Show-PhaseMessage or similar UI function
                # The current throw pattern displays ugly PowerShell stack traces that don't help users
                throw "Thread $($job.ThreadId) failed with error: $($result.Error). All threads terminated. Cannot continue with incomplete data."
            }                if ($result.ProcessedData -and $result.ProcessedData.Count -gt 0) {
                    $allProcessedData += $result.ProcessedData
                }
                if ($result.TestResults -and $result.TestResults.Count -gt 0) {
                    $allTestResults += $result.TestResults
                }
                if ($result.SequentialTests -and $result.SequentialTests.Count -gt 0) {
                    $allSequentialTests += $result.SequentialTests
                }

            } catch {
                Write-Host "Error collecting results from thread $($job.ThreadId): $($_.Exception.Message)" -ForegroundColor Red

                # BRUTAL CLEANUP: Any error during collection also triggers full termination
                foreach ($killJob in $jobs) {
                    try {
                        if ($killJob.PowerShell.InvocationStateInfo.State -eq 'Running') {
                            $killJob.PowerShell.Stop()
                        }
                        $killJob.PowerShell.Dispose()
                    } catch {
                        # Ignore errors during forced cleanup
                    }
                }

                try {
                    $runspacePool.Close()
                    $runspacePool.Dispose()
                } catch {
                    # Ignore cleanup errors
                }

                # TODO: UX IMPROVEMENT NEEDED - PowerShell exceptions are not user-friendly
                # Replace this with a custom error message using Show-PhaseMessage or similar UI function
                # The current throw pattern displays ugly PowerShell stack traces that don't help users
                throw "Thread collection failed for Thread $($job.ThreadId): $($_.Exception.Message). All threads terminated."
            } finally {
                # Normal disposal for successfully processed threads
                $job.PowerShell.Dispose()
            }
        }

        # Show completion message with green checkmark
        Write-Host "`r [INFO] " -NoNewline -ForegroundColor Cyan
        Write-Host "Waiting For Threads To Return [" -NoNewline -ForegroundColor Gray
        Write-Host "$completedThreads" -NoNewline -ForegroundColor $NumberColor
        Write-Host "/" -NoNewline -ForegroundColor Gray
        Write-Host "$totalThreads" -NoNewline -ForegroundColor $NumberColor
        Write-Host "] - " -NoNewline -ForegroundColor Gray
        Write-Host "Complete" -ForegroundColor Green

    } finally {
        # Final cleanup - only runs if no failures occurred
        try {
            $runspacePool.Close()
            $runspacePool.Dispose()
        } catch {
            # Ignore final cleanup errors (may already be disposed)
        }
    }

    Show-PhaseMessageHighlight -Message "Writing $($allProcessedData.Count) Records To The Database" -HighlightText "$($allProcessedData.Count)" -HighlightColor $NumberColor -BaseColor $BaseColor -InfoColor $InfoColor

    # Phase 2: Sequential database writes from collected data - CRITICAL: Any failure is fatal
    foreach ($processedFile in $allProcessedData) {
        try {
            # Add service record
            $serviceRefId = Add-ServiceRecord -Name $processedFile.ServiceName

            # Add file record
            $fileRefId = Add-FileRecord -ServiceRefId $serviceRefId -FilePath $processedFile.RelativePath -FileContent $processedFile.FileContent

            # MATCH SEQUENTIAL LOGIC: Add struct records FIRST to get StructRefIds for local resolution
            $localStructDatabase = @{}
            foreach ($struct in $processedFile.StructDefinitions) {
                $structRefId = Add-StructRecord -FileRefId $fileRefId -Line $struct.Line -StructName $struct.StructName
                $localStructDatabase[$struct.StructName] = $structRefId
            }

            # MATCH SEQUENTIAL LOGIC: Add test function records with local struct resolution
            foreach ($testFunction in $processedFile.TestFunctions) {
                # Resolve StructRefId from local file first (exactly like Get-TestFunctionsFromFile)
                $structRefId = if ($testFunction.StructName -and $localStructDatabase.ContainsKey($testFunction.StructName)) {
                    $localStructDatabase[$testFunction.StructName]
                } else {
                    $null  # Will be resolved later by cross-file resolution
                }

                $testFunctionRefId = Add-TestFunctionRecord -FileRefId $fileRefId `
                    -StructRefId $structRefId `
                    -FunctionName $testFunction.FunctionName `
                    -Line $testFunction.Line `
                    -TestPrefix $testFunction.TestPrefix `
                    -SequentialEntryPointRefId 0 `
                    -FunctionBody $testFunction.FunctionBody

                $functionDatabase[$testFunction.FunctionName] = $testFunctionRefId
            }

        } catch {
            Write-Host "CRITICAL DATABASE ERROR for file $($processedFile.RelativePath): $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "FATAL: Database write failure detected. Data integrity compromised. Exiting immediately..." -ForegroundColor Red

            # Database failure is unrecoverable
            # TODO: UX IMPROVEMENT NEEDED - PowerShell exceptions are not user-friendly
            # Replace this with a custom error message using Show-PhaseMessage or similar UI function
            # The current throw pattern displays ugly PowerShell stack traces that don't help users
            throw "Database write failed for file '$($processedFile.RelativePath)': $($_.Exception.Message). Cannot continue with corrupted database state."
        }
    }

    # Show-PhaseMessage -Message "Database population complete"

    return @{
        AllTestResults = $allTestResults
        AllSequentialTests = $allSequentialTests
        FunctionDatabase = $functionDatabase
    }
}

Export-ModuleMember -Function Invoke-FileProcessingPhase, Invoke-DatabasePopulation, Invoke-SequentialTestParsing
