# ReferencesProcessing.psm1
# Reference processing and analysis for TerraCorder

function Invoke-RelationalReferencesPopulation {
    <#
    .SYNOPSIS
        RELATIONAL References Population: Use proper foreign key relationships and JOINs instead of content crawling
    .DESCRIPTION
        This function performs comprehensive reference population using optimized relational database operations.
        It handles direct resource references, template function references, and indirect configuration references
        using pre-loaded data and O(1) hashtable lookups for maximum performance.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$AllRelevantFiles,
        [Parameter(Mandatory = $true)]
        [string]$ResourceName,
        [Parameter(Mandatory = $true)]
        [string]$RepositoryDirectory,
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Green",
        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    # PRE-LOAD ALL DATABASE DATA ONCE (no loops!)
    $allFiles = Get-Files
    $allTestFunctions = Get-TestFunctions
    $allTemplateFunctions = Get-TemplateFunctions
    $allTemplateReferences = Get-TemplateReferences

    Show-PhaseMessageMultiHighlight -Message "Analyzing $($allFiles.Count) Files, $($allTestFunctions.Count) Test Functions, And $($allTemplateFunctions.Count) Test Configuration Functions" -HighlightTexts @("$($allFiles.Count)", "$($allTestFunctions.Count)", "$($allTemplateFunctions.Count)") -HighlightColors @($NumberColor, $NumberColor, $NumberColor) -BaseColor $BaseColor -InfoColor $InfoColor

    # TODO: Database Query Optimization
    # Currently building in-memory hashtables for O(1) lookups, but this data already exists in the database.
    # Should add database query functions to Database.psm1:
    #   - Get-TestFunctionsByFileRefId($fileRefId) - returns test functions for a specific file
    #   - Get-TemplateFunctionsByFileRefId($fileRefId) - returns template functions for a specific file
    # This would eliminate the need to:
    #   1. Load ALL test/template functions into memory
    #   2. Build hashtable indexes manually
    #   3. Maintain duplicate data structures
    # The database already has internal indexing - we should leverage it instead of rebuilding indexes.
    # Same architectural issue as Show-RunTestsByService (which was already optimized).
    # Performance impact: ~588ms currently, likely minimal improvement but cleaner architecture.

    # BUILD O(1) LOOKUP HASHTABLES
    $filePathToId = @{}
    $fileIdToTestFuncs = @{}
    $fileIdToTemplateFuncs = @{}

    foreach ($file in $allFiles) {
        $filePathToId[$file.FilePath] = $file.FileRefId
    }

    foreach ($testFunc in $allTestFunctions) {
        if (-not $fileIdToTestFuncs.ContainsKey($testFunc.FileRefId)) {
            $fileIdToTestFuncs[$testFunc.FileRefId] = @()
        }
        $fileIdToTestFuncs[$testFunc.FileRefId] += $testFunc
    }

    foreach ($templateFunc in $allTemplateFunctions) {
        if (-not $fileIdToTemplateFuncs.ContainsKey($templateFunc.FileRefId)) {
            $fileIdToTemplateFuncs[$templateFunc.FileRefId] = @()
        }
        $fileIdToTemplateFuncs[$templateFunc.FileRefId] += $templateFunc
    }

    # PHASE 5A: DIRECT REFERENCES (using file content, O(1) file lookups)
    Show-PhaseMessage -Message "Discovering Direct Resource References" -BaseColor $BaseColor -InfoColor $InfoColor
    $directReferencesAdded = 0

    $fileCount = 0
    $totalFiles = $AllRelevantFiles.Count
    foreach ($file in $AllRelevantFiles) {
        $fileCount++
        if ($fileCount % 50 -eq 0 -or $fileCount -eq 1) {
            Show-InlineProgress -Current $fileCount -Total $totalFiles -Activity "Processing Files" -NumberColor $NumberColor -ItemColor $ItemColor -InfoColor $InfoColor -BaseColor $BaseColor
        }
        $relativePath = $file.FullName.Replace($RepositoryDirectory, "").Replace("\", "/").TrimStart("/")
        $fileRefId = $filePathToId[$relativePath]

        if (-not $fileRefId) { continue }

        # OPTIMIZED APPROACH: Scan extracted function bodies instead of full file content
        # All direct resource references occur within test/template function bodies
        $contentToScan = ""

        # Get test function bodies for this file
        $testFuncsForFile = $fileIdToTestFuncs[$fileRefId]
        if ($testFuncsForFile -and $testFuncsForFile.Count -gt 0) {
            $functionBodies = $testFuncsForFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_.FunctionBody) } | ForEach-Object { $_.FunctionBody }
            $contentToScan = $functionBodies -join "`n`n"
        }

        # Also get template function bodies for this file
        $templateFuncsForFile = $fileIdToTemplateFuncs[$fileRefId]
        if ($templateFuncsForFile -and $templateFuncsForFile.Count -gt 0) {
            $templateBodies = $templateFuncsForFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_.FunctionBody) } | ForEach-Object { $_.FunctionBody }
            if ($templateBodies -and $templateBodies.Count -gt 0) {
                $contentToScan += "`n`n" + ($templateBodies -join "`n`n")
            }
        }

        if ([string]::IsNullOrWhiteSpace($contentToScan)) { continue }

        # Find DirectResourceReferences - simple line scanning
        $lines = $contentToScan -split "`n"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $lineNumber = $i + 1

            if ($line -match [regex]::Escape($ResourceName)) {
                # Skip test check functions
                if ($line -match 'check\.That\(' -or $line -match 'MatchesOtherKey\(' -or $line -match 'CheckWithState\(') {
                    continue
                }

                # Determine reference type using normalized ReferenceTypes
                $referenceType = "ATTRIBUTE_REFERENCE"  # Default reference type name
                $context = $line.Trim()

                if ($Global:RegexPatterns.ResourceDefinition.IsMatch($line) -and $line -match [regex]::Escape($ResourceName)) {
                    $referenceType = "RESOURCE_REFERENCE"
                } elseif ($Global:RegexPatterns.DataSource.IsMatch($line) -and $line -match [regex]::Escape($ResourceName)) {
                    $referenceType = "DATA_SOURCE_REFERENCE"
                }

                Add-DirectResourceReferenceRecord -FileRefId $fileRefId -ReferenceType $referenceType -Line $lineNumber -Context $context | Out-Null
                $directReferencesAdded++
            }
        }
    }

    Show-InlineProgress -Current $totalFiles -Total $totalFiles -Activity "Processing Files" -Completed -NumberColor $NumberColor -ItemColor $ItemColor -InfoColor $InfoColor -BaseColor $BaseColor
    Show-PhaseMessageHighlight -Message "Found $directReferencesAdded Direct Resource References" -HighlightText "$directReferencesAdded" -HighlightColor $NumberColor -BaseColor $BaseColor -InfoColor $InfoColor

    # PHASE 5B: TEMPLATE REFERENCES
    Show-PhaseMessage -Message "Discovering Test Configuration References" -BaseColor $BaseColor -InfoColor $InfoColor
    $templateReferencesAdded = 0

    # PERFORMANCE OPTIMIZATION: Calculate template function names once, not for every file
    # Use hashtable for O(1) lookups instead of O(n) array searches
    $templateFuncNamesArray = $allTemplateFunctions | ForEach-Object { $_.TemplateFunctionName } | Sort-Object -Unique
    $templateFuncNames = @{}
    foreach ($name in $templateFuncNamesArray) { $templateFuncNames[$name] = $true }

    $fileCount = 0
    $totalFiles = $AllRelevantFiles.Count
    foreach ($file in $AllRelevantFiles) {
        $fileCount++
        if ($fileCount % 50 -eq 0 -or $fileCount -eq 1) {
            Show-InlineProgress -Current $fileCount -Total $totalFiles -Activity "Processing Files" -NumberColor $NumberColor -ItemColor $ItemColor -InfoColor $InfoColor -BaseColor $BaseColor
        }
        $relativePath = $file.FullName.Replace($RepositoryDirectory, "").Replace("\", "/").TrimStart("/")
        $fileRefId = $filePathToId[$relativePath]

        if (-not $fileRefId) { continue }

        # O(1) lookup instead of database query!
        $testFuncsForFile = $fileIdToTestFuncs[$fileRefId]

        if (-not $testFuncsForFile) { continue }

        # PERFORMANCE OPTIMIZATION: Use extracted function bodies from TestFunctions table
        # instead of reading full file content and re-extracting function bodies
        # This eliminates the ~35MB file content duplication bottleneck

        foreach ($testFunc in $testFuncsForFile) {
            # Use pre-extracted function body from TestFunctions table - eliminates Get-FunctionBody overhead
            $testFunctionBody = $testFunc.FunctionBody
            if ([string]::IsNullOrWhiteSpace($testFunctionBody)) { continue }

            $stepNumber = 1

            # PERFORMANCE OPTIMIZATION: Single regex to find all Config: patterns, then filter
            # This eliminates 2000+ individual regex calls per test function
            $allConfigPattern = "Config:\s*(\w+)\.(\w+)\s*\("
            $allConfigMatches = [regex]::Matches($testFunctionBody, $allConfigPattern)

            foreach ($match in $allConfigMatches) {
                $receiverVariable = $match.Groups[1].Value
                $calledFuncName = $match.Groups[2].Value

                # Only process if this function name is in our template functions list
                if ($templateFuncNames.ContainsKey($calledFuncName)) {
                    $structRefId = $testFunc.StructRefId
                    if ($structRefId -and $structRefId -gt 0) {
                        # Get the actual TestFunctionStepRefId for this step
                        $testFunctionStepRefId = Get-TestFunctionStepRefIdByIndex -TestFunctionRefId $testFunc.TestFunctionRefId -StepIndex $stepNumber
                        if ($testFunctionStepRefId -gt 0) {
                            $templateReference = "$receiverVariable.$calledFuncName"
                            Add-TemplateReferenceRecord -TestFunctionRefId $testFunc.TestFunctionRefId -StructRefId $structRefId -TestFunctionStepRefId $testFunctionStepRefId -TemplateReference $templateReference -TemplateVariable $receiverVariable -TemplateMethod $calledFuncName | Out-Null
                            $templateReferencesAdded++
                        }
                        $stepNumber++
                    }
                }
            }

            # ApplyStep pattern optimization (single regex, then filter)
            $applyStepMatches = $Global:RegexPatterns.ApplyStepPattern.Matches($testFunctionBody)
            foreach ($match in $applyStepMatches) {
                $structVar = $match.Groups[1].Value
                $funcName = $match.Groups[2].Value

                # Only process if this function name is in our template functions list
                if ($templateFuncNames.ContainsKey($funcName)) {
                    $structRefId = $testFunc.StructRefId
                    if ($structRefId -and $structRefId -gt 0) {
                        # Get the actual TestFunctionStepRefId for this step
                        $testFunctionStepRefId = Get-TestFunctionStepRefIdByIndex -TestFunctionRefId $testFunc.TestFunctionRefId -StepIndex $stepNumber
                        if ($testFunctionStepRefId -gt 0) {
                            $templateReference = "$structVar.$funcName"
                            Add-TemplateReferenceRecord -TestFunctionRefId $testFunc.TestFunctionRefId -StructRefId $structRefId -TestFunctionStepRefId $testFunctionStepRefId -TemplateReference $templateReference -TemplateVariable $structVar -TemplateMethod $funcName | Out-Null
                        }
                        $templateReferencesAdded++
                        $stepNumber++
                    }
                }
            }
        }
    }

    # Show completion for the progress
    Show-InlineProgress -Current $totalFiles -Total $totalFiles -Activity "Processing Files" -Completed -NumberColor $NumberColor -ItemColor $ItemColor -InfoColor $InfoColor -BaseColor $BaseColor

    Show-PhaseMessageHighlight -Message "Found $templateReferencesAdded Test Configuration References" -HighlightText "$templateReferencesAdded" -HighlightColor $NumberColor -BaseColor $BaseColor -InfoColor $InfoColor

    # PHASE 5C: RELATIONAL INDIRECT REFERENCES - NO MORE CONTENT CRAWLING!
    Show-PhaseMessage -Message "Processing Test Configuration Indirect References" -BaseColor $BaseColor -InfoColor $InfoColor

    # Dependencies: RelationalQueries.psm1 (loaded by main script)

    # Get current database data to pass to relational function
    $allTemplateReferences = Get-TemplateReferences
    $currentTestFunctions = Get-TestFunctions
    $currentTemplateFunctions = Get-TemplateFunctions

    # Use proper relational queries instead of content crawling!
    $indirectReferencesAdded = Set-IndirectConfigReferencesRelational -TemplateReferences $allTemplateReferences -TestFunctions $currentTestFunctions -TemplateFunctions $currentTemplateFunctions -NumberColor $NumberColor
    Show-PhaseMessageHighlight -Message "Found $indirectReferencesAdded Test Configuration Indirect References" -HighlightText "$indirectReferencesAdded" -HighlightColor $NumberColor -BaseColor $BaseColor -InfoColor $InfoColor

    return @{
        DirectReferences = $directReferencesAdded
        TemplateReferences = $templateReferencesAdded
        IndirectReferences = $indirectReferencesAdded
    }
}

function Update-ServiceImpactReferentialIntegrity {
    <#
    .SYNOPSIS
    Phase 5.5: Classifies ServiceImpactTypeId for IndirectConfigReferences based on service boundaries

    .DESCRIPTION
    Post-Phase 5 classification that populates ServiceImpactTypeId for all IndirectConfigReferences.
    Determines whether a template function's service matches the resource being searched for.

    ServiceImpactTypeId Classification:
    - SAME_SERVICE (14): Template is in the same Azure service as the target resource
    - CROSS_SERVICE (15): Template is in a different Azure service than the target resource

    Example: cognitive service template containing azurerm_recovery_services_vault would be CROSS_SERVICE
    because cognitive (ServiceRefId=1) ≠ recoveryservices (ServiceRefId=12)

    This runs after Phase 5 when all IndirectConfigReferences are available.

    .PARAMETER ResourceName
    The Azure resource name (e.g., "azurerm_recovery_services_vault") to determine owning service
    #>
    param(
        [Parameter(Mandatory = $true)]
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

    Show-PhaseMessage -Message "Classifying Service Impact Referential Integrity" -BaseColor $BaseColor -InfoColor $InfoColor

    # Get all necessary data
    $indirectRefs = Get-IndirectConfigReferences
    $templateFunctions = Get-TemplateFunctions
    $files = Get-Files

    # Determine target resource's ServiceRefId by finding the resource definition file
    # Pattern: azurerm_recovery_services_vault → *recovery_services_vault_resource*.go
    # Extract the resource-specific part (remove "azurerm_" prefix)
    $resourcePattern = $ResourceName -replace '^azurerm_', ''

    # Find the file that defines this resource (should match *{resource}_resource*.go pattern)
    $targetResourceServiceRefId = $null
    $resourceFile = $files | Where-Object { $_.FilePath -like "*${resourcePattern}_resource*.go" } | Select-Object -First 1

    if ($resourceFile) {
        # Use proper database lookup to get ServiceRefId from FilePath
        $targetResourceServiceRefId = Get-ServiceRefIdByFilePath -FilePath $resourceFile.FilePath
    }

    if (-not $targetResourceServiceRefId) {
        Write-Warning "Could not determine target resource's ServiceRefId for $ResourceName - no resource definition file found"
        return
    }

    # Build lookup dictionaries for performance
    $templateFunctionLookup = @{}
    foreach ($templateFunc in $templateFunctions) {
        $templateFunctionLookup[$templateFunc.TemplateFunctionRefId] = $templateFunc
    }

    $fileLookup = @{}
    foreach ($file in $files) {
        $fileLookup[$file.FileRefId] = $file
    }

    $sameServiceCount = 0
    $crossServiceCount = 0

    foreach ($indirectRef in $indirectRefs) {
        # Get the template function that contains the resource
        $templateFunc = $templateFunctionLookup[$indirectRef.SourceTemplateFunctionRefId]
        if (-not $templateFunc) {
            continue
        }

        # Get the file for the template function
        $templateFile = $fileLookup[$templateFunc.FileRefId]
        if (-not $templateFile) {
            continue
        }

        $templateServiceRefId = $templateFile.ServiceRefId

        # Compare template's service with target resource's service
        if ($templateServiceRefId -eq $targetResourceServiceRefId) {
            # SAME_SERVICE: recoveryservices template using recoveryservices vault
            $result = Update-IndirectConfigReferenceServiceImpact -IndirectRefId $indirectRef.IndirectRefId -ServiceImpactTypeId 14 -ResourceOwningServiceRefId $targetResourceServiceRefId
            if ($result) {
                $sameServiceCount++
            }
        } else {
            # CROSS_SERVICE: cognitive template using recoveryservices vault
            $result = Update-IndirectConfigReferenceServiceImpact -IndirectRefId $indirectRef.IndirectRefId -ServiceImpactTypeId 15 -ResourceOwningServiceRefId $targetResourceServiceRefId
            if ($result) {
                $crossServiceCount++
            }
        }
    }

    if ($sameServiceCount -gt 0 -or $crossServiceCount -gt 0) {
        Show-PhaseMessageMultiHighlight -Message "Classified $sameServiceCount SAME_SERVICE And $crossServiceCount CROSS_SERVICE Indirect Dependencies" -HighlightTexts @($sameServiceCount, "SAME_SERVICE", $crossServiceCount, "CROSS_SERVICE") -HighlightColors @($NumberColor, $ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor
    } else {
        Show-PhaseMessage -Message "No Indirect Dependencies Found For Service Impact Classification" -BaseColor $BaseColor -InfoColor $InfoColor
    }
}

Export-ModuleMember -Function Invoke-RelationalReferencesPopulation, Update-ServiceImpactReferentialIntegrity
