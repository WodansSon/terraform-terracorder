# TemplateProcessing.psm1
# Template function processing for TerraCorder

function Invoke-TemplateFunctionProcessing {
    <#
    .SYNOPSIS
        Process template functions and build template function database
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$AllRelevantFiles,
        [Parameter(Mandatory = $true)]
        [hashtable]$FileContents,
        [Parameter(Mandatory = $true)]
        [string]$RepositoryDirectory,
        [Parameter(Mandatory = $true)]
        [string]$ResourceName,
        [Parameter(Mandatory = $true)]
        [hashtable]$RegexPatterns,
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Green",
        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    $allTemplateFunctionsWithResource = @{}
    $templateFunctionDatabase = @()

    $totalFiles = $AllRelevantFiles.Count
    $currentFile = 0

    # Scan all relevant files to find template functions that contain our resource
    foreach ($file in $AllRelevantFiles) {
        $currentFile++
        if ($currentFile % 50 -eq 0 -or $currentFile -eq 1) {
            Show-InlineProgress -Current $currentFile -Total $totalFiles -Activity "Processing Test Configuration Functions" -NumberColor $NumberColor -ItemColor $ItemColor -InfoColor $InfoColor -BaseColor $BaseColor
        }

        $content = $FileContents[$file.FullName]
        $relativePath = $file.FullName.Replace($RepositoryDirectory, "").Replace("\", "/").TrimStart("/")

        # Find template functions using the pattern
        $templateMatches = $RegexPatterns.TemplateFunction.Matches($content)

        foreach ($match in $templateMatches) {
            $funcName = $match.Groups[1].Value
            $funcBody = Get-FunctionBody -Content $content -FunctionMatch $match

            # Process ALL template functions in files we're analyzing
            $containsResource = $funcBody -match [regex]::Escape($ResourceName)

            if (-not $allTemplateFunctionsWithResource.ContainsKey($funcName)) {
                $allTemplateFunctionsWithResource[$funcName] = @()
            }
            $allTemplateFunctionsWithResource[$funcName] += $relativePath

            $fileRefId = Get-FileRefIdByPath -FilePath $relativePath
            if ($fileRefId) {

                # ENHANCED STRUCT RESOLUTION: Check receiver pattern first, then fallback to body parsing
                $structRefId = $null
                $receiverVariable = ""

                # Phase 1: Check for receiver pattern (func (r LoadBalancerOutboundRule) method...)
                $receiverMatch = $RegexPatterns.ReceiverMethod.Match($funcBody)
                if ($receiverMatch.Success) {
                    $receiverVariable = $receiverMatch.Groups[1].Value  # e.g., "r"
                    $receiverStructName = $receiverMatch.Groups[2].Value  # e.g., "LoadBalancerOutboundRule"

                    # Look up struct using database function
                    $structRefId = Get-StructRefIdByName -StructName $receiverStructName
                }

                # Phase 2: If no receiver match, check function body for struct instantiations
                if ($null -eq $structRefId) {
                    # Look for patterns like: r := StructName{}
                    $structInstantiationMatches = [regex]::Matches($funcBody, '(?:^|\s)(?:\w+)\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{\}')
                    foreach ($match in $structInstantiationMatches) {
                        $structName = $match.Groups[1].Value
                        $structRefId = Get-StructRefIdByName -StructName $structName
                        if ($structRefId) {
                            break
                        }
                    }
                }

                # Phase 3: Final fallback - use same-file struct lookup
                if ($null -eq $structRefId) {
                    $structs = Get-StructsByFileRefId -FileRefId $fileRefId
                    $structRefId = if ($structs -and $structs.Count -gt 0) { $structs[0].StructRefId } else { $null }
                }

                # Add template function to database
                $templateFunctionRefId = Add-TemplateFunctionRecord -TemplateFunctionName $funcName -StructRefId $structRefId -FileRefId $fileRefId -FunctionBody $funcBody -Line $match.Index -ReceiverVariable $receiverVariable

                # PERFORMANCE OPTIMIZATION: Extract and store function calls for Phase 5 lookup
                if (-not [string]::IsNullOrWhiteSpace($funcBody)) {
                    # Extract struct references (e.g., "SomeStruct{")
                    $structMatches = [regex]::Matches($funcBody, '\b([A-Z][a-zA-Z0-9_]*)\s*\{')
                    foreach ($structMatch in $structMatches) {
                        $structName = $structMatch.Groups[1].Value
                        if ($structName -notmatch '^(if|for|switch|select)$') {
                            Add-TemplateCallRecord -CallerTemplateFunctionRefId $templateFunctionRefId -CalledName $structName -CallType "struct"
                        }
                    }

                    # Extract function calls (e.g., "receiverVar.FunctionName(")
                    if (-not [string]::IsNullOrEmpty($receiverVariable)) {
                        $funcCallMatches = [regex]::Matches($funcBody, "\b$([regex]::Escape($receiverVariable))\.(\w+)\(")
                        foreach ($funcCallMatch in $funcCallMatches) {
                            $calledFuncName = $funcCallMatch.Groups[1].Value
                            Add-TemplateCallRecord -CallerTemplateFunctionRefId $templateFunctionRefId -CalledName $calledFuncName -CallType "function"
                        }
                    }
                }
            }

            $templateFunctionDatabase += [PSCustomObject]@{
                FunctionName = $funcName
                FilePath = $relativePath
                FunctionBody = $funcBody
                ContainsResource = $containsResource
            }
        }

        # Also scan for ApplyStep calls to find additional template functions
        $applyStepMatches = $RegexPatterns.ApplyStepPattern.Matches($content)
        foreach ($match in $applyStepMatches) {
            $funcName = $match.Groups[2].Value

            # Look for the actual template function definition
            $templatePattern = New-DynamicFunctionPattern -FunctionName $funcName
            $templateFunctionMatch = $templatePattern.Match($content)

            if ($templateFunctionMatch.Success) {
                $funcBody = Get-FunctionBody -Content $content -FunctionMatch $templateFunctionMatch

                # Process this template function
                $containsResource = $funcBody -match [regex]::Escape($ResourceName)

                if (-not $allTemplateFunctionsWithResource.ContainsKey($funcName)) {
                    $allTemplateFunctionsWithResource[$funcName] = @()
                }
                $allTemplateFunctionsWithResource[$funcName] += $relativePath

                # FAST LOOKUP: Use database function instead of cached index
                $fileRefId = Get-FileRefIdByPath -FilePath $relativePath
                if ($fileRefId) {

                    # ENHANCED STRUCT RESOLUTION: Check receiver pattern first, then fallback to body parsing
                    $structRefId = $null
                    $receiverVariable = ""

                    # Phase 1: Check for receiver pattern (func (r LoadBalancerOutboundRule) method...)
                    $receiverMatch = $RegexPatterns.ReceiverMethod.Match($funcBody)
                    if ($receiverMatch.Success) {
                        $receiverVariable = $receiverMatch.Groups[1].Value  # e.g., "r"
                        $receiverStructName = $receiverMatch.Groups[2].Value  # e.g., "LoadBalancerOutboundRule"

                        # Look up struct using database function
                        $structRefId = Get-StructRefIdByName -StructName $receiverStructName
                    }

                    # Phase 2: If no receiver match, check function body for struct instantiations
                    if ($null -eq $structRefId) {
                        # Look for patterns like: r := StructName{}
                        $structInstantiationMatches = [regex]::Matches($funcBody, '(?:^|\s)(?:\w+)\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{\}')
                        foreach ($match in $structInstantiationMatches) {
                            $structName = $match.Groups[1].Value
                            $structRefId = Get-StructRefIdByName -StructName $structName
                            if ($structRefId) {
                                break
                            }
                        }
                    }

                    # Phase 3: Final fallback - use same-file struct lookup (original logic)
                    if ($null -eq $structRefId) {
                        $structs = Get-StructsByFileRefId -FileRefId $fileRefId
                        $structRefId = if ($structs -and $structs.Count -gt 0) { $structs[0].StructRefId } else { $null }
                    }

                    # Add template function to database if not already added
                    $existingTemplate = Get-TemplateFunctions | Where-Object { $_.TemplateFunctionName -eq $funcName -and $_.FileRefId -eq $fileRefId }
                    if (-not $existingTemplate) {
                        $templateFunctionRefId = Add-TemplateFunctionRecord -TemplateFunctionName $funcName -StructRefId $structRefId -FileRefId $fileRefId -FunctionBody $funcBody -Line $templateFunctionMatch.Index -ReceiverVariable $receiverVariable

                        # PERFORMANCE OPTIMIZATION: Extract and store function calls for Phase 5 lookup
                        if (-not [string]::IsNullOrWhiteSpace($funcBody)) {
                            # Extract struct references (e.g., "SomeStruct{")
                            $structMatches = [regex]::Matches($funcBody, '\b([A-Z][a-zA-Z0-9_]*)\s*\{')
                            foreach ($structMatch in $structMatches) {
                                $structName = $structMatch.Groups[1].Value
                                if ($structName -notmatch '^(if|for|switch|select)$') {
                                    Add-TemplateCallRecord -CallerTemplateFunctionRefId $templateFunctionRefId -CalledName $structName -CallType "struct"
                                }
                            }

                            # Extract function calls (e.g., "receiverVar.FunctionName(")
                            if (-not [string]::IsNullOrEmpty($receiverVariable)) {
                                $funcCallMatches = [regex]::Matches($funcBody, "\b$([regex]::Escape($receiverVariable))\.(\w+)\(")
                                foreach ($funcCallMatch in $funcCallMatches) {
                                    $calledFuncName = $funcCallMatch.Groups[1].Value
                                    Add-TemplateCallRecord -CallerTemplateFunctionRefId $templateFunctionRefId -CalledName $calledFuncName -CallType "function"
                                }
                            }
                        }
                    }
                }

                # Add to template database if not already there
                $existingInDatabase = $templateFunctionDatabase | Where-Object { $_.FunctionName -eq $funcName -and $_.FilePath -eq $relativePath }
                if (-not $existingInDatabase) {
                    $templateFunctionDatabase += [PSCustomObject]@{
                        FunctionName = $funcName
                        FilePath = $relativePath
                        FunctionBody = $funcBody
                        ContainsResource = $containsResource
                    }
                }
            }
        }
    }

    Show-InlineProgress -Current $totalFiles -Total $totalFiles -Activity "Processing Test Configuration Functions" -Completed -NumberColor $NumberColor -ItemColor $ItemColor -InfoColor $InfoColor -BaseColor $BaseColor

    return @{
        TemplateFunctions = $allTemplateFunctionsWithResource
        TemplateDatabase = $templateFunctionDatabase
    }
}

function Invoke-DynamicTemplateDependencyDiscovery {
    <#
    .SYNOPSIS
        Discover missing template function dependencies
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$AllTestFileNames,
        [Parameter(Mandatory = $true)]
        [string]$RepositoryDirectory,
        [Parameter(Mandatory = $true)]
        [hashtable]$AllTemplateFunctionsWithResource,
        [Parameter(Mandatory = $true)]
        [hashtable]$RegexPatterns,
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    $newFilesDiscovered = 0
    $iterationCount = 0
    $maxIterations = 5  # Prevent infinite loops

    # Performance optimization: Track searched functions to avoid duplicates
    $notFoundFunctions = @{}  # Functions we've searched for but not found

    Show-PhaseMessage -Message "Discovering Missing Test Configuration Function Dependencies" -BaseColor $BaseColor -InfoColor $InfoColor

    do {
        $iterationCount++
        $newDependenciesFound = $false

        # Get all current template functions from database
        $currentTemplateFunctions = Get-TemplateFunctions

        # PERFORMANCE OPTIMIZATION: Build lookup index for existing functions using database data
        $existingFunctionNames = @{}
        foreach ($func in $currentTemplateFunctions) {
            $existingFunctionNames[$func.TemplateFunctionName] = $true
        }

        # Find template function calls in current functions
        $missingFunctions = @{}
        foreach ($templateFunc in $currentTemplateFunctions) {
            $funcBody = $templateFunc.FunctionBody
            $receiverVar = $templateFunc.ReceiverVariable

            # Look for template function calls: receiverVar.functionName(
            if (-not [string]::IsNullOrEmpty($receiverVar)) {
                $callPattern = New-DynamicCallPattern -VariableName $receiverVar
                $functionMatches = $callPattern.Matches($funcBody)

                foreach ($match in $functionMatches) {
                    $calledFunctionName = $match.Groups[1].Value

                    # PERFORMANCE FIX: Use hashtable lookup instead of Where-Object
                    if (-not $existingFunctionNames.ContainsKey($calledFunctionName) -and -not $notFoundFunctions.ContainsKey($calledFunctionName)) {
                        # This is a missing dependency that we haven't searched for yet
                        if (-not $missingFunctions.ContainsKey($calledFunctionName)) {
                            $missingFunctions[$calledFunctionName] = @()
                        }
                        $missingFunctions[$calledFunctionName] += $templateFunc.FileRefId
                    }
                }
            }
        }

        # DATABASE-FIRST dependency search using file content from database
        if ($missingFunctions.Count -gt 0) {
            foreach ($missingFuncName in $missingFunctions.Keys) {
                $functionFound = $false

                # Search through all test files using database file content
                foreach ($fullPath in $AllTestFileNames) {
                    # Get content from database first, then from disk if needed
                    $content = Get-FileContent -FullPath $fullPath
                    if ([string]::IsNullOrWhiteSpace($content)) {
                        try {
                            $content = Get-Content $fullPath -Raw -ErrorAction SilentlyContinue
                            if ([string]::IsNullOrWhiteSpace($content)) { continue }
                        } catch {
                            continue
                        }
                    }

                    # Look for the specific missing function
                    $specificFuncPattern = "func\s+(?:\([^)]+\)\s+)?$([regex]::Escape($missingFuncName))\s*\([^)]*(?:acceptance\.TestData|TestData)[^)]*\)\s+string\s*\{((?:[^{}]+|\{(?:[^{}]+|\{[^{}]*\})*\})*)\}"
                    $specificMatch = [regex]::Match($content, $specificFuncPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

                    if ($specificMatch.Success) {
                        $functionFound = $true
                        $funcBody = $specificMatch.Groups[1].Value.Trim()
                        $relativePath = $fullPath.Replace($RepositoryDirectory, "").TrimStart('\').Replace("\", "/")

                        if (-not $AllTemplateFunctionsWithResource.ContainsKey($missingFuncName)) {
                            $AllTemplateFunctionsWithResource[$missingFuncName] = @()
                        }
                        $AllTemplateFunctionsWithResource[$missingFuncName] += $relativePath

                        # Add to database using database functions
                        $fileRefId = Get-FileRefIdByPath -FilePath $relativePath
                        if (-not $fileRefId) {
                            # Add the file to database first
                            $serviceRefId = Add-ServiceForFile -FilePath $relativePath
                            Add-FileRecord -FilePath $relativePath -ServiceRefId $serviceRefId | Out-Null
                            # Get the FileRefId for the newly added file
                            $fileRefId = Get-FileRefIdByPath -FilePath $relativePath
                        }

                            if ($fileRefId) {
                                # ENHANCED STRUCT RESOLUTION: Check receiver pattern first, then fallback to body parsing
                                $structRefId = $null
                                $receiverVariable = ""

                                # Phase 1: Check for receiver pattern (func (r LoadBalancerOutboundRule) method...)
                                $receiverMatch = $RegexPatterns.ReceiverMethod.Match($funcBody)
                                if ($receiverMatch.Success) {
                                    $receiverVariable = $receiverMatch.Groups[1].Value  # e.g., "r"
                                    $receiverStructName = $receiverMatch.Groups[2].Value  # e.g., "LoadBalancerOutboundRule"

                                    # Look up struct using database function
                                    $structRefId = Get-StructRefIdByName -StructName $receiverStructName
                                }

                                # Phase 2: If no receiver match, check function body for struct instantiations
                                if ($null -eq $structRefId) {
                                    # Look for patterns like: r := StructName{}
                                    $structInstantiationMatches = [regex]::Matches($funcBody, '(?:^|\s)(?:\w+)\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{\}')
                                    foreach ($match in $structInstantiationMatches) {
                                        $structName = $match.Groups[1].Value
                                        $structRefId = Get-StructRefIdByName -StructName $structName
                                        if ($structRefId) {
                                            break
                                        }
                                    }
                                }

                                # Phase 3: Final fallback - use same-file struct lookup (original logic)
                                if ($null -eq $structRefId) {
                                    $structs = Get-StructsByFileRefId -FileRefId $fileRefId
                                    $structRefId = if ($structs -and $structs.Count -gt 0) { $structs[0].StructRefId } else { $null }
                                }

                                # Add function to database
                                $templateFunctionRefId = Add-TemplateFunctionRecord -TemplateFunctionName $missingFuncName -StructRefId $structRefId -FileRefId $fileRefId -FunctionBody $funcBody -ReceiverVariable $receiverVariable

                                # PERFORMANCE OPTIMIZATION: Extract and store function calls for Phase 5 lookup
                                if (-not [string]::IsNullOrWhiteSpace($funcBody)) {
                                    # Extract struct references (e.g., "SomeStruct{")
                                    $structMatches = [regex]::Matches($funcBody, '\b([A-Z][a-zA-Z0-9_]*)\s*\{')
                                    foreach ($structMatch in $structMatches) {
                                        $structName = $structMatch.Groups[1].Value
                                        if ($structName -notmatch '^(if|for|switch|select)$') {
                                            Add-TemplateCallRecord -CallerTemplateFunctionRefId $templateFunctionRefId -CalledName $structName -CallType "struct"
                                        }
                                    }

                                    # Extract function calls (e.g., "receiverVar.FunctionName(")
                                    if (-not [string]::IsNullOrEmpty($receiverVariable)) {
                                        $funcCallMatches = [regex]::Matches($funcBody, "\b$([regex]::Escape($receiverVariable))\.(\w+)\(")
                                        foreach ($funcCallMatch in $funcCallMatches) {
                                            $calledFuncName = $funcCallMatch.Groups[1].Value
                                            Add-TemplateCallRecord -CallerTemplateFunctionRefId $templateFunctionRefId -CalledName $calledFuncName -CallType "function"
                                        }
                                    }
                                }

                                $newDependenciesFound = $true
                            }
                        }

                        if ($fileRefId) {
                            # ENHANCED STRUCT RESOLUTION: Check receiver pattern first, then fallback to body parsing
                            $structRefId = $null
                            $receiverVariable = ""

                            # Phase 1: Check for receiver pattern (func (r LoadBalancerOutboundRule) method...)
                            $receiverMatch = $RegexPatterns.ReceiverMethod.Match($funcBody)
                            if ($receiverMatch.Success) {
                                $receiverVariable = $receiverMatch.Groups[1].Value  # e.g., "r"
                                $receiverStructName = $receiverMatch.Groups[2].Value  # e.g., "LoadBalancerOutboundRule"

                                # Look up struct using database function
                                $structRefId = Get-StructRefIdByName -StructName $receiverStructName
                            }

                            # Phase 2: If no receiver match, check function body for struct instantiations
                            if ($null -eq $structRefId) {
                                # Look for patterns like: r := StructName{}
                                $structInstantiationMatches = [regex]::Matches($funcBody, '(?:^|\s)(?:\w+)\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{\}')
                                foreach ($match in $structInstantiationMatches) {
                                    $structName = $match.Groups[1].Value
                                    $structRefId = Get-StructRefIdByName -StructName $structName
                                    if ($structRefId) {
                                        break
                                    }
                                }
                            }

                            # Phase 3: Final fallback - use same-file struct lookup
                            if ($null -eq $structRefId) {
                                $structs = Get-StructsByFileRefId -FileRefId $fileRefId
                                $structRefId = if ($structs -and $structs.Count -gt 0) { $structs[0].StructRefId } else { $null }
                            }

                            # Add function to database
                            $templateFunctionRefId = Add-TemplateFunctionRecord -TemplateFunctionName $missingFuncName -StructRefId $structRefId -FileRefId $fileRefId -FunctionBody $funcBody -ReceiverVariable $receiverVariable

                            # PERFORMANCE OPTIMIZATION: Extract and store function calls for Phase 5 lookup
                            if (-not [string]::IsNullOrWhiteSpace($funcBody)) {
                                # Extract struct references (e.g., "SomeStruct{")
                                $structMatches = [regex]::Matches($funcBody, '\b([A-Z][a-zA-Z0-9_]*)\s*\{')
                                foreach ($structMatch in $structMatches) {
                                    $structName = $structMatch.Groups[1].Value
                                    $referencedStructRefId = Get-StructRefIdByName -StructName $structName
                                    if ($referencedStructRefId) {
                                        Add-TemplateReferenceRecord -TemplateFunctionRefId $templateFunctionRefId -StructRefId $referencedStructRefId | Out-Null
                                    }
                                }
                            }

                            $newDependenciesFound = $true
                            $newFilesDiscovered++
                        }
                        break  # Found the function, move to next missing function
                    }
                }

                # Mark this function as searched (whether found or not)
                if (-not $functionFound) {
                    $notFoundFunctions[$missingFuncName] = $true
                }
            }
    } while ($newDependenciesFound -and $iterationCount -lt $maxIterations)

    return @{
        NewFilesDiscovered = $newFilesDiscovered
        IterationCount = $iterationCount
        UpdatedTemplateFunctions = $AllTemplateFunctionsWithResource
    }
}

Export-ModuleMember -Function Invoke-TemplateFunctionProcessing, Invoke-DynamicTemplateDependencyDiscovery
