#!/usr/bin/env pwsh
<#
.SYNOPSIS
    AST-based data import module for TerraCorder

.DESCRIPTION
    Imports Replicode JSON output and populates database tables.
    Replaces all regex-based pattern matching with semantic analysis.

.NOTES
    Version: 3.0.0
    Requires: Database.psm1, UI.psm1

    Replicode Output Schema:
    - file_path: string
    - functions: array (with IsTestFunc, ReceiverType, FunctionName, ServiceName, Line)
    - test_steps: array (with source_function, config_struct, config_method, etc.)
    - template_calls: array (with source_function, target_struct, target_method, is_local_call)
    - calls: array (all function calls)
#>

#region Helper Functions

function Get-OrCreateServiceId {
    param([string]$ServiceName)

    if ([string]::IsNullOrWhiteSpace($ServiceName)) {
        return $null
    }

    $existing = $script:Services.Values | Where-Object { $_.Name -eq $ServiceName } | Select-Object -First 1
    if ($existing) {
        return $existing.ServiceRefId
    }

    return Add-ServiceRecord -Name $ServiceName
}

function Get-OrCreateStructId {
    param([string]$StructName)

    if ([string]::IsNullOrWhiteSpace($StructName)) {
        return $null
    }

    $existing = $script:Structs.Values | Where-Object { $_.StructName -eq $StructName } | Select-Object -First 1
    if ($existing) {
        return $existing.StructRefId
    }

    return Add-StructRecord -StructName $StructName
}

function Get-OrCreateResourceId {
    param([string]$ResourceName)

    if ([string]::IsNullOrWhiteSpace($ResourceName)) {
        return $null
    }

    $existing = $script:Resources.Values | Where-Object { $_.ResourceName -eq $ResourceName } | Select-Object -First 1
    if ($existing) {
        return $existing.ResourceRefId
    }

    return Add-ResourceRecord -ResourceName $ResourceName
}

#endregion

#region Import Functions

function Import-FunctionsFromAST {
    param(
        [object]$ASTData,
        [int]$FileRefId
    )

    $testFunctionIds = @{}
    $templateFunctionIds = @{}

    if (-not $ASTData.functions) {
        return @{ TestFunctions = $testFunctionIds; TemplateFunctions = $templateFunctionIds }
    }

    $filePath = $ASTData.file_path

    foreach ($func in $ASTData.functions) {
        $structRefId = Get-OrCreateStructId -StructName $func.ReceiverType

        if ($func.IsTestFunc -eq $true) {
            # Test function - calculate test prefix: include underscore if present, otherwise full function name
            $testPrefix = if ($func.FunctionName -match '_') {
                ($func.FunctionName -split '_')[0] + '_'
            } else {
                $func.FunctionName
            }

            $testFuncId = Add-TestFunctionRecord `
                -FileRefId $FileRefId `
                -StructRefId $structRefId `
                -FunctionName $func.FunctionName `
                -Line $func.Line `
                -TestPrefix $testPrefix

            # Store with File:FunctionName key for global lookups (needed for sequential references)
            $globalKey = "$($filePath):$($func.FunctionName)"
            $testFunctionIds[$globalKey] = $testFuncId

            # Also store with just FunctionName for local lookups (backward compatibility)
            $testFunctionIds[$func.FunctionName] = $testFuncId
        }
        else {
            # Template function (determine if returns string by checking if receiver exists)
            $receiverType = if ([string]::IsNullOrWhiteSpace($func.ReceiverVar)) { "value" } else { "pointer" }
            $returnsString = 1  # Assume all template functions return string for now

            $templateFuncId = Add-TemplateFunctionRecord `
                -FileRefId $FileRefId `
                -StructRefId $structRefId `
                -TemplateFunctionName $func.FunctionName `
                -ReceiverType $receiverType `
                -Line $func.Line `
                -ReturnsString $returnsString

            # Store by struct.function key
            if (-not [string]::IsNullOrWhiteSpace($func.ReceiverType)) {
                $key = "$($func.ReceiverType).$($func.FunctionName)"
                $templateFunctionIds[$key] = $templateFuncId
            }

            # ALSO store by File:Function key for direct resource reference lookups
            $globalKey = "$($filePath):$($func.FunctionName)"
            $templateFunctionIds[$globalKey] = $templateFuncId
        }
    }

    return @{ TestFunctions = $testFunctionIds; TemplateFunctions = $templateFunctionIds }
}

function Import-TestStepsFromAST {
    param(
        [object]$ASTData,
        [hashtable]$TestFunctionIds,
        [hashtable]$TemplateFunctionIds
    )

    if (-not $ASTData.test_steps) {
        return
    }

    foreach ($step in $ASTData.test_steps) {
        # Get test function ID
        $testFuncId = $TestFunctionIds[$step.source_function]
        if (-not $testFuncId) {
            continue
        }

        # Get template function ID
        $templateKey = "$($step.config_struct).$($step.config_method)"
        $templateFuncId = $TemplateFunctionIds[$templateKey]
        if (-not $templateFuncId) {
            continue
        }

        # Get or create service and struct IDs
        $targetServiceRefId = Get-OrCreateServiceId -ServiceName $step.config_service
        $targetStructRefId = Get-OrCreateStructId -StructName $step.config_struct

        # Determine reference type
        $referenceTypeName = if ($step.is_local_call -eq $true) { "SAME_SERVICE" } else { "CROSS_SERVICE" }
        $referenceTypeId = Get-ReferenceTypeId -ReferenceTypeName $referenceTypeName

        # Add test step record
        [void](Add-TestStepRecord `
            -TestFunctionRefId $testFuncId `
            -TemplateFunctionRefId $templateFuncId `
            -StepIndex $step.step_index `
            -TargetStructRefId $targetStructRefId `
            -TargetServiceRefId $targetServiceRefId `
            -ReferenceTypeId $referenceTypeId `
            -Line $step.source_line)
    }
}

function Import-TemplateCallsFromAST {
    param(
        [object]$ASTData,
        [hashtable]$TemplateFunctionIds,
        [hashtable]$TemplateNameToKey  # Reverse lookup: FunctionName -> Struct.FunctionName
    )

    if (-not $ASTData.template_calls) {
        return
    }

    foreach ($call in $ASTData.template_calls) {
        # Skip external calls (no target_struct means it's calling stdlib or external code)
        if ([string]::IsNullOrWhiteSpace($call.target_struct)) {
            continue
        }

        # Get target template function ID
        $targetKey = "$($call.target_struct).$($call.target_method)"
        $targetTemplateFuncId = $TemplateFunctionIds[$targetKey]
        if (-not $targetTemplateFuncId) {
            continue
        }

        # Get source template function ID using reverse lookup
        $sourceKey = $TemplateNameToKey[$call.source_function]
        if (-not $sourceKey) {
            continue
        }

        $sourceTemplateFuncId = $TemplateFunctionIds[$sourceKey]
        if (-not $sourceTemplateFuncId) {
            continue
        }

        # Get or create service IDs
        $sourceServiceRefId = Get-OrCreateServiceId -ServiceName $call.source_service
        $targetServiceRefId = Get-OrCreateServiceId -ServiceName $call.target_service

        # Determine reference type
        $referenceTypeName = if ($call.is_local_call -eq $true) { "SAME_SERVICE" } else { "CROSS_SERVICE" }
        $referenceTypeId = Get-ReferenceTypeId -ReferenceTypeName $referenceTypeName

        # Determine if crosses service boundary
        $crossesServiceBoundary = if ($call.source_service -ne $call.target_service) { 1 } else { 0 }

        # Add template call chain record
        [void](Add-TemplateCallChainRecord `
            -SourceTemplateFunctionRefId $sourceTemplateFuncId `
            -TargetTemplateFunctionRefId $targetTemplateFuncId `
            -SourceServiceRefId $sourceServiceRefId `
            -TargetServiceRefId $targetServiceRefId `
            -ChainDepth 1 `
            -CrossesServiceBoundary $crossesServiceBoundary `
            -ReferenceTypeId $referenceTypeId `
            -IsLocalCall ($call.is_local_call -eq $true))
    }
}

function Build-LegacyReferenceTablesFromTestSteps {
    <#
    .SYNOPSIS
    Build TemplateReferences and IndirectConfigReferences tables from TestSteps

    .DESCRIPTION
    The AST schema uses TestSteps with direct FK relationships, but the original
    blast radius analysis expects TemplateReferences and IndirectConfigReferences tables.
    This function generates those legacy tables from the modern TestSteps data.

    IMPORTANT: This function is called multiple times (Phase 2, Phase 2.5), so it only
    processes NEW test steps that haven't been converted yet (prevents duplicates).
    #>

    # Track which steps have been processed (prevents duplicates across multiple Import-ASTOutput calls)
    if ($null -eq $script:LastProcessedTestStepRefId) {
        $script:LastProcessedTestStepRefId = 0
    }

    # Get all test steps
    $allTestSteps = Get-AllTestFunctionSteps

    # Filter to only NEW steps (not yet processed)
    $testSteps = $allTestSteps | Where-Object { $_.TestStepRefId -gt $script:LastProcessedTestStepRefId }

    if ($testSteps.Count -eq 0) {
        # No new steps to process
        return
    }

    # Get test functions and template functions for lookups
    $testFunctions = Get-TestFunctions
    $templateFunctions = Get-TemplateFunctions

    # Build lookup tables
    $testFuncLookup = @{}
    foreach ($tf in $testFunctions) {
        $testFuncLookup[[int]$tf.TestFunctionRefId] = $tf
    }

    $templateFuncLookup = @{}
    foreach ($tmpl in $templateFunctions) {
        $templateFuncLookup[[int]$tmpl.TemplateFunctionRefId] = $tmpl
    }

    foreach ($step in $testSteps) {
        # Get test function and template function
        $testFunc = $testFuncLookup[[int]$step.TestFunctionRefId]
        $templateFunc = $templateFuncLookup[[int]$step.TemplateFunctionRefId]

        if (-not $testFunc -or -not $templateFunc) { continue }

        # Create TemplateReference record (old schema format)
        # TemplateReference format was "r.basic" where r is receiver variable, basic is function name
        $templateVariable = "r"  # AST doesn't track receiver variable in test code, use default
        $templateMethod = $templateFunc.TemplateFunctionName
        $templateReference = "$templateVariable.$templateMethod"

        $templateRefId = Add-TemplateReferenceRecord `
            -TestFunctionRefId $step.TestFunctionRefId `
            -TestFunctionStepRefId $step.TestStepRefId `
            -StructRefId $step.TargetStructRefId `
            -TemplateReference $templateReference `
            -TemplateVariable $templateVariable `
            -TemplateMethod $templateMethod

        # Create IndirectConfigReference record (derived from service comparison)
        # Get test function's service
        $testFuncService = $testFunc.ServiceRefId
        $templateService = $step.TargetServiceRefId

        # Determine service impact type
        $serviceImpactTypeName = if ($testFuncService -eq $templateService) { "SAME_SERVICE" } else { "CROSS_SERVICE" }
        $serviceImpactTypeId = Get-ReferenceTypeId -ReferenceTypeName $serviceImpactTypeName

        # Add indirect reference
        [void](Add-IndirectConfigReferenceRecord `
            -TestFunctionStepRefId $step.TestStepRefId `
            -TemplateReferenceRefId $templateRefId `
            -SourceTemplateFunctionRefId $step.TemplateFunctionRefId `
            -ServiceImpactTypeId $serviceImpactTypeId)

        # Update last processed ID to prevent reprocessing this step
        if ($step.TestStepRefId -gt $script:LastProcessedTestStepRefId) {
            $script:LastProcessedTestStepRefId = $step.TestStepRefId
        }
    }
}

function Import-ASTOutput {
    <#
    .SYNOPSIS
        Main entry point for importing Replicode output
    #>
    param(
        [string]$ASTAnalyzerPath,
        [string[]]$TestFiles,
        [string]$RepoRoot,
        [string]$ResourceName = "",
        [string]$NumberColor = "Yellow",
        [string]$ItemColor = "Cyan",
        [string]$BaseColor = "Gray",
        [string]$InfoColor = "Cyan"
    )

    $totalFiles = $TestFiles.Count
    $processedFiles = 0
    $failedFiles = 0

    Show-PhaseMessageMultiHighlight -Message "Processing $totalFiles Test Files With Replicode..." -Highlights @(
        @{ Text = "$totalFiles"; Color = $NumberColor }
        @{ Text = "Replicode"; Color = $ItemColor }
    ) -BaseColor $BaseColor -InfoColor $InfoColor

    # Process files in parallel for performance
    $progressCounter = 0
    $results = $TestFiles | ForEach-Object -ThrottleLimit $Global:ThreadCount -Parallel {
        $file = $_
        $replicodePath = $using:ASTAnalyzerPath
        $repoRoot = $using:RepoRoot
        $resourceName = $using:ResourceName

        try {
            # Run Replicode with resourcename filter
            $output = & $replicodePath -file $file -reporoot $repoRoot -resourcename $resourceName 2>&1

            if ($LASTEXITCODE -ne 0) {
                return @{ Success = $false; File = $file; Error = "Exit code $LASTEXITCODE" }
            }

            # Parse JSON
            $astData = $output | ConvertFrom-Json

            return @{ Success = $true; File = $file; ASTData = $astData }
        }
        catch {
            return @{ Success = $false; File = $file; Error = $_.Exception.Message }
        }
    } | ForEach-Object {
        # Progress indicator (runs in main thread)
        $progressCounter++
        if ($progressCounter % 50 -eq 0 -or $progressCounter -eq $totalFiles) {
            Show-InlineProgress -Current $progressCounter -Total $totalFiles -Activity "Processing Files"
        }
        $_  # Pass through the result
    }

    # Show final completion
    Show-InlineProgress -Current $totalFiles -Total $totalFiles -Activity "Processing Files" -Completed

    Show-PhaseMessageHighlight -Message "Importing Replicode Data Into Database..." -HighlightText "Replicode" -HighlightColor $ItemColor -BaseColor $BaseColor -InfoColor $InfoColor

    # Two-pass import:
    # Pass 1: Import all functions to build global lookup tables
    # Pass 2: Import test steps and template calls using global lookups

    $globalTestFunctionIds = @{}
    $globalTemplateFunctionIds = @{}
    $templateFunctionNameToKey = @{}  # FunctionName -> Struct.FunctionName
    $fileData = @()  # Array, not hashtable!

    # Progress tracking for Pass 1
    $pass1Counter = 0
    $totalResults = $results.Count

    # Pass 1: Import files and functions
    foreach ($result in $results) {
        $pass1Counter++

        # Show progress every 50 files or at the end
        if ($pass1Counter % 50 -eq 0 -or $pass1Counter -eq $totalResults) {
            Show-InlineProgress -Current $pass1Counter -Total $totalResults -Activity "  Importing Functions"
        }

        if (-not $result.Success) {
            $failedFiles++
            Show-ErrorMessage -ErrorTitle "Replicode Error:" -ErrorMessage "Failed to process $($result.File)`: $($result.Error)"
            continue
        }

        $file = $result.File
        $astData = $result.ASTData
        $processedFiles++

        try {
            # Extract service name from first function (all should have same service)
            $serviceName = if ($astData.functions -and $astData.functions.Count -gt 0) {
                $astData.functions[0].ServiceName
            } else {
                "unknown"
            }

            # Get or create service
            $serviceRefId = Get-OrCreateServiceId -ServiceName $serviceName

            # Add file record
            $fileRefId = Add-FileRecord `
                -FilePath $astData.file_path `
                -ServiceRefId $serviceRefId

            # Import functions (both test and template)
            $functionMaps = Import-FunctionsFromAST -ASTData $astData -FileRefId $fileRefId

            # Merge into global lookups
            foreach ($key in $functionMaps.TestFunctions.Keys) {
                $globalTestFunctionIds[$key] = $functionMaps.TestFunctions[$key]
            }
            foreach ($key in $functionMaps.TemplateFunctions.Keys) {
                $globalTemplateFunctionIds[$key] = $functionMaps.TemplateFunctions[$key]
                # Also build reverse lookup: FunctionName -> Struct.FunctionName
                $parts = $key -split '\.'
                if ($parts.Length -eq 2) {
                    $funcName = $parts[1]
                    $templateFunctionNameToKey[$funcName] = $key
                }
            }

            # Store for Pass 2
            $fileData += @{ ASTData = $astData; File = $file }
        }
        catch {
            $failedFiles++
            Show-ErrorMessage -ErrorTitle "Import Error:" -ErrorMessage "Error importing $file`: $_"
        }
    }

    # Show Pass 1 completion
    Show-InlineProgress -Current $totalResults -Total $totalResults -Activity "  Importing Functions" -Completed

    # Pass 2: Import test steps, template calls, sequential references, and direct resource references using global lookups
    $pass2Counter = 0
    $totalFileData = $fileData.Count

    foreach ($data in $fileData) {
        $pass2Counter++

        # Show progress every 50 files or at the end
        if ($pass2Counter % 50 -eq 0 -or $pass2Counter -eq $totalFileData) {
            Show-InlineProgress -Current $pass2Counter -Total $totalFileData -Activity "  Importing References"
        }

        try {
            # Import test steps
            Import-TestStepsFromAST `
                -ASTData $data.ASTData `
                -TestFunctionIds $globalTestFunctionIds `
                -TemplateFunctionIds $globalTemplateFunctionIds

            # Import template calls
            Import-TemplateCallsFromAST `
                -ASTData $data.ASTData `
                -TemplateFunctionIds $globalTemplateFunctionIds `
                -TemplateNameToKey $templateFunctionNameToKey

            # Import sequential references
            Import-SequentialReferencesFromAST `
                -ASTData $data.ASTData `
                -TestFunctionIds $globalTestFunctionIds

            # Import direct resource references
            Import-DirectResourceReferencesFromAST `
                -ASTData $data.ASTData `
                -TemplateFunctionIds $globalTemplateFunctionIds
        }
        catch {
            Show-ErrorMessage -ErrorTitle "Import Error:" -ErrorMessage "Error importing test steps/calls for $($data.File)`: $_"
        }
    }

    # Show Pass 2 completion
    Show-InlineProgress -Current $totalFileData -Total $totalFileData -Activity "  Importing References" -Completed

    # Pass 3: Generate TemplateReferences and IndirectConfigReferences from TestSteps
    # This populates the legacy tables needed for blast radius analysis
    Build-LegacyReferenceTablesFromTestSteps

    $successCount = $processedFiles - $failedFiles
    Show-PhaseMessageMultiHighlight -Message "Replicode Import Complete: $successCount/$totalFiles Files Processed Successfully" -Highlights @(
        @{ Text = "Replicode"; Color = $ItemColor }
        @{ Text = "$successCount"; Color = $NumberColor }
        @{ Text = "$totalFiles"; Color = $NumberColor }
    ) -BaseColor $BaseColor -InfoColor $InfoColor

    if ($failedFiles -gt 0) {
        Show-PhaseMessage -Message "$failedFiles Files Failed To Process"
    }
}

function Import-SequentialReferencesFromAST {
    <#
    .SYNOPSIS
    Import sequential references from AST JSON output

    .DESCRIPTION
    Processes sequential_references array from AST and populates SequentialReferences table.
    Handles both t.Run() and acceptance.RunTestsInSequence() patterns.

    .PARAMETER ASTData
    The parsed AST JSON object

    .PARAMETER TestFunctionIds
    Hashtable mapping "File:FunctionName" -> TestFunctionRefId
    #>
    param(
        [object]$ASTData,
        [hashtable]$TestFunctionIds
    )

    if (-not $ASTData.sequential_references -or $ASTData.sequential_references.Count -eq 0) {
        return
    }

    foreach ($seqRef in $ASTData.sequential_references) {
        # Build lookup keys for entry point and referenced function
        $entryPointKey = "$($seqRef.entry_point_file)`:$($seqRef.entry_point_function)"
        $referencedKey = "$($seqRef.entry_point_file)`:$($seqRef.referenced_function)"  # Assume same file initially

        # Get entry point function ID
        $entryPointFuncId = $TestFunctionIds[$entryPointKey]
        if (-not $entryPointFuncId) {
            # Entry point not found - skip this reference
            continue
        }

        # Try to find referenced function ID
        # First try same file, then try all files (cross-file sequential references)
        $referencedFuncId = $TestFunctionIds[$referencedKey]
        if (-not $referencedFuncId) {
            # Try to find in all files by function name only
            $funcName = $seqRef.referenced_function
            foreach ($key in $TestFunctionIds.Keys) {
                if ($key -match "`:$([regex]::Escape($funcName))$") {
                    $referencedFuncId = $TestFunctionIds[$key]
                    break
                }
            }
        }

        # If still not found, check if this function exists in the global TestFunctions table
        # (it might have been imported in Phase 2, but we're now in Phase 2.5 discovering sequential refs)
        if (-not $referencedFuncId) {
            $existingFunc = Get-TestFunctionByName -FunctionName $seqRef.referenced_function
            if ($existingFunc -and $existingFunc.FileRefId -ne 0) {
                # Found the actual function - use its RefId instead of creating a stub
                $referencedFuncId = $existingFunc.TestFunctionRefId

                # Add to lookup for future references in this import session
                $lookupKey = "$($existingFunc.FileRefId)`:$($seqRef.referenced_function)"
                $TestFunctionIds[$lookupKey] = $referencedFuncId
            }
        }

        # If still not found after checking global table, create a stub record for truly external reference
        if (-not $referencedFuncId) {
            # Calculate actual test prefix even for external functions
            $testPrefix = if ($seqRef.referenced_function -match '_') {
                ($seqRef.referenced_function -split '_')[0] + '_'
            } else {
                $seqRef.referenced_function
            }

            # Create stub test function record with FileRefId=0 and ReferenceTypeRefId=10 (EXTERNAL_REFERENCE)
            $referencedFuncId = Add-TestFunctionRecord `
                -FileRefId 0 `
                -StructRefId $null `
                -FunctionName $seqRef.referenced_function `
                -TestPrefix $testPrefix `
                -ReferenceTypeRefId 10 `
                -Line 0

            # Add to lookup for future references
            $stubKey = "EXTERNAL`:$($seqRef.referenced_function)"
            $TestFunctionIds[$stubKey] = $referencedFuncId
        }

        # Add sequential reference record
        [void](Add-SequentialReferenceRecord `
            -EntryPointFunctionRefId $entryPointFuncId `
            -ReferencedFunctionRefId $referencedFuncId `
            -SequentialGroup $seqRef.sequential_group `
            -SequentialKey $seqRef.sequential_key)
    }
}

function Import-DirectResourceReferencesFromAST {
    <#
    .SYNOPSIS
    Import direct resource references from AST JSON output

    .DESCRIPTION
    Processes direct_resource_references array from AST and populates DirectResourceReferences table.
    Extracts resource blocks and attribute references from HCL template strings.

    .PARAMETER ASTData
    The parsed AST JSON object

    .PARAMETER TemplateFunctionIds
    Hashtable mapping "File:FunctionName" -> TemplateFunctionRefId
    #>
    param(
        [object]$ASTData,
        [hashtable]$TemplateFunctionIds
    )

    if (-not $ASTData.direct_resource_references -or $ASTData.direct_resource_references.Count -eq 0) {
        return
    }

    foreach ($directRef in $ASTData.direct_resource_references) {
        # Build lookup key for template function
        $templateKey = "$($directRef.template_file)`:$($directRef.template_function)"

        # Get template function ID
        $templateFuncId = $TemplateFunctionIds[$templateKey]
        if (-not $templateFuncId) {
            # Template function not found - skip this reference
            continue
        }

        # Get or create resource ID
        $resourceId = Get-OrCreateResourceId -ResourceName $directRef.resource_name

        # Determine reference type ID
        $referenceTypeId = if ($directRef.reference_type -eq "RESOURCE_BLOCK") { 5 } else { 4 }  # 5=RESOURCE_BLOCK, 4=ATTRIBUTE_REFERENCE

        # Add direct resource reference record
        [void](Add-DirectResourceReferenceRecord `
            -TemplateFunctionRefId $templateFuncId `
            -ResourceRefId $resourceId `
            -ReferenceTypeId $referenceTypeId `
            -Context $directRef.context `
            -TemplateLine $directRef.template_line `
            -ContextLine $directRef.context_line)
    }
}

#endregion

#region Export
Export-ModuleMember -Function @(
    'Import-ASTOutput'
)
#endregion
