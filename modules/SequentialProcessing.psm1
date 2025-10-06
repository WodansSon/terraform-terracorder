# SequentialProcessing.psm1
# Sequential reference processing for TerraCorder

function Invoke-SequentialReferencesPopulation {
    <#
    .SYNOPSIS
        Populate SequentialReferences table with sequential test data
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$AllSequentialTests,
        [Parameter(Mandatory = $true)]
        [hashtable]$FunctionDatabase
    )

    $sequentialReferencesAdded = 0
    $externalStubsCreated = 0

    foreach ($seqTest in $AllSequentialTests) {
        $entryPointFunctionRefId = $FunctionDatabase[$seqTest.MainFunction]

        if ($entryPointFunctionRefId) {
            # Get the entry point function details to use as template for stubs
            $entryPointFunction = Get-TestFunctionById -TestFunctionRefId $entryPointFunctionRefId

            # Find at least one existing function in this sequential test to use as template
            $templateFunction = $null
            foreach ($mapping in $seqTest.SequentialMappings) {
                if ($FunctionDatabase[$mapping.Function]) {
                    $templateFunction = Get-TestFunctionById -TestFunctionRefId $FunctionDatabase[$mapping.Function]
                    break
                }
            }

            foreach ($mapping in $seqTest.SequentialMappings) {
                $referencedFunctionRefId = $FunctionDatabase[$mapping.Function]

                # If function doesn't exist, create external stub
                if (-not $referencedFunctionRefId) {
                    # Use template function to copy relational chain, fallback to entry point
                    $template = if ($templateFunction) { $templateFunction } else { $entryPointFunction }

                    # Extract test prefix from function name (everything before last underscore + underscore)
                    $functionName = $mapping.Function
                    $testPrefix = if ($functionName -match '^(.+)_[^_]+$') { $matches[1] + '_' } else { 'External_' }

                    # Create stub TestFunction record with same relational chain as template
                    $stubFunctionRefId = Add-TestFunctionRecord `
                        -FileRefId $template.FileRefId `
                        -StructRefId $template.StructRefId `
                        -FunctionName $functionName `
                        -TestPrefix $testPrefix `
                        -Line 0 `
                        -SequentialEntryPointRefId $entryPointFunctionRefId `
                        -FunctionBody "EXTERNAL_REFERENCE"

                    # Add to function database for future lookups
                    $FunctionDatabase[$functionName] = $stubFunctionRefId
                    $referencedFunctionRefId = $stubFunctionRefId
                    $externalStubsCreated++

                    # Create TestFunctionSteps record marking it as EXTERNAL_REFERENCE
                    Add-TestFunctionStepRecord `
                        -TestFunctionRefId $stubFunctionRefId `
                        -StepIndex 1 `
                        -StepBody "EXTERNAL_REFERENCE" `
                        -ConfigTemplate $null `
                        -StructRefId $null `
                        -ReferenceTypeId 10 `
                        -StructVisibilityTypeId 10 | Out-Null
                }

                if ($referencedFunctionRefId) {
                    Add-SequentialReferenceRecord -EntryPointFunctionRefId $entryPointFunctionRefId -ReferencedFunctionRefId $referencedFunctionRefId -SequentialGroup $mapping.Group -SequentialKey $mapping.Key | Out-Null
                    $sequentialReferencesAdded++

                    # Update the referenced function to link it to the entry point
                    Update-TestFunctionSequentialInfo -TestFunctionRefId $referencedFunctionRefId -SequentialEntryPointRefId $entryPointFunctionRefId
                }
            }
        }
    }

    return @{
        SequentialReferencesAdded = $sequentialReferencesAdded
        ExternalStubsCreated = $externalStubsCreated
    }
}

function Get-RelevantSequentialTests {
    <#
    .SYNOPSIS
        Filter sequential tests to only those that reference resource functions
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$AllSequentialTests,
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [array]$ResourceFunctions = @()
    )

    return $AllSequentialTests | Where-Object {
        $seqTest = $_
        ($seqTest.ReferencedFunctions | Where-Object { $ResourceFunctions -contains $_ }).Count -gt 0
    }
}

function Get-ServiceTestResults {
    <#
    .SYNOPSIS
        Group test results by service and create test command data
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$AllTestResults,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$AllSequentialTests,
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [array]$ResourceFunctions = @()
    )

    # Include services that have files with DIRECT references to the resource
    $resourceFiles = $AllTestResults | Where-Object { $_.HasResource }
    $relevantServices = $resourceFiles | Select-Object -ExpandProperty Service -Unique

    # ALSO include services that have INDIRECT references (via templates)
    # Get all test functions that have indirect references
    $allIndirectRefs = Get-IndirectConfigReferences
    if ($allIndirectRefs -and $allIndirectRefs.Count -gt 0) {
        $templateRefs = Get-TemplateReferences
        $testFunctions = Get-TestFunctions
        $files = Get-Files
        $services = Get-Services

        # Build lookup tables for performance
        $templateRefLookup = @{}
        foreach ($tr in $templateRefs) {
            $templateRefLookup[$tr.TemplateReferenceRefId] = $tr
        }

        $testFuncLookup = @{}
        foreach ($tf in $testFunctions) {
            $testFuncLookup[$tf.TestFunctionRefId] = $tf
        }

        $fileLookup = @{}
        foreach ($f in $files) {
            $fileLookup[$f.FileRefId] = $f
        }

        $serviceLookup = @{}
        foreach ($s in $services) {
            $serviceLookup[$s.ServiceRefId] = $s
        }

        # Trace: IndirectConfigReference -> TemplateReference -> TestFunction -> File -> Service
        foreach ($indirectRef in $allIndirectRefs) {
            $templateRef = $templateRefLookup[$indirectRef.TemplateReferenceRefId]
            if ($templateRef) {
                $testFunc = $testFuncLookup[$templateRef.TestFunctionRefId]
                if ($testFunc) {
                    $file = $fileLookup[$testFunc.FileRefId]
                    if ($file) {
                        $service = $serviceLookup[$file.ServiceRefId]
                        if ($service -and $relevantServices -notcontains $service.Name) {
                            $relevantServices += $service.Name
                        }
                    }
                }
            }
        }
    }

    # Also include services that have sequential tests referencing our resource functions
    foreach ($seqTest in $AllSequentialTests) {
        $hasResourceFunction = $false
        foreach ($refFunc in $seqTest.ReferencedFunctions) {
            if ($ResourceFunctions -contains $refFunc) {
                $hasResourceFunction = $true
                break
            }
        }
        if ($hasResourceFunction -and $relevantServices -notcontains $seqTest.Service) {
            $relevantServices += $seqTest.Service
        }
    }

    # Filter results to only relevant services
    $relevantResults = $AllTestResults | Where-Object { $relevantServices -contains $_.Service }
    $serviceGroups = $relevantResults | Group-Object Service

    return @{
        RelevantServices = $relevantServices
        ServiceGroups = $serviceGroups
        RelevantResults = $relevantResults
    }
}

Export-ModuleMember -Function Invoke-SequentialReferencesPopulation, Get-RelevantSequentialTests, Get-ServiceTestResults
