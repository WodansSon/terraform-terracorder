# DatabaseMode.psm1
# Query and visualization functions for Database-Only Mode
# These functions provide deep analysis without re-running discovery phases

function Show-DirectReferences {
    <#
    .SYNOPSIS
    Display all direct resource references from the database

    .PARAMETER NumberColor
    Color for numbers in output

    .PARAMETER ItemColor
    Color for item types in output

    .PARAMETER BaseColor
    Color for base text in output

    .PARAMETER InfoColor
    Color for info prefix in output
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",

        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    Write-Host ""
    Write-Separator
    Write-Host "  DIRECT RESOURCE REFERENCES ANALYSIS" -ForegroundColor $ItemColor
    Write-Separator
    Write-Host ""

    $directRefs = Get-DirectResourceReferences

    if ($directRefs.Count -eq 0) {
        Show-PhaseMessageHighlight -Message "No Direct Resource References Found In Database" -HighlightText "No" -HighlightColor "Yellow" -BaseColor $BaseColor -InfoColor $InfoColor
        return
    }

    Show-PhaseMessageMultiHighlight -Message "Found $($directRefs.Count) Direct Resource References" -HighlightTexts @("$($directRefs.Count)", "Direct") -HighlightColors @($NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor
    Write-Host ""

    # Group by file first, then display references within each file
    $groupedByFile = $directRefs | Group-Object -Property FileRefId | Sort-Object { Get-FilePathByRefId -FileRefId $_.Name }
    $totalFiles = $groupedByFile.Count
    $currentFileIndex = 0

    foreach ($fileGroup in $groupedByFile) {
        $currentFileIndex++
        $filePath = Get-FilePathByRefId -FileRefId $fileGroup.Name
        $fileRefCount = $fileGroup.Count

        Write-Host "  File: " -ForegroundColor $ItemColor -NoNewline
        Write-Host "./$filePath " -ForegroundColor Magenta -NoNewline
        Write-Host "(" -ForegroundColor $ItemColor -NoNewline
        Write-Host "$fileRefCount " -ForegroundColor $NumberColor -NoNewline
        Write-Host "References" -ForegroundColor $ItemColor -NoNewline
        Write-Host ")" -ForegroundColor $ItemColor

        # Calculate column widths for alignment
        $maxLineNumWidth = ($fileGroup.Group | ForEach-Object { $_.LineNumber.ToString().Length } | Measure-Object -Maximum).Maximum
        $maxContextWidth = 100

        # Sort by line number within file
        foreach ($ref in $fileGroup.Group | Sort-Object LineNumber) {
            $lineNumStr = $ref.LineNumber.ToString().PadLeft($maxLineNumWidth)

            Write-Host "    Line " -ForegroundColor $InfoColor -NoNewline
            Write-Host "${lineNumStr}" -ForegroundColor $NumberColor -NoNewline
            Write-Host ": " -ForegroundColor $InfoColor -NoNewline

            $context = $ref.Context.Trim()
            if ($context.Length -gt $maxContextWidth) {
                $context = $context.Substring(0, $maxContextWidth - 3) + "..."
            }
            Write-Host "$context" -ForegroundColor $InfoColor
        }

        # Only print blank line if not the last file
        if ($currentFileIndex -lt $totalFiles) {
            Write-Host ""
        }
    }
}

function Show-IndirectReferences {
    <#
    .SYNOPSIS
    Display all indirect/template-based references from the database

    .PARAMETER NumberColor
    Color for numbers in output

    .PARAMETER ItemColor
    Color for item types in output

    .PARAMETER BaseColor
    Color for base text in output

    .PARAMETER InfoColor
    Color for info prefix in output
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",

        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    Write-Host ""
    Write-Separator
    Write-Host " INDIRECT REFERENCES ANALYSIS:" -ForegroundColor $ItemColor
    Write-Separator
    Write-Host ""

    $indirectRefs = Get-IndirectConfigReferences
    $templateRefs = Get-TemplateReferences
    $sequentialRefs = Get-SequentialReferences

    if ($indirectRefs.Count -eq 0 -and $templateRefs.Count -eq 0 -and $sequentialRefs.Count -eq 0) {
        Show-PhaseMessageHighlight -Message "No Indirect References Found In Database" -HighlightText "No" -HighlightColor "Yellow" -BaseColor $BaseColor -InfoColor $InfoColor
        return
    }

    # Service Impact Analysis (ServiceImpactTypeId is loaded as integer from Database.psm1)
    $sameServiceRefs = $indirectRefs | Where-Object { $_.ServiceImpactTypeId -eq 14 }
    $crossServiceRefs = $indirectRefs | Where-Object { $_.ServiceImpactTypeId -eq 15 }

    Write-Host "  Total Impact: " -ForegroundColor $InfoColor -NoNewline
    Write-Host "$($indirectRefs.Count + $sequentialRefs.Count) " -ForegroundColor $NumberColor -NoNewline
    Write-Host "test functions affected by this resource change" -ForegroundColor $InfoColor
    Write-Host ""

    # Template Dependencies (explain what this means)
    if ($indirectRefs.Count -gt 0) {
        Write-Host "  Template Dependencies: " -ForegroundColor $InfoColor -NoNewline
        Write-Host "$($indirectRefs.Count) " -ForegroundColor $NumberColor -NoNewline
        Write-Host "tests use templates that configure this resource" -ForegroundColor $InfoColor

        if ($sameServiceRefs.Count -gt 0) {
            Write-Host "     - " -ForegroundColor DarkGray -NoNewline
            Write-Host "$($sameServiceRefs.Count) " -ForegroundColor Green -NoNewline
            Write-Host "templates in the same service folder " -ForegroundColor Gray -NoNewline
            Write-Host "(LOW RISK)" -ForegroundColor Green
        }
        if ($crossServiceRefs.Count -gt 0) {
            Write-Host "     - " -ForegroundColor DarkGray -NoNewline
            Write-Host "$($crossServiceRefs.Count) " -ForegroundColor Red -NoNewline
            Write-Host "templates in different service folders " -ForegroundColor Gray -NoNewline
            Write-Host "(HIGH RISK - requires cross-service coordination)" -ForegroundColor Red
        }
        Write-Host ""
    }

    # Sequential Test Chains (explain what this means)
    if ($sequentialRefs.Count -gt 0) {
        Write-Host "  Sequential Test Chains: " -ForegroundColor $InfoColor -NoNewline
        Write-Host "$($sequentialRefs.Count) " -ForegroundColor $NumberColor -NoNewline
        Write-Host "tests are called by other tests in the blast radius" -ForegroundColor $InfoColor
        Write-Host "     - " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($sequentialRefs.Count) " -ForegroundColor Yellow -NoNewline
        Write-Host "tests run as part of larger test sequences " -ForegroundColor Gray -NoNewline
        Write-Host "(MEDIUM RISK)" -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Separator

    # Pre-build template reference lookup for O(1) access
    $templateRefLookup = @{}
    foreach ($templateRef in $templateRefs) {
        if (-not $templateRefLookup.ContainsKey($templateRef.TemplateReferenceRefId)) {
            $templateRefLookup[$templateRef.TemplateReferenceRefId] = $templateRef
        }
    }

    # Pre-build test function steps lookup for O(1) access
    $testFuncStepLookup = @{}
    foreach ($step in Get-AllTestFunctionSteps) {
        if (-not $testFuncStepLookup.ContainsKey($step.TestFunctionStepRefId)) {
            $testFuncStepLookup[$step.TestFunctionStepRefId] = $step
        }
    }

    # Pre-build template functions lookup for O(1) access to source template file paths
    $templateFuncLookup = @{}
    foreach ($templateFunc in Get-TemplateFunctions) {
        if (-not $templateFuncLookup.ContainsKey($templateFunc.TemplateFunctionRefId)) {
            $templateFuncLookup[$templateFunc.TemplateFunctionRefId] = $templateFunc
        }
    }

    # Build file-based grouping - Join: IndirectConfigReferences → TemplateReferences → TestFunctionSteps → TestFunctions → Files
    $fileGroups = @{}
    foreach ($indirectRef in $indirectRefs) {
        # Get TemplateReference
        $templateRef = $templateRefLookup[$indirectRef.TemplateReferenceRefId]
        if (-not $templateRef) { continue }

        # Get TestFunction (has the line number and file reference)
        $testFunc = Get-TestFunctionById -TestFunctionRefId $templateRef.TestFunctionRefId
        if (-not $testFunc) { continue }

        # Get TestFunctionStep (has the step index)
        $testFuncStep = $testFuncStepLookup[$templateRef.TestFunctionStepRefId]
        if (-not $testFuncStep) { continue }

        # Get reference type name from the TestFunctionStep (CROSS_FILE, EMBEDDED_SELF, etc.)
        $refTypeName = Get-ReferenceTypeName -ReferenceTypeId $testFuncStep.ReferenceTypeId

        # Get service impact type name from the IndirectConfigReference (SAME_SERVICE, CROSS_SERVICE)
        $serviceImpactTypeName = $null
        if ($indirectRef.PSObject.Properties['ServiceImpactTypeId'] -and $indirectRef.ServiceImpactTypeId) {
            $serviceImpactTypeName = Get-ReferenceTypeName -ReferenceTypeId $indirectRef.ServiceImpactTypeId
        }

        # Get the resource's owning service name for cross-service references
        $resourceOwningServiceName = $null
        if ($indirectRef.PSObject.Properties['ResourceOwningServiceRefId'] -and $indirectRef.ResourceOwningServiceRefId) {
            $services = Get-Services
            $resourceOwningServiceName = $services | Where-Object { $_.ServiceRefId -eq $indirectRef.ResourceOwningServiceRefId } | Select-Object -First 1 -ExpandProperty Name
        }

        # Group by file
        $fileRefId = $testFunc.FileRefId
        if (-not $fileGroups.ContainsKey($fileRefId)) {
            $fileGroups[$fileRefId] = @()
        }

        $fileGroups[$fileRefId] += @{
            TestFunc                  = $testFunc
            TestFuncStep              = $testFuncStep
            TemplateRef               = $templateRef
            RefTypeName               = $refTypeName
            ServiceImpactTypeName     = $serviceImpactTypeName
            ResourceOwningServiceName = $resourceOwningServiceName
        }
    }

    # Add Sequential References - these are test functions that call other test functions sequentially
    # The entry point is the test in our blast radius, and it calls the referenced function
    foreach ($seqRef in $sequentialRefs) {
        # Get the referenced function (the sequential test being called)
        $referencedFunc = Get-TestFunctionById -TestFunctionRefId $seqRef.ReferencedFunctionRefId
        if (-not $referencedFunc) { continue }

        # Get the entry point function to show the calling relationship
        $entryPointFunc = Get-TestFunctionById -TestFunctionRefId $seqRef.EntryPointFunctionRefId
        if (-not $entryPointFunc) { continue }

        # Group by file where the ENTRY POINT is located (not the referenced function)
        $fileRefId = $entryPointFunc.FileRefId
        if (-not $fileGroups.ContainsKey($fileRefId)) {
            $fileGroups[$fileRefId] = @()
        }

        $fileGroups[$fileRefId] += @{
            TestFunc              = $referencedFunc
            SequentialEntryPoint  = $entryPointFunc
            SequentialKey         = $seqRef.SequentialKey
            SequentialGroup       = $seqRef.SequentialGroup
            IsSequential          = $true
        }
    }

    # Display grouped by file with better organization
    $sortedFileRefIds = $fileGroups.Keys | Sort-Object
    $totalFiles = $sortedFileRefIds.Count
    $currentFileIndex = 0

    Write-Host " Blast Radius Analysis:" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""

    foreach ($fileRefId in $sortedFileRefIds) {
        $currentFileIndex++
        $refs = $fileGroups[$fileRefId]
        $filePath = Get-FilePathByRefId -FileRefId $fileRefId

        # Separate sequential and template references
        $sequentialRefs = $refs | Where-Object { $_.IsSequential }
        $templateRefs = $refs | Where-Object { -not $_.IsSequential }

        # Deduplicate template references based on unique combination of TestFunction + Step + Template
        # Multiple IndirectConfigReferences can point to the same test step/template combination
        if ($templateRefs.Count -gt 0) {
            $uniqueTemplateRefs = @{}
            foreach ($tref in $templateRefs) {
                $key = "$($tref.TestFunc.TestFunctionRefId)-$($tref.TestFuncStep.TestFunctionStepRefId)-$($tref.TemplateRef.TemplateReferenceRefId)"
                if (-not $uniqueTemplateRefs.ContainsKey($key)) {
                    $uniqueTemplateRefs[$key] = $tref
                }
            }
            $templateRefs = $uniqueTemplateRefs.Values
        }

        # File header
        Write-Host "File: " -ForegroundColor Cyan -NoNewline
        Write-Host "$filePath" -ForegroundColor Magenta
        Write-Host "   " -NoNewline
        if ($templateRefs.Count -gt 0) {
            $templateLabel = if ($templateRefs.Count -eq 1) { "Test Configuration Function" } else { "Test Configuration Functions" }
            Write-Host "   $($templateRefs.Count) " -ForegroundColor $NumberColor -NoNewline
            Write-Host "$templateLabel" -ForegroundColor $InfoColor -NoNewline
        }
        if ($templateRefs.Count -gt 0 -and $sequentialRefs.Count -gt 0) {
            Write-Host ", " -ForegroundColor $BaseColor -NoNewline
        }
        if ($sequentialRefs.Count -gt 0) {
            Write-Host "$($sequentialRefs.Count) " -ForegroundColor $NumberColor -NoNewline
            Write-Host "Sequential" -ForegroundColor $InfoColor -NoNewline
        }
        Write-Host ""
        Write-Host ""

        if ($refs.Count -gt 0) {
            $maxLineNumWidth = ($refs | ForEach-Object { $_.TestFunc.Line.ToString().Length } | Measure-Object -Maximum).Maximum

            # Display template references first (if any)
            if ($templateRefs.Count -gt 0) {
                Write-Host "   Test Configuration Function Dependencies:" -ForegroundColor $ItemColor
                Write-Host ""

                # Get executing service name from the file path (e.g., internal/services/recoveryservices/...)
                $executingServiceName = "unknown"
                if ($filePath -match 'internal/services/([^/]+)/') {
                    $executingServiceName = $matches[1]
                }

                # Group by test function to consolidate steps
                $functionGroups = @{}
                foreach ($refInfo in $templateRefs) {
                    $funcId = $refInfo.TestFunc.TestFunctionRefId
                    if (-not $functionGroups.ContainsKey($funcId)) {
                        $functionGroups[$funcId] = @{
                            TestFunc = $refInfo.TestFunc
                            Steps = @()
                            ServiceImpactTypeName = $refInfo.ServiceImpactTypeName
                            ResourceOwningServiceName = $refInfo.ResourceOwningServiceName
                        }
                    }
                    $functionGroups[$funcId].Steps += $refInfo
                }

                # Sort by test function line number
                $sortedFunctions = $functionGroups.Values | Sort-Object { $_.TestFunc.Line }
                $totalFunctions = $sortedFunctions.Count
                $currentFunctionIndex = 0

                foreach ($funcGroup in $sortedFunctions) {
                    $currentFunctionIndex++
                    $lineNumStr = $funcGroup.TestFunc.Line.ToString().PadLeft($maxLineNumWidth)

                    # Determine color based on service impact
                    $impactColor = "White"
                    if ($funcGroup.ServiceImpactTypeName -eq "CROSS_SERVICE") {
                        $impactColor = "Yellow"
                    } elseif ($funcGroup.ServiceImpactTypeName -eq "SAME_SERVICE") {
                        $impactColor = "Green"
                    }

                    # Function name
                    Write-Host "     Function: " -ForegroundColor $BaseColor -NoNewline
                    Write-Host "$($funcGroup.TestFunc.FunctionName)" -ForegroundColor White

                    # Show service context - only for cross-service references (before Function Location)
                    if ($executingServiceName -ne $funcGroup.ResourceOwningServiceName) {
                        # Cross-service - show which service is referencing this resource
                        Write-Host "               Referenced From  : " -ForegroundColor $BaseColor -NoNewline
                        Write-Host "$executingServiceName" -ForegroundColor Cyan
                    }

                    # Function location
                    Write-Host "               Function Location: " -ForegroundColor $BaseColor -NoNewline
                    Write-Host "Line ${lineNumStr}" -ForegroundColor $NumberColor

                    # Display steps (sorted by step index)
                    $sortedSteps = $funcGroup.Steps | Sort-Object { $_.TestFuncStep.StepIndex }
                    foreach ($stepInfo in $sortedSteps) {
                        Write-Host "               Step $($stepInfo.TestFuncStep.StepIndex)           : " -ForegroundColor $BaseColor -NoNewline
                        Write-Host "$($stepInfo.TemplateRef.TemplateVariable).$($stepInfo.TemplateRef.TemplateMethod)" -ForegroundColor $impactColor
                    }

                    # Add blank line between functions (but not after the last one)
                    if ($currentFunctionIndex -lt $totalFunctions) {
                        Write-Host ""
                    }
                }
            }

            # Display sequential references (if any)
            if ($sequentialRefs.Count -gt 0) {
                Write-Host "   Sequential Call Chain:" -ForegroundColor $ItemColor
                Write-Host ""

                # Define Unicode box-drawing characters using [char] to ensure proper single-width rendering
                $pipe = [char]0x2502      # vertical line
                $tee = [char]0x251C       # T-junction (branch continues)
                $corner = [char]0x2514    # corner (last branch)
                $arrow = [char]0x2500     # horizontal line
                $teeDown = [char]0x252C   # T-junction down (children below)
                $rarrow = [char]0x25BA    # right-pointing arrow

                # Define base left padding for tree structure
                $basePadding = "     "    # 5 spaces - Entry point level indentation

                # Group by entry point, then by sequential group
                $entryPointGroups = @{}
                foreach ($refInfo in $sequentialRefs) {
                    $epId = $refInfo.SequentialEntryPoint.TestFunctionRefId
                    if (-not $entryPointGroups.ContainsKey($epId)) {
                        $entryPointGroups[$epId] = @{
                            EntryPoint = $refInfo.SequentialEntryPoint
                            Groups = @{}
                        }
                    }

                    $groupName = $refInfo.SequentialGroup
                    if (-not $entryPointGroups[$epId].Groups.ContainsKey($groupName)) {
                        $entryPointGroups[$epId].Groups[$groupName] = @()
                    }
                    $entryPointGroups[$epId].Groups[$groupName] += $refInfo
                }

                # Display each entry point and its sequential groups
                $allEntryPoints = $entryPointGroups.Values
                $totalEntryPoints = $allEntryPoints.Count
                $currentEntryPointIndex = 0

                foreach ($epData in $allEntryPoints) {
                    $currentEntryPointIndex++
                    $entryPoint = $epData.EntryPoint

                    # Entry point level - shows T-down to indicate Sequential Groups belong to it
                    $entryPrefix = $basePadding

                    Write-Host "$entryPrefix Entry Point: " -ForegroundColor $InfoColor -NoNewline
                    Write-Host "Line " -ForegroundColor $BaseColor -NoNewline
                    Write-Host "$($entryPoint.Line)" -ForegroundColor $NumberColor -NoNewline
                    Write-Host ": " -ForegroundColor $BaseColor -NoNewline
                    Write-Host "$($entryPoint.FunctionName)" -ForegroundColor $ItemColor
                    Write-Host "       $pipe" -ForegroundColor $BaseColor

                    # Display each sequential group
                    $groupNames = $epData.Groups.Keys | Sort-Object
                    $totalGroups = $groupNames.Count
                    $currentGroupIndex = 0

                    foreach ($groupName in $groupNames) {
                        $currentGroupIndex++
                        $isLastGroup = ($currentGroupIndex -eq $totalGroups)

                        # Group level - Keys align with the T-down character position
                        $groupPrefix = if ($isLastGroup) { "          " } else { "       $pipe  " }

                        $rawSteps = $epData.Groups[$groupName]
                        # Sort only if there are multiple steps, otherwise preserve the single item
                        if ($rawSteps.Count -gt 1) {
                            $steps = @($rawSteps | Sort-Object -Property SequentialKey)
                        } else {
                            $steps = @($rawSteps)
                        }

                        # Display each step in the group
                        $stepCount = $steps.Count

                        # Determine group branch based on position - always show T-down since groups have keys as children
                        $groupBranch = if ($isLastGroup) { "$corner$arrow$arrow$teeDown" } else { "$tee$arrow$arrow$teeDown" }

                        Write-Host "       $groupBranch$arrow$rarrow" -ForegroundColor $BaseColor -NoNewline
                        Write-Host " Sequential Group: " -ForegroundColor $BaseColor -NoNewline
                        Write-Host "$groupName" -ForegroundColor $NumberColor

                        # Only show the continuation pipe if there are multiple keys
                        if ($stepCount -gt 1) {
                            Write-Host "$groupPrefix$pipe" -ForegroundColor $BaseColor
                        }
                        $currentStep = 0
                        foreach ($step in $steps) {
                            $currentStep++
                            $isLastStep = ($currentStep -eq $stepCount)

                            # DEBUG: Output stepCount value
                            # Write-Host "[DEBUG] stepCount=$stepCount, isLastStep=$isLastStep" -ForegroundColor Red

                            # When there's only one key, use corner; otherwise use tee/corner based on position
                            if ($stepCount -eq 1) {
                                $stepBranch = "$corner$arrow$teeDown$arrow"
                            } else {
                                $stepBranch = if ($isLastStep) { "$corner$arrow$teeDown$arrow" } else { "$tee$arrow$teeDown$arrow" }
                            }

                            # Key level - builds on group prefix
                            $keyPrefix = if ($isLastStep) { "$groupPrefix " } else { "$groupPrefix$pipe" }

                            # Key header with T-junction down for children
                            Write-Host "$groupPrefix$stepBranch$rarrow " -ForegroundColor $BaseColor -NoNewline
                            Write-Host "Key     : " -ForegroundColor $BaseColor -NoNewline
                            Write-Host "$($step.SequentialKey)" -ForegroundColor $NumberColor

                            # Configuration Function with T-junction (not last item) - aligned with T-down
                            Write-Host "$keyPrefix $tee$arrow$rarrow Function: " -ForegroundColor $BaseColor -NoNewline
                            Write-Host "$($step.TestFunc.FunctionName)" -ForegroundColor $InfoColor

                            # Function Location (last item uses corner) - aligned with T-down
                            Write-Host "$keyPrefix $corner$arrow$rarrow Location: " -ForegroundColor $BaseColor -NoNewline
                            if ($step.TestFunc.Line -eq 0) {
                                Write-Host "External Reference " -ForegroundColor $NumberColor -NoNewline
                                Write-Host "(" -ForegroundColor $BaseColor -NoNewline
                                Write-Host "Not Tracked" -ForegroundColor Red -NoNewline
                                Write-Host ")" -ForegroundColor $BaseColor
                            } else {
                                Write-Host "Line $($step.TestFunc.Line)" -ForegroundColor $NumberColor
                            }

                            if (-not $isLastStep) {
                                Write-Host "$groupPrefix$pipe" -ForegroundColor $BaseColor
                            }
                        }

                        # Continuation pipe between groups (unless it's the last group)
                        if (-not $isLastGroup) {
                            Write-Host "       $pipe" -ForegroundColor $BaseColor
                        }
                    }

                    # Add newline between entry points (unless it's the last one)
                    if ($currentEntryPointIndex -lt $totalEntryPoints) {
                        Write-Host ""
                    }
                }
            }
        }

        # Separator between files
        if ($currentFileIndex -lt $totalFiles) {
            Write-Host ""
        }
    }

    Write-Host ""
    Write-Separator
    Write-Host " End of Blast Radius Analysis" -ForegroundColor Cyan
    Write-Separator
}

function Show-SequentialReferences {
    <#
    .SYNOPSIS
    Display all sequential test dependencies from the database

    .PARAMETER NumberColor
    Color for numbers in output

    .PARAMETER ItemColor
    Color for item types in output

    .PARAMETER BaseColor
    Color for base text in output

    .PARAMETER InfoColor
    Color for info prefix in output
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",

        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    Write-Host ""
    Write-Separator
    Write-Host "  SEQUENTIAL TEST DEPENDENCIES ANALYSIS" -ForegroundColor $ItemColor
    Write-Separator
    Write-Host ""

    $sequentialRefs = Get-SequentialReferences

    if ($sequentialRefs.Count -eq 0) {
        Show-PhaseMessageHighlight -Message "No Sequential References Found In Database" -HighlightText "No" -HighlightColor "Yellow" -BaseColor $BaseColor -InfoColor $InfoColor
        return
    }

    Show-PhaseMessageMultiHighlight -Message "Found $($sequentialRefs.Count) Sequential Test Dependencies" -HighlightTexts @("$($sequentialRefs.Count)", "Sequential") -HighlightColors @($NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor
    Write-Host ""

    # Group by sequential group
    $groupedBySequence = $sequentialRefs | Group-Object -Property SequentialGroup
    $totalGroups = $groupedBySequence.Count
    $currentGroupIndex = 0

    foreach ($group in $groupedBySequence) {
        $currentGroupIndex++
        $sequenceGroup = $group.Name
        $count = $group.Count

        Write-Host "  Sequential Group: " -ForegroundColor $ItemColor -NoNewline
        Write-Host "$sequenceGroup " -ForegroundColor White -NoNewline
        Write-Host "($count dependencies)" -ForegroundColor $NumberColor
        Write-Host ""

        foreach ($ref in $group.Group | Sort-Object SequentialKey) {
            # Get entry point function
            $entryFunc = Get-TestFunctionById -TestFunctionRefId $ref.EntryPointFunctionRefId
            # Get referenced function
            $refFunc = Get-TestFunctionById -TestFunctionRefId $ref.ReferencedFunctionRefId

            if ($entryFunc -and $refFunc) {
                Write-Host "    " -NoNewline
                Write-Host "$($entryFunc.FunctionName)" -ForegroundColor $NumberColor -NoNewline
                Write-Host " -> " -ForegroundColor $BaseColor -NoNewline
                Write-Host "$($refFunc.FunctionName)" -ForegroundColor White
            }
        }

        # Only print blank line if not the last group
        if ($currentGroupIndex -lt $totalGroups) {
            Write-Host ""
        }
    }
}

function Show-CrossFileReferences {
    <#
    .SYNOPSIS
    Display cross-file struct references from the database

    .PARAMETER NumberColor
    Color for numbers in output

    .PARAMETER ItemColor
    Color for item types in output

    .PARAMETER BaseColor
    Color for base text in output

    .PARAMETER InfoColor
    Color for info prefix in output
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",

        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    Write-Host ""
    Write-Separator
    Write-Host "  CROSS-FILE STRUCT REFERENCES ANALYSIS" -ForegroundColor $ItemColor
    Write-Separator
    Write-Host ""

    # Get all test function steps with CROSS_FILE reference type
    $crossFileTypeId = Get-ReferenceTypeId -ReferenceTypeName "CROSS_FILE"
    $crossFileSteps = Get-TestFunctionStepsByReferenceType -ReferenceTypeId $crossFileTypeId

    if ($crossFileSteps.Count -eq 0) {
        Show-PhaseMessageHighlight -Message "No Cross-File References Found In Database" -HighlightText "No" -HighlightColor "Yellow" -BaseColor $BaseColor -InfoColor $InfoColor
        return
    }

    Show-PhaseMessageMultiHighlight -Message "Found $($crossFileSteps.Count) Cross-File Struct References" -HighlightTexts @("$($crossFileSteps.Count)", "Cross-File") -HighlightColors @($NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor
    Write-Host ""

    # Build file-based grouping
    $fileGroups = @{}
    foreach ($step in $crossFileSteps) {
        $testFunc = Get-TestFunctionById -TestFunctionRefId $step.TestFunctionRefId
        if ($testFunc) {
            $fileRefId = $testFunc.FileRefId
            if (-not $fileGroups.ContainsKey($fileRefId)) {
                $fileGroups[$fileRefId] = @()
            }
            $fileGroups[$fileRefId] += @{
                TestFunc = $testFunc
                Step     = $step
            }
        }
    }

    # Display grouped by file
    $sortedFileRefIds = $fileGroups.Keys | Sort-Object
    $totalFiles = $sortedFileRefIds.Count
    $currentFileIndex = 0

    foreach ($fileRefId in $sortedFileRefIds) {
        $currentFileIndex++
        $refs = $fileGroups[$fileRefId]
        $filePath = Get-FilePathByRefId -FileRefId $fileRefId

        Write-Host "  File: " -ForegroundColor $ItemColor -NoNewline
        Write-Host "$filePath " -ForegroundColor Magenta -NoNewline
        Write-Host "($($refs.Count) cross-file references)" -ForegroundColor $NumberColor

        foreach ($refInfo in ($refs | Sort-Object { $_.TestFunc.FunctionName })) {
            Write-Host "    Test: " -ForegroundColor $ItemColor -NoNewline
            Write-Host "$($refInfo.TestFunc.FunctionName)" -ForegroundColor White

            if ($refInfo.Step.StructRefId) {
                $struct = Get-StructById -StructRefId $refInfo.Step.StructRefId
                if ($struct) {
                    $structFilePath = Get-FilePathByRefId -FileRefId $struct.FileRefId

                    Write-Host "      Struct: " -ForegroundColor $BaseColor -NoNewline
                    Write-Host "$($struct.StructName)" -ForegroundColor $NumberColor -NoNewline
                    Write-Host " (from $structFilePath)" -ForegroundColor $BaseColor
                }
            }

            if ($refInfo.Step.ConfigTemplate) {
                $template = $refInfo.Step.ConfigTemplate.Trim()
                if ($template.Length -gt 80) {
                    $template = $template.Substring(0, 77) + "..."
                }
                Write-Host "      Template: " -ForegroundColor $BaseColor -NoNewline
                Write-Host "$template" -ForegroundColor DarkGray
            }
        }

        # Only print blank line if not the last file
        if ($currentFileIndex -lt $totalFiles) {
            Write-Host ""
        }
    }
}

function Show-AllReferences {
    <#
    .SYNOPSIS
    Display all reference types from the database

    .PARAMETER NumberColor
    Color for numbers in output

    .PARAMETER ItemColor
    Color for item types in output

    .PARAMETER BaseColor
    Color for base text in output

    .PARAMETER InfoColor
    Color for info prefix in output
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",

        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    Show-DatabaseStatistics -NumberColor $NumberColor -ItemColor $ItemColor -BaseColor $BaseColor -InfoColor $InfoColor
    Show-DirectReferences -NumberColor $NumberColor -ItemColor $ItemColor -BaseColor $BaseColor -InfoColor $InfoColor
    Show-IndirectReferences -NumberColor $NumberColor -ItemColor $ItemColor -BaseColor $BaseColor -InfoColor $InfoColor
    Show-SequentialReferences -NumberColor $NumberColor -ItemColor $ItemColor -BaseColor $BaseColor -InfoColor $InfoColor
    Show-CrossFileReferences -NumberColor $NumberColor -ItemColor $ItemColor -BaseColor $BaseColor -InfoColor $InfoColor
}

Export-ModuleMember -Function @(
    'Show-DirectReferences',
    'Show-IndirectReferences',
    'Show-SequentialReferences',
    'Show-CrossFileReferences',
    'Show-AllReferences'
)
