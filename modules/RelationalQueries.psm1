# RelationalQueries.psm1
# PROPER RELATIONAL DATABASE QUERIES - NO MORE CONTENT CRAWLING!
# Uses foreign key relationships and JOINs to derive IndirectConfigReferences

function Set-IndirectConfigReferencesRelational {
    <#
    .SYNOPSIS
    Populate IndirectConfigReferences table using proper relational JOINs instead of content crawling

    .DESCRIPTION
    Uses existing foreign key relationships between:
    - TemplateReferences -> TestFunctions -> Files
    - TemplateFunctions -> Files

    Derives CROSS_FILE vs EMBEDDED_SELF based on FileRefId comparisons instead of parsing content!
    #>
    param(
        [Parameter(Mandatory = $false)]
        [array]$TemplateReferences = $null,
        [Parameter(Mandatory = $false)]
        [array]$TestFunctions = $null,
        [Parameter(Mandatory = $false)]
        [array]$TemplateFunctions = $null,
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Green"
    )

    $recordCount = 0

    try {



        # Use passed parameters or get from Database module
        if (-not $TemplateReferences) {
            $TemplateReferences = Get-TemplateReferences
        }
        if (-not $TestFunctions) { $TestFunctions = Get-TestFunctions }
        if (-not $TemplateFunctions) { $TemplateFunctions = Get-TemplateFunctions }

        # Save original TemplateReferences for iteration (before converting to hashtable for lookups)
        $originalTemplateReferences = $TemplateReferences

        # Convert to hashtables if they're arrays (for faster lookups, but we'll iterate over original)
        if ($TemplateReferences -is [array]) {
            $templateRefHash = @{}
            foreach ($ref in $TemplateReferences) { $templateRefHash[$ref.TemplateReferenceRefId] = $ref }
            $TemplateReferences = $templateRefHash
        }

        if ($TestFunctions -is [array]) {
            $testFuncHash = @{}
            foreach ($func in $TestFunctions) {
                # Convert string IDs to integers for proper hashtable lookup
                $testFuncId = [int]$func.TestFunctionRefId
                $testFuncHash[$testFuncId] = $func
            }
            $TestFunctions = $testFuncHash
        }

        # BUILD O(1) LOOKUP INDEX: TemplateFunctionName + StructRefId -> TemplateFunction
        $templateFuncByNameAndStruct = @{}
        if ($TemplateFunctions -is [array]) {
            foreach ($func in $TemplateFunctions) {
                $key = "$($func.TemplateFunctionName)|$($func.StructRefId)"
                if (-not $templateFuncByNameAndStruct.ContainsKey($key)) {
                    $templateFuncByNameAndStruct[$key] = @()
                }
                $templateFuncByNameAndStruct[$key] += $func
            }
        } else {
            foreach ($func in $TemplateFunctions.Values) {
                $key = "$($func.TemplateFunctionName)|$($func.StructRefId)"
                if (-not $templateFuncByNameAndStruct.ContainsKey($key)) {
                    $templateFuncByNameAndStruct[$key] = @()
                }
                $templateFuncByNameAndStruct[$key] += $func
            }
        }

        # Get all template references (test functions calling templates) - use original array, not converted hashtable
        $templateReferenceValues = $originalTemplateReferences

        foreach ($templateRef in $templateReferenceValues) {

            # Extract template function name from template reference
            # e.g., "r.basic" -> "basic", "r.requiresImport" -> "requiresImport"
            $templateName = $templateRef.TemplateReference
            if ($templateName -match '^[a-zA-Z_]+\.(.+)$') {
                $templateFunctionName = $matches[1]
            } else {
                $templateFunctionName = $templateName
            }

            # O(1) LOOKUP instead of O(N) scan!
            $lookupKey = "$templateFunctionName|$($templateRef.StructRefId)"
            $matchingTemplateFunctions = $templateFuncByNameAndStruct[$lookupKey]



            if (-not $matchingTemplateFunctions) { continue }

            foreach ($templateFunc in $matchingTemplateFunctions) {
                # Add indirect config reference record using proper foreign keys
                $indirectRefId = Add-IndirectConfigReferenceRecord -TemplateReferenceRefId $templateRef.TemplateReferenceRefId -SourceTemplateFunctionRefId $templateFunc.TemplateFunctionRefId

                if ($indirectRefId) {
                    $recordCount++

                }
            }
        }

        # Return the count (no need for verbose output messages)
        return $recordCount

    } catch {
        Write-Error " RELATIONAL QUERY FAILED: $($_.Exception.Message)"
        return 0
    }
}

function Get-CrossFileReferencesRelational {
    <#
    .SYNOPSIS
    Get cross-file references using relational JOINs instead of content crawling

    .DESCRIPTION
    Uses foreign key relationships to identify template calls that cross file boundaries:
    - TemplateReferences.TestFunctionRefId -> TestFunctions.FileRefId
    - TemplateFunctions.FileRefId
    - Compare FileRefIds to identify cross-file calls
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    Show-PhaseMessage -Message "RELATIONAL QUERY: Finding Cross-File References Using JOINs..." -BaseColor $BaseColor -InfoColor $InfoColor

    $crossFileRefs = @()

    # SQL-equivalent JOIN query using PowerShell
    # SELECT tr.*, tf_test.FileRefId as TestFileId, tf_template.FileRefId as TemplateFileId
    # FROM TemplateReferences tr
    # JOIN TestFunctions tf_test ON tr.TestFunctionRefId = tf_test.FunctionRefId
    # JOIN TemplateFunctions tf_template ON tr.TemplateReference LIKE '%' + tf_template.TemplateFunctionName
    # WHERE tf_test.FileRefId != tf_template.FileRefId

    foreach ($indirectRef in $script:IndirectConfigReferences.Values) {
        # Get related records using foreign keys
        $templateRef = $script:TemplateReferences[$indirectRef.TemplateReferenceRefId]
        $testFunc = $script:TestFunctions[$templateRef.TestFunctionRefId]
        $templateFunc = $script:TemplateFunctions[$indirectRef.SourceTemplateFunctionRefId]

        # Check if this is a cross-file reference using FileRefId comparison
        if ($testFunc.FileRefId -ne $templateFunc.FileRefId) {
            $testFile = $script:Files[$testFunc.FileRefId]
            $templateFile = $script:Files[$templateFunc.FileRefId]

            $crossFileRefs += [PSCustomObject]@{
                TestFunction = $testFunc.FunctionName
                TestFile = $testFile.FilePath
                TemplateFunction = $templateFunc.TemplateFunctionName
                TemplateFile = $templateFile.FilePath
                TemplateReference = $templateRef.TemplateReference
                ReferenceType = Get-ReferenceTypeName (Get-ReferenceTypeId "CROSS_FILE")
            }
        }
    }

    Show-PhaseMessageHighlight -Message "Found # Cross-File References Using Relational Logic" -HighlightText "$($crossFileRefs.Count)" -HighlightColor "Green" -BaseColor $BaseColor -InfoColor $InfoColor
    return $crossFileRefs
}

function Get-FileReferenceStatistics {
    <#
    .SYNOPSIS
    Generate comprehensive statistics using relational queries instead of content analysis

    .DESCRIPTION
    Uses foreign key relationships to derive statistics:
    - Files with template functions (JOIN TemplateFunctions -> Files)
    - Cross-file vs embedded references (FileRefId comparisons)
    - Template call patterns (TemplateReferences -> TestFunctions JOINs)
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    Show-PhaseMessage -Message "RELATIONAL STATISTICS: Analyzing Using Foreign Key Relationships..." -BaseColor $BaseColor -InfoColor $InfoColor

    # Count records in each table
    $stats = [PSCustomObject]@{
        Services = $script:Services.Count
        Files = $script:Files.Count
        Structs = $script:Structs.Count
        TestFunctions = $script:TestFunctions.Count
        TemplateFunctions = $script:TemplateFunctions.Count
        DirectResourceReferences = $script:DirectResourceReferences.Count
        TemplateReferences = $script:TemplateReferences.Count
        IndirectConfigReferences = $script:IndirectConfigReferences.Count
        SequentialReferences = $script:SequentialReferences.Count
    }

    # Relational statistics using JOINs
    $filesWithTemplates = ($script:TemplateFunctions.Values | Group-Object FileRefId).Count
    $filesWithTests = ($script:TestFunctions.Values | Group-Object FileRefId).Count

    # Cross-file reference analysis using FileRefId comparisons
    $crossFileCount = 0
    $embeddedSelfCount = 0

    foreach ($indirectRef in $script:IndirectConfigReferences.Values) {
        $referenceType = $script:ReferenceTypes[$indirectRef.ReferenceTypeId].ReferenceTypeName
        if ($referenceType -eq "CROSS_FILE") {
            $crossFileCount++
        } elseif ($referenceType -eq "EMBEDDED_SELF") {
            $embeddedSelfCount++
        }
    }

    $stats | Add-Member -NotePropertyName "FilesWithTemplateFunctions" -NotePropertyValue $filesWithTemplates
    $stats | Add-Member -NotePropertyName "FilesWithTestFunctions" -NotePropertyValue $filesWithTests
    $stats | Add-Member -NotePropertyName "CrossFileReferences" -NotePropertyValue $crossFileCount
    $stats | Add-Member -NotePropertyName "EmbeddedSelfReferences" -NotePropertyValue $embeddedSelfCount

    Show-PhaseMessage -Message "Statistics Generated Using Relational Queries (No Content Parsing!)" -BaseColor $BaseColor -InfoColor $InfoColor
    return $stats
}

# Export functions for use in FastPhase5 and other modules
Export-ModuleMember -Function Set-IndirectConfigReferencesRelational, Get-CrossFileReferencesRelational, Get-FileReferenceStatistics
