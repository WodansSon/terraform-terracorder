# DatabaseMode.psm1
# Query and visualization functions for Database-Only Mode
# These functions provide deep analysis without re-running discovery phases

# ============================================================================
# MODULE-LEVEL VARIABLES
# ============================================================================
# Cache of imported resources for filtering support
$script:ImportedResources = @()

# ============================================================================
# PERFORMANCE OPTIMIZATION: Precompiled Regex Patterns
# ============================================================================
# These regex patterns are compiled once at module load time and reused across
# all function calls. This provides ~3x performance improvement over using
# PowerShell's -match and -replace operators, which recompile the pattern on
# every use. The RegexOptions.Compiled flag generates IL code for the regex,
# making it much faster for repeated use.
#
# Performance Impact:
# - Without precompilation: ~9 seconds for ShowIndirectReferences
# - With precompilation: ~3 seconds for ShowIndirectReferences
# - No functional changes to output
# ============================================================================
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

function Show-DatabaseStatistics {
    <#
    .SYNOPSIS
    Display available analysis options and resources in the database

    .PARAMETER Resources
    Array of resource records from Resources.csv

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
        [array]$Resources = @(),

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
    Write-Host "  AVAILABLE ANALYSIS OPTIONS" -ForegroundColor $ItemColor
    Write-Separator
    Write-Host ""

    # Show resources in database
    if ($Resources.Count -gt 0) {
        Write-Host "  Resources in Database:" -ForegroundColor $InfoColor
        Write-Host ""
        foreach ($resource in $Resources) {
            Write-Host "    [" -ForegroundColor $BaseColor -NoNewline
            Write-Host $resource.ResourceRefId -ForegroundColor $NumberColor -NoNewline
            Write-Host "] " -ForegroundColor $BaseColor -NoNewline
            Write-Host $resource.ResourceName -ForegroundColor Green
        }
        Write-Host ""
    }

    Write-Host "  Query Options:" -ForegroundColor $InfoColor
    Write-Host ""
    Write-Host "    -ShowDirectReferences      " -ForegroundColor Green -NoNewline
    Write-Host ": View all direct resource/data declarations and attribute usages" -ForegroundColor $BaseColor
    Write-Host "    -ShowIndirectReferences    " -ForegroundColor Green -NoNewline
    Write-Host ": View template dependencies and sequential test chains" -ForegroundColor $BaseColor
    Write-Host ""

    if ($Resources.Count -gt 1) {
        Write-Host "  Filter by Resource:" -ForegroundColor $InfoColor
        Write-Host ""
        Write-Host "    -ResourceName <name>       " -ForegroundColor Green -NoNewline
        Write-Host ": Filter results to specific resource" -ForegroundColor $BaseColor
        Write-Host ""
    }

    Write-Host "  Examples:" -ForegroundColor $InfoColor
    Write-Host "    .\terracorder.ps1 -DatabaseDirectory .\output -ShowDirectReferences" -ForegroundColor $BaseColor
    Write-Host "    .\terracorder.ps1 -DatabaseDirectory .\output -ShowIndirectReferences" -ForegroundColor $BaseColor

    if ($Resources.Count -gt 1) {
        Write-Host "    .\terracorder.ps1 -DatabaseDirectory .\output -ShowDirectReferences -ResourceName """ -ForegroundColor $BaseColor -NoNewline
        Write-Host $Resources[0].ResourceName -ForegroundColor Green -NoNewline
        Write-Host """" -ForegroundColor $BaseColor
    }
}

function Show-DirectReferences {
    <#
    .SYNOPSIS
    Display all direct resource references from the database

    .PARAMETER ResourceName
    Optional filter to show only references for specific resource

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
        [string]$ResourceName = "",

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

    # Get resource filter if specified
    $resourceRefId = $null
    if ($ResourceName) {
        $resource = $script:ImportedResources | Where-Object { $_.ResourceName -eq $ResourceName } | Select-Object -First 1
        if (-not $resource) {
            Write-Host "  [" -ForegroundColor $BaseColor -NoNewline
            Write-Host "ERROR" -ForegroundColor Red -NoNewline
            Write-Host "] Resource '" -ForegroundColor $BaseColor -NoNewline
            Write-Host $ResourceName -ForegroundColor Yellow -NoNewline
            Write-Host "' not found in database" -ForegroundColor $BaseColor
            Write-Host ""
            Write-Host "  Available resources:" -ForegroundColor $InfoColor
            foreach ($res in $script:ImportedResources) {
                Write-Host "    - " -ForegroundColor $BaseColor -NoNewline
                Write-Host $res.ResourceName -ForegroundColor Green
            }
            return
        }
        $resourceRefId = $resource.ResourceRefId
        Write-Host "  Filtering by Resource: " -ForegroundColor $InfoColor -NoNewline
        Write-Host $ResourceName -ForegroundColor Green
        Write-Host ""
    }

    $directRefs = Get-DirectResourceReferences -ResourceRefId $resourceRefId

    if ($directRefs.Count -eq 0) {
        Show-PhaseMessageHighlight -Message "No Direct Resource References Found In Database" -HighlightText "No" -HighlightColor "Yellow" -BaseColor $BaseColor -InfoColor $InfoColor
        return
    }

    # Separate references by type for summary
    $resourceRefs = $directRefs | Where-Object { $_.ReferenceTypeId -in @(5, 6) }  # RESOURCE_REFERENCE, DATA_SOURCE_REFERENCE
    $attributeRefs = $directRefs | Where-Object { $_.ReferenceTypeId -eq 4 }        # ATTRIBUTE_REFERENCE

    # Display summary
    Write-Host "  Total References: " -ForegroundColor $InfoColor -NoNewline
    Write-Host "$($directRefs.Count) " -ForegroundColor $NumberColor -NoNewline
    Write-Host "direct resource references found" -ForegroundColor $InfoColor
    Write-Host ""

    if ($resourceRefs.Count -gt 0) {
        Write-Host "  Direct Resource/Data Source References: " -ForegroundColor $InfoColor -NoNewline
        Write-Host "$($resourceRefs.Count) " -ForegroundColor $NumberColor -NoNewline
        Write-Host "resource and data source declarations" -ForegroundColor $InfoColor
    }

    if ($attributeRefs.Count -gt 0) {
        Write-Host "  Attribute References: " -ForegroundColor $InfoColor -NoNewline
        Write-Host "$($attributeRefs.Count) " -ForegroundColor $NumberColor -NoNewline
        Write-Host "attribute usages in test configurations" -ForegroundColor $InfoColor
    }

    Write-Host ""
    Write-Separator
    Write-Host ""

    # Group by file first, then display references within each file
    $groupedByFile = $directRefs | Group-Object -Property FileRefId | Sort-Object { Get-FilePathByRefId -FileRefId $_.Name }
    $totalFiles = $groupedByFile.Count
    $currentFileIndex = 0

    foreach ($fileGroup in $groupedByFile) {
        $currentFileIndex++
        $filePath = Get-FilePathByRefId -FileRefId $fileGroup.Name
        $fileRefCount = $fileGroup.Count

        # Separate references by type within this file
        $resourceRefs = $fileGroup.Group | Where-Object { $_.ReferenceTypeId -in @(5, 6) }  # RESOURCE_REFERENCE, DATA_SOURCE_REFERENCE
        $attributeRefs = $fileGroup.Group | Where-Object { $_.ReferenceTypeId -eq 4 }        # ATTRIBUTE_REFERENCE

        Write-Host " File: " -ForegroundColor $InfoColor -NoNewline
        Write-Host "./$filePath" -ForegroundColor $BaseColor
        Write-Host "   " -NoNewline
        Write-Host "$fileRefCount " -ForegroundColor $NumberColor -NoNewline
        Write-Host "Total References" -ForegroundColor $InfoColor -NoNewline

        if ($resourceRefs.Count -gt 0) {
            Write-Host ", " -ForegroundColor $BaseColor -NoNewline
            Write-Host "$($resourceRefs.Count) " -ForegroundColor $NumberColor -NoNewline
            Write-Host "Direct References" -ForegroundColor $InfoColor -NoNewline
        }
        if ($attributeRefs.Count -gt 0) {
            Write-Host ", " -ForegroundColor $BaseColor -NoNewline
            Write-Host "$($attributeRefs.Count) " -ForegroundColor $NumberColor -NoNewline
            Write-Host "Attribute References" -ForegroundColor $InfoColor -NoNewline
        }
        Write-Host ""
        Write-Host ""

        # Calculate column widths for alignment
        $maxLineNumWidth = ($fileGroup.Group | ForEach-Object { $_.LineNumber.ToString().Length } | Measure-Object -Maximum).Maximum
        $maxContextWidth = 100

        # Get syntax colors for highlighting
        $colors = Get-VSCodeSyntaxColors

        # Display Direct Resource/Data Source References
        if ($resourceRefs.Count -gt 0) {
            Write-Separator -Indent 4
            Write-Host "      Direct Resource References:" -ForegroundColor $InfoColor
            Write-Separator -Indent 4

            foreach ($ref in $resourceRefs | Sort-Object LineNumber) {
                $lineNumStr = $ref.LineNumber.ToString().PadLeft($maxLineNumWidth)

                # Write-HostRGB "      Reference: " $colors.Highlight -NoNewline
                Write-Host "      " -NoNewline
                $context = $ref.Context.Trim()
                # Normalize whitespace: collapse multiple spaces to single space
                $context = $script:CompiledRegex.Whitespace.Replace($context, ' ')
                if ($context.Length -gt $maxContextWidth) {
                    $context = $context.Substring(0, $maxContextWidth - 3) + "..."
                }

                # Syntax highlighting: Highlight resource type in StringHighlight, rest in salmon (string color)
                # Matches how format specifiers like %d, %s appear in Go sprintf blocks
                $match = $script:CompiledRegex.ResourceOrData.Match($context)
                if ($match.Success) {
                    Write-HostRGB "${lineNumStr}" $colors.LineNumber -NoNewline
                    Write-HostRGB ": " $colors.Label -NoNewline
                    Write-HostRGB "$($match.Groups[1].Value) " $colors.String -NoNewline          # Keyword - Salmon
                    Write-HostRGB '"' $colors.String -NoNewline                                   # Opening quote - Salmon
                    Write-HostRGB "$($match.Groups[2].Value)" $colors.StringHighlight -NoNewline  # Resource type - StringHighlight
                    Write-HostRGB '"' $colors.String -NoNewline                                   # Closing quote - Salmon
                    Write-HostRGB "$($match.Groups[3].Value)" $colors.String                      # Rest - Salmon
                } else {
                    Write-Host "$context" -ForegroundColor $BaseColor
                }
            }

            Write-Host ""
        }

        # Display Attribute References
        if ($attributeRefs.Count -gt 0) {
            Write-Separator -Indent 4
            Write-Host "      Attribute Resource References:" -ForegroundColor $InfoColor
            Write-Separator -Indent 4

            foreach ($ref in $attributeRefs | Sort-Object LineNumber) {
                $lineNumStr = $ref.LineNumber.ToString().PadLeft($maxLineNumWidth)

                Write-Host "      " -NoNewline
                Write-HostRGB "${lineNumStr}" $colors.LineNumber -NoNewline
                Write-HostRGB ": " $colors.Label -NoNewline

                $context = $ref.Context.Trim()
                # Normalize whitespace: collapse multiple spaces to single space
                $context = $script:CompiledRegex.Whitespace.Replace($context, ' ')
                if ($context.Length -gt $maxContextWidth) {
                    $context = $context.Substring(0, $maxContextWidth - 3) + "..."
                }

                # Syntax highlighting: Highlight resource type in StringHighlight, rest in salmon (string color)
                # Just look for azurerm_* anywhere in the line
                $colors = Get-VSCodeSyntaxColors
                $match = $script:CompiledRegex.AzureResourceName.Match($context)
                if ($match.Success) {
                    # Write parts only if they're not empty
                    if ($match.Groups[1].Value) {
                        Write-HostRGB $match.Groups[1].Value $colors.String -NoNewline       # Everything before resource name - Salmon
                    }
                    Write-HostRGB $match.Groups[2].Value $colors.StringHighlight -NoNewline  # Resource name - StringHighlight
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

    .PARAMETER FilePath
    The file path being processed

    .PARAMETER NumberColor
    Color for numbers in output

    .PARAMETER ItemColor
    Color for item types in output
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$TemplateRefs,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

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

    # Get VS Code color scheme for function highlighting
    $colors = Get-VSCodeSyntaxColors

    # Get executing service name from the file path (e.g., internal/services/recoveryservices/...)
    $executingServiceName = "unknown"
    $match = $script:CompiledRegex.ServicePath.Match($FilePath)
    if ($match.Success) {
        $executingServiceName = $match.Groups[1].Value
    }

    # Group by test function to consolidate steps
    $functionGroups = @{}
    foreach ($refInfo in $TemplateRefs) {
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
        Write-HostRGB "$($funcGroup.TestFunc.FunctionName)" $colors.Function

        # Show service context - only for cross-service references
        if ($executingServiceName -ne $funcGroup.ResourceOwningServiceName) {
            # Cross-service - show which service is referencing this resource
            Write-HostRGB "               Referenced From: " $colors.Highlight -NoNewline
            Write-HostRGB "$executingServiceName" $colors.Type
        }

        # Display steps (sorted by step index)
        $sortedSteps = $funcGroup.Steps | Sort-Object { $_.TestFuncStep.StepIndex }
        # Calculate max step index width for alignment
        $maxStepWidth = ($sortedSteps | ForEach-Object { $_.TestFuncStep.StepIndex.ToString().Length } | Measure-Object -Maximum).Maximum
        foreach ($stepInfo in $sortedSteps) {
            $stepNumStr = $stepInfo.TestFuncStep.StepIndex.ToString().PadLeft($maxStepWidth)
            Write-HostRGB "               Step " $colors.Highlight -NoNewline
            Write-Host "$stepNumStr" -ForegroundColor $NumberColor -NoNewline
            Write-HostRGB ": " $colors.Highlight -NoNewline
            Write-HostRGB "Config" $colors.Highlight -NoNewline
            Write-HostRGB ": " $colors.Label -NoNewline
            Write-HostRGB "$($stepInfo.TemplateRef.TemplateVariable)" $colors.Variable -NoNewline
            Write-HostRGB "." $colors.Label -NoNewline
            Write-HostRGB "$($stepInfo.TemplateRef.TemplateMethod)" $colors.Function
        }
    }
}

function Show-SequentialCallChain {
    <#
    .SYNOPSIS
    Display sequential call chain (sequential references)

    .PARAMETER SequentialRefs
    Array of sequential reference info objects

    .PARAMETER FilePath
    The file path being processed

    .PARAMETER NumberColor
    Color for numbers in output

    .PARAMETER ItemColor
    Color for item types in output
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$SequentialRefs,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

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

    # Get VS Code color scheme
    $colors = Get-VSCodeSyntaxColors

    # Define Unicode box-drawing characters
    $pipe = [char]0x2502      # vertical line
    $tee = [char]0x251C       # T-junction (branch continues)
    $corner = [char]0x2514    # corner (last branch)
    $arrow = [char]0x2500     # horizontal line
    $teeDown = [char]0x252C   # T-junction down (children below)
    $rarrow = [char]0x25BA    # right-pointing arrow

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
        Write-HostRGB "      Entry Point: " $colors.Highlight -NoNewline
        Write-HostRGB "$($entryPoint.Line)" $colors.LineNumber -NoNewline
        Write-HostRGB ": " $colors.Highlight -NoNewline
        Write-HostRGB "$($entryPoint.FunctionName)" $colors.Function

        # Display entry point pipe
        Write-HostRGB "       $pipe" $colors.Highlight

        # Display each sequential group
        # Use GetEnumerator() to avoid conflicts with reserved property names like "keys"
        $groupNames = @($epGroup.SequentialGroups.GetEnumerator() | ForEach-Object { [string]$_.Key } | Sort-Object)
        $totalGroups = $groupNames.Count
        $currentGroupIndex = 0

        foreach ($groupName in $groupNames) {
            $currentGroupIndex++
            $isLastGroup = ($currentGroupIndex -eq $totalGroups)

            # Group level - Keys align with the T-down character position
            $groupPrefix = if ($isLastGroup) { "          " } else { "       $pipe  " }

            $rawSteps = $epGroup.SequentialGroups[$groupName]

            # Group by SequentialKey to count unique keys (not total references)
            $uniqueKeys = $rawSteps | Group-Object -Property SequentialKey
            $steps = @($uniqueKeys | Sort-Object Name)

            # Display each step in the group
            $stepCount = $steps.Count

            # Determine group branch based on position - always show T-down since groups have keys as children
            $groupBranch = if ($isLastGroup) { "$corner$arrow$arrow$teeDown" } else { "$tee$arrow$arrow$teeDown" }

            Write-HostRGB "       $groupBranch$arrow$rarrow" $colors.Highlight -NoNewline
            Write-HostRGB " Sequential Group: " $colors.Highlight -NoNewline
            Write-HostRGB "$groupName" $colors.String
            Write-HostRGB "$groupPrefix$pipe" $colors.Highlight

            $currentStep = 0
            foreach ($keyGroup in $steps) {
                $currentStep++
                $isLastStep = ($currentStep -eq $stepCount)

                # When there's only one key, use corner; otherwise use tee/corner based on position
                if ($stepCount -eq 1) {
                    $stepBranch = "$corner$arrow$teeDown$arrow"
                } else {
                    $stepBranch = if ($isLastStep) { "$corner$arrow$teeDown$arrow" } else { "$tee$arrow$teeDown$arrow" }
                }

                # Key level - builds on group prefix
                $keyPrefix = if ($isLastStep) { "$groupPrefix " } else { "$groupPrefix$pipe" }

                # Get the first step from this key group (they all have the same key)
                $step = $keyGroup.Group | Select-Object -First 1

                # Key header with T-junction down for children
                Write-HostRGB "$groupPrefix$stepBranch$rarrow " $colors.Highlight -NoNewline
                Write-HostRGB "Key     : " $colors.Highlight -NoNewline
                if ([string]::IsNullOrEmpty($step.SequentialKey)) {
                    Write-Host "(empty)" -ForegroundColor DarkGray
                } else {
                    Write-HostRGB "$($step.SequentialKey)" $colors.String
                }

                # Configuration Function - always on one line with corner
                Write-HostRGB "$keyPrefix $corner$arrow$rarrow Function: " $colors.Highlight -NoNewline

                # Show line number or External Reference prefix, then function name
                if ([string]::IsNullOrWhiteSpace($step.TestFunc.Line) -or $step.TestFunc.Line -eq 0) {
                    # External Reference
                    Write-HostRGB "External Reference" $colors.Function -NoNewline
                    Write-HostRGB ": " $colors.Label -NoNewline

                    # Function name
                    if ([string]::IsNullOrEmpty($step.TestFunc.FunctionName)) {
                        Write-Host "(unknown)" -ForegroundColor DarkGray
                    } else {
                        Write-HostRGB "$($step.TestFunc.FunctionName)" $colors.Variable
                    }
                } else {
                    # Has line number - show it as prefix
                    Write-HostRGB "$($step.TestFunc.Line)" $colors.LineNumber -NoNewline
                    Write-HostRGB ": " $colors.Highlight -NoNewline

                    # Function name
                    if ([string]::IsNullOrEmpty($step.TestFunc.FunctionName)) {
                        Write-Host "(unknown)" -ForegroundColor DarkGray
                    } else {
                        Write-HostRGB "$($step.TestFunc.FunctionName)" $colors.Function
                    }
                }

                if (-not $isLastStep) {
                    Write-HostRGB "$groupPrefix$pipe" $colors.Highlight
                }
            }

            # Continuation pipe between groups (unless it's the last group)
            if (-not $isLastGroup) {
                Write-HostRGB "       $pipe" $colors.Highlight
            }
        }
    }
}

function Show-IndirectReferences {
    <#
    .SYNOPSIS
    Display all indirect/template-based references from the database

    .PARAMETER ResourceName
    Optional filter to show only references for specific resource

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
        [string]$ResourceName = "",

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

    # Get resource filter if specified
    $resourceRefId = $null
    if ($ResourceName) {
        $resource = $script:ImportedResources | Where-Object { $_.ResourceName -eq $ResourceName } | Select-Object -First 1
        if (-not $resource) {
            Write-Host "  [" -ForegroundColor $BaseColor -NoNewline
            Write-Host "ERROR" -ForegroundColor Red -NoNewline
            Write-Host "] Resource '" -ForegroundColor $BaseColor -NoNewline
            Write-Host $ResourceName -ForegroundColor Yellow -NoNewline
            Write-Host "' not found in database" -ForegroundColor $BaseColor
            Write-Host ""
            Write-Host "  Available resources:" -ForegroundColor $InfoColor
            foreach ($res in $script:ImportedResources) {
                Write-Host "    - " -ForegroundColor $BaseColor -NoNewline
                Write-Host $res.ResourceName -ForegroundColor Green
            }
            return
        }
        $resourceRefId = $resource.ResourceRefId
        Write-Host "  Filtering by Resource: " -ForegroundColor $InfoColor -NoNewline
        Write-Host $ResourceName -ForegroundColor Green
        Write-Host ""
    }

    $indirectRefs = Get-IndirectConfigReferences -ResourceRefId $resourceRefId
    $templateRefs = Get-TemplateReferences -ResourceRefId $resourceRefId
    $sequentialRefs = Get-SequentialReferences -ResourceRefId $resourceRefId

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
            Write-Host "(" -ForegroundColor Gray -NoNewline
            Write-Host "LOW RISK" -ForegroundColor Green -NoNewline
            Write-Host ")" -ForegroundColor Gray
        }
        if ($crossServiceRefs.Count -gt 0) {
            Write-Host "     - " -ForegroundColor DarkGray -NoNewline
            Write-Host "$($crossServiceRefs.Count) " -ForegroundColor Magenta -NoNewline
            Write-Host "templates in different service folders " -ForegroundColor Gray -NoNewline
            Write-Host "(" -ForegroundColor Gray -NoNewline
            Write-Host "HIGH RISK - CROSS SERVICE REFERENCE" -ForegroundColor Magenta -NoNewline
            Write-Host ")" -ForegroundColor Gray
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
        Write-Host "(" -ForegroundColor Gray -NoNewline
        Write-Host "MEDIUM RISK" -ForegroundColor Yellow -NoNewline
        Write-Host ")" -ForegroundColor Gray
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

        # Add blank before file header (except first file)
        if ($currentFileIndex -gt 1) {
            Write-Host ""
        }

        # File header
        Write-Host " File: " -ForegroundColor $InfoColor -NoNewline
        Write-Host "./$filePath" -ForegroundColor $BaseColor

        # Get the resource name from the first reference's TestFunction
        $resourceName = "unknown"
        $firstRef = $refs | Select-Object -First 1
        if ($firstRef -and $firstRef.TestFunc) {
            $testFunc = $firstRef.TestFunc
            if ($testFunc.ResourceRefId) {
                $resource = Get-ResourceById -ResourceRefId $testFunc.ResourceRefId
                if ($resource) {
                    $resourceName = $resource.ResourceName
                }
            }
        }
        Write-Host "   Referenced Resource: " -ForegroundColor $InfoColor -NoNewline
        Write-Host "$resourceName" -ForegroundColor $NumberColor

        if ($templateRefs.Count -gt 0) {
            $templateLabel = if ($templateRefs.Count -eq 1) { "Test Step Configuration Function Reference" } else { "Test Step Configuration Function References" }
            Write-Host "   $($templateRefs.Count) " -ForegroundColor $NumberColor -NoNewline
            # Only use -NoNewline if there are also sequential refs (so we can add comma)
            if ($sequentialRefs.Count -gt 0) {
                Write-Host "$templateLabel" -ForegroundColor $InfoColor -NoNewline
            } else {
                Write-Host "$templateLabel" -ForegroundColor $InfoColor
            }
        }
        if ($templateRefs.Count -gt 0 -and $sequentialRefs.Count -gt 0) {
            Write-Host ", " -ForegroundColor $BaseColor -NoNewline
        }
        if ($sequentialRefs.Count -gt 0) {
            # Add indent if this is the first line (no template refs)
            if ($templateRefs.Count -eq 0) {
                Write-Host "   " -NoNewline
            }
            $sequentialLabel = if ($sequentialRefs.Count -eq 1) { "Sequential Key Reference" } else { "Sequential Key References" }
            Write-Host "$($sequentialRefs.Count) " -ForegroundColor $NumberColor -NoNewline
            Write-Host "$sequentialLabel" -ForegroundColor $InfoColor
        }

        if ($refs.Count -gt 0) {
            # Display template references first (if any)
            if ($templateRefs.Count -gt 0) {
                Show-TemplateFunctionDependencies -TemplateRefs $templateRefs -FilePath $filePath -NumberColor $NumberColor -ItemColor $ItemColor
            }

            # Display sequential references (if any)
            if ($sequentialRefs.Count -gt 0) {
                Show-SequentialCallChain -SequentialRefs $sequentialRefs -FilePath $filePath -NumberColor $NumberColor -ItemColor $ItemColor
            }
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

function Set-ImportedResourcesCache {
    <#
    .SYNOPSIS
    Set the imported resources cache for filtering

    .PARAMETER Resources
    Array of resource records from Import-DatabaseFromCSV

    .DESCRIPTION
    Internal function to set the module-level cache of imported resources
    for use in filtering queries by resource
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Resources
    )

    $script:ImportedResources = $Resources
}

Export-ModuleMember -Function @(
    'Show-DatabaseStatistics',
    'Show-DirectReferences',
    'Show-IndirectReferences',
    'Set-ImportedResourcesCache'
)
