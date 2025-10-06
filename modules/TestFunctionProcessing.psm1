# TestFunctionProcessing.psm1 - Extract individual test function bodies to eliminate content duplication

# Dependencies: PatternAnalysis.psm1, Database.psm1 (loaded by main script)

function Get-TestFunctionsFromFile {
    <#
    .SYNOPSIS
        Extract individual test function bodies from Go files to reduce storage duplication
    .DESCRIPTION
        This function extracts test function bodies using the same approach as template functions,
        eliminating the need to store full file content and reducing storage from ~98MB to individual function bodies.
    .PARAMETER FilePath
        The path to the Go file to process
    .PARAMETER FileRefId
        The database file reference ID
    .PARAMETER Content
        The file content to process
    .PARAMETER StructDatabase
        Hashtable mapping struct names to StructRefIds for this file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [int]$FileRefId,
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $false)]
        [hashtable]$StructDatabase = @{}
    )

    $extractedTestFunctions = @()



    # Extract standard test functions: func TestAccXxx_xxx(t *testing.T)
    $testFunctionMatches = @()
    $testFunctionMatches += $Global:RegexPatterns.TestFunction.Matches($Content)
    $testFunctionMatches += $Global:RegexPatterns.LowerTestFunction.Matches($Content)



    foreach ($match in $testFunctionMatches) {
        $funcName = $match.Groups[1].Value
        $funcBody = Get-FunctionBody -Content $Content -FunctionMatch $match

        if (-not [string]::IsNullOrWhiteSpace($funcBody)) {
            # Calculate test prefix: include underscore if present, otherwise full function name
            $testPrefix = if ($funcName -match '_') {
                ($funcName -split '_')[0] + '_'
            } else {
                $funcName
            }

            # Extract struct name for later JOIN-based resolution
            $structName = Get-StructNameFromFunctionBody -FunctionBody $funcBody

            # Try to resolve StructRefId from local file first
            $structRefId = if ($structName -and $StructDatabase.ContainsKey($structName)) {
                $StructDatabase[$structName]
            } else {
                $null
            }

            # Add test function to database - struct resolution will happen later via JOIN
            $testFunctionRefId = Add-TestFunctionRecord -FileRefId $FileRefId -StructRefId $structRefId -FunctionName $funcName -Line $match.Index -TestPrefix $testPrefix -SequentialEntryPointRefId 0 -FunctionBody $funcBody

            $extractedTestFunctions += [PSCustomObject]@{
                TestFunctionRefId = $testFunctionRefId
                TestFunctionName = $funcName
                FileRefId = $FileRefId
                FunctionBody = $funcBody
                Line = $match.Index
                FilePath = $FilePath
                TestPrefix = $testPrefix
            }


        }
    }

    return $extractedTestFunctions
}

function Get-StructNameFromFunctionBody {
    <#
    .SYNOPSIS
        Extract struct name from test function body for later JOIN-based resolution
    .DESCRIPTION
        Looks for patterns like "r := WorkloadsSAPThreeTierVirtualInstanceResource{}" or "StructName{}.method()"
        and returns the struct name for later database JOIN resolution
    .PARAMETER FunctionBody
        The test function body content
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FunctionBody
    )

    # Pattern to match struct instantiation: variable := StructName{} or variable := &StructName{}
    $structInstantiationPattern = '(?:^|\s)(?:\w+)\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{\}'

    # Pattern to match direct struct method calls: StructName{}.method()
    $structMethodCallPattern = '([A-Z][A-Za-z0-9_]*)\{\}\.'

    # Check assignment pattern first
    $structMatches = [regex]::Matches($FunctionBody, $structInstantiationPattern)
    if ($structMatches.Count -gt 0) {
        return $structMatches[0].Groups[1].Value
    }

    # Check method call pattern
    $methodCallMatches = [regex]::Matches($FunctionBody, $structMethodCallPattern)
    if ($methodCallMatches.Count -gt 0) {
        return $methodCallMatches[0].Groups[1].Value
    }

    return $null
}

# Export functions for use by other modules
Export-ModuleMember -Function Get-TestFunctionsFromFile, Get-StructNameFromFunctionBody
