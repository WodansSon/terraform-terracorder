# TemplateProcessingStrategies.psm1
# Clean Strategy Pattern implementations for template processing

#region Strategy Interfaces and Base Classes

class ITemplateFunctionProcessor {
    [PSCustomObject] ProcessTemplateFunction([string]$funcName, [string]$funcBody, [string]$relativePath, [hashtable]$regexPatterns, [string]$resourceName) {
        throw "Must implement ProcessTemplateFunction"
    }
}

class IStructResolver {
    [PSCustomObject] ResolveStruct([string]$funcBody, [hashtable]$regexPatterns, [int]$fileRefId) {
        throw "Must implement ResolveStruct"
    }
}

class IDependencyResolver {
    [hashtable] ResolveDependencies([array]$currentTemplateFunctions, [hashtable]$functionIndex, [hashtable]$contentCache) {
        throw "Must implement ResolveDependencies"
    }
}

#endregion

#region Struct Resolution Strategy

class StructResolutionStrategy : IStructResolver {
    [PSCustomObject] ResolveStruct([string]$funcBody, [hashtable]$regexPatterns, [int]$fileRefId) {
        $result = @{
            StructRefId = $null
            ReceiverVariable = ""
        }

        # Phase 1: Check for receiver pattern (func (r LoadBalancerOutboundRule) method...)
        $receiverMatch = $regexPatterns.ReceiverMethod.Match($funcBody)
        if ($receiverMatch.Success) {
            $result.ReceiverVariable = $receiverMatch.Groups[1].Value
            $receiverStructName = $receiverMatch.Groups[2].Value

            # DATABASE-FIRST: Query database for struct by name
            $struct = Get-Structs | Where-Object { $_.StructName -eq $receiverStructName } | Select-Object -First 1
            if ($struct) {
                $result.StructRefId = $struct.StructRefId
                return [PSCustomObject]$result
            }
        }

        # Phase 2: Check function body for struct instantiations
        if ($null -eq $result.StructRefId) {
            $structInstantiationMatches = [regex]::Matches($funcBody, '(?:^|\s)(?:\w+)\s*:=\s*(?:&)?([A-Z][A-Za-z0-9_]*)\s*\{\}')
            foreach ($match in $structInstantiationMatches) {
                $structName = $match.Groups[1].Value
                # DATABASE-FIRST: Query database for struct by name
                $struct = Get-Structs | Where-Object { $_.StructName -eq $structName } | Select-Object -First 1
                if ($struct) {
                    $result.StructRefId = $struct.StructRefId
                    break
                }
            }
        }

        # Phase 3: Final fallback - use same-file struct lookup
        if ($null -eq $result.StructRefId) {
            # DATABASE-FIRST: Query database for structs in this file
            $structs = Get-Structs | Where-Object { $_.FileRefId -eq $fileRefId }
            $result.StructRefId = if ($structs) { $structs[0].StructRefId } else { $null }
        }

        return [PSCustomObject]$result
    }
}

#endregion

#region Template Function Processing Strategy

class TemplateFunctionProcessingStrategy : ITemplateFunctionProcessor {
    [IStructResolver]$StructResolver

    TemplateFunctionProcessingStrategy([IStructResolver]$structResolver) {
        $this.StructResolver = $structResolver
    }

    [PSCustomObject] ProcessTemplateFunction([string]$funcName, [string]$funcBody, [string]$relativePath, [hashtable]$regexPatterns, [string]$resourceName) {
        # DATABASE-FIRST: Query database for file record
        $fileRecord = Get-Files | Where-Object { $_.FilePath -eq $relativePath } | Select-Object -First 1

        if (-not $fileRecord) {
            return $null
        }

        $fileRefId = $fileRecord.FileRefId

        # Use clean struct resolution strategy
        $structInfo = $this.StructResolver.ResolveStruct($funcBody, $regexPatterns, $fileRefId)

        # Add template function to database
        $templateFunctionRefId = Add-TemplateFunctionRecord -TemplateFunctionName $funcName -StructRefId $structInfo.StructRefId -FileRefId $fileRefId -FunctionBody $funcBody -ReceiverVariable $structInfo.ReceiverVariable

        # Extract and store function calls for Phase 5 lookup
        $this.ExtractAndStoreFunctionCalls($funcBody, $templateFunctionRefId, $structInfo.ReceiverVariable)

        return [PSCustomObject]@{
            FunctionName = $funcName
            FilePath = $relativePath
            FunctionBody = $funcBody
            ContainsResource = ($funcBody -match [regex]::Escape($resourceName))
            TemplateRefId = $templateFunctionRefId
        }
    }

    [void] ExtractAndStoreFunctionCalls([string]$funcBody, [int]$templateFunctionRefId, [string]$receiverVariable) {
        if ([string]::IsNullOrWhiteSpace($funcBody)) {
            return
        }

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

#endregion

#region Dependency Resolution Strategy

class DependencyResolutionStrategy : IDependencyResolver {
    [ITemplateFunctionProcessor]$TemplateProcessor
    [string]$RepositoryDirectory
    [hashtable]$RegexPatterns
    [hashtable]$AllTemplateFunctionsWithResource

    DependencyResolutionStrategy([ITemplateFunctionProcessor]$templateProcessor, [string]$repositoryDirectory, [hashtable]$regexPatterns, [hashtable]$allTemplateFunctionsWithResource) {
        $this.TemplateProcessor = $templateProcessor
        $this.RepositoryDirectory = $repositoryDirectory
        $this.RegexPatterns = $regexPatterns
        $this.AllTemplateFunctionsWithResource = $allTemplateFunctionsWithResource
    }

    [hashtable] ResolveDependencies([array]$currentTemplateFunctions, [hashtable]$functionIndex, [hashtable]$contentCache) {
        # Build lookup index for existing functions
        $existingFunctionNames = @{}
        foreach ($func in $currentTemplateFunctions) {
            $existingFunctionNames[$func.TemplateFunctionName] = $true
        }

        # Find missing dependencies
        $missingFunctions = $this.FindMissingDependencies($currentTemplateFunctions, $existingFunctionNames)

        # Resolve missing dependencies
        $resolvedCount = $this.ResolveMissingFunctions($missingFunctions, $functionIndex, $contentCache)

        return @{
            ResolvedCount = $resolvedCount
            MissingFunctions = $missingFunctions
        }
    }

    [hashtable] FindMissingDependencies([array]$currentTemplateFunctions, [hashtable]$existingFunctionNames) {
        $missingFunctions = @{}

        foreach ($templateFunc in $currentTemplateFunctions) {
            $funcBody = $templateFunc.FunctionBody
            $receiverVar = $templateFunc.ReceiverVariable

            if (-not [string]::IsNullOrEmpty($receiverVar)) {
                $callPattern = New-DynamicCallPattern -VariableName $receiverVar
                $functionMatches = $callPattern.Matches($funcBody)

                foreach ($match in $functionMatches) {
                    $calledFunctionName = $match.Groups[1].Value

                    if (-not $existingFunctionNames.ContainsKey($calledFunctionName)) {
                        if (-not $missingFunctions.ContainsKey($calledFunctionName)) {
                            $missingFunctions[$calledFunctionName] = @()
                        }
                        $missingFunctions[$calledFunctionName] += $templateFunc.FileRefId
                    }
                }
            }
        }

        return $missingFunctions
    }

    [int] ResolveMissingFunctions([hashtable]$missingFunctions, [hashtable]$functionIndex, [hashtable]$contentCache) {
        $resolvedCount = 0

        foreach ($missingFuncName in $missingFunctions.Keys) {
            if ($functionIndex.ContainsKey($missingFuncName)) {
                $filesWithFunction = $functionIndex[$missingFuncName]

                $resolved = $this.ProcessMissingFunction($missingFuncName, $filesWithFunction, $contentCache)
                if ($resolved) {
                    $resolvedCount++
                }
            }
        }

        return $resolvedCount
    }

    [bool] ProcessMissingFunction([string]$functionName, [array]$candidateFiles, [hashtable]$contentCache) {
        foreach ($fullPath in $candidateFiles) {
            # Get content from cache or database
            $content = $this.GetFileContent($fullPath, $contentCache)
            if ([string]::IsNullOrWhiteSpace($content)) {
                continue
            }

            # Extract the specific function
            $funcBody = $this.ExtractSpecificFunction($functionName, $content)
            if ([string]::IsNullOrWhiteSpace($funcBody)) {
                continue
            }

            # Process the function using clean strategy
            $relativePath = $fullPath.Replace($this.RepositoryDirectory, "").TrimStart('\').Replace("\", "/")
            $result = $this.TemplateProcessor.ProcessTemplateFunction($functionName, $funcBody, $relativePath, $this.RegexPatterns, "")

            if ($result) {
                # Update the shared collection
                if (-not $this.AllTemplateFunctionsWithResource.ContainsKey($functionName)) {
                    $this.AllTemplateFunctionsWithResource[$functionName] = @()
                }
                $this.AllTemplateFunctionsWithResource[$functionName] += $relativePath
                return $true
            }
        }

        return $false
    }

    [string] GetFileContent([string]$fullPath, [hashtable]$contentCache) {
        if ($contentCache.ContainsKey($fullPath)) {
            return $contentCache[$fullPath]
        }

        $content = Get-FileContent -FullPath $fullPath
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            $contentCache[$fullPath] = $content
        }
        return $content
    }

    [string] ExtractSpecificFunction([string]$functionName, [string]$content) {
        $specificFuncPattern = "func\s+(?:\([^)]+\)\s+)?$([regex]::Escape($functionName))\s*\([^)]*(?:acceptance\.TestData|TestData)[^)]*\)\s+string\s*\{((?:[^{}]+|\{(?:[^{}]+|\{[^{}]*\})*\})*)\}"
        $specificMatch = [regex]::Match($content, $specificFuncPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

        if ($specificMatch.Success) {
            return $specificMatch.Groups[1].Value.Trim()
        }
        return ""
    }
}

#endregion

#region Strategy Factory

class TemplateProcessingStrategyFactory {
    static [ITemplateFunctionProcessor] CreateTemplateFunctionProcessor() {
        $structResolver = [StructResolutionStrategy]::new()
        return [TemplateFunctionProcessingStrategy]::new($structResolver)
    }

    static [IDependencyResolver] CreateDependencyResolver([string]$repositoryDirectory, [hashtable]$regexPatterns, [hashtable]$allTemplateFunctionsWithResource) {
        $templateProcessor = [TemplateProcessingStrategyFactory]::CreateTemplateFunctionProcessor()
        return [DependencyResolutionStrategy]::new($templateProcessor, $repositoryDirectory, $regexPatterns, $allTemplateFunctionsWithResource)
    }
}

#endregion

Export-ModuleMember -Function * -Variable *
