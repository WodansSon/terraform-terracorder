# TestFunctionSteps Processing Module
# Handles both regular TestStep arrays and sequential pattern functions
# Creates unified step-level analysis with proper ReferenceType classification

# PERFORMANCE OPTIMIZATION: Precompiled regex patterns to avoid recompiling thousands of times
$script:ConfigRegexVariableMethod = [regex]::new('Config:\s*(\w+)\.(\w+)', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$script:ConfigRegexStructMethod = [regex]::new('Config:\s*([A-Za-z][A-Za-z0-9_]*)\{\}\.(\w+)', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$script:ConfigRegexLegacyFunction = [regex]::new('Config:\s*func\s*\([^)]*\)\s*[^{]*\{\s*return\s+(\w+)\.(\w+)\s*\(', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$script:ConfigRegexHelperFunction = [regex]::new('Config:\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\([^)]*\)', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$script:StructAssignmentRegex = [regex]::new('(?:^|\s)(\w+)\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{\}', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$script:StructMethodCallRegex = [regex]::new('([A-Z][A-Za-z0-9_]*)\{\}\.', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$script:TestResourceRegex = [regex]::new('TestResource:\s*(\w+)', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$script:TestStepArrayRegex = [regex]::new('\[\]acceptance\.TestStep\s*\{', [System.Text.RegularExpressions.RegexOptions]::Compiled)

# Note: Variable-specific patterns like FunctionCallAssignmentRegex, StructLiteralAssignmentRegex,
# and VariableDeclarationRegex must be created dynamically when the variable name is known

#region Pattern Strategy Functions - Clean Architecture

<#
.SYNOPSIS
Clean architecture pattern strategies to replace nested if-else chains

.DESCRIPTION
These functions implement the Strategy Pattern to eliminate the "nasty web of if-else statements"
while preserving performance through optimized lookups and pre-compiled regex patterns.
#>

function Get-ConfigVariablePattern {
    <#
    .SYNOPSIS
    Detects and extracts Config: variable.method patterns

    .DESCRIPTION
    Pure function that identifies Config: r.basic(data) patterns and extracts variable name and method
    #>
    param(
        [string]$StepBody
    )

    $match = $script:ConfigRegexVariableMethod.Match($StepBody)
    if ($match.Success) {
        return @{
            IsMatch = $true
            VariableName = $match.Groups[1].Value
            MethodName = $match.Groups[2].Value
            PatternType = 'ConfigVariable'
        }
    }

    return @{ IsMatch = $false }
}

function Get-DirectStructPattern {
    <#
    .SYNOPSIS
    Detects and extracts direct struct method call patterns

    .DESCRIPTION
    Pure function that identifies StructName{}.method patterns
    #>
    param(
        [string]$StepBody
    )

    $match = $script:ConfigRegexStructMethod.Match($StepBody)
    if ($match.Success) {
        return @{
            IsMatch = $true
            StructName = $match.Groups[1].Value
            MethodName = $match.Groups[2].Value
            PatternType = 'DirectStruct'
        }
    }

    return @{ IsMatch = $false }
}

function Get-TestResourcePattern {
    <#
    .SYNOPSIS
    Detects and extracts TestResource: variable patterns

    .DESCRIPTION
    Pure function that identifies TestResource: variable patterns
    #>
    param(
        [string]$StepBody
    )

    $match = $script:TestResourceRegex.Match($StepBody)
    if ($match.Success) {
        return @{
            IsMatch = $true
            VariableName = $match.Groups[1].Value
            PatternType = 'TestResource'
        }
    }

    return @{ IsMatch = $false }
}

function Get-LegacyFunctionPattern {
    <#
    .SYNOPSIS
    Detects and extracts legacy anonymous function patterns

    .DESCRIPTION
    Pure function that identifies Config: func(...) { return variable.method(...) } patterns
    #>
    param(
        [string]$StepBody
    )

    $match = $script:ConfigRegexLegacyFunction.Match($StepBody)
    if ($match.Success) {
        return @{
            IsMatch = $true
            VariableName = $match.Groups[1].Value
            MethodName = $match.Groups[2].Value
            PatternType = 'LegacyFunction'
        }
    }

    return @{ IsMatch = $false }
}

function Get-EmbeddedStructPattern {
    <#
    .SYNOPSIS
    Detects and extracts embedded struct assignment patterns

    .DESCRIPTION
    Pure function that identifies variable := StructName{} patterns within step body
    #>
    param(
        [string]$StepBody
    )

    $match = $script:StructAssignmentRegex.Match($StepBody)
    if ($match.Success) {
        return @{
            IsMatch = $true
            VariableName = $match.Groups[1].Value
            StructName = $match.Groups[2].Value
            PatternType = 'EmbeddedStruct'
        }
    }

    return @{ IsMatch = $false }
}

function Get-HelperFunctionPattern {
    <#
    .SYNOPSIS
    Detects and extracts helper function call patterns

    .DESCRIPTION
    Pure function that identifies Config: helperFunction(data) patterns
    #>
    param(
        [string]$StepBody
    )

    $match = $script:ConfigRegexHelperFunction.Match($StepBody)
    if ($match.Success) {
        return @{
            IsMatch = $true
            FunctionName = $match.Groups[1].Value
            PatternType = 'HelperFunction'
        }
    }

    return @{ IsMatch = $false }
}

#endregion

#region Struct Resolution Strategy Functions

function Resolve-StructFromLiteralAssignment {
    <#
    .SYNOPSIS
    Resolves struct name from literal assignment patterns

    .DESCRIPTION
    Pure function that finds variable := StructName{} patterns in function body
    #>
    param(
        [string]$FunctionBody,
        [string]$VariableName
    )

    $pattern = "(?:^|\s)" + [regex]::Escape($VariableName) + "\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{"
    if ($FunctionBody -match $pattern) {
        return @{
            IsResolved = $true
            StructName = $matches[1]
            ResolverType = 'LiteralAssignment'
        }
    }

    return @{ IsResolved = $false }
}

function Resolve-StructFromFunctionCall {
    <#
    .SYNOPSIS
    Resolves struct name from function call assignment patterns

    .DESCRIPTION
    Pure function that finds variable := functionName() patterns and converts to struct names
    #>
    param(
        [string]$FunctionBody,
        [string]$VariableName
    )

    $pattern = "(?:^|\s)" + [regex]::Escape($VariableName) + "\s*:=\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\("
    if ($FunctionBody -match $pattern) {
        $functionName = $matches[1]

        # Convert function name to struct name using common patterns
        $structName = if ($functionName -match '^new(.+)Resource$') {
            $matches[1] + "Resource"
        } elseif ($functionName -match '^new(.+)$') {
            $matches[1]
        } else {
            # Fallback: capitalize first letter
            $functionName.Substring(0,1).ToUpper() + $functionName.Substring(1)
        }

        return @{
            IsResolved = $true
            StructName = $structName
            ResolverType = 'FunctionCall'
        }
    }

    return @{ IsResolved = $false }
}

function Resolve-StructFromVariableDeclaration {
    <#
    .SYNOPSIS
    Resolves struct name from variable declaration patterns

    .DESCRIPTION
    Pure function that finds var variable StructName patterns in function body
    #>
    param(
        [string]$FunctionBody,
        [string]$VariableName
    )

    $pattern = "(?:^|\s)var\s+" + [regex]::Escape($VariableName) + "\s+([A-Z][A-Za-z0-9_]*)\s*(?:\n|$|\s)"
    if ($FunctionBody -match $pattern) {
        return @{
            IsResolved = $true
            StructName = $matches[1]
            ResolverType = 'VariableDeclaration'
        }
    }

    return @{ IsResolved = $false }
}

function Resolve-StructName {
    <#
    .SYNOPSIS
    Orchestrates struct name resolution using multiple strategies

    .DESCRIPTION
    Clean pipeline that tries each resolution strategy in order until one succeeds
    #>
    param(
        [string]$FunctionBody,
        [string]$VariableName
    )

    # Strategy 1: Literal assignment (r := StructName{})
    $literalResult = Resolve-StructFromLiteralAssignment -FunctionBody $FunctionBody -VariableName $VariableName
    if ($literalResult.IsResolved) {
        return $literalResult
    }

    # Strategy 2: Function call assignment (r := newStructNameResource())
    $functionResult = Resolve-StructFromFunctionCall -FunctionBody $FunctionBody -VariableName $VariableName
    if ($functionResult.IsResolved) {
        return $functionResult
    }

    # Strategy 3: Variable declaration (var r StructName)
    $varResult = Resolve-StructFromVariableDeclaration -FunctionBody $FunctionBody -VariableName $VariableName
    if ($varResult.IsResolved) {
        return $varResult
    }

    return @{ IsResolved = $false }
}

#endregion

#region Reference Type Classification Functions

function Get-ReferenceTypeForSameFileStruct {
    <#
    .SYNOPSIS
    Determines reference type for same-file struct references

    .DESCRIPTION
    Pure function that classifies reference types when struct is in the same file
    #>
    param(
        [string]$PatternType,
        [bool]$IsLegacyPattern = $false
    )

    if ($IsLegacyPattern) {
        return 9  # ANONYMOUS_FUNCTION_REFERENCE
    }

    switch ($PatternType) {
        'EmbeddedStruct' { return 1 }      # SELF_CONTAINED (assignment pattern)
        'ConfigVariable' { return 1 }      # SELF_CONTAINED (variable method call)
        'DirectStruct' { return 3 }        # SELF_EMBEDDED (method call pattern)
        'TestResource' { return 3 }        # SELF_EMBEDDED (TestResource pattern)
        default { return 1 }               # SELF_CONTAINED (fallback)
    }
}

function Get-ReferenceTypeForCrossFile {
    <#
    .SYNOPSIS
    Determines reference type for cross-file struct references

    .DESCRIPTION
    Pure function that classifies reference types when struct is in a different file
    #>
    param(
        [bool]$IsLegacyPattern = $false
    )

    if ($IsLegacyPattern) {
        return 9  # ANONYMOUS_FUNCTION_REFERENCE
    }

    return 2  # CROSS_FILE (deferred resolution)
}

function Test-IsLegacyPattern {
    <#
    .SYNOPSIS
    Detects legacy function patterns that require special handling

    .DESCRIPTION
    Pure function that identifies patterns requiring ANONYMOUS_FUNCTION_REFERENCE classification
    #>
    param(
        [string]$FunctionBody,
        [string]$PatternType
    )

    # Legacy function pattern is always legacy
    if ($PatternType -eq 'LegacyFunction') {
        return $true
    }

    # TestResource with legacy step patterns
    if ($PatternType -eq 'TestResource' -and $FunctionBody -match '(DisappearsStep|ApplyStep|ImportStep|PlanOnlyStep)') {
        return $true
    }

    return $false
}

#endregion

function Resolve-TestStepObjects {
    <#
    .SYNOPSIS
    Parse individual test step objects from TestStep array content

    .DESCRIPTION
    Identifies and extracts individual test step objects like:
    {
        Config: r.basic(data),
        Check: resource.ComposeTestCheckFunc(...)
    }

    .PARAMETER StepsContent
    The content inside the []resource.TestStep{...} array
    #>
    param(
        [string]$StepsContent
    )

    $steps = @()
    $braceCount = 0
    $currentStep = ""
    $inString = $false
    $escapeNext = $false
    $inTestStepObject = $false

    for ($i = 0; $i -lt $StepsContent.Length; $i++) {
        $char = $StepsContent[$i]

        if ($escapeNext) {
            $currentStep += $char
            $escapeNext = $false
            continue
        }

        if ($char -eq '\') {
            $escapeNext = $true
            $currentStep += $char
            continue
        }

        if ($char -eq '"' -and !$escapeNext) {
            $inString = !$inString
            $currentStep += $char
            continue
        }

        if (!$inString) {
            if ($char -eq '{') {
                if ($braceCount -eq 0) {
                    # Starting a new test step object
                    $inTestStepObject = $true
                    $currentStep = ""
                }
                $braceCount++
                $currentStep += $char
            } elseif ($char -eq '}') {
                $braceCount--
                $currentStep += $char

                if ($braceCount -eq 0 -and $inTestStepObject) {
                    # Completed a test step object
                    $trimmedStep = $currentStep.Trim()
                    if ($trimmedStep -and $trimmedStep.Length -gt 2) {  # Must be more than just {}
                        # Verify this looks like a test step (contains Config: or Check: or similar)
                        if ($Global:RegexPatterns.TestStepFieldPattern.IsMatch($trimmedStep)) {
                            # Check if this is entirely commented out
                            $lines = $trimmedStep -split "`n"
                            $isCommentedOut = $true

                            foreach ($line in $lines) {
                                $cleanLine = $line.Trim()
                                # Skip empty lines and lines that are just braces
                                if ($cleanLine -and $cleanLine -ne '{' -and $cleanLine -ne '}') {
                                    # If we find a non-empty line that doesn't start with //, it's not fully commented
                                    if (-not $cleanLine.StartsWith('//')) {
                                        $isCommentedOut = $false
                                        break
                                    }
                                }
                            }

                            # Only add if not entirely commented out
                            if (-not $isCommentedOut) {
                                $steps += $trimmedStep
                            }
                        }
                    }
                    $inTestStepObject = $false
                    $currentStep = ""
                }
            } else {
                $currentStep += $char
            }
        } else {
            $currentStep += $char
        }
    }

    return $steps
}

# TODO: REMOVE AFTER PERFORMANCE TESTING - OLD IMPLEMENTATION FOR REFERENCE
# This function uses nested loops for struct lookups - inefficient
function Resolve-InlineTestSteps {
    param(
        [PSCustomObject]$TestFunction
    )

    $steps = @()

    # Look for TestStep array patterns - more robust approach
    $stepsContent = $null

    # First try to find the start of TestStep array
    if ($TestFunction.FunctionBody -match '\[\]acceptance\.TestStep\s*\{') {
        # Find the position of this match
        $startPos = $TestFunction.FunctionBody.IndexOf($matches[0]) + $matches[0].Length

        # Now find the matching closing brace by counting braces
        $braceCount = 0
        $endPos = $startPos
        $inString = $false
        $escapeNext = $false

        for ($i = $startPos; $i -lt $TestFunction.FunctionBody.Length; $i++) {
            $char = $TestFunction.FunctionBody[$i]

            if ($escapeNext) {
                $escapeNext = $false
                continue
            }

            if ($char -eq '\') {
                $escapeNext = $true
                continue
            }

            if ($char -eq '"' -and !$escapeNext) {
                $inString = !$inString
                continue
            }

            if (!$inString) {
                if ($char -eq '{') {
                    $braceCount++
                } elseif ($char -eq '}') {
                    $braceCount--
                    if ($braceCount -lt 0) {
                        $endPos = $i
                        break
                    }
                }
            }
        }

        if ($endPos -gt $startPos) {
            $stepsContent = $TestFunction.FunctionBody.Substring($startPos, $endPos - $startPos)
        }
    }

    if ($stepsContent) {

        # Parse individual test step objects { Config: ..., Check: ... }
        $stepBodies = Resolve-TestStepObjects $stepsContent
        $stepIndex = 1

        foreach ($stepBody in $stepBodies) {
            if (-not $stepBody.Trim()) { continue }

            $configTemplate = $null
            $structRefId = $null
            $referenceTypeId = 1  # Default to SELF_CONTAINED

            # Extract config template reference (r.method or StructName{}.method)
            if ($stepBody -match 'Config:\s*(\w+)\.(\w+)') {
                $variableName = $matches[1]
                $methodName = $matches[2]

                # Resolve variable to actual struct type by looking for assignment in function body
                if ($TestFunction.FunctionBody -match "(?:^|\s)$variableName\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{\}") {
                    $actualStructName = $matches[1]
                    $configTemplate = "$actualStructName.$methodName"
                } else {
                    # Fallback to variable name if can't resolve
                    $configTemplate = "$variableName.$methodName"
                }
            }
            # Also handle direct struct method calls in Config
            elseif ($stepBody -match 'Config:\s*([A-Z][A-Za-z0-9_]*)\{\}\.(\w+)') {
                $configTemplate = "$($matches[1]){}.$($matches[2])"
            }

            # Check for struct patterns - THREE STEP RESOLUTION:
            # Step 1: Only assignment patterns can be resolved immediately (self-contained)
            # Step 2: Other patterns are marked for later resolution in Phase 4a.6
            # Step 3: Variable-based method calls are marked for deferred resolution

            # Pattern 1: Assignment pattern - variable := StructName{} (can resolve immediately)
            if ($stepBody -match '(?:^|\s)(\w+)\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{\}') {
                $structName = $matches[2]

                # Try to find struct in same file for immediate resolution
                $sameFileStructs = Get-StructsByFileRefId -FileRefId $TestFunction.FileRefId
                $sameFileStruct = $null
                foreach ($struct in $sameFileStructs) {
                    if ($struct.StructName -eq $structName) {
                        $sameFileStruct = $struct
                        break
                    }
                }

                if ($sameFileStruct) {
                    $structRefId = $sameFileStruct.StructRefId
                    $referenceTypeId = 1  # SELF_CONTAINED
                } else {
                    # Assignment pattern but cross-file - mark for later resolution
                    $structRefId = $null
                    $referenceTypeId = 2  # CROSS_FILE

                }
            }
            # Pattern 2: Method call pattern - StructName{}.Method (defer resolution but check if same file)
            elseif ($stepBody -match '([A-Z][A-Za-z0-9_]*)\{\}\.') {
                $structName = $matches[1]

                # Check if this struct exists in the same file for proper categorization
                $sameFileStructs = Get-StructsByFileRefId -FileRefId $TestFunction.FileRefId
                $sameFileStruct = $null
                foreach ($struct in $sameFileStructs) {
                    if ($struct.StructName -eq $structName) {
                        $sameFileStruct = $struct
                        break
                    }
                }

                if ($sameFileStruct) {
                    # Same file but method call - this is SELF_EMBEDDED
                    $structRefId = $null  # Still defer resolution for method calls
                    $referenceTypeId = 3  # SELF_EMBEDDED (same file, method call pattern)

                } else {
                    # Different file - this is CROSS_FILE
                    $structRefId = $null
                    $referenceTypeId = 2  # CROSS_FILE (deferred resolution)

                }
            }
            # Pattern 3: Variable-based method calls - Config: variable.method (defer resolution)
            elseif ($stepBody -match 'Config:\s*(\w+)\.(\w+)') {
                $variableName = $matches[1]

                # Look for variable assignment in the full function body to determine same-file vs cross-file
                # Pattern 3a: Struct literal assignment - r := StructName{} or r := StructName{field: value}
                if ($TestFunction.FunctionBody -match "(?:^|\s)$variableName\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{") {
                    $structName = $matches[1]
                }
                # Pattern 3b: Function call assignment - r := newStructNameResource()
                elseif ($TestFunction.FunctionBody -match "(?:^|\s)$variableName\s*:=\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\(") {
                    $functionName = $matches[1]
                    # Convert function name to potential struct name using common patterns
                    # e.g., newSoftwareUpdateConfigurationResource() -> SoftwareUpdateConfigurationResource
                    if ($functionName -match '^new(.+)Resource$') {
                        $structName = $matches[1] + "Resource"
                    } elseif ($functionName -match '^new(.+)$') {
                        $structName = $matches[1]
                    } else {
                        # Fallback: capitalize first letter and assume it's the struct name
                        $structName = $functionName.Substring(0,1).ToUpper() + $functionName.Substring(1)
                    }

                }
                # Pattern 3c: Variable declaration - var variable StructName
                elseif ($TestFunction.FunctionBody -match "(?:^|\s)var\s+$variableName\s+([A-Z][A-Za-z0-9_]*)\s*(?:\n|$|\s)") {
                    $structName = $matches[1]

                }

                # Now resolve the struct if we found one
                if ($structName) {
                    # Check if this struct exists in the same file for proper categorization
                    $sameFileStructs = Get-StructsByFileRefId -FileRefId $TestFunction.FileRefId
                    $sameFileStruct = $null
                    foreach ($struct in $sameFileStructs) {
                        if ($struct.StructName -eq $structName) {
                            $sameFileStruct = $struct
                            break
                        }
                    }

                    if ($sameFileStruct) {
                        # Same file - resolve immediately for SELF_CONTAINED
                        $structRefId = $sameFileStruct.StructRefId
                        $referenceTypeId = 1  # SELF_CONTAINED (same file, variable method call)

                    } else {
                        # Different file - mark for cross-file resolution
                        $structRefId = $null
                        $referenceTypeId = 2  # CROSS_FILE (deferred resolution)

                    }
                } else {
                    # Can't resolve variable assignment - mark for deferred resolution
                    $structRefId = $null
                    $referenceTypeId = 2  # CROSS_FILE (deferred resolution)

                }
            }
            # Pattern 4: TestResource reference - TestResource: variable (defer resolution)
            elseif ($stepBody -match 'TestResource:\s*(\w+)') {
                $variableName = $matches[1]

                # Check if this is a legacy function pattern (DisappearsStep, ApplyStep, etc.)
                $isLegacyPattern = $false
                if ($TestFunction.FunctionBody -match '(DisappearsStep|ApplyStep|ImportStep|PlanOnlyStep)') {
                    $isLegacyPattern = $true

                }

                # Look for variable assignment in the full function body to determine same-file vs cross-file
                # Pattern 4a: Struct literal assignment - r := StructName{} or r := StructName{field: value}
                if ($TestFunction.FunctionBody -match "(?:^|\s)$variableName\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{") {
                    $structName = $matches[1]
                }
                # Pattern 4b: Function call assignment - r := newStructNameResource()
                elseif ($TestFunction.FunctionBody -match "(?:^|\s)$variableName\s*:=\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\(") {
                    $functionName = $matches[1]
                    # Convert function name to potential struct name using common patterns
                    if ($functionName -match '^new(.+)Resource$') {
                        $structName = $matches[1] + "Resource"
                    } elseif ($functionName -match '^new(.+)$') {
                        $structName = $matches[1]
                    } else {
                        # Fallback: capitalize first letter and assume it's the struct name
                        $structName = $functionName.Substring(0,1).ToUpper() + $functionName.Substring(1)
                    }

                }
                # Pattern 4c: Variable declaration - var variable StructName
                elseif ($TestFunction.FunctionBody -match "(?:^|\s)var\s+$variableName\s+([A-Z][A-Za-z0-9_]*)\s*(?:\n|$|\s)") {
                    $structName = $matches[1]

                }

                # Set appropriate reference type based on legacy pattern detection
                if ($isLegacyPattern) {
                    $referenceTypeId = 9  # ANONYMOUS_FUNCTION_REFERENCE

                }

                if ($structName) {
                    # For Pattern 4 (TestResource): Check if anonymous function pattern already set the reference type
                    if ($referenceTypeId -ne 9) {  # If not already set to ANONYMOUS_FUNCTION_REFERENCE
                        # Check if this struct exists in the same file for proper categorization
                        $sameFileStructs = Get-StructsByFileRefId -FileRefId $TestFunction.FileRefId
                        $sameFileStruct = $null
                        foreach ($struct in $sameFileStructs) {
                            if ($struct.StructName -eq $structName) {
                                $sameFileStruct = $struct
                                break
                            }
                        }

                        if ($sameFileStruct) {
                            # Same file - this is SELF_EMBEDDED (TestResource pattern, same file)
                            $structRefId = $null  # Defer resolution to maintain consistency
                            $referenceTypeId = 3  # SELF_EMBEDDED

                        } else {
                            # Different file - this is CROSS_FILE
                            $structRefId = $null
                            $referenceTypeId = 2  # CROSS_FILE (deferred resolution)

                        }
                    }
                    # If already set to ANONYMOUS_FUNCTION_REFERENCE (9), keep it as is
                } else {
                    # Can't resolve TestResource variable assignment - use appropriate fallback
                    $structRefId = $null
                    if ($referenceTypeId -ne 9) {  # If not already set to ANONYMOUS_FUNCTION_REFERENCE
                        $referenceTypeId = 2  # CROSS_FILE (deferred resolution)

                    }
                }
            }
            # Pattern 5: Legacy function pattern - Config: func(...) { return variable.method(...) }
            elseif ($stepBody -match 'Config:\s*func\s*\([^)]*\)\s*[^{]*\{\s*return\s+(\w+)\.(\w+)\s*\(') {
                $variableName = $matches[1]

                # This is always a legacy pattern since it uses anonymous function in Config
                $isLegacyPattern = $true


                # Look for variable assignment in the full function body to determine same-file vs cross-file
                # Pattern 5a: Struct literal assignment - r := StructName{} or r := StructName{field: value}
                if ($TestFunction.FunctionBody -match "(?:^|\s)$variableName\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{") {
                    $structName = $matches[1]
                }
                # Pattern 5b: Function call assignment - r := newStructNameResource()
                elseif ($TestFunction.FunctionBody -match "(?:^|\s)$variableName\s*:=\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\(") {
                    $functionName = $matches[1]
                    # Convert function name to potential struct name using common patterns
                    if ($functionName -match '^new(.+)Resource$') {
                        $structName = $matches[1] + "Resource"
                    } elseif ($functionName -match '^new(.+)$') {
                        $structName = $matches[1]
                    } else {
                        # Fallback: capitalize first letter and assume it's the struct name
                        $structName = $functionName.Substring(0,1).ToUpper() + $functionName.Substring(1)
                    }

                }
                # Pattern 5c: Variable declaration - var variable StructName
                elseif ($TestFunction.FunctionBody -match "(?:^|\s)var\s+$variableName\s+([A-Z][A-Za-z0-9_]*)\s*(?:\n|$|\s)") {
                    $structName = $matches[1]

                }

                # Always use ANONYMOUS_FUNCTION_REFERENCE for Pattern 5 (anonymous Config functions)
                $referenceTypeId = 9  # ANONYMOUS_FUNCTION_REFERENCE


                if ($structName) {
                    # Pattern 5 always uses ANONYMOUS_FUNCTION_REFERENCE, no need to check file location
                    # Already set above: $referenceTypeId = 9  # ANONYMOUS_FUNCTION_REFERENCE
                } else {
                    # Can't resolve anonymous Config variable assignment - keep ANONYMOUS_FUNCTION_REFERENCE
                    $structRefId = $null
                    # Already set above: $referenceTypeId = 9  # ANONYMOUS_FUNCTION_REFERENCE

                }
            }
            # Pattern 6: Edge case fallback - use StructRefId when no other patterns match
            else {
                # This handles edge cases like Config: basicConfig, Config: config, Config: functionCall(data), etc.
                # Use the function's primary struct as fallback for unresolved patterns
                if ($TestFunction.StructRefId -and $TestFunction.StructRefId -ne "" -and $TestFunction.StructRefId -ne "0") {
                    $structRefId = $TestFunction.StructRefId
                    $referenceTypeId = 1  # SELF_CONTAINED (function's primary struct)

                } else {
                    # Pattern 6a: Helper function call pattern - Config: helperFunction(data)
                    if ($stepBody -match 'Config:\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\([^)]*\)') {
                        # For data source tests, try to infer the main resource struct
                        if ($TestFunction.FunctionName -match 'DataSource.*_(.+)$') {
                            # Try to find a matching resource struct by converting DataSource pattern to Resource pattern
                            # e.g., TestAccKustoClusterDataSource_basic -> KustoClusterResource
                            if ($TestFunction.FunctionName -match 'TestAcc([A-Z][a-zA-Z0-9_]*)DataSource') {
                                $baseStructName = $matches[1] + "Resource"
                                # Look for this struct in the database
                                $inferredStructRefId = Get-StructRefIdByName -StructName $baseStructName
                                if ($inferredStructRefId) {
                                    $structRefId = $inferredStructRefId
                                    $referenceTypeId = 2  # CROSS_FILE (inferred from data source pattern)

                                }
                            }
                        }
                    }

                    # Pattern 6b: Receiver variable pattern that failed cross-file resolution
                    elseif ($stepBody -match 'Config:\s*(\w+)\.(\w+)' -and $configTemplate) {
                        $variableName = $matches[1]
                        # If we have a ConfigTemplate but no struct resolution, try naming patterns
                        if ($configTemplate -match '^([a-z]+)\.') {
                            # Try common struct naming patterns based on function name
                            if ($TestFunction.FunctionName -match 'TestAcc([A-Z][a-zA-Z0-9_]*)') {
                                $baseStructName = $matches[1] + "Resource"
                                $inferredStructRefId = Get-StructRefIdByName -StructName $baseStructName
                                if ($inferredStructRefId) {
                                    $structRefId = $inferredStructRefId
                                    $referenceTypeId = 2  # CROSS_FILE (inferred from naming pattern)

                                }
                            }
                        }
                    }

                    # If still not resolved, mark as external reference
                    if (-not $structRefId) {
                        $structRefId = $null
                        $referenceTypeId = 10  # EXTERNAL_REFERENCE (external dependencies not in our codebase)

                    }
                }
            }

            # Determine initial visibility based on function name (Go convention)
            $initialVisibility = if ($TestFunction.FunctionName -cmatch '^[a-z]') { 11 } else { 12 }  # PRIVATE_REFERENCE : PUBLIC_REFERENCE

            $step = @{
                TestFunctionRefId = $TestFunction.TestFunctionRefId
                StepIndex = $stepIndex
                StepBody = $stepBody.Trim()
                ConfigTemplate = $configTemplate
                StructRefId = $structRefId
                ReferenceTypeId = $referenceTypeId
                StructVisibilityTypeId = $initialVisibility
            }

            $steps += $step
            $stepIndex++
        }
    }

    return $steps
}

function Invoke-TestFunctionSteps {
    param(
        [PSCustomObject]$TestFunction
    )

    $steps = @()

    # Regular function - parse inline TestStep array
    $inlineSteps = Resolve-InlineTestSteps $TestFunction

    if ($inlineSteps.Count -gt 0) {
        $steps = $inlineSteps
    }

    return $steps
}

function Add-TestFunctionStep {
    param(
        [int]$TestFunctionRefId,
        [int]$StepIndex,
        [string]$StepBody,
        [string]$ConfigTemplate,
        [object]$StructRefId,
        [int]$ReferenceTypeId,
        [int]$StructVisibilityTypeId = 12  # Default to PUBLIC_REFERENCE
    )

    # Use the hashtable-based database system instead of SQLite
    return Add-TestFunctionStepRecord -TestFunctionRefId $TestFunctionRefId `
                                    -StepIndex $StepIndex `
                                    -StepBody $StepBody `
                                    -ConfigTemplate $ConfigTemplate `
                                    -StructRefId $StructRefId `
                                    -ReferenceTypeId $ReferenceTypeId `
                                    -StructVisibilityTypeId $StructVisibilityTypeId
}

# OPTIMIZED DATABASE-FIRST IMPLEMENTATION
function Update-CrossFileStructReferencesInSteps {
    <#
    .SYNOPSIS
    Database-first optimized version that eliminates nested loops and uses pre-built lookup tables

    .DESCRIPTION
    Performance improvements:
    - Pre-builds lookup tables once instead of repeated database calls
    - Uses O(1) hashtable lookups instead of O(n) nested loops
    - Batches struct name resolution instead of individual calls
    - Eliminates redundant regex parsing of function bodies
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    Show-PhaseMessage -Message "Resolving Test Namespace References" -BaseColor $BaseColor -InfoColor $InfoColor

    # Get steps efficiently from the database using O(1) indexed lookups
    $crossFileSteps = Get-TestFunctionStepsByReferenceType -ReferenceTypeId 2
    $selfEmbeddedSteps = Get-TestFunctionStepsByReferenceType -ReferenceTypeId 3
    $resolvedCount = 0
    $privateCount = 0

    # Ensure we have arrays and safe count calculation
    $crossFileSteps = @($crossFileSteps)
    $selfEmbeddedSteps = @($selfEmbeddedSteps)
    $totalReferences = $crossFileSteps.Count + $selfEmbeddedSteps.Count
    Show-PhaseMessageHighlight -Message "Processing $($totalReferences) Namespace References" -HighlightText $totalReferences -HighlightColor $NumberColor -BaseColor $BaseColor -InfoColor $InfoColor

    # OPTIMIZATION 1: Pre-build all lookup tables once instead of repeated calls
    # Show-PhaseMessage -Message "Building optimized lookup tables..."

    # Build FileRefId -> Structs lookup table (O(1) instead of repeated Get-StructsByFileRefId calls)
    $fileToStructsLookup = @{}
    $allStructs = Get-Structs
    foreach ($struct in $allStructs) {
        $fileRefId = $struct.FileRefId
        if (-not $fileToStructsLookup.ContainsKey($fileRefId)) {
            $fileToStructsLookup[$fileRefId] = @{}
        }
        $fileToStructsLookup[$fileRefId][$struct.StructName] = $struct
    }

    # Build StructName -> StructRefId lookup table (batch all at once)
    $structNameToIdLookup = @{}
    foreach ($struct in $allStructs) {
        $structNameToIdLookup[$struct.StructName] = $struct.StructRefId
    }

    # Build TestFunctionRefId -> TestFunction lookup table (avoid repeated Get-TestFunctionById calls)
    $uniqueFunctionIds = ($crossFileSteps + $selfEmbeddedSteps | Select-Object -Property TestFunctionRefId -Unique).TestFunctionRefId
    $functionLookup = @{}
    foreach ($funcId in $uniqueFunctionIds) {
        $functionLookup[$funcId] = Get-TestFunctionById -TestFunctionRefId $funcId
    }

    # Show-PhaseMessage -Message "Database indexes built successfully"

    # OPTIMIZATION 2: Process steps with direct hashtable lookups instead of nested loops
    $stepsToResolve = $crossFileSteps + $selfEmbeddedSteps

    foreach ($step in $stepsToResolve) {
        # Extract struct name from step body using multiple resolution strategies
        $structName = $null

        # OPTIMIZATION 3: Use pre-built function lookup instead of database call
        $testFunction = $functionLookup[$step.TestFunctionRefId]
        if (-not $testFunction) {
            Write-Warning "Could not find test function for step $($step.TestFunctionStepRefId)"
            continue
        }

        # CLEAN ARCHITECTURE: Use pattern strategy functions instead of nested if-else chains
        $structName = $null

        # Pattern Detection Pipeline - systematic approach using strategy functions
        $embeddedStructResult = Get-EmbeddedStructPattern -StepBody $step.StepBody
        if ($embeddedStructResult.IsMatch) {
            $structName = $embeddedStructResult.StructName
        } else {
            $directStructResult = Get-DirectStructPattern -StepBody $step.StepBody
            if ($directStructResult.IsMatch) {
                $structName = $directStructResult.StructName
            } else {
                $configVarResult = Get-ConfigVariablePattern -StepBody $step.StepBody
                if ($configVarResult.IsMatch) {
                    # Use clean struct resolution strategy
                    $structResolution = Resolve-StructName -FunctionBody $testFunction.FunctionBody -VariableName $configVarResult.VariableName
                    if ($structResolution.IsResolved) {
                        $structName = $structResolution.StructName
                    }
                } else {
                    $testResourceResult = Get-TestResourcePattern -StepBody $step.StepBody
                    if ($testResourceResult.IsMatch) {
                        # Use clean struct resolution strategy
                        $structResolution = Resolve-StructName -FunctionBody $testFunction.FunctionBody -VariableName $testResourceResult.VariableName
                        if ($structResolution.IsResolved) {
                            $structName = $structResolution.StructName
                        }
                    } else {
                        $legacyFuncResult = Get-LegacyFunctionPattern -StepBody $step.StepBody
                        if ($legacyFuncResult.IsMatch) {
                            # Use clean struct resolution strategy
                            $structResolution = Resolve-StructName -FunctionBody $testFunction.FunctionBody -VariableName $legacyFuncResult.VariableName
                            if ($structResolution.IsResolved) {
                                $structName = $structResolution.StructName
                            }
                        }
                    }
                }
            }
        }

        if ($structName) {
            # OPTIMIZATION 4: Use pre-built lookup table instead of Get-StructRefIdByName database call
            $structRefId = $structNameToIdLookup[$structName]

            if ($structRefId) {
                # Check if this is a private struct (starts with lowercase)
                $isPrivateStruct = $structName -cmatch '^[a-z]'

                # Update the step using the database update function
                $result = Update-TestFunctionStepStructRefId -TestFunctionStepRefId $step.TestFunctionStepRefId -StructRefId $structRefId
                if ($result) {
                    $resolvedCount++

                    # Set StructVisibilityTypeId for all resolved steps based on struct visibility
                    $visibilityTypeId = if ($isPrivateStruct) { 11 } else { 12 }  # PRIVATE_REFERENCE : PUBLIC_REFERENCE
                    Update-TestFunctionStepStructVisibility -TestFunctionStepRefId $step.TestFunctionStepRefId -StructVisibilityTypeId $visibilityTypeId | Out-Null

                    if ($isPrivateStruct) {
                        $privateCount++
                    }
                }
            } else {
                # Struct not found - this is handled by fallback rules in Phase 4a.7
                # Suppressing warning since EXTERNAL_REFERENCE classification will be applied
                Write-Verbose "CROSS_FILE struct '$structName' not found for step $($step.TestFunctionStepRefId) - will be classified as EXTERNAL_REFERENCE"
            }
        }
    }

    Show-PhaseMessageMultiHighlight -Message "Resolved $resolvedCount Namespace References ($($crossFileSteps.Count) CROSS_FILE, $($selfEmbeddedSteps.Count) EMBEDDED_SELF, $privateCount PRIVATE_REFERENCE)" -HighlightTexts @("$resolvedCount", "$($crossFileSteps.Count)", "CROSS_FILE", "$($selfEmbeddedSteps.Count)", "EMBEDDED_SELF", "$privateCount", "PRIVATE_REFERENCE") -HighlightColors @($NumberColor, $NumberColor, $ItemColor, $NumberColor, $ItemColor, $NumberColor, $ItemColor)
}

function Update-TestFunctionStepReferentialIntegrity {
    <#
    .SYNOPSIS
    Phase 4a.7: Updates StructVisibilityTypeId for unresolved references to maintain referential integrity

    .DESCRIPTION
    Post-resolution cleanup that ensures all test function steps have proper StructVisibilityTypeId values
    according to the normalized schema design. Handles cases where struct resolution failed but we can
    still classify the visibility based on the reference type.

    Updates:
    - ANONYMOUS_FUNCTION_REFERENCE (9) -> StructVisibilityTypeId = PRIVATE_REFERENCE (11)
    - CROSS_FILE (2) with empty StructRefId -> StructVisibilityTypeId = EXTERNAL_REFERENCE (10)

    Note: Lowercase function visibility is now handled during initial step creation for better performance.
    Note: ServiceImpactTypeId classification happens in Phase 5 after IndirectConfigReferences are populated.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    Show-PhaseMessage -Message "Updating Referential Integrity For Unresolved Namespace References" -BaseColor $BaseColor -InfoColor $InfoColor

    # Use direct database queries instead of Where-Object for performance
    # Get ANONYMOUS_FUNCTION_REFERENCE steps (ReferenceTypeId = 9) with unresolved visibility
    $anonymousSteps = Get-TestFunctionStepsByReferenceType -ReferenceTypeId 9

    # Get CROSS_FILE steps (ReferenceTypeId = 2) with unresolved visibility
    $crossFileSteps = Get-TestFunctionStepsByReferenceType -ReferenceTypeId 2

    # Filter cross-file steps to only those with empty StructRefId (unresolved struct)
    $unresolvedCrossFileSteps = @()
    foreach ($step in $crossFileSteps) {
        if (-not $step.StructRefId -or $step.StructRefId -eq "" -or $step.StructRefId -eq "0") {
            $unresolvedCrossFileSteps += $step
        }
    }

    $totalUnresolvedSteps = $anonymousSteps.Count + $unresolvedCrossFileSteps.Count

    if ($totalUnresolvedSteps -eq 0) {
        Show-PhaseMessage -Message "No Unresolved Namespace References Found" -BaseColor $BaseColor -InfoColor $InfoColor
        return
    }

    Show-PhaseMessageMultiHighlight -Message "Processing $($anonymousSteps.Count) ANONYMOUS_FUNCTION And $($unresolvedCrossFileSteps.Count) Unresolved CROSS_FILE References" -HighlightTexts @($anonymousSteps.Count, "ANONYMOUS_FUNCTION", $unresolvedCrossFileSteps.Count, "CROSS_FILE") -HighlightColors @($NumberColor, $ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

    $anonymousUpdates = 0
    $crossFileUpdates = 0

    # Process ANONYMOUS_FUNCTION_REFERENCE steps (ReferenceTypeId = 9)
    # All anonymous function references should be marked as PRIVATE_REFERENCE (11)
    foreach ($step in $anonymousSteps) {
        # Only update if StructVisibilityTypeId is not already set
        if (-not $step.StructVisibilityTypeId -or $step.StructVisibilityTypeId -eq "") {
            $result = Update-TestFunctionStepStructVisibility -TestFunctionStepRefId $step.TestFunctionStepRefId -StructVisibilityTypeId 11
            if ($result) {
                $anonymousUpdates++
            } else {
                Write-Warning "Failed to update StructVisibilityTypeId for ANONYMOUS_FUNCTION step $($step.TestFunctionStepRefId)"
            }
        }
    }

    # Process unresolved CROSS_FILE steps (ReferenceTypeId = 2 with empty StructRefId)
    # These should be marked as EXTERNAL_REFERENCE (10)
    foreach ($step in $unresolvedCrossFileSteps) {
        # Only update if StructVisibilityTypeId is not already set
        if (-not $step.StructVisibilityTypeId -or $step.StructVisibilityTypeId -eq "") {
            $result = Update-TestFunctionStepStructVisibility -TestFunctionStepRefId $step.TestFunctionStepRefId -StructVisibilityTypeId 10
            if ($result) {
                $crossFileUpdates++
            } else {
                Write-Warning "Failed to update StructVisibilityTypeId for CROSS_FILE step $($step.TestFunctionStepRefId)"
            }
        }
    }

    Show-PhaseMessageMultiHighlight -Message "Updated Referential Integrity For $anonymousUpdates ANONYMOUS_FUNCTION -> PRIVATE_REFERENCE, $crossFileUpdates CROSS_FILE -> EXTERNAL_REFERENCE" -HighlightTexts @($anonymousUpdates, "ANONYMOUS_FUNCTION", "PRIVATE_REFERENCE", $crossFileUpdates, "CROSS_FILE", "EXTERNAL_REFERENCE") -HighlightColors @($NumberColor, $ItemColor, $ItemColor, $NumberColor, $ItemColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor
}

function Update-SequentialEntryPointReferences {
    <#
    .SYNOPSIS
    Phase 6.5: Updates TestFunctions table to mark sequential entry points after SequentialReferences are populated

    .DESCRIPTION
    This function runs after Phase 6 when SequentialReferences table is populated.
    It updates the SequentialEntryPointRefId field in TestFunctions from "0" to "13" for entry point functions.
    This is a clean referential update that maintains proper relational integrity.
    #>

    try {
        $sequentialRefs = Get-SequentialReferences
        if (-not $sequentialRefs -or $sequentialRefs.Count -eq 0) {
            return 0
        }

        # Get unique entry point function IDs from SequentialReferences table
        $entryPointIds = $sequentialRefs | Select-Object EntryPointFunctionRefId -Unique | ForEach-Object { $_.EntryPointFunctionRefId }

        $updatedCount = 0

        # Update TestFunctions: change SequentialEntryPointRefId from "0" to "13" for entry points
        foreach ($entryPointId in $entryPointIds) {
            $result = Update-TestFunctionSequentialInfo -TestFunctionRefId $entryPointId -SequentialEntryPointRefId 13
            if ($result) {
                $updatedCount++
            }
        }

        return $updatedCount

    } catch {
        Write-Host " ERROR: Failed to update sequential entry point references: $($_.Exception.Message)" -ForegroundColor Red
        # TODO: UX IMPROVEMENT NEEDED - PowerShell exceptions are not user-friendly
        # Replace this with a custom error message using Show-PhaseMessage or similar UI function
        # The current throw pattern displays ugly PowerShell stack traces that don't help users
        throw
    }
}

function Invoke-TestFunctionStepsProcessing {
    <#
    .SYNOPSIS
    Processes all test functions for step analysis and struct visibility detection

    .DESCRIPTION
    Encapsulates the business logic for processing test function steps, including:
    - Adding test function step records to the database
    - Detecting and updating struct visibility based on Go naming conventions
    - Handling both public and private struct references

    .PARAMETER TestFunctions
    Array of test functions to process

    .OUTPUTS
    Returns the total number of steps processed
    #>
    param(
        [Parameter(Mandatory = $false)]
        [array]$TestFunctions,
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Green",
        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray"
    )

    try {
        # Get test functions from database if not provided
        if (-not $TestFunctions) {
            $TestFunctions = Get-TestFunctions
        }

        $totalStepsProcessed = 0
        $totalFunctions = $TestFunctions.Count
        $currentFunction = 0

        foreach ($testFunction in $TestFunctions) {
            $currentFunction++
            if ($currentFunction % 50 -eq 0 -or $currentFunction -eq 1) {
                Show-InlineProgress -Current $currentFunction -Total $totalFunctions -Activity "Processing Test Function Steps" -NumberColor $NumberColor -ItemColor $ItemColor -InfoColor $InfoColor -BaseColor $BaseColor
            }

            $steps = Invoke-TestFunctionSteps $testFunction
            foreach ($step in $steps) {
                # Add the test function step record first
                $stepRefId = Add-TestFunctionStepRecord -TestFunctionRefId $step.TestFunctionRefId `
                                                       -StepIndex $step.StepIndex `
                                                       -StepBody $step.StepBody `
                                                       -ConfigTemplate $step.ConfigTemplate `
                                                       -StructRefId $step.StructRefId `
                                                       -ReferenceTypeId $step.ReferenceTypeId

                # Detect and update struct visibility if we have a struct reference
                if ($step.StructRefId -and $step.StructRefId -ne "" -and $step.StructRefId -ne "0") {
                    # Use O(1) hashtable lookup instead of O(n) Where-Object filtering
                    $struct = Get-StructById -StructRefId $step.StructRefId

                    if ($struct -and $struct.StructName) {
                        # Determine struct visibility based on Go naming conventions
                        # Default: Public visibility (most provider structs are public)
                        # Exception: Private visibility only for lowercase test-local structs
                        $structVisibilityTypeId = 12  # PUBLIC_REFERENCE (default)

                        if ($struct.StructName -cmatch '^[a-z]') {
                            # Private struct (lowercase first letter) - test-local structs like dataSourceStorageShare
                            $structVisibilityTypeId = 11  # PRIVATE_REFERENCE
                        }
                        # Note: Uppercase structs stay as PUBLIC_REFERENCE (12)

                        # Update the struct visibility
                        Update-TestFunctionStepStructVisibility -TestFunctionStepRefId $stepRefId -StructVisibilityTypeId $structVisibilityTypeId | Out-Null
                    }
                }

                $totalStepsProcessed++
            }
        }

        Show-InlineProgress -Current $totalFunctions -Total $totalFunctions -Activity "Processing Test Function Steps" -Completed -NumberColor $NumberColor -ItemColor $ItemColor -InfoColor $InfoColor -BaseColor $BaseColor

        return $totalStepsProcessed

    } catch {
        Write-Host " ERROR: Failed to process test function steps: $($_.Exception.Message)" -ForegroundColor Red
        # TODO: UX IMPROVEMENT NEEDED - PowerShell exceptions are not user-friendly
        # Replace this with a custom error message using Show-PhaseMessage or similar UI function
        # The current throw pattern displays ugly PowerShell stack traces that don't help users
        throw
    }
}

Export-ModuleMember -Function @(
    'Invoke-TestFunctionSteps',
    'Add-TestFunctionStep',
    'Update-CrossFileStructReferencesInSteps',
    'Update-SequentialEntryPointReferences',
    'Update-TestFunctionStepReferentialIntegrity',
    'Invoke-TestFunctionStepsProcessing'
)
