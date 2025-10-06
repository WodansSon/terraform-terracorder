# PatternAnalysis.psm1
# Pattern matching and content analysis for TerraCorder

# Initialize regex patterns
function Initialize-RegexPatterns {
    <#
    .SYNOPSIS
        Initialize precompiled regex patterns for maximum performance
    #>

    return @{
        # Struct and type definitions
        StructDefinition = [regex]::new('^type\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+struct\s*\{')

        # Function definitions
        TestFunction = [regex]::new('func\s+(Test\w*)\s*\(')
        LowerTestFunction = [regex]::new('func\s+(test\w*)\s*\(')
        MainTestFunction = [regex]::new('^func\s+(Test\w+)\s*\(')
        MainLowerTestFunction = [regex]::new('^func\s+(test\w+)\s*\(')

        # Sequential test patterns
        RunTestsInSequence = [regex]::new('acceptance\.RunTestsInSequence')
        RunTestsInSequenceCall = [regex]::new('acceptance\.RunTestsInSequence\s*\(')
        MapBasedSequential = [regex]::new('\b\w+\s*:?=\s*map\[string\]map\[string\]func\(t\s*\*testing\.T\)')
        SequentialGroup = [regex]::new('^\s*"([^"]+)"\s*:\s*\{')
        SequentialFunction = [regex]::new('^\s*"([^"]+)"\s*:\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*,?')
        SequentialGroupEnd = [regex]::new('^\s*\}\s*,?\s*$')
        SequentialEnd = [regex]::new('^\s*\}\)\s*$')

        # Resource reference patterns
        ResourceDefinition = [regex]::new('resource\s+"')
        DataSource = [regex]::new('data\s+"')

        # Template function patterns
        ReceiverMethod = [regex]::new('func\s*\(\s*(\w+)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\)\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\([^)]*\)\s*string\s*\{')
        ConfigFunction = [regex]::new('func\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\([^)]*\)\s*string\s*\{')
        TemplateFunction = [regex]::new('func\s+(?:\([^)]+\)\s+)?(\w+)\s*\([^)]*(?:acceptance\.TestData|TestData)[^)]*\)\s+string')
        TemplateFunctionCall = [regex]::new('\b(\w+)\s*\(')
        TestFunctionPrefix = [regex]::new('^Test[A-Z]')

        # Struct instantiation patterns
        StructInstantiation = [regex]::new(':=\s*STRUCTNAME\{\}')  # Will be updated with actual struct name
        StructMethod = [regex]::new('STRUCTNAME\{\}\s*\.')  # Will be updated with actual struct name
        ReceiverPattern = [regex]::new('\(\s*\w+\s+STRUCTNAME\s*\)')  # Will be updated with actual struct name

        # Configuration reference patterns
        ConfigField = [regex]::new('Config:\s*([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*(?:\([^)]*\))?)')
        ConfigMethod = [regex]::new('func\s*\(\s*\w+\s+\*?(\w+)\s*\)\s*(\w+)\s*\([^)]*\)\s*string')
        DirectConfigCall = [regex]::new('([a-zA-Z_][a-zA-Z0-9_]*)\s*\(')
        VariableConfigCall = [regex]::new('(\w+)\s*:?=\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\(')

        # Optimized patterns for TestFunctionSteps processing
        ConfigVariableMethod = [regex]::new('Config:\s*(\w+)\.(\w+)')
        TestStepArrayPattern = [regex]::new('\[\]acceptance\.TestStep\s*\{')
        StructInstantiationPattern = [regex]::new('(?:^|\s)(\w+)\s*:=\s*(?:&)?([A-Za-z][A-Za-z0-9_]*)\s*\{')
        FunctionCallPattern = [regex]::new('(?:^|\s)(\w+)\s*:=\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\(')
        VarDeclarationPattern = [regex]::new('(?:^|\s)var\s+(\w+)\s+([A-Za-z][A-Za-z0-9_]*)\s*(?:\n|$|\s)')
        StructMethodPattern = [regex]::new('Config:\s*([A-Za-z][A-Za-z0-9_]*)\{\}\.(\w+)')
        EmbeddedStructPattern = [regex]::new('(?:^|\s)(\w+)\s*:=\s*(?:&)?([A-Za-z][A-Za-z0-9_]*)\s*\{\}')
        DirectStructPattern = [regex]::new('([A-Za-z][A-Za-z0-9_]*)\{\}\.')
        TestResourcePattern = [regex]::new('TestResource:\s*(\w+)')
        LegacyConfigPattern = [regex]::new('Config:\s*func\s*\([^)]*\)\s*[^{]*\{\s*return\s+(\w+)\.(\w+)\s*\(')
        NewResourceFunctionPattern = [regex]::new('^new(.+)Resource$')
        NewFunctionPattern = [regex]::new('^new(.+)$')
        TestStepFieldPattern = [regex]::new('\b(Config|Check|PreConfig|PostConfig|PlanOnly|Destroy|ExpectNonEmptyPlan|ExpectError):\s*')
        ApplyStepPattern = [regex]::new('\.ApplyStep\s*\(\s*(\w+)\.(\w+)\s*,\s*\w+\s*\)')

        # Template content validation
        TemplateContent = [regex]::new('resource\s+"|data\s+"|provider\s+"|terraform\s*\{|fmt\.Sprintf|return\s+`')

        # Underscore pattern for test prefixes
        UnderscorePattern = [regex]::new('_')

        # Brace counting patterns
        OpenBrace = [regex]::new('\{')
        CloseBrace = [regex]::new('\}')

        # Cross-service patterns
        ExternalResource = [regex]::new('([A-Z][a-zA-Z0-9_]*Resource|[A-Z][a-zA-Z0-9_]*DataSource)\{\}\.([a-zA-Z_][a-zA-Z0-9_]*)')
        ExternalFunction = [regex]::new('([a-zA-Z_][a-zA-Z0-9_]*(?:Config|Template)[a-zA-Z0-9_]*)\s*\(')
    }
}

function New-DynamicFunctionPattern {
    <#
    .SYNOPSIS
        Create a regex pattern for finding a specific function definition
    #>
    param([string]$FunctionName)

    return [regex]::new("func\s+(?:\([^)]+\)\s+)?$([regex]::Escape($FunctionName))\s*\([^)]*(?:acceptance\.TestData|TestData)[^)]*\)\s+string")
}

function New-DynamicCallPattern {
    <#
    .SYNOPSIS
        Create a regex pattern for finding method calls on a specific variable
    #>
    param([string]$VariableName)

    return [regex]::new("\b$([regex]::Escape($VariableName))\.(\w+)\(")
}

function Get-StructDefinitions {
    <#
    .SYNOPSIS
        Extract struct definitions from file content
    #>
    param(
        [string]$FileContent,
        [hashtable]$Patterns = (Initialize-RegexPatterns)
    )

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

function Get-FunctionBody {
    <#
    .SYNOPSIS
        Extract function body with proper brace matching
    #>
    param(
        [string]$Content,
        [System.Text.RegularExpressions.Match]$FunctionMatch
    )

    $funcStart = $FunctionMatch.Index
    $remaining = $Content.Substring($funcStart)

    # Find the opening brace of the function
    $openBraceIndex = $remaining.IndexOf('{')
    if ($openBraceIndex -eq -1) {
        return ""
    }

    # Count braces to find the end of the function
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

    return $remaining.Substring(0, [Math]::Min($funcBodyEnd, $remaining.Length))
}

Export-ModuleMember -Function Initialize-RegexPatterns, Get-StructDefinitions, Get-FunctionBody, New-DynamicFunctionPattern, New-DynamicCallPattern
