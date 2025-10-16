# DatabaseMode.psm1
# Query and visualization functions for Database-Only Mode
# These functions provide deep analysis without re-running discovery phases

# ============================================================================
# MODULE CONSTANTS
# ============================================================================
$script:ARROW_CHAR = [char]0x2192  # Unicode Right Arrow Character

# ============================================================================
# MODULE STATE: Cache for loaded data tables
# ============================================================================
$script:DatabaseDirectory = $null  # Store database directory for context
$script:CompiledRegex = @{
    # Matches: resource "azurerm_..." or data "azurerm_..."
    # Groups: 1=keyword(resource|data), 2=resource_type, 3=rest_of_line
    ResourceOrData = [regex]::new('^(resource|data)\s+"([^"]+)"(.*)$', [System.Text.RegularExpressions.RegexOptions]::Compiled)

    # Matches: azurerm_resource_name anywhere in text
    # Groups: 1=before, 2=resource_name(azurerm_*), 3=after
    AzureResourceName = [regex]::new('(.*?)(azurerm_[a-z0-9_]+)(.*)', [System.Text.RegularExpressions.RegexOptions]::Compiled)

    # Matches: internal/services/servicename/...
    # Groups: 1=service_name
    ServicePath = [regex]::new('internal/services/([^/]+)/', [System.Text.RegularExpressions.RegexOptions]::Compiled)

    # Matches: one or more whitespace characters (for normalization)
    Whitespace = [regex]::new('\s+', [System.Text.RegularExpressions.RegexOptions]::Compiled)
}

# ============================================================================
# VISUALIZATION FUNCTIONS
# ============================================================================

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

    # Separate references by type for summary
    $resourceRefs = $directRefs | Where-Object { $_.ReferenceTypeId -eq 5 }  # RESOURCE_BLOCK
    $attributeRefs = $directRefs | Where-Object { $_.ReferenceTypeId -eq 4 }  # ATTRIBUTE_REFERENCE

    # Display summary
    Write-Host "  Total References: " -ForegroundColor $InfoColor -NoNewline
    Write-Host "$($directRefs.Count) " -ForegroundColor $NumberColor -NoNewline
    Write-Host "direct resource references found" -ForegroundColor $InfoColor
    Write-Host ""

    if ($resourceRefs.Count -gt 0) {
        Write-Host "  Resource Block References: " -ForegroundColor $InfoColor -NoNewline
        Write-Host "$($resourceRefs.Count) " -ForegroundColor $NumberColor -NoNewline
        Write-Host "resource block declarations" -ForegroundColor $InfoColor
    }

    if ($attributeRefs.Count -gt 0) {
        Write-Host "  Attribute References: " -ForegroundColor $InfoColor -NoNewline
        Write-Host "$($attributeRefs.Count) " -ForegroundColor $NumberColor -NoNewline
        Write-Host "attribute usages in test configurations" -ForegroundColor $InfoColor
    }

    Write-Host ""
    Write-Separator
    Write-Host ""

    # Get template functions and create lookup hashtable for O(1) access
    $templateFunctions = Get-TemplateFunctions
    $templateFuncLookup = @{}
    foreach ($tf in $templateFunctions) {
        # Use integer key for fast lookup
        $templateFuncLookup[[int]$tf.TemplateFunctionRefId] = $tf
    }

    # Get files and create lookup hashtable for O(1) access
    $files = Get-Files
    $fileLookup = @{}
    foreach ($f in $files) {
        # Use integer key for fast lookup
        $fileLookup[[int]$f.FileRefId] = $f.FilePath
    }

    # Add calculated line numbers and file paths to references
    $enrichedRefs = $directRefs | ForEach-Object {
        $currentRef = $_

        # Convert to int for hashtable lookup
        $tfId = [int]$currentRef.TemplateFunctionRefId        # Safe hashtable lookup with null checks
        if ($templateFuncLookup.ContainsKey($tfId)) {
            $templateFunc = $templateFuncLookup[$tfId]
            $fileId = [int]$templateFunc.FileRefId

            if ($fileLookup.ContainsKey($fileId)) {
                $filePath = $fileLookup[$fileId]
                $actualLine = [int]$currentRef.TemplateLine + [int]$currentRef.ContextLine

                [PSCustomObject]@{
                    DirectRefId = $currentRef.DirectRefId
                    TemplateFunctionRefId = $currentRef.TemplateFunctionRefId
                    ResourceRefId = $currentRef.ResourceRefId
                    ReferenceTypeId = $currentRef.ReferenceTypeId
                    Context = $currentRef.Context
                    TemplateLine = $currentRef.TemplateLine
                    ContextLine = $currentRef.ContextLine
                    ActualLine = $actualLine
                    FilePath = $filePath
                    TemplateFunction = $templateFunc.FunctionName
                }
            }
        }
    } | Where-Object { $_ -ne $null }

    # Group by file first, then display references within each file
    $groupedByFile = $enrichedRefs | Group-Object -Property FilePath | Sort-Object Name
    $totalFiles = $groupedByFile.Count

    $currentFileIndex = 0
    foreach ($fileGroup in $groupedByFile) {
        $currentFileIndex++
        $filePath = $fileGroup.Name
        $fileRefCount = $fileGroup.Count

        # Separate references by type within this file
        $resourceRefs = $fileGroup.Group | Where-Object { $_.ReferenceTypeId -eq 5 }  # RESOURCE_BLOCK
        $attributeRefs = $fileGroup.Group | Where-Object { $_.ReferenceTypeId -eq 4 }  # ATTRIBUTE_REFERENCE

        Write-Host " File: " -ForegroundColor $InfoColor -NoNewline
        Write-Host "./$filePath" -ForegroundColor $BaseColor
        Write-Host "   " -NoNewline
        Write-Host "$fileRefCount " -ForegroundColor $NumberColor -NoNewline
        Write-Host "Total References" -ForegroundColor $InfoColor -NoNewline

        if ($resourceRefs.Count -gt 0) {
            Write-Host ", " -ForegroundColor $BaseColor -NoNewline
            Write-Host "$($resourceRefs.Count) " -ForegroundColor $NumberColor -NoNewline
            Write-Host "Resource Blocks" -ForegroundColor $InfoColor -NoNewline
        }
        if ($attributeRefs.Count -gt 0) {
            Write-Host ", " -ForegroundColor $BaseColor -NoNewline
            Write-Host "$($attributeRefs.Count) " -ForegroundColor $NumberColor -NoNewline
            Write-Host "Attributes" -ForegroundColor $InfoColor -NoNewline
        }
        Write-Host ""
        Write-Host ""

        # Calculate column widths for alignment
        $maxLineNumWidth = ($fileGroup.Group | ForEach-Object { $_.ActualLine.ToString().Length } | Measure-Object -Maximum).Maximum
        $maxContextWidth = 100

        # Get syntax colors for highlighting
        $colors = Get-VSCodeSyntaxColors

        # Display Resource Block References
        if ($resourceRefs.Count -gt 0) {
            Write-Separator -Indent 4
            Write-Host "      Resource Block References:" -ForegroundColor $InfoColor
            Write-Separator -Indent 4

            foreach ($ref in $resourceRefs | Sort-Object ActualLine) {
                $lineNumStr = $ref.ActualLine.ToString().PadLeft($maxLineNumWidth)

                Write-Host "      " -NoNewline
                $context = $ref.Context.Trim()
                # Normalize whitespace: collapse multiple spaces to single space
                $context = $script:CompiledRegex.Whitespace.Replace($context, ' ')
                if ($context.Length -gt $maxContextWidth) {
                    $context = $context.Substring(0, $maxContextWidth - 3) + "..."
                }

                # Syntax highlighting: Highlight resource type with background color (VS Code find style)
                $match = $script:CompiledRegex.ResourceOrData.Match($context)
                if ($match.Success) {
                    Write-HostRGB "${lineNumStr}" $colors.LineNumber -NoNewline
                    Write-HostRGB ": " $colors.Label -NoNewline
                    Write-HostRGB "$($match.Groups[1].Value) " $colors.String -NoNewline          # Keyword
                    Write-HostRGB '"' $colors.String -NoNewline                                   # Opening quote
                    Write-HostRGB "$($match.Groups[2].Value)" $colors.String -BackgroundColor $colors.FindBackground -NoNewline  # Resource type with highlight background
                    Write-HostRGB '"' $colors.String -NoNewline                                   # Closing quote
                    Write-HostRGB "$($match.Groups[3].Value)" $colors.String                      # Rest
                } else {
                    Write-HostRGB "${lineNumStr}" $colors.LineNumber -NoNewline
                    Write-HostRGB ": " $colors.Label -NoNewline
                    Write-Host "$context" -ForegroundColor $BaseColor
                }
            }

            Write-Host ""
        }

        # Display Attribute References
        if ($attributeRefs.Count -gt 0) {
            Write-Separator -Indent 4
            Write-Host "      Attribute References:" -ForegroundColor $InfoColor
            Write-Separator -Indent 4

            foreach ($ref in $attributeRefs | Sort-Object ActualLine) {
                $lineNumStr = $ref.ActualLine.ToString().PadLeft($maxLineNumWidth)

                Write-Host "      " -NoNewline
                Write-HostRGB "${lineNumStr}" $colors.LineNumber -NoNewline
                Write-HostRGB ": " $colors.Label -NoNewline

                $context = $ref.Context.Trim()
                # Normalize whitespace: collapse multiple spaces to single space
                $context = $script:CompiledRegex.Whitespace.Replace($context, ' ')
                if ($context.Length -gt $maxContextWidth) {
                    $context = $context.Substring(0, $maxContextWidth - 3) + "..."
                }

                # Syntax highlighting: Highlight resource type with background color (VS Code find style)
                # Just look for azurerm_* anywhere in the line
                $colors = Get-VSCodeSyntaxColors
                $match = $script:CompiledRegex.AzureResourceName.Match($context)
                if ($match.Success) {
                    # Write parts only if they're not empty
                    if ($match.Groups[1].Value) {
                        Write-HostRGB $match.Groups[1].Value $colors.String -NoNewline       # Everything before resource name - Salmon
                    }
                    Write-HostRGB $match.Groups[2].Value $colors.String -BackgroundColor $colors.FindBackground -NoNewline  # Resource name with highlight background
                    if ($match.Groups[3].Value) {
                        Write-HostRGB $match.Groups[3].Value $colors.String                  # Everything after resource name - Salmon
                    } else {
                        Write-Host ""  # End the line if there's nothing after
                    }
                } else {
                    Write-Host "$context" -ForegroundColor $BaseColor
                }
            }

            # Only add blank line if not the last file
            if ($currentFileIndex -lt $totalFiles) {
                Write-Host ""
            }
        }
    }
}

function Show-TemplateFunctionDependencies {
    <#
    .SYNOPSIS
    Display test configuration function dependencies (template references)

    .PARAMETER TemplateRefs
    Array of template reference info objects

    .PARAMETER Colors
    VS Code syntax color scheme object

    .PARAMETER NumberColor
    Color for numbers in output

    .PARAMETER ItemColor
    Color for item types in output
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$TemplateRefs,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Colors = $null,

        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan"
    )

    if ($TemplateRefs.Count -eq 0) {
        return
    }

    Write-Host ""
    Write-Separator -Indent 3
    Write-Host "     Test Configuration Function Dependencies:" -ForegroundColor $ItemColor
    Write-Separator -Indent 3

    # Get VS Code color scheme for function highlighting (use provided or get new)
    if (-not $Colors) {
        $colors = Get-VSCodeSyntaxColors
    } else {
        $colors = $Colors
    }

    # Group by test function to consolidate steps
    $functionGroups = @{}
    foreach ($refInfo in $TemplateRefs) {
        $funcId = $refInfo.TestFunc.TestFunctionRefId
        if (-not $functionGroups.ContainsKey($funcId)) {
            $functionGroups[$funcId] = @{
                TestFunc = $refInfo.TestFunc
                Steps = @()
                StepKeys = @{}  # Track unique steps to prevent duplicates
                ServiceImpactTypeName = $refInfo.ServiceImpactTypeName
                ResourceOwningServiceName = $refInfo.ResourceOwningServiceName
                SourceTemplateFunction = $refInfo.SourceTemplateFunction
            }
        }

        # Deduplicate steps - same TestFunctionStep + TemplateRef + Struct = duplicate IndirectConfigReference
        $stepKey = "$($refInfo.TestFuncStep.TestFunctionStepRefId)-$($refInfo.TemplateRef.TemplateReferenceRefId)"
        if ($refInfo.SourceTemplateFunction) {
            $stepKey += "-$($refInfo.SourceTemplateFunction.StructRefId)"
        }

        if (-not $functionGroups[$funcId].StepKeys.ContainsKey($stepKey)) {
            $functionGroups[$funcId].StepKeys[$stepKey] = $true
            $functionGroups[$funcId].Steps += $refInfo
        }
    }

    # Sort by test function line number
    $sortedFunctions = $functionGroups.Values | Sort-Object { $_.TestFunc.Line }
    $currentFunctionIndex = 0

    foreach ($funcGroup in $sortedFunctions) {
        $currentFunctionIndex++

        # Add blank line between functions (not before first)
        if ($currentFunctionIndex -gt 1) {
            Write-Host ""
        }

        # Function name
        Write-HostRGB "     Function: " $colors.Highlight -NoNewline
        Write-HostRGB "$($funcGroup.TestFunc.Line)" $colors.LineNumber -NoNewline
        Write-HostRGB ": " $colors.Highlight -NoNewline
        Write-HostRGB "$($funcGroup.TestFunc.FunctionName)" $colors.FunctionHighlight

        # Display steps (sorted by step index)
        $sortedSteps = $funcGroup.Steps | Sort-Object { $_.TestFuncStep.StepIndex }
        # Calculate max step index width for alignment
        $maxStepWidth = ($sortedSteps | ForEach-Object { $_.TestFuncStep.StepIndex.ToString().Length } | Measure-Object -Maximum).Maximum
        foreach ($stepInfo in $sortedSteps) {
            $stepNumStr = $stepInfo.TestFuncStep.StepIndex.ToString().PadLeft($maxStepWidth)
            Write-HostRGB "               Step " $colors.Highlight -NoNewline
            Write-HostRGB "$stepNumStr" $colors.Number -NoNewline
            Write-HostRGB ": " $colors.Highlight -NoNewline
            Write-HostRGB "Config" $colors.Highlight -NoNewline
            Write-HostRGB ": " $colors.Label -NoNewline
            Write-HostRGB "$($stepInfo.TemplateRef.TemplateVariable)" $colors.Highlight -NoNewline
            Write-HostRGB "." $colors.Label -NoNewline
            Write-HostRGB "$($stepInfo.TemplateRef.TemplateMethod)" $colors.FunctionHighlight -NoNewline

            # Show reference type details with proper formatting
            if ($stepInfo.RefTypeName) {
                # Parse the RefTypeName (e.g., "CROSS_FILE;SAME_SERVICE" or "SELF_CONTAINED")
                $refTypes = $stepInfo.RefTypeName -split ';'
                $fileRefType = $refTypes[0]
                $serviceRefType = if ($refTypes.Count -gt 1) { $refTypes[1] } else { $null }

                # Get reference type names from database for comparison
                $REF_NAME_CROSS_FILE = Get-ReferenceTypeName -ReferenceTypeId $REF_ID_CROSS_FILE
                $REF_NAME_EXTERNAL_REFERENCE = Get-ReferenceTypeName -ReferenceTypeId $REF_ID_EXTERNAL_REFERENCE
                $REF_NAME_SELF_CONTAINED = Get-ReferenceTypeName -ReferenceTypeId $REF_ID_SELF_CONTAINED
                $REF_NAME_EMBEDDED_SELF = Get-ReferenceTypeName -ReferenceTypeId $REF_ID_EMBEDDED_SELF
                $REF_NAME_CROSS_SERVICE = Get-ReferenceTypeName -ReferenceTypeId $REF_ID_CROSS_SERVICE

                # For CROSS_FILE, show the call chain with arrow
                # If same struct: r.method1 -> r.method2: CROSS_FILE
                # If different struct: r.method1 -> OtherStruct{}.method2: CROSS_FILE
                # For EXTERNAL_REFERENCE, show: r.method -> EXTERNAL_REFERENCE
                # For SELF_CONTAINED, just show type since receiver IS the template: r.basic: SELF_CONTAINED
                if ($fileRefType -eq $REF_NAME_CROSS_FILE -and $stepInfo.TargetTemplateInfo) {
                    # Target info was pre-joined from database
                    $targetStruct = $stepInfo.TargetTemplateInfo.Struct
                    $targetFunc = $stepInfo.TargetTemplateInfo.TemplateFunction

                    # Check if source and target are from the same struct
                    $sameStruct = $false
                    if ($stepInfo.SourceTemplateFunction -and $stepInfo.SourceTemplateFunction.StructRefId -eq $targetStruct.StructRefId) {
                        $sameStruct = $true
                    }

                    Write-Host " " -NoNewline
                    Write-HostRGB "->" $colors.Label -NoNewline
                    Write-Host " " -NoNewline

                    if ($sameStruct) {
                        # Same struct: use the receiver variable (e.g., r.template)
                        Write-HostRGB "$($stepInfo.TemplateRef.TemplateVariable)" $colors.Highlight -NoNewline
                        Write-HostRGB "." $colors.Label -NoNewline
                        Write-HostRGB "$($targetFunc.TemplateFunctionName)" $colors.FunctionHighlight -NoNewline
                    } else {
                        # Different struct: show full notation (e.g., OtherStruct{}.method)
                        Write-HostRGB "$($targetStruct.StructName)" $colors.Type -NoNewline
                        Write-HostRGB "{}" $colors.BracketLevel1 -NoNewline
                        Write-HostRGB "." $colors.Label -NoNewline
                        Write-HostRGB "$($targetFunc.TemplateFunctionName)" $colors.FunctionHighlight -NoNewline
                    }

                    # Show service boundary if cross-service (before the reference type)
                    # Show WHERE the cross-service boundary is crossed: template's service -> resource's service
                    if ($serviceRefType -eq $REF_NAME_CROSS_SERVICE) {
                        Write-Host " " -NoNewline
                        Write-HostRGB "(" $colors.Label -NoNewline

                        # Get the template's service (from the target template function's file)
                        $templateServiceName = $null
                        if ($stepInfo.TargetTemplateInfo -and $stepInfo.TargetTemplateInfo.TemplateFunction -and $stepInfo.TargetTemplateInfo.TemplateFunction.FileRefId) {
                            $templateFileRefId = [int]$stepInfo.TargetTemplateInfo.TemplateFunction.FileRefId
                            $templateFile = Get-FileRecordByRefId -FileRefId $templateFileRefId
                            if ($templateFile -and $templateFile.ServiceRefId) {
                                $templateServiceId = [int]$templateFile.ServiceRefId
                                $allServices = Get-Services
                                $templateService = $allServices | Where-Object { $_.ServiceRefId -eq $templateServiceId } | Select-Object -First 1
                                if ($templateService) {
                                    $templateServiceName = $templateService.Name
                                }
                            }
                        }

                        if ($templateServiceName) {
                            Write-HostRGB "$templateServiceName" $colors.Type -NoNewline
                            Write-Host " " -NoNewline
                            Write-HostRGB "->" $colors.Label -NoNewline
                            Write-Host " " -NoNewline
                        }
                        if ($stepInfo.ResourceOwningServiceName) {
                            Write-HostRGB "$($stepInfo.ResourceOwningServiceName)" $colors.Type -NoNewline
                        }
                        Write-HostRGB ")" $colors.Label -NoNewline
                    }

                    Write-HostRGB ":" $colors.Label -NoNewline
                    Write-Host " " -NoNewline
                    Write-HostRGB "$fileRefType" $colors.Function -NoNewline

                    # Show service impact type if cross-service (append with semicolon)
                    if ($serviceRefType -eq $REF_NAME_CROSS_SERVICE) {
                        Write-HostRGB ";" $colors.Label -NoNewline
                        Write-Host " " -NoNewline
                        Write-HostRGB "$serviceRefType" $colors.ControlFlow -NoNewline
                    }
                }
                # For EXTERNAL_REFERENCE, show that it calls something unknown/external
                # We don't know if the external call itself crosses services (we don't have that code)
                # But we still want to show if the test→resource relationship is cross-service
                elseif ($fileRefType -eq $REF_NAME_EXTERNAL_REFERENCE) {
                    Write-Host " " -NoNewline
                    Write-HostRGB "->" $colors.Label -NoNewline
                    Write-Host " " -NoNewline
                    Write-HostRGB "$fileRefType" $colors.RegexClass -NoNewline

                    # Show service impact type if cross-service (test service != resource service)
                    # This indicates the test impacts a resource in a different service, not that the external call crosses services
                    if ($serviceRefType -eq $REF_NAME_CROSS_SERVICE) {
                        Write-HostRGB ";" $colors.Label -NoNewline
                        Write-Host " " -NoNewline
                        Write-HostRGB "$serviceRefType" $colors.ControlFlow -NoNewline
                    }
                }
                # For SELF_CONTAINED/EMBEDDED_SELF, just show the type (receiver IS the template)
                else {
                    Write-Host " " -NoNewline
                    Write-HostRGB ":" $colors.Label -NoNewline
                    Write-Host " " -NoNewline

                    $fileRefColor = switch ($fileRefType) {
                        $REF_NAME_CROSS_FILE { $colors.Function }
                        $REF_NAME_EXTERNAL_REFERENCE { $colors.RegexClass }
                        $REF_NAME_SELF_CONTAINED { $colors.Comment }
                        $REF_NAME_EMBEDDED_SELF { $colors.Type }
                        default { $colors.Label }
                    }
                    Write-HostRGB "$fileRefType" $fileRefColor -NoNewline
                }
            }

            Write-Host ""  # End the line
        }
    }
}

function Show-SequentialCallChain {
    <#
    .SYNOPSIS
    Display sequential call chain (sequential references)

    .PARAMETER SequentialRefs
    Array of sequential reference info objects

    .PARAMETER Colors
    VS Code syntax color scheme object

    .PARAMETER ItemColor
    Color for item types in output
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$SequentialRefs,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Colors = $null,

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan"
    )

    if ($SequentialRefs.Count -eq 0) {
        return
    }

    Write-Host ""
    Write-Separator -Indent 3
    Write-Host "     Sequential Call Chain:" -ForegroundColor $ItemColor
    Write-Separator -Indent 3
    Write-Host ""

    # Get VS Code color scheme (use provided or get new)
    if (-not $Colors) {
        $colors = Get-VSCodeSyntaxColors
    } else {
        $colors = $Colors
    }

    # Define Unicode box-drawing characters
    $vPipe = [char]0x2502     # vertical line
    $rTee = [char]0x251C      # T-junction right (branch continues)
    $corner = [char]0x2514    # corner (last branch)
    $hPipe = [char]0x2500     # horizontal line
    $dTee = [char]0x252C      # T-junction down (children below)
    $rArrow = [char]0x25BA    # right-pointing arrow

    $treeColor = $colors.LineNumberMuted
    $elementColor = $colors.Type

    # Group by sequential entry point (these are the functions that call t.Run)
    $entryPointGroups = @{}
    foreach ($refInfo in $SequentialRefs) {
        $entryPoint = $refInfo.SequentialEntryPoint
        $epKey = "$($entryPoint.Line):$($entryPoint.FunctionName)"

        if (-not $entryPointGroups.ContainsKey($epKey)) {
            $entryPointGroups[$epKey] = @{
                EntryPoint = $entryPoint
                SequentialGroups = @{}
            }
        }

        # Group by sequential group within the entry point
        # Ensure groupName is a string to prevent hashtable key issues
        $seqGroup = $refInfo.SequentialGroup

        # Handle case where SequentialGroup might be an object or hashtable
        if ($seqGroup -is [hashtable] -or $seqGroup -is [System.Collections.IDictionary]) {
            # If it's a hashtable, try to get a meaningful string representation
            # This shouldn't happen, but handle it gracefully
            $seqGroupKey = "Unknown"
        } elseif ($null -eq $seqGroup -or [string]::IsNullOrWhiteSpace($seqGroup)) {
            $seqGroupKey = "(empty)"
        } else {
            $seqGroupKey = [string]$seqGroup
        }

        if (-not $entryPointGroups[$epKey].SequentialGroups.ContainsKey($seqGroupKey)) {
            $entryPointGroups[$epKey].SequentialGroups[$seqGroupKey] = @()
        }

        $entryPointGroups[$epKey].SequentialGroups[$seqGroupKey] += $refInfo
    }

    # Sort entry points by line number
    $sortedEntryPoints = $entryPointGroups.Values | Sort-Object { $_.EntryPoint.Line }
    $currentEntryPointIndex = 0

    foreach ($epGroup in $sortedEntryPoints) {
        $currentEntryPointIndex++

        # Add blank line between entry points (not before first)
        if ($currentEntryPointIndex -gt 1) {
            Write-Host ""
        }

        $entryPoint = $epGroup.EntryPoint

        # Display entry point
        Write-HostRGB "      Entry Point" $elementColor -NoNewline
        Write-HostRGB ": " $colors.Label -NoNewline
        Write-HostRGB "$($entryPoint.Line)" $colors.LineNumber -NoNewline
        Write-HostRGB ": " $colors.Label -NoNewline
        Write-HostRGB "$($entryPoint.FunctionName)" $colors.Highlight

        # Display entry point pipe
        Write-HostRGB "       $vPipe" $treeColor

        # Display each sequential group
        # Use GetEnumerator() to avoid conflicts with reserved property names like "keys"
        $groupNames = @($epGroup.SequentialGroups.GetEnumerator() | ForEach-Object { [string]$_.Key } | Sort-Object)
        $totalGroups = $groupNames.Count
        $currentGroupIndex = 0

        foreach ($groupName in $groupNames) {
            $currentGroupIndex++
            $isLastGroup = ($currentGroupIndex -eq $totalGroups)

            # Group level - Keys align with the T-down character position
            $groupPrefix = if ($isLastGroup) { "          " } else { "       $vPipe  " }

            $rawSteps = $epGroup.SequentialGroups[$groupName]

            # Group by SequentialKey to count unique keys (not total references)
            $uniqueKeys = $rawSteps | Group-Object -Property SequentialKey
            $steps = @($uniqueKeys | Sort-Object Name)

            # Display each step in the group
            $stepCount = $steps.Count

            # Determine group branch based on position - always show T-down since groups have keys as children
            $groupBranch = if ($isLastGroup) { "$corner$hPipe$hPipe$dTee" } else { "$rTee$hPipe$hPipe$dTee" }

            Write-HostRGB "       $groupBranch$hPipe$hPipe$hPipe$rArrow" $treeColor -NoNewline
            Write-HostRGB " Group   " $elementColor -NoNewline
            Write-HostRGB ": " $colors.Label -NoNewline
            Write-HostRGB "`"$groupName`"" $colors.String

            $currentStep = 0
            foreach ($keyGroup in $steps) {
                $currentStep++
                $isLastStep = ($currentStep -eq $stepCount)

                # When there's only one key, use corner; otherwise use tee/corner based on position
                if ($stepCount -eq 1) {
                    $stepBranch = "$corner$hPipe$dTee$hPipe"
                } else {
                    $stepBranch = if ($isLastStep) { "$corner$hPipe$dTee$hPipe" } else { "$rTee$hPipe$dTee$hPipe" }
                }

                # Key level - builds on group prefix
                $keyPrefix = if ($isLastStep) { "$groupPrefix " } else { "$groupPrefix$vPipe" }

                # Get the first step from this key group (they all have the same key)
                $step = $keyGroup.Group | Select-Object -First 1

                # Key header with T-junction down for children
                Write-HostRGB "$groupPrefix$stepBranch$rArrow " $treeColor -NoNewline
                Write-HostRGB "Key     " $elementColor -NoNewline
                Write-HostRGB ": " $colors.Label -NoNewline
                if ([string]::IsNullOrEmpty($step.SequentialKey)) {
                    Write-Host "(empty)" -ForegroundColor DarkGray
                } else {
                    Write-HostRGB "`"$($step.SequentialKey)`"" $colors.String
                }

                # Configuration Function - always on one line with corner
                Write-HostRGB "$keyPrefix $corner$hPipe$rArrow " $treeColor -NoNewline
                Write-HostRGB "Function" $elementColor -NoNewline
                Write-HostRGB ": " $colors.Label -NoNewline

                # Show line number or reference type prefix, then function name
                if ([string]::IsNullOrWhiteSpace($step.TestFunc.Line) -or $step.TestFunc.Line -eq 0) {
                    # Function name
                    if ([string]::IsNullOrEmpty($step.TestFunc.FunctionName)) {
                        Write-Host "(unknown)" -ForegroundColor DarkGray
                    } else {
                        Write-HostRGB "$($step.TestFunc.FunctionName)" $colors.Highlight -NoNewline
                    }

                    Write-HostRGB ": " $colors.Label -NoNewline

                    # No line number - show reference type (e.g., EXTERNAL_REFERENCE, PRIVATE_REFERENCE, PUBLIC_REFERENCE)
                    if ($step.TestFunc.ReferenceTypeRefId -and $step.TestFunc.ReferenceTypeRefId -gt 0) {
                        $refTypeName = Get-ReferenceTypeName -ReferenceTypeId $step.TestFunc.ReferenceTypeRefId
                        Write-HostRGB "$refTypeName" $colors.RegexClass
                    } else {
                        Write-HostRGB "EXTERNAL_REFERENCE" $colors.RegexClass
                    }
                } else {
                    # Has line number - show it as prefix
                    Write-HostRGB "$($step.TestFunc.Line)" $colors.LineNumber -NoNewline
                    Write-HostRGB ": " $colors.Highlight -NoNewline

                    # Function name
                    if ([string]::IsNullOrEmpty($step.TestFunc.FunctionName)) {
                        Write-Host "(unknown)" -ForegroundColor DarkGray
                    } else {
                        Write-HostRGB "$($step.TestFunc.FunctionName)" $colors.Highlight
                    }
                }

                if (-not $isLastStep) {
                    Write-HostRGB "$groupPrefix$vPipe" $treeColor
                }
            }

            # Continuation pipe between groups (unless it's the last group)
            if (-not $isLastGroup) {
                Write-HostRGB "       $vPipe" $treeColor
            }
        }
    }
}

function Show-IndirectReferences {
    <#
    .SYNOPSIS
    Display all indirect/template-based references from the database

    .PARAMETER DatabaseDirectory
    Directory containing the database CSV files (for loading TemplateCalls)

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
        [string]$DatabaseDirectory = "",

        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",

        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    # Store database directory for use in helper functions
    if ($DatabaseDirectory) {
        $script:DatabaseDirectory = $DatabaseDirectory
    }

    # Get VS Code color scheme for consistent syntax highlighting
    $colors = Get-VSCodeSyntaxColors

    # Define semantic element colors
    $headerColor = $colors.Type
    $labelColor = $colors.Highlight
    $textColor = $colors.Comment
    $numberColor = $colors.Number
    $lowRiskColor = $colors.String        # Green-ish/Salmon
    $mediumRiskColor = $colors.EscapeChar # Muted gold/yellow
    $highRiskColor = $colors.ControlFlow  # Purple
    $mutedColor = $colors.LineNumberMuted
    $bulletColor = $colors.LineNumberMuted

    Write-Host ""
    Write-Separator
    Write-Host " INDIRECT REFERENCES ANALYSIS:" -ForegroundColor $ItemColor
    Write-Separator
    Write-Host ""

    $perfTimer = [System.Diagnostics.Stopwatch]::StartNew()

    # Use hash tables directly instead of converting to arrays
    $indirectRefsHash = Get-IndirectConfigReferencesHashTable
    $templateRefsHash = Get-TemplateReferencesHashTable
    $sequentialRefsHash = Get-SequentialReferencesHashTable

    if ($indirectRefsHash.Count -eq 0 -and $templateRefsHash.Count -eq 0 -and $sequentialRefsHash.Count -eq 0) {
        Show-PhaseMessageHighlight -Message "No Indirect References Found In Database" -HighlightText "No" -HighlightColor "Yellow" -BaseColor $BaseColor -InfoColor $InfoColor
        return
    }

    # Service Impact Analysis - RECALCULATE at runtime based on resource ownership
    # The stored ServiceImpactTypeId is based on test-service vs struct-service (AST context)
    # But we need test-service vs resource-owning-service for true cross-service analysis
    $resourceOwningServiceId = $null
    $resources = @(Get-Resources)
    if ($resources.Count -gt 0) {
        $targetResource = $resources[0]
        if ($targetResource -and $targetResource.ResourceRegistrationRefId) {
            $registration = Get-ResourceRegistrationByName -ResourceName $targetResource.ResourceName
            if ($registration) {
                $resourceOwningServiceId = [int]$registration.ServiceRefId
            }
        }
    }

    # Recalculate service impact for each indirect reference
    $sameServiceRefs = @()
    $crossServiceRefs = @()

    foreach ($indirectRef in $indirectRefsHash.Values) {
        # Get the test function's service using hash table lookup
        $templateRefId = $indirectRef.TemplateReferenceRefId
        if ($templateRefsHash.ContainsKey($templateRefId)) {
            $templateRef = $templateRefsHash[$templateRefId]
            $testFunc = Get-TestFunctionById -TestFunctionRefId $templateRef.TestFunctionRefId
            if ($testFunc -and $testFunc.FileRefId) {
                $fileRefId = [int]$testFunc.FileRefId
                $testFile = Get-FileRecordByRefId -FileRefId $fileRefId
                if ($testFile -and $testFile.ServiceRefId) {
                    $testServiceId = [int]$testFile.ServiceRefId

                    # Compare test service vs resource-owning service
                    if ($resourceOwningServiceId -and $testServiceId -eq $resourceOwningServiceId) {
                        $sameServiceRefs += $indirectRef
                    } elseif ($resourceOwningServiceId) {
                        $crossServiceRefs += $indirectRef
                    }
                }
            }
        }
    }

    Write-Host "  Total Impact: " -ForegroundColor $ItemColor -NoNewline
    Write-Host "$($indirectRefsHash.Count + $sequentialRefsHash.Count) " -ForegroundColor Yellow -NoNewline
    Write-Host "test functions affected by this resource change" -ForegroundColor $BaseColor
    Write-Host ""

    # Template Dependencies (explain what this means)
    if ($indirectRefsHash.Count -gt 0) {
        Write-Host "  Template Dependencies: " -ForegroundColor $ItemColor -NoNewline
        Write-Host "$($indirectRefsHash.Count) " -ForegroundColor Yellow -NoNewline
        Write-Host "tests use templates that configure this resource" -ForegroundColor $BaseColor

        if ($sameServiceRefs.Count -gt 0) {
            Write-Host "     - " -ForegroundColor $ItemColor -NoNewline
            Write-Host "$($sameServiceRefs.Count) " -ForegroundColor Yellow  -NoNewline
            Write-Host "templates in the same service folder " -ForegroundColor $BaseColor -NoNewline
            Write-Host "(" -ForegroundColor $BaseColor -NoNewline
            Write-HostRGB "LOW RISK" $textColor -NoNewline
            Write-Host ")" -ForegroundColor $BaseColor
        }
        if ($crossServiceRefs.Count -gt 0) {
            Write-Host "     - " -ForegroundColor $ItemColor -NoNewline
            Write-Host "$($crossServiceRefs.Count) " -Yellow -NoNewline
            Write-Host "templates in different service folders " -ForegroundColor $BaseColor -NoNewline
            Write-Host "(" $mutedColor -ForegroundColor $BaseColor -NoNewline
            Write-HostRGB "HIGH RISK " $highRiskColor -NoNewline
            Write-Host "- " -ForegroundColor $BaseColor -NoNewline
            Write-HostRGB "CROSS SERVICE REFERENCE" $highRiskColor -NoNewline
            Write-Host ")" -ForegroundColor $BaseColor
        }
        Write-Host ""
    }

    # Sequential Test Chains (explain what this means)
    if ($sequentialRefsHash.Count -gt 0) {
        Write-Host "  Sequential Test Chains: " -ForegroundColor $ItemColor -NoNewline
        Write-Host "$($sequentialRefsHash.Count) " -ForegroundColor Yellow -NoNewline
        Write-Host "tests are called by other tests in the blast radius" -ForegroundColor $BaseColor
        Write-Host "     - " -ForegroundColor $ItemColor -NoNewline
        Write-Host "$($sequentialRefsHash.Count) " -ForegroundColor Yellow -NoNewline
        Write-Host "tests run as part of larger test sequences " -ForegroundColor $BaseColor -NoNewline
        Write-Host "(" -ForegroundColor $BaseColor -NoNewline
        Write-HostRGB "MEDIUM RISK" $mediumRiskColor -NoNewline
        Write-Host ")" -ForegroundColor $BaseColor
        Write-Host ""
    }

    Write-Separator

    $templateRefLookup = Get-TemplateReferencesHashTable  # Already indexed by TemplateReferenceRefId
    $testFuncStepLookup = Get-TestStepsHashTable          # Already indexed by TestStepRefId
    $templateFuncLookup = Get-TemplateFunctionsHashTable  # Already indexed by TemplateFunctionRefId
    $structsLookup = Get-StructsHashTable                 # Already indexed by StructRefId
    $servicesLookup = Get-ServicesHashTable               # Already indexed by ServiceRefId

    # Template call chain needs special indexing by SourceTemplateFunctionRefId
    $templateCallChainLookup = @{}
    foreach ($callChain in (Get-TemplateCallChainsHashTable).Values) {
        $sourceId = $callChain.SourceTemplateFunctionRefId
        if (-not $templateCallChainLookup.ContainsKey($sourceId)) {
            $templateCallChainLookup[$sourceId] = @()
        }
        $templateCallChainLookup[$sourceId] += $callChain
    }

    # Get reference type names from database (avoid hardcoding strings throughout the code)
    # Use IDs for comparisons (stable database values), convert to names only for display
    $REF_ID_CROSS_FILE = 2
    $REF_ID_EMBEDDED_SELF = 3
    $REF_ID_EXTERNAL_REFERENCE = 10
    $REF_ID_SELF_CONTAINED = 1
    $REF_ID_SAME_SERVICE = 14
    $REF_ID_CROSS_SERVICE = 15

    # Build file-based grouping - Join: IndirectConfigReferences -> TemplateReferences -> TestFunctionSteps -> TestFunctions -> Files
    $fileGroups = @{}
    foreach ($indirectRef in $indirectRefsHash.Values) {
        # Get TemplateReference
        $templateRef = $templateRefLookup[$indirectRef.TemplateReferenceRefId]
        if (-not $templateRef) { continue }

        # Get TestFunction (has the line number and file reference)
        $testFunc = Get-TestFunctionById -TestFunctionRefId $templateRef.TestFunctionRefId
        if (-not $testFunc) { continue }

        # Get TestFunctionStep (has the step index)
        $testFuncStep = $testFuncStepLookup[$templateRef.TestFunctionStepRefId]
        if (-not $testFuncStep) { continue }

        # Get reference type ID from IndirectConfigReference (file location: CROSS_FILE or EMBEDDED_SELF)
        $fileReferenceTypeId = $null
        if ($indirectRef.PSObject.Properties['ReferenceTypeId'] -and $indirectRef.ReferenceTypeId) {
            $fileReferenceTypeId = $indirectRef.ReferenceTypeId
        }

        # Get the source template function (the one being called in the test step)
        $sourceTemplateFunction = $null
        if ($indirectRef.SourceTemplateFunctionRefId) {
            $sourceTemplateFunction = $templateFuncLookup[$indirectRef.SourceTemplateFunctionRefId]
        }

        # Get target template info for ALL templates (both EMBEDDED_SELF and CROSS_FILE)
        # This shows what the template is calling (e.g., r.basic calls BackupProtectedFileShareResource.base)
        $targetTemplateInfo = $null
        if ($sourceTemplateFunction) {
            # Get the target struct and function name for display
            if ($sourceTemplateFunction.StructRefId) {
                $sourceStruct = $structsLookup[$sourceTemplateFunction.StructRefId]
                if ($sourceStruct) {
                    $targetTemplateInfo = @{
                        TemplateFunction = $sourceTemplateFunction
                        Struct = $sourceStruct
                    }
                }
            }
        }

        # CHECK: If the template makes cross-file calls to other templates (e.g., data source -> resource)
        # Override EMBEDDED_SELF to CROSS_FILE if template calls another template in a different file
        # AND override the target info to show the cross-file target instead of the source
        $crossFileCallInfo = $null
        if ($fileReferenceTypeId -eq $REF_ID_EMBEDDED_SELF -and $indirectRef.SourceTemplateFunctionRefId) {
            # Use pre-built lookup instead of querying every time
            $crossFileCallsForSource = $templateCallChainLookup[$indirectRef.SourceTemplateFunctionRefId]
            if ($crossFileCallsForSource) {
                $crossFileCall = $crossFileCallsForSource | Where-Object {
                    $_.ReferenceTypeId -eq $REF_ID_CROSS_FILE -or $_.ReferenceTypeId -eq $REF_ID_EXTERNAL_REFERENCE
                } | Select-Object -First 1

                if ($crossFileCall) {
                    # Check if it's an external reference (unresolved target)
                    if ($crossFileCall.ReferenceTypeId -eq $REF_ID_EXTERNAL_REFERENCE) {
                        $fileReferenceTypeId = $REF_ID_EXTERNAL_REFERENCE
                        $crossFileCallInfo = $crossFileCall
                        # For external references, targetTemplateInfo stays as source (we don't know the target)
                    } else {
                        $fileReferenceTypeId = $REF_ID_CROSS_FILE
                        $crossFileCallInfo = $crossFileCall

                        # Join to get target template function and struct info (OVERRIDE the source info)
                        if ($crossFileCall.TargetTemplateFunctionRefId) {
                            $targetTemplateFunc = $templateFuncLookup[$crossFileCall.TargetTemplateFunctionRefId]
                            if ($targetTemplateFunc -and $targetTemplateFunc.StructRefId) {
                                $targetStruct = $structsLookup[$targetTemplateFunc.StructRefId]
                                if ($targetStruct) {
                                    $targetTemplateInfo = @{
                                        TemplateFunction = $targetTemplateFunc
                                        Struct = $targetStruct
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        # RECALCULATE service impact type at runtime based on resource ownership
        # Compare test function's service vs resource-owning service (not struct service)
        $serviceImpactTypeId = $null
        $testServiceName = $null
        if ($testFunc -and $testFunc.FileRefId) {
            $fileRefId = [int]$testFunc.FileRefId
            $testFile = Get-FileRecordByRefId -FileRefId $fileRefId
            if ($testFile -and $testFile.ServiceRefId -and $resourceOwningServiceId) {
                $testServiceId = [int]$testFile.ServiceRefId

                # Get the test service name for display (use pre-built lookup)
                $testService = $servicesLookup[$testServiceId]
                if ($testService) {
                    $testServiceName = $testService.Name
                }

                if ($testServiceId -eq $resourceOwningServiceId) {
                    $serviceImpactTypeId = $REF_ID_SAME_SERVICE
                } else {
                    $serviceImpactTypeId = $REF_ID_CROSS_SERVICE
                }
            }
        }

        # Get the resource-owning service name for display (use pre-built lookup)
        $resourceOwningServiceName = $null
        if ($resourceOwningServiceId) {
            $owningService = $servicesLookup[$resourceOwningServiceId]
            if ($owningService) {
                $resourceOwningServiceName = $owningService.Name
            }
        }

        # Convert IDs to names for display: "CROSS_FILE;SAME_SERVICE" or "SELF_CONTAINED"
        $fileRefTypeName = if ($fileReferenceTypeId) { Get-ReferenceTypeName -ReferenceTypeId $fileReferenceTypeId } else { $null }
        $serviceImpactTypeName = if ($serviceImpactTypeId) { Get-ReferenceTypeName -ReferenceTypeId $serviceImpactTypeId } else { $null }

        $refTypeName = if ($fileReferenceTypeId -eq $REF_ID_EMBEDDED_SELF) {
            Get-ReferenceTypeName -ReferenceTypeId $REF_ID_SELF_CONTAINED  # Same file = self-contained
        } elseif ($fileRefTypeName -and $serviceImpactTypeName) {
            "$fileRefTypeName;$serviceImpactTypeName"  # e.g., "CROSS_FILE;SAME_SERVICE"
        } elseif ($fileRefTypeName) {
            $fileRefTypeName  # Just file reference type if no service info
        } else {
            "UNKNOWN"
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
            TestServiceName           = $testServiceName
            ResourceOwningServiceName = $resourceOwningServiceName
            SourceTemplateFunction    = $sourceTemplateFunction
            CrossFileCallInfo         = $crossFileCallInfo
            TargetTemplateInfo        = $targetTemplateInfo
        }
    }

    # Add Sequential References - these are test functions that call other test functions sequentially
    # The entry point is the test in our blast radius, and it calls the referenced function
    foreach ($seqRef in $sequentialRefsHash.Values) {
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
    $currentFileIndex = 0

    Write-Host " Blast Radius Analysis:" -ForegroundColor $ItemColor
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

        # Add blank before file header (except first file)
        if ($currentFileIndex -gt 1) {
            Write-Host ""
        }

        # File header
        Write-HostRGB " File: " $labelColor -NoNewline
        Write-HostRGB "./$filePath" $textColor
        if ($templateRefs.Count -gt 0) {
            $templateLabel = if ($templateRefs.Count -eq 1) { "Test Step Configuration Function Reference" } else { "Test Step Configuration Function References" }
            Write-HostRGB "   $($templateRefs.Count) " $numberColor -NoNewline
            # Only use -NoNewline if there are also sequential refs (so we can add comma)
            if ($sequentialRefs.Count -gt 0) {
                Write-HostRGB "$templateLabel" $labelColor -NoNewline
            } else {
                Write-HostRGB "$templateLabel" $labelColor
            }
        }
        if ($templateRefs.Count -gt 0 -and $sequentialRefs.Count -gt 0) {
            Write-HostRGB ", " $textColor -NoNewline
        }
        if ($sequentialRefs.Count -gt 0) {
            # Add indent if this is the first line (no template refs)
            if ($templateRefs.Count -eq 0) {
                Write-Host "   " -NoNewline
            }
            $sequentialLabel = if ($sequentialRefs.Count -eq 1) { "Sequential Key Reference" } else { "Sequential Key References" }
            Write-HostRGB "$($sequentialRefs.Count) " $numberColor -NoNewline
            Write-HostRGB "$sequentialLabel" $labelColor
        }

        if ($refs.Count -gt 0) {
            # Display template references first (if any)
            if ($templateRefs.Count -gt 0) {
                Show-TemplateFunctionDependencies -TemplateRefs $templateRefs -Colors $colors -NumberColor $NumberColor -ItemColor $ItemColor
            }

            # Display sequential references (if any)
            if ($sequentialRefs.Count -gt 0) {
                Show-SequentialCallChain -SequentialRefs $sequentialRefs -Colors $colors -ItemColor $ItemColor
            }
        }
    }

    Write-Host ""
    Write-Separator
    Write-HostRGB " End of Blast Radius Analysis" $headerColor
    Write-Separator
}

Export-ModuleMember -Function @(
    'Show-DirectReferences',
    'Show-IndirectReferences'
)
