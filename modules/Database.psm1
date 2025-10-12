# Database.psm1
# In-memory hashtable-based database for TerraCorder
# Implements normalized tables as defined in NORMALIZED_SCHEMA.md

# NORMALIZED RELATIONAL DATABASE DESIGN
# Proper foreign key relationships and lookup tables

<#
REFERENCE TYPES DOCUMENTATION
=============================
ReferenceTypeId 1: SELF_CONTAINED - Reference resolved within the same file where struct is defined
ReferenceTypeId 2: CROSS_FILE - Reference points to struct defined in a different file within same service
ReferenceTypeId 3: EMBEDDED_SELF - Reference is embedded within the same struct definition
ReferenceTypeId 4: ATTRIBUTE_REFERENCE - Reference to struct attributes or nested properties
ReferenceTypeId 5: RESOURCE_REFERENCE - Reference to Terraform resource instances
ReferenceTypeId 6: DATA_SOURCE_REFERENCE - Reference to Terraform data source instances
ReferenceTypeId 7: TEMPLATE_FUNCTION - Reference found in template functions or configurations
ReferenceTypeId 8: SEQUENTIAL_REFERENCE - Reference found in sequential test step execution
ReferenceTypeId 9: ANONYMOUS_FUNCTION_REFERENCE - Reference found in anonymous function test step patterns (DisappearsStep, ApplyStep, ImportStep, PlanOnlyStep)
                                      These are anonymous Config function patterns like:
                                      Config: func(d acceptance.TestData) string { return r.method(...) }
ReferenceTypeId 10: EXTERNAL_REFERENCE - Reference to external dependencies not in our locally cached codebase
                                         These are legitimate test prerequisites from other providers/modules
#>

# Unified ReferenceTypes lookup table (for both IndirectConfigReferences and DirectResourceReferences)
$script:ReferenceTypes = @{
    1 = [PSCustomObject]@{ ReferenceTypeId = 1; ReferenceTypeName = "SELF_CONTAINED" }
    2 = [PSCustomObject]@{ ReferenceTypeId = 2; ReferenceTypeName = "CROSS_FILE" }
    3 = [PSCustomObject]@{ ReferenceTypeId = 3; ReferenceTypeName = "EMBEDDED_SELF" }
    4 = [PSCustomObject]@{ ReferenceTypeId = 4; ReferenceTypeName = "ATTRIBUTE_REFERENCE" }
    5 = [PSCustomObject]@{ ReferenceTypeId = 5; ReferenceTypeName = "RESOURCE_REFERENCE" }
    6 = [PSCustomObject]@{ ReferenceTypeId = 6; ReferenceTypeName = "DATA_SOURCE_REFERENCE" }
    7 = [PSCustomObject]@{ ReferenceTypeId = 7; ReferenceTypeName = "TEMPLATE_FUNCTION" }
    8 = [PSCustomObject]@{ ReferenceTypeId = 8; ReferenceTypeName = "SEQUENTIAL_REFERENCE" }
    9 = [PSCustomObject]@{ ReferenceTypeId = 9; ReferenceTypeName = "ANONYMOUS_FUNCTION_REFERENCE" }
    10 = [PSCustomObject]@{ ReferenceTypeId = 10; ReferenceTypeName = "EXTERNAL_REFERENCE" }
    11 = [PSCustomObject]@{ ReferenceTypeId = 11; ReferenceTypeName = "PRIVATE_REFERENCE" }
    12 = [PSCustomObject]@{ ReferenceTypeId = 12; ReferenceTypeName = "PUBLIC_REFERENCE" }
    13 = [PSCustomObject]@{ ReferenceTypeId = 13; ReferenceTypeName = "SEQUENTIAL_ENTRYPOINT" }
    14 = [PSCustomObject]@{ ReferenceTypeId = 14; ReferenceTypeName = "SAME_SERVICE" }
    15 = [PSCustomObject]@{ ReferenceTypeId = 15; ReferenceTypeName = "CROSS_SERVICE" }
}

# Quick lookup by name (unified for all reference types)
$script:ReferenceTypeLookup = @{
    "SELF_CONTAINED" = 1
    "CROSS_FILE" = 2
    "EMBEDDED_SELF" = 3
    "ATTRIBUTE_REFERENCE" = 4
    "RESOURCE_REFERENCE" = 5
    "DATA_SOURCE_REFERENCE" = 6
    "TEMPLATE_FUNCTION" = 7
    "SEQUENTIAL_REFERENCE" = 8
    "ANONYMOUS_FUNCTION_REFERENCE" = 9
    "EXTERNAL_REFERENCE" = 10
    "PRIVATE_REFERENCE" = 11
    "PUBLIC_REFERENCE" = 12
    "SEQUENTIAL_ENTRYPOINT" = 13
    "SAME_SERVICE" = 14
    "CROSS_SERVICE" = 15
}

# Global in-memory database tables (normalized with foreign keys)
$script:Resources = @{}                 # ResourceRefId -> Resource record (ResourceName)
$script:Services = @{}                  # ServiceRefId -> Service record (with ResourceRefId FK)
$script:Files = @{}                     # FileRefId -> File record (with ServiceRefId FK)
$script:Structs = @{}                   # StructRefId -> Struct record (with ServiceRefId, FileRefId FKs)
$script:TestFunctions = @{}             # FunctionRefId -> TestFunction record (with ServiceRefId, FileRefId, StructRefId FKs)
$script:TestSteps = @{}                 # TestStepRefId -> TestStep record (with TestFunctionRefId, TemplateFunctionRefId, TargetStructRefId, TargetServiceRefId, ReferenceTypeId FKs)
$script:TestFunctionStepIndex = $null   # Composite index: "TestFunctionRefId-StepIndex" -> TestFunctionStepRefId (built on first use)
$script:DirectResourceReferences = @{}  # DirectRefId -> DirectReference record (with FileRefId, ReferenceTypeId FKs)
$script:IndirectConfigReferences = @{}  # IndirectRefId -> IndirectReference record (with TestFunctionStepRefId, TemplateReferenceRefId, SourceTemplateFunctionRefId, ReferenceTypeId FKs)
$script:TemplateFunctions = @{}         # TemplateFunctionRefId -> TemplateFunction record (with ServiceRefId, FileRefId, StructRefId FKs)
$script:TemplateCallChain = @{}         # ChainRefId -> TemplateCallChain record (AST-optimized template call chains)
$script:TemplateChainResources = @{}    # ChainResourceRefId -> Junction table (ChainRefId → ResourceRefId)
$script:SequentialReferences = @{}      # SequentialRefId -> Sequential record (with EntryPointFunctionRefId, ReferencedFunctionRefId FKs)
$script:TemplateReferences = @{}        # TemplateReferenceRefId -> TemplateReference record (with TestFunctionRefId, TestFunctionStepRefId, StructRefId FKs)

# Performance indexes for O(1) lookups
$script:FilePathToRefIdIndex = @{}      # FilePath -> FileRefId (for fast reverse lookups)
$script:StructsByFileIndex = @{}        # FileRefId -> Array of StructRefIds (for O(1) file-based struct lookups)
$script:StructsByNameIndex = @{}        # StructName -> StructRefId (for O(1) name-based struct lookups)
$script:TestFunctionStepsByRefTypeIndex = @{}  # ReferenceTypeId -> Array of TestFunctionStepRefIds (for O(1) reference type filtering)
$script:TestFunctionsByIdIndex = @{}    # TestFunctionRefId -> TestFunction record (for O(1) test function lookups)
$script:TestFunctionsByNameIndex = @{}  # FunctionName -> Array of TestFunctionRefIds (for O(1) name-based lookups, can have duplicates)

# Auto-increment counters for primary keys
$script:ResourceRefIdCounter = 1
$script:ServiceRefIdCounter = 1
$script:FileRefIdCounter = 1
$script:StructRefIdCounter = 1             # For Structs table
$script:FunctionRefIdCounter = 1
$script:TestFunctionStepRefIdCounter = 1   # For TestFunctionSteps table
$script:TestStepRefIdCounter = 1           # For AST-optimized TestSteps table
$script:ConfigRefIdCounter = 1
$script:DirectRefIdCounter = 1
$script:IndirectRefIdCounter = 1
$script:TemplateFunctionRefIdCounter = 1   # For TemplateFunctions table
$script:TemplateCallRefIdCounter = 1       # For TemplateCalls table
$script:TemplateCallChainRefIdCounter = 1  # For AST-optimized TemplateCallChain table
$script:TemplateChainResourcesRefIdCounter = 1  # For junction table
$script:SequentialRefIdCounter = 1
$script:TemplateReferenceRefIdCounter = 1  # For TemplateReferences table

# Database path for exports
# Script-level variables for in-memory database tables
$script:ExportDirectory = $null
$script:RepositoryPath = $null

function Initialize-TerraDatabase {
    <#
    .SYNOPSIS
    Initialize the TerraCorder in-memory database

    .PARAMETER ExportDirectory
    Directory path where CSV export files will be stored

    .PARAMETER RepositoryDirectory
    Root directory of the repository for path calculations

    .PARAMETER ResourceName
    The Terraform resource name being analyzed (e.g., azurerm_subnet)

    .PARAMETER NumberColor
    Color for numbers in output messages

    .PARAMETER ItemColor
    Color for item types in output messages

    .PARAMETER ElapsedColor
    Color for elapsed time in output messages
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExportDirectory,
        [Parameter(Mandatory = $false)]
        [string]$RepositoryDirectory = $null,
        [Parameter(Mandatory = $false)]
        [string]$ResourceName = $null,
        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Green",
        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",
        [Parameter(Mandatory = $false)]
        [string]$ElapsedColor = "Yellow",
        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",
        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    # Start timing for database initialization
    $initStartTime = Get-Date

    $script:ExportDirectory = $ExportDirectory

    # Set repository path if provided
    if ($RepositoryDirectory) {
        $script:RepositoryPath = $RepositoryDirectory
        if (-not $script:RepositoryPath.EndsWith("\")) {
            $script:RepositoryPath += "\"
        }
    }

    # Ensure export directory exists for CSV exports
    if (!(Test-Path $ExportDirectory)) {
        New-Item -ItemType Directory -Path $ExportDirectory -Force | Out-Null
    }

    # Clear all in-memory tables
    $script:Resources.Clear()
    $script:Services.Clear()
    $script:Files.Clear()
    $script:Structs.Clear()
    $script:TestFunctions.Clear()
    $script:TestSteps.Clear()
    $script:DirectResourceReferences.Clear()
    $script:IndirectConfigReferences.Clear()
    $script:TemplateFunctions.Clear()  # Template function definitions
    $script:TemplateCallChain.Clear()  # AST-optimized call chains
    $script:TemplateChainResources.Clear()  # Junction table
    $script:SequentialReferences.Clear()
    $script:TemplateReferences.Clear()

    # Clear performance indexes
    $script:FilePathToRefIdIndex.Clear()
    $script:TestFunctionStepIndex = $null  # Clear step lookup index
    $script:StructsByFileIndex.Clear()     # Clear struct-by-file index
    $script:StructsByNameIndex.Clear()     # Clear struct-by-name index
    $script:TestFunctionStepsByRefTypeIndex.Clear()  # Clear steps-by-reference-type index
    $script:TestFunctionsByIdIndex.Clear()  # Clear test-function-by-id index
    $script:TestFunctionsByNameIndex.Clear()  # Clear test-function-by-name index

    # Reset counters
    $script:ResourceRefIdCounter = 1
    $script:ServiceRefIdCounter = 1
    $script:FileRefIdCounter = 1
    $script:StructRefIdCounter = 1
    $script:FunctionRefIdCounter = 1
    $script:TestFunctionStepRefIdCounter = 1  # Counter for test function steps (deprecated table)
    $script:TestStepRefIdCounter = 1  # Counter for AST-based test steps
    $script:ConfigRefIdCounter = 1
    $script:DirectRefIdCounter = 1
    $script:IndirectRefIdCounter = 1
    $script:TemplateFunctionRefIdCounter = 1  # For TemplateFunctions table
    $script:TemplateCallChainRefIdCounter = 1  # For AST-based TemplateCallChain
    $script:TemplateChainResourcesRefIdCounter = 1  # For junction table
    $script:SequentialRefIdCounter = 1
    $script:TemplateReferenceRefIdCounter = 1

    # INITIALIZE NORMALIZED LOOKUP TABLES (master data)
    Show-PhaseMessage -Message "Creating Database Tables" -BaseColor $BaseColor -InfoColor $InfoColor

    # Populate Resources table if ResourceName is provided
    if ($ResourceName) {
        $script:Resources[1] = [PSCustomObject]@{
            ResourceRefId = 1
            ResourceName = $ResourceName
        }
        Show-PhaseMessageHighlight -Message "Initialized Resources Table: $ResourceName" -HighlightText "$ResourceName" -HighlightColor $ItemColor -BaseColor $BaseColor -InfoColor $InfoColor
    }

    Show-PhaseMessageHighlight -Message "Populating ReferenceTypes Table" -HighlightText "ReferenceTypes" -HighlightColor $ItemColor -BaseColor $BaseColor -InfoColor $InfoColor
    $initElapsed = (Get-Date) - $initStartTime
    Show-PhaseCompletionGeneric -Description "Database Initialization" -DurationMs ([math]::Round($initElapsed.TotalMilliseconds, 0))
}

function Get-ReferenceTypeName {
    <#
    .SYNOPSIS
    Get ReferenceType name by ID from the normalized lookup table

    .PARAMETER ReferenceTypeId
    The ID of the reference type (1-7)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$ReferenceTypeId
    )

    if ($script:ReferenceTypes.ContainsKey($ReferenceTypeId)) {
        return $script:ReferenceTypes[$ReferenceTypeId].ReferenceTypeName
    }
}

function Get-ReferenceTypes {
    <#
    .SYNOPSIS
    Get all reference types from the lookup table
    #>
    $referenceTypesArray = @()
    foreach ($refType in $script:ReferenceTypes.GetEnumerator()) {
        $referenceTypesArray += [PSCustomObject]@{
            ReferenceTypeId = $refType.Key
            ReferenceTypeName = $refType.Value.ReferenceTypeName
            Description = $refType.Value.Description
        }
    }
    return $referenceTypesArray
}

function Get-ReferenceTypeId {
    <#
    .SYNOPSIS
    Get ReferenceType ID by name from the normalized lookup table

    .PARAMETER ReferenceTypeName
    The name of the reference type (e.g., "CROSS_FILE", "EMBEDDED_SELF")
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReferenceTypeName
    )

    if ($script:ReferenceTypeLookup.ContainsKey($ReferenceTypeName)) {
        return $script:ReferenceTypeLookup[$ReferenceTypeName]
    } else {
        return 0  # Unknown reference type
    }
}

function Add-ServiceRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    # Check if service already exists
    foreach ($service in $script:Services.Values) {
        if ($service.Name -eq $Name) {
            return $service.ServiceRefId
        }
    }

    $serviceRefId = $script:ServiceRefIdCounter++
    $script:Services[$serviceRefId] = [PSCustomObject]@{
        ServiceRefId = $serviceRefId
        Name = $Name
    }

    return $serviceRefId
}

function Add-ResourceRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceName
    )

    # Check if resource already exists
    foreach ($resource in $script:Resources.Values) {
        if ($resource.ResourceName -eq $ResourceName) {
            return $resource.ResourceRefId
        }
    }

    $resourceRefId = $script:ResourceRefIdCounter++
    $script:Resources[$resourceRefId] = [PSCustomObject]@{
        ResourceRefId = $resourceRefId
        ResourceName = $ResourceName
    }

    return $resourceRefId
}

function Add-FileRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [int]$ServiceRefId
    )

    # DEDUPLICATION: Check if file already exists (prevents duplicates from Phase 2 + Phase 2.5)
    if ($script:FilePathToRefIdIndex.ContainsKey($FilePath)) {
        return $script:FilePathToRefIdIndex[$FilePath]
    }

    $fileRefId = $script:FileRefIdCounter++
    $script:Files[$fileRefId] = [PSCustomObject]@{
        FileRefId = $fileRefId
        FilePath = $FilePath
        ServiceRefId = $ServiceRefId
    }

    # Maintain performance index for O(1) path-to-FileRefId lookups
    $script:FilePathToRefIdIndex[$FilePath] = $fileRefId

    return $fileRefId
}

function Add-StructRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StructName
    )

    # Check if struct already exists
    foreach ($struct in $script:Structs.Values) {
        if ($struct.StructName -eq $StructName) {
            return $struct.StructRefId
        }
    }

    $structRefId = $script:StructRefIdCounter++
    $script:Structs[$structRefId] = [PSCustomObject]@{
        StructRefId = $structRefId
        StructName = $StructName
    }

    return $structRefId
}

function Add-TestFunctionRecord {
    param(
        [Parameter(Mandatory = $true)]
        [int]$FileRefId,
        [Parameter(Mandatory = $false)]
        [Nullable[int]]$StructRefId,
        [Parameter(Mandatory = $true)]
        [string]$FunctionName,
        [Parameter(Mandatory = $true)]
        [int]$Line,
        [Parameter(Mandatory = $true)]
        [string]$TestPrefix,
        [Parameter(Mandatory = $false)]
        [int]$ReferenceTypeRefId = 0,
        [Parameter(Mandatory = $false)]
        [int]$SequentialEntryPointRefId = 0
    )

    $functionRefId = $script:FunctionRefIdCounter++
    $testFunction = [PSCustomObject]@{
        TestFunctionRefId = $functionRefId          # Primary key
        FileRefId = $FileRefId                      # Foreign key to Files
        StructRefId = $StructRefId                  # Foreign key to Structs
        Line = $Line                                # Line number where function was found
        FunctionName = $FunctionName                # Function name
        TestPrefix = $TestPrefix                    # Test prefix up to and including first underscore
        ReferenceTypeRefId = $ReferenceTypeRefId    # Foreign key to ReferenceTypes (e.g., EXTERNAL_REFERENCE)
        SequentialEntryPointRefId = $SequentialEntryPointRefId # Foreign key to the entry point function that calls this function
    }

    $script:TestFunctions[$functionRefId] = $testFunction

    # Maintain performance index for O(1) test function by ID lookups
    $script:TestFunctionsByIdIndex[$functionRefId] = $testFunction

    # Maintain performance index for O(1) test function by name lookups (supports duplicates)
    if (-not $script:TestFunctionsByNameIndex.ContainsKey($FunctionName)) {
        $script:TestFunctionsByNameIndex[$FunctionName] = @()
    }
    $script:TestFunctionsByNameIndex[$FunctionName] += $functionRefId

    return $functionRefId
}

function Add-TestFunctionStepRecord {
    <#
    .SYNOPSIS
    Add a test function step record with proper foreign keys

    .PARAMETER TestFunctionRefId
    Foreign key to TestFunctions table

    .PARAMETER StepIndex
    Step index within the function (1, 2, 3...)

    .PARAMETER StepBody
    The actual step content or "SEQUENTIAL_PATTERN" for sequential functions

    .PARAMETER ConfigTemplate
    Template reference like "r.basicConfig" or "testResource.updateConfig"

    .PARAMETER StructRefId
    Foreign key to Structs table if struct detected

    .PARAMETER ReferenceTypeId
    Foreign key to ReferenceTypes table

    .PARAMETER StructVisibilityTypeId
    Foreign key to ReferenceTypes table for struct visibility (PRIVATE_REFERENCE=11, PUBLIC_REFERENCE=12)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionRefId,
        [Parameter(Mandatory = $true)]
        [int]$StepIndex,
        [Parameter(Mandatory = $true)]
        [string]$StepBody,
        [Parameter(Mandatory = $false)]
        [string]$ConfigTemplate = $null,
        [Parameter(Mandatory = $false)]
        [Nullable[int]]$StructRefId = $null,
        [Parameter(Mandatory = $true)]
        [int]$ReferenceTypeId,
        [Parameter(Mandatory = $false)]
        [Nullable[int]]$StructVisibilityTypeId = $null
    )

    $stepRefId = $script:TestFunctionStepRefIdCounter++
    $step = [PSCustomObject]@{
        TestFunctionStepRefId = $stepRefId          # Primary key
        TestFunctionRefId = $TestFunctionRefId      # Foreign key to TestFunctions
        StepIndex = $StepIndex                      # Step order within function
        StepBody = $StepBody                        # Step content
        ConfigTemplate = $ConfigTemplate            # Template reference
        StructRefId = $StructRefId                  # Foreign key to Structs
        ReferenceTypeId = $ReferenceTypeId          # Foreign key to ReferenceTypes
        StructVisibilityTypeId = $StructVisibilityTypeId # Foreign key to ReferenceTypes for struct visibility
    }

    $script:TestFunctionSteps[$stepRefId] = $step

    # Maintain performance indexes for reference type filtering
    if (-not $script:TestFunctionStepsByRefTypeIndex.ContainsKey($ReferenceTypeId)) {
        $script:TestFunctionStepsByRefTypeIndex[$ReferenceTypeId] = @()
    }
    $script:TestFunctionStepsByRefTypeIndex[$ReferenceTypeId] += $stepRefId

    return $stepRefId
}

function Get-TestFunctionStepsByFunctionId {
    <#
    .SYNOPSIS
    Get all test function steps for a specific function

    .PARAMETER TestFunctionRefId
    The TestFunction ID to get steps for
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionRefId
    )

    return $script:TestFunctionSteps.Values | Where-Object { $_.TestFunctionRefId -eq $TestFunctionRefId } | Sort-Object StepIndex
}

function Get-AllTestFunctionSteps {
    <#
    .SYNOPSIS
    Get all test function steps from the database - O(1) operation
    #>
    return $script:TestSteps.Values
}

function Get-TestFunctionStepsByReferenceType {
    <#
    .SYNOPSIS
    Get all test function steps with a specific ReferenceTypeId (O(1) index-based lookup)

    .PARAMETER ReferenceTypeId
    The reference type ID to filter by

    .RETURNS
    Array of test function step records for the specified reference type
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$ReferenceTypeId
    )

    # O(1) index-based lookup instead of O(n) Where-Object filtering
    if ($script:TestFunctionStepsByRefTypeIndex.ContainsKey($ReferenceTypeId)) {
        $stepRefIds = $script:TestFunctionStepsByRefTypeIndex[$ReferenceTypeId]
        $refTypeSteps = @()
        foreach ($stepRefId in $stepRefIds) {
            if ($script:TestSteps.ContainsKey($stepRefId)) {
                $refTypeSteps += $script:TestSteps[$stepRefId]
            }
        }
        return $refTypeSteps
    }

    return @()
}

function Update-TestFunctionStepStructRefId {
    <#
    .SYNOPSIS
    Update the StructRefId for a TestFunctionStep record

    .PARAMETER TestFunctionStepRefId
    The TestFunctionStep ID to update

    .PARAMETER StructRefId
    The new StructRefId to set
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionStepRefId,
        [Parameter(Mandatory = $true)]
        [int]$StructRefId
    )

    if ($script:TestFunctionSteps.ContainsKey($TestFunctionStepRefId)) {
        $script:TestFunctionSteps[$TestFunctionStepRefId].StructRefId = $StructRefId
        return $true
    }

    Write-Warning "TestFunctionStepRefId $TestFunctionStepRefId not found in database"
    return $false
}

function Update-TestFunctionStepReferenceType {
    <#
    .SYNOPSIS
    Update the ReferenceTypeId for a TestFunctionStep record

    .PARAMETER TestFunctionStepRefId
    The TestFunctionStep ID to update

    .PARAMETER ReferenceTypeId
    The new ReferenceTypeId to set
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionStepRefId,
        [Parameter(Mandatory = $true)]
        [int]$ReferenceTypeId
    )

    if ($script:TestFunctionSteps.ContainsKey($TestFunctionStepRefId)) {
        $script:TestFunctionSteps[$TestFunctionStepRefId].ReferenceTypeId = $ReferenceTypeId
        return $true
    }

    Write-Warning "TestFunctionStepRefId $TestFunctionStepRefId not found in database"
    return $false
}

function Update-TestFunctionStepStructVisibility {
    <#
    .SYNOPSIS
    Update the StructVisibilityTypeId for a TestFunctionStep record

    .PARAMETER TestFunctionStepRefId
    The TestFunctionStep ID to update

    .PARAMETER StructVisibilityTypeId
    The new StructVisibilityTypeId to set (11=PRIVATE_REFERENCE, 12=PUBLIC_REFERENCE)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionStepRefId,
        [Parameter(Mandatory = $true)]
        [int]$StructVisibilityTypeId
    )

    if ($script:TestFunctionSteps.ContainsKey($TestFunctionStepRefId)) {
        $script:TestFunctionSteps[$TestFunctionStepRefId].StructVisibilityTypeId = $StructVisibilityTypeId
        return $true
    }

    Write-Warning "TestFunctionStepRefId $TestFunctionStepRefId not found in database"
    return $false
}

function Update-IndirectConfigReferenceServiceImpact {
    <#
    .SYNOPSIS
    Update the ServiceImpactTypeId for an IndirectConfigReference record

    .PARAMETER IndirectRefId
    The IndirectConfigReference ID to update

    .PARAMETER ServiceImpactTypeId
    The new ServiceImpactTypeId to set (14=SAME_SERVICE, 15=CROSS_SERVICE)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$IndirectRefId,
        [Parameter(Mandatory = $true)]
        [int]$ServiceImpactTypeId
    )

    if ($script:IndirectConfigReferences.ContainsKey($IndirectRefId)) {
        $script:IndirectConfigReferences[$IndirectRefId].ServiceImpactTypeId = $ServiceImpactTypeId
        return $true
    }

    Write-Warning "IndirectRefId $IndirectRefId not found in database"
    return $false
}



function Get-TestFunctionStepRefIdByIndex {
    <#
    .SYNOPSIS
    Get TestFunctionStepRefId by TestFunctionRefId and step index (1-based) - O(1) lookup

    .PARAMETER TestFunctionRefId
    The TestFunction ID

    .PARAMETER StepIndex
    The 1-based step index within the function
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionRefId,
        [Parameter(Mandatory = $true)]
        [int]$StepIndex
    )

    # Create composite key for O(1) lookup
    $compositeKey = "$TestFunctionRefId-$StepIndex"

    # Build index on first use if not exists
    if (-not $script:TestFunctionStepIndex) {
        $script:TestFunctionStepIndex = @{}
        foreach ($step in $script:TestFunctionSteps.Values) {
            $key = "$($step.TestFunctionRefId)-$($step.StepIndex)"
            $script:TestFunctionStepIndex[$key] = $step.TestFunctionStepRefId
        }
    }

    if ($script:TestFunctionStepIndex.ContainsKey($compositeKey)) {
        return $script:TestFunctionStepIndex[$compositeKey]
    }

    # If no TestFunctionStep exists for this index, return 0 (silently - this is normal for functions without TestStep arrays)
    return 0
}

function Add-DirectResourceReferenceRecord {
    <#
    .SYNOPSIS
    Add a direct resource reference record with proper foreign keys

    .PARAMETER TemplateFunctionRefId
    Foreign key to TemplateFunctions table

    .PARAMETER ResourceRefId
    Foreign key to Resources table

    .PARAMETER ReferenceTypeId
    Reference type ID (4=ATTRIBUTE_REFERENCE, 5=RESOURCE_BLOCK)

    .PARAMETER Context
    The actual HCL line containing the reference

    .PARAMETER TemplateLine
    Line number in source file where template function is defined

    .PARAMETER ContextLine
    Line number within the HCL template string
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TemplateFunctionRefId,
        [Parameter(Mandatory = $true)]
        [int]$ResourceRefId,
        [Parameter(Mandatory = $true)]
        [int]$ReferenceTypeId,
        [Parameter(Mandatory = $false)]
        [string]$Context = "",
        [Parameter(Mandatory = $false)]
        [int]$TemplateLine = 0,
        [Parameter(Mandatory = $false)]
        [int]$ContextLine = 0
    )

    $directRefId = $script:DirectRefIdCounter++
    $script:DirectResourceReferences[$directRefId] = [PSCustomObject]@{
        DirectRefId = $directRefId                      # Primary key
        TemplateFunctionRefId = $TemplateFunctionRefId  # Foreign key to TemplateFunctions
        ResourceRefId = $ResourceRefId                  # Foreign key to Resources
        ReferenceTypeId = $ReferenceTypeId              # Foreign key to ReferenceTypes (4 or 5)
        Context = $Context                              # The actual HCL line
        TemplateLine = $TemplateLine                    # Line in source file where template function starts
        ContextLine = $ContextLine                      # Line within HCL template string
    }

    return $directRefId
}

function Add-IndirectConfigReferenceRecord {
    <#
    .SYNOPSIS
    Add indirect config reference using proper foreign key relationships (NORMALIZED DESIGN)

    .PARAMETER TestFunctionStepRefId
    Foreign key to TestFunctionSteps table - which test step this reference belongs to

    .PARAMETER TemplateReferenceRefId
    Foreign key to TemplateReferences table

    .PARAMETER SourceTemplateFunctionRefId
    Foreign key to TemplateFunctions table - the source template function

    .PARAMETER ServiceImpactTypeId
    Foreign key to ReferenceTypes table for service impact classification (SAME_SERVICE=14, CROSS_SERVICE=15)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionStepRefId,
        [Parameter(Mandatory = $true)]
        [int]$TemplateReferenceRefId,
        [Parameter(Mandatory = $true)]
        [int]$SourceTemplateFunctionRefId,
        [Parameter(Mandatory = $false)]
        [Nullable[int]]$ServiceImpactTypeId = $null
    )

    # NORMALIZED: Compute ReferenceType using proper foreign key relationships
    # Get template reference and source template function records using FKs
    $templateRef = $script:TemplateReferences[$TemplateReferenceRefId]
    $sourceTemplateFunc = $script:TemplateFunctions[$SourceTemplateFunctionRefId]

    if (-not $templateRef -or -not $sourceTemplateFunc) {
        Write-Warning "Invalid foreign key references: TemplateReferenceRefId=$TemplateReferenceRefId, SourceTemplateFunctionRefId=$SourceTemplateFunctionRefId"
        return $null
    }

    # Get test function that calls the template (via TemplateReference FK)
    $testFunc = $script:TestFunctions[$templateRef.TestFunctionRefId]
    if (-not $testFunc) {
        Write-Warning "Invalid TestFunctionRefId in TemplateReference: $($templateRef.TestFunctionRefId)"
        return $null
    }

    # Determine ReferenceType using file relationships (proper relational logic!)
    $testFileRefId = $testFunc.FileRefId
    $templateFileRefId = $sourceTemplateFunc.FileRefId

    $referenceTypeId = if ($testFileRefId -eq $templateFileRefId) {
        3  # EMBEDDED_SELF
    } else {
        2  # CROSS_FILE
    }

    $indirectRefId = $script:IndirectRefIdCounter++
    $script:IndirectConfigReferences[$indirectRefId] = [PSCustomObject]@{
        IndirectRefId = $indirectRefId                          # Primary key
        TestFunctionStepRefId = $TestFunctionStepRefId          # Foreign key to TestFunctionSteps
        TemplateReferenceRefId = $TemplateReferenceRefId        # Foreign key to TemplateReferences
        SourceTemplateFunctionRefId = $SourceTemplateFunctionRefId  # Foreign key to TemplateFunctions
        ReferenceTypeId = $referenceTypeId                      # Foreign key to ReferenceTypes (normalized!)
        ServiceImpactTypeId = $ServiceImpactTypeId              # Foreign key to ReferenceTypes for service impact
    }

    return $indirectRefId
}

function Add-TemplateFunctionRecord {
    <#
    .SYNOPSIS
    Add template function record (AST-optimized schema without function bodies)

    .DESCRIPTION
    Stores template function metadata extracted by Replicode.
    Function bodies are NOT stored (304K row reduction).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateFunctionName,
        [Parameter(Mandatory = $true)]
        [int]$StructRefId,
        [Parameter(Mandatory = $true)]
        [int]$FileRefId,
        [Parameter(Mandatory = $true)]
        [string]$ReceiverType,  # "pointer" or "value"
        [Parameter(Mandatory = $true)]
        [bool]$ReturnsString,  # true if returns string, false otherwise
        [Parameter(Mandatory = $true)]
        [int]$Line
    )

    $templateFunctionRefId = $script:TemplateFunctionRefIdCounter++
    $script:TemplateFunctions[$templateFunctionRefId] = [PSCustomObject]@{
        TemplateFunctionRefId = $templateFunctionRefId
        TemplateFunctionName = $TemplateFunctionName
        StructRefId = $StructRefId
        FileRefId = $FileRefId
        ReceiverType = $ReceiverType
        ReturnsString = $ReturnsString
        Line = $Line
    }

    return $templateFunctionRefId
}

#region AST-Optimized Functions (Phase 1)

function Add-TemplateCallChainRecord {
    <#
    .SYNOPSIS
    Add template call chain record (replaces TemplateCalls + IndirectConfigReferences)

    .DESCRIPTION
    Stores template → template call chains resolved by Replicode.
    Supports both same-file (local) and cross-file template calls.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$SourceTemplateFunctionRefId,
        [Parameter(Mandatory = $true)]
        [int]$TargetTemplateFunctionRefId,
        [Parameter(Mandatory = $true)]
        [int]$SourceServiceRefId,
        [Parameter(Mandatory = $true)]
        [int]$TargetServiceRefId,
        [Parameter(Mandatory = $true)]
        [int]$ChainDepth,
        [Parameter(Mandatory = $true)]
        [bool]$CrossesServiceBoundary,
        [Parameter(Mandatory = $true)]
        [int]$ReferenceTypeId,
        [Parameter(Mandatory = $true)]
        [bool]$IsLocalCall
    )

    $chainRefId = $script:TemplateCallChainRefIdCounter++
    $script:TemplateCallChain[$chainRefId] = [PSCustomObject]@{
        ChainRefId = $chainRefId
        SourceTemplateFunctionRefId = $SourceTemplateFunctionRefId
        TargetTemplateFunctionRefId = $TargetTemplateFunctionRefId
        SourceServiceRefId = $SourceServiceRefId
        TargetServiceRefId = $TargetServiceRefId
        ChainDepth = $ChainDepth
        CrossesServiceBoundary = $CrossesServiceBoundary
        ReferenceTypeId = $ReferenceTypeId
        IsLocalCall = $IsLocalCall
    }

    return $chainRefId
}

function Add-TemplateChainResourceRecord {
    <#
    .SYNOPSIS
    Add junction table record linking template call chains to ultimate resource references

    .DESCRIPTION
    Stores which resources are ultimately referenced at the end of template call chains.
    Replaces JSON arrays with proper relational design.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$ChainRefId,
        [Parameter(Mandatory = $true)]
        [int]$ResourceRefId
    )

    $chainResourceRefId = $script:TemplateChainResourcesRefIdCounter++
    $script:TemplateChainResources[$chainResourceRefId] = [PSCustomObject]@{
        ChainResourceRefId = $chainResourceRefId
        ChainRefId = $ChainRefId
        ResourceRefId = $ResourceRefId
    }

    return $chainResourceRefId
}

function Add-TestStepRecord {
    <#
    .SYNOPSIS
    Add test step record with FK relationships (AST-optimized schema)

    .DESCRIPTION
    Stores test step → template relationships using direct FK references.
    Replaces ConfigTemplate strings with TemplateFunctionRefId FK.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionRefId,
        [Parameter(Mandatory = $true)]
        [int]$TemplateFunctionRefId,  # Direct FK to template being called
        [Parameter(Mandatory = $true)]
        [int]$StepIndex,
        [Parameter(Mandatory = $true)]
        [int]$TargetStructRefId,
        [Parameter(Mandatory = $true)]
        [int]$TargetServiceRefId,  # FK to Services table
        [Parameter(Mandatory = $true)]
        [int]$ReferenceTypeId,
        [Parameter(Mandatory = $true)]
        [int]$Line
    )

    $testStepRefId = $script:TestStepRefIdCounter++
    $script:TestSteps[$testStepRefId] = [PSCustomObject]@{
        TestStepRefId = $testStepRefId
        TestFunctionRefId = $TestFunctionRefId
        TemplateFunctionRefId = $TemplateFunctionRefId
        StepIndex = $StepIndex
        TargetStructRefId = $TargetStructRefId
        TargetServiceRefId = $TargetServiceRefId
        ReferenceTypeId = $ReferenceTypeId
        Line = $Line
    }

    return $testStepRefId
}

function Add-DirectResourceReference {
    <#
    .SYNOPSIS
    Add direct resource reference with FK relationships (AST-optimized schema)

    .DESCRIPTION
    Stores direct resource mentions in template functions using FK references.
    Replaces ResourceName strings with ResourceRefId FK.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TemplateFunctionRefId,  # FK to template containing reference
        [Parameter(Mandatory = $true)]
        [int]$ResourceRefId,  # FK to Resources table
        [Parameter(Mandatory = $true)]
        [int]$ReferenceTypeId,
        [Parameter(Mandatory = $true)]
        [string]$Context,
        [Parameter(Mandatory = $true)]
        [int]$Line
    )

    $directRefId = $script:DirectRefIdCounter++
    $script:DirectResourceReferences[$directRefId] = [PSCustomObject]@{
        DirectRefId = $directRefId
        TemplateFunctionRefId = $TemplateFunctionRefId
        ResourceRefId = $ResourceRefId
        ReferenceTypeId = $ReferenceTypeId
        Context = $Context
        Line = $Line
    }

    return $directRefId
}

# Alias for backward compatibility
Set-Alias -Name Add-DirectResourceReferenceRecord -Value Add-DirectResourceReference
Set-Alias -Name Add-TestFunctionStepRecord -Value Add-TestStepRecord

#endregion

function Add-SequentialReferenceRecord {
    <#
    .SYNOPSIS
    Add a sequential reference record linking a referenced function to its entry point

    .PARAMETER EntryPointFunctionRefId
    Foreign key to TestFunctions - the main entry point function (e.g., TestAccCustomIpPrefixV4)

    .PARAMETER ReferencedFunctionRefId
    Foreign key to TestFunctions - the referenced function (e.g., testAccCustomIpPrefix_ipv4)

    .PARAMETER SequentialGroup
    The group name from the acceptance.RunTestsInSequence map (e.g., "ipv4", "ipv6")

    .PARAMETER SequentialKey
    The key name from the acceptance.RunTestsInSequence map (e.g., "commissioned", "requiresImport")
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$EntryPointFunctionRefId,
        [Parameter(Mandatory = $true)]
        [int]$ReferencedFunctionRefId,
        [Parameter(Mandatory = $true)]
        [string]$SequentialGroup,
        [Parameter(Mandatory = $true)]
        [string]$SequentialKey
    )

    $sequentialRefId = $script:SequentialRefIdCounter++
    $script:SequentialReferences[$sequentialRefId] = [PSCustomObject]@{
        SequentialRefId = $sequentialRefId                  # Primary key
        EntryPointFunctionRefId = $EntryPointFunctionRefId  # Foreign key to TestFunctions (main function)
        ReferencedFunctionRefId = $ReferencedFunctionRefId  # Foreign key to TestFunctions (referenced function)
        SequentialGroup = $SequentialGroup                  # Group name (e.g., "ipv4", "ipv6")
        SequentialKey = $SequentialKey                      # Key name (e.g., "commissioned", "requiresImport")
    }

    return $sequentialRefId
}

function Add-TemplateReferenceRecord {
    <#
    .SYNOPSIS
    Add a template reference record linking a test function to a template method call

    .PARAMETER TestFunctionRefId
    Foreign key to TestFunctions - the test function making the template call

    .PARAMETER StructRefId
    Foreign key to Structs - the struct context of the calling test function

    .PARAMETER TestFunctionStepRefId
    Foreign key to TestFunctionSteps - the specific step containing this template reference

    .PARAMETER TemplateReference
    The actual template reference (e.g., "r.basic", "r.requiresImport")

    .PARAMETER TemplateVariable
    The variable used (e.g., "r") - can be null

    .PARAMETER TemplateMethod
    The method called (e.g., "basic", "requiresImport") - can be null
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionRefId,
        [Parameter(Mandatory = $true)]
        [int]$StructRefId,
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionStepRefId,
        [Parameter(Mandatory = $true)]
        [string]$TemplateReference,
        [Parameter(Mandatory = $false)]
        [string]$TemplateVariable = "",
        [Parameter(Mandatory = $false)]
        [string]$TemplateMethod = ""
    )

    $templateReferenceRefId = $script:TemplateReferenceRefIdCounter++
    $script:TemplateReferences[$templateReferenceRefId] = [PSCustomObject]@{
        TemplateReferenceRefId = $templateReferenceRefId    # Primary key
        TestFunctionRefId = $TestFunctionRefId              # Foreign key to TestFunctions
        TestFunctionStepRefId = $TestFunctionStepRefId      # Foreign key to TestFunctionSteps
        StructRefId = $StructRefId                          # Foreign key to Structs (struct context)
        TemplateReference = $TemplateReference              # Full template reference (e.g., "r.basic")
        TemplateVariable = $TemplateVariable                # Variable used (e.g., "r")
        TemplateMethod = $TemplateMethod                    # Method called (e.g., "basic")
    }

    return $templateReferenceRefId
}

# Query functions for the analysis phases
function Get-TestFunctions {
    return $script:TestFunctions.Values
}

function Get-TestFunctionById {
    <#
    .SYNOPSIS
    Get a test function by ID (O(1) index-based lookup)

    .PARAMETER TestFunctionRefId
    The TestFunction ID to retrieve

    .RETURNS
    Test function record or $null if not found
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionRefId
    )

    # O(1) index-based lookup instead of O(n) iteration/filtering
    if ($script:TestFunctionsByIdIndex.ContainsKey($TestFunctionRefId)) {
        return $script:TestFunctionsByIdIndex[$TestFunctionRefId]
    }

    return $null
}

function Get-TestFunctionByName {
    <#
    .SYNOPSIS
    Get test functions by function name (O(1) index-based lookup)

    .PARAMETER FunctionName
    The function name to search for

    .RETURNS
    First matching test function record (prioritizes non-external records), or $null if not found

    .DESCRIPTION
    This function uses O(1) index lookup to find test functions by name. If multiple records exist
    with the same name (e.g., one external stub and one actual function), it returns the actual
    function (FileRefId != 0) first.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FunctionName
    )

    # O(1) index lookup - returns array of TestFunctionRefIds
    if (-not $script:TestFunctionsByNameIndex.ContainsKey($FunctionName)) {
        return $null
    }

    $functionRefIds = $script:TestFunctionsByNameIndex[$FunctionName]

    # If multiple records exist, prioritize non-external (FileRefId != 0)
    foreach ($refId in $functionRefIds) {
        $func = $script:TestFunctionsByIdIndex[$refId]
        if ($func.FileRefId -ne 0) {
            return $func  # Return actual function first
        }
    }

    # If no actual function found, return first match (external stub)
    if ($functionRefIds.Count -gt 0) {
        return $script:TestFunctionsByIdIndex[$functionRefIds[0]]
    }

    return $null
}

function Get-SequentialReferences {
    <#
    .SYNOPSIS
    Get all sequential reference records

    .DESCRIPTION
    Returns all sequential reference records that link referenced functions to their entry points
    #>
    return $script:SequentialReferences.Values
}

function Get-Structs {
    return $script:Structs.Values  # Renamed table
}

function Get-StructById {
    <#
    .SYNOPSIS
    Get a struct by its StructRefId using O(1) hashtable lookup
    .PARAMETER StructRefId
    The ID of the struct to retrieve
    .DESCRIPTION
    Provides O(1) performance instead of O(n) Where-Object filtering
    #>
    param(
        [int]$StructRefId
    )

    return $script:Structs[$StructRefId]
}

function Get-StructRefIdByName {
    <#
    .SYNOPSIS
    Get the StructRefId for a struct by name from the global structs table (O(1) index-based lookup)
    .PARAMETER StructName
    The name of the struct to look up
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StructName
    )

    # O(1) index-based lookup instead of O(n) iteration
    if ($script:StructsByNameIndex.ContainsKey($StructName)) {
        return $script:StructsByNameIndex[$StructName]
    }

    return $null
}

function Get-DirectResourceReferences {
    return $script:DirectResourceReferences.Values
}

function Get-IndirectConfigReferences {
    return $script:IndirectConfigReferences.Values
}

function Get-TemplateReferences {
    <#
    .SYNOPSIS
    Get all template reference records

    .DESCRIPTION
    Returns all template reference records that link test functions to their template method calls
    #>
    return $script:TemplateReferences.Values
}

function Get-Files {
    return $script:Files.Values
}

function Get-FileRefIdByPath {
    <#
    .SYNOPSIS
        Get FileRefId by file path using O(1) index lookup

    .PARAMETER FilePath
        Relative file path to get FileRefId for

    .RETURNS
        FileRefId integer, or $null if not found
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if ($script:FilePathToRefIdIndex.ContainsKey($FilePath)) {
        return $script:FilePathToRefIdIndex[$FilePath]
    }

    return $null
}

function Get-FilePathByRefId {
    <#
    .SYNOPSIS
        Retrieve file path from the database by FileRefId (O(1) lookup)

    .PARAMETER FileRefId
        FileRefId to retrieve path for

    .RETURNS
        File path string, or $null if not found
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$FileRefId
    )

    if ($script:Files.ContainsKey($FileRefId)) {
        return $script:Files[$FileRefId].FilePath
    }

    return $null
}

function Get-FileRecordByRefId {
    <#
    .SYNOPSIS
        Retrieve complete file record from the database by FileRefId (O(1) lookup)

    .PARAMETER FileRefId
        FileRefId to retrieve record for

    .RETURNS
        Complete file record object, or $null if not found
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$FileRefId
    )

    if ($script:Files.ContainsKey($FileRefId)) {
        return $script:Files[$FileRefId]
    }

    return $null
}

function Get-Services {
    return $script:Services.Values
}

function Get-ServiceRefIdByFilePath {
    <#
    .SYNOPSIS
    Get ServiceRefId for a file by its FilePath - O(1) indexed lookup

    .PARAMETER FilePath
    The file path to look up (e.g., "internal/services/recoveryservices/vault_resource_test.go")

    .DESCRIPTION
    Uses the FilePathToRefIdIndex for O(1) lookup, then retrieves ServiceRefId from Files table.
    Returns the authoritative ServiceRefId for the file, or $null if file not found.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    # O(1) lookup via index
    if ($script:FilePathToRefIdIndex.ContainsKey($FilePath)) {
        $fileRefId = $script:FilePathToRefIdIndex[$FilePath]
        if ($script:Files.ContainsKey($fileRefId)) {
            return $script:Files[$fileRefId].ServiceRefId
        }
    }

    return $null
}

function Get-TemplateFunctions {  # Renamed from Get-TestConfiguration
    return $script:TemplateFunctions.Values  # Renamed table
}

function Get-ExportDirectory {
    return $script:ExportDirectory
}

function Export-DatabaseToCSV {
    <#
    .SYNOPSIS
    Export all database tables to CSV files for analysis
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$ExportPath = $script:ExportDirectory,

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",

        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    if (-not $ExportPath) {
        # TODO: UX IMPROVEMENT NEEDED - PowerShell exceptions are not user-friendly
        # Replace this with a custom error message using Show-PhaseMessage or similar UI function
        # The current throw pattern displays ugly PowerShell stack traces that don't help users
        throw "No export path specified and no database path set"
    }

    # If ExportPath is a directory, use it directly
    # If ExportPath is a file path, get its parent directory
    if (Test-Path $ExportPath -PathType Container) {
        $exportDir = $ExportPath
    } elseif ($ExportPath.EndsWith('.csv') -or $ExportPath.Contains('.')) {
        # Looks like a file path, get parent directory
        $exportDir = Split-Path $ExportPath -Parent
    } else {
        # Treat as directory path
        $exportDir = $ExportPath
    }

    # Resolve to absolute path to avoid showing relative paths with ".."
    $resolvedDir = Resolve-Path $exportDir -ErrorAction SilentlyContinue
    if ($resolvedDir) {
        $exportDir = $resolvedDir.Path
    }

    if (!(Test-Path $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }

    # Helper function to export table with headers even when empty
    function Export-TableWithHeaders {
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [object[]]$Data,
            [Parameter(Mandatory = $true)]
            [string]$FilePath,
            [Parameter(Mandatory = $true)]
            [hashtable]$EmptyRowTemplate
        )

        if ($Data -and $Data.Count -gt 0) {
            # Table has data, export normally
            $Data | Export-Csv -Path $FilePath -NoTypeInformation
        } else {
            # Table is empty, write just the header
            $headerNames = $EmptyRowTemplate.Keys | Sort-Object
            $headerLine = '"' + ($headerNames -join '","') + '"'
            $headerLine | Set-Content $FilePath
        }
    }    try {
        # Define empty row templates for each table
        $emptyTemplates = @{
            Resources = @{
                ResourceRefId = $null
                ResourceName = ""
            }
            Services = @{
                ServiceRefId = $null
                ResourceRefId = $null
                Name = ""
            }
            Files = @{
                FileRefId = $null
                FilePath = ""
                ServiceRefId = $null
            }
            Structs = @{
                StructRefId = $null
                ResourceRefId = $null
                FileRefId = $null
                Line = $null
                StructName = ""
            }
            TestFunctions = @{
                TestFunctionRefId = $null
                ResourceRefId = $null
                FileRefId = $null
                StructRefId = 0
                Line = $null
                FunctionName = ""
                TestPrefix = ""
                ReferenceTypeRefId = 0
                SequentialEntryPointRefId = 0
            }
            TestSteps = @{
                TestStepRefId = $null  # Primary key
                TestFunctionRefId = $null  # FK to TestFunctions
                TemplateFunctionRefId = $null  # FK to TemplateFunctions (direct FK replaces ConfigTemplate string)
                StepIndex = $null  # Sequential step number within test
                TargetStructRefId = $null  # FK to Structs (explicit target struct)
                TargetServiceRefId = $null  # FK to Services (explicit target service)
                ReferenceTypeId = $null  # FK to ReferenceTypes enum
                Line = $null  # Source line number in Go file
            }
            DirectResourceReferences = @{
                DirectRefId = $null
                TemplateFunctionRefId = $null
                ResourceRefId = $null
                ReferenceTypeId = $null
                Context = ""
                TemplateLine = $null
                ContextLine = $null
            }
            IndirectConfigReferences = @{
                IndirectRefId = $null
                TestFunctionStepRefId = $null
                TemplateReferenceRefId = $null
                SourceTemplateFunctionRefId = $null
                ReferenceTypeId = $null
                ServiceImpactTypeId = $null
            }
            TemplateFunctions = @{
                TemplateFunctionRefId = $null
                ResourceRefId = $null
                TemplateFunctionName = ""
                StructRefId = $null
                FileRefId = $null
                Line = $null
                ReceiverVariable = ""
            }
            SequentialReferences = @{
                SequentialRefId = $null
                EntryPointFunctionRefId = $null
                ReferencedFunctionRefId = $null
                SequentialGroup = ""
                SequentialKey = ""
            }
            TemplateReferences = @{
                TemplateReferenceRefId = $null
                TestFunctionRefId = $null
                TestFunctionStepRefId = $null
                StructRefId = $null
                TemplateReference = ""
                TemplateVariable = ""
                TemplateMethod = ""
            }
            ReferenceTypes = @{
                ReferenceTypeId = $null
                ReferenceTypeName = ""
            }
        }

        # Convert ReferenceTypes hashtable to array of objects for CSV export
        $referenceTypesArray = @()
        foreach ($refType in $script:ReferenceTypes.GetEnumerator()) {
            # $refType.Key = Integer ID, $refType.Value = PSCustomObject with ReferenceTypeId and ReferenceTypeName
            $referenceTypesArray += [PSCustomObject]@{
                ReferenceTypeId = $refType.Value.ReferenceTypeId
                ReferenceTypeName = $refType.Value.ReferenceTypeName
            }
        }

        # Export each table to CSV with headers
        Export-TableWithHeaders -Data @($script:Resources.Values) -FilePath (Join-Path $exportDir "Resources.csv") -EmptyRowTemplate $emptyTemplates.Resources

        # Add ResourceRefId = 1 to records during export (cold path) to avoid overhead during record creation (hot path)
        $servicesWithResourceRef = @($script:Services.Values) | ForEach-Object {
            $_ | Add-Member -NotePropertyName "ResourceRefId" -NotePropertyValue 1 -PassThru -Force
        }
        Export-TableWithHeaders -Data $servicesWithResourceRef -FilePath (Join-Path $exportDir "Services.csv") -EmptyRowTemplate $emptyTemplates.Services

        Export-TableWithHeaders -Data @($script:Files.Values) -FilePath (Join-Path $exportDir "Files.csv") -EmptyRowTemplate $emptyTemplates.Files

        $structsWithResourceRef = @($script:Structs.Values) | ForEach-Object {
            $_ | Add-Member -NotePropertyName "ResourceRefId" -NotePropertyValue 1 -PassThru -Force
        }
        Export-TableWithHeaders -Data $structsWithResourceRef -FilePath (Join-Path $exportDir "Structs.csv") -EmptyRowTemplate $emptyTemplates.Structs

        $testFunctionsWithResourceRef = @($script:TestFunctions.Values) | ForEach-Object {
            $_ | Add-Member -NotePropertyName "ResourceRefId" -NotePropertyValue 1 -PassThru -Force
        }
        Export-TableWithHeaders -Data $testFunctionsWithResourceRef -FilePath (Join-Path $exportDir "TestFunctions.csv") -EmptyRowTemplate $emptyTemplates.TestFunctions
        Export-TableWithHeaders -Data @($script:TestSteps.Values) -FilePath (Join-Path $exportDir "TestFunctionSteps.csv") -EmptyRowTemplate $emptyTemplates.TestSteps
        Export-TableWithHeaders -Data @($script:DirectResourceReferences.Values) -FilePath (Join-Path $exportDir "DirectResourceReferences.csv") -EmptyRowTemplate $emptyTemplates.DirectResourceReferences
        Export-TableWithHeaders -Data @($script:IndirectConfigReferences.Values) -FilePath (Join-Path $exportDir "IndirectConfigReferences.csv") -EmptyRowTemplate $emptyTemplates.IndirectConfigReferences

        $templateFunctionsWithResourceRef = @($script:TemplateFunctions.Values) | ForEach-Object {
            $_ | Add-Member -NotePropertyName "ResourceRefId" -NotePropertyValue 1 -PassThru -Force
        }
        Export-TableWithHeaders -Data $templateFunctionsWithResourceRef -FilePath (Join-Path $exportDir "TemplateFunctions.csv") -EmptyRowTemplate $emptyTemplates.TemplateFunctions

        Export-TableWithHeaders -Data @($script:SequentialReferences.Values) -FilePath (Join-Path $exportDir "SequentialReferences.csv") -EmptyRowTemplate $emptyTemplates.SequentialReferences
        Export-TableWithHeaders -Data @($script:TemplateReferences.Values) -FilePath (Join-Path $exportDir "TemplateReferences.csv") -EmptyRowTemplate $emptyTemplates.TemplateReferences
        Export-TableWithHeaders -Data @($referenceTypesArray) -FilePath (Join-Path $exportDir "ReferenceTypes.csv") -EmptyRowTemplate $emptyTemplates.ReferenceTypes

        # Calculate dynamic table count by counting actual CSV files in export directory
        $csvFiles = Get-ChildItem -Path $exportDir -Filter "*.csv" -File
        $tableCount = $csvFiles.Count

        Show-PhaseMessageMultiHighlight -Message "Exported: $tableCount Tables" -HighlightTexts @("$tableCount") -HighlightColors @($NumberColor) -BaseColor $BaseColor -InfoColor $InfoColor
    }
    catch {
        # TODO: UX IMPROVEMENT NEEDED - PowerShell exceptions are not user-friendly
        # Replace this with a custom error message using Show-PhaseMessage or similar UI function
        # Example: Show-PhaseMessage -Message "Failed to export database: <friendly error description>" -InfoColor "Red"
        # The current Write-Error + throw pattern displays ugly PowerShell stack traces that don't help users
        Write-Error "Failed to export database to CSV: $($_.Exception.Message)"
        throw
    }
}

function Close-TerraDatabase {
    <#
    .SYNOPSIS
    Clean up the database (placeholder for compatibility)
    #>

    Write-Host "In-memory database closed" -ForegroundColor Green
}

function Invoke-TemplatePopulation {
    <#
    .SYNOPSIS
    Templates table is now populated during Phase 5 (CONFIG METHOD ANALYSIS)
    when configuration methods are discovered and analyzed. This function just reports the results.
    #>

    Write-Host "`n=== TEMPLATE FUNCTIONS TABLE RESULTS ===" -ForegroundColor Cyan
    Write-Host "TemplateFunctions records populated during Phase 5: $($script:TemplateFunctions.Count)" -ForegroundColor Green
    Write-Host "=== TEMPLATE FUNCTIONS COMPLETED ===" -ForegroundColor Cyan
}

function Get-DatabaseStats {
    <#
    .SYNOPSIS
    Get statistics about the current state of all database tables
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$ExportDirectory  # Not used in in-memory implementation, kept for compatibility
    )

    $stats = [PSCustomObject]@{
        # Map the in-memory database tables to expected property names
        Resources = $script:Services.Count
        Tests = $script:TestFunctions.Count
        Functions = $script:Structs.Count
        Dependencies = $script:DirectResourceReferences.Count
        Relationships = $script:IndirectConfigReferences.Count

        # Additional stats for completeness
        ResourcesTable = $script:Resources.Count
        Services = $script:Services.Count
        Files = $script:Files.Count
        Structs = $script:Structs.Count
        TestFunctions = $script:TestFunctions.Count
        TestFunctionSteps = $script:TestSteps.Count  # AST-optimized table name
        DirectResourceReferences = $script:DirectResourceReferences.Count
        IndirectConfigReferences = $script:IndirectConfigReferences.Count
        TemplateFunctions = $script:TemplateFunctions.Count
        SequentialReferences = $script:SequentialReferences.Count
        TemplateReferences = $script:TemplateReferences.Count
        TotalRecords = $script:Resources.Count + $script:Services.Count + $script:Files.Count + $script:Structs.Count + $script:TestFunctions.Count + $script:TestFunctionSteps.Count + $script:DirectResourceReferences.Count + $script:IndirectConfigReferences.Count + $script:TemplateFunctions.Count + $script:SequentialReferences.Count + $script:TemplateReferences.Count
    }

    return $stats
}

function Get-StructsByFileRefId {
    <#
    .SYNOPSIS
    Gets all struct records for a specific file (O(1) index-based lookup)

    .PARAMETER FileRefId
    The file reference ID to filter by

    .RETURNS
    Array of struct records for the specified file
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$FileRefId
    )

    # O(1) index-based lookup instead of O(n) iteration
    if ($script:StructsByFileIndex.ContainsKey($FileRefId)) {
        $structRefIds = $script:StructsByFileIndex[$FileRefId]
        $fileStructs = @()
        foreach ($structRefId in $structRefIds) {
            if ($script:Structs.ContainsKey($structRefId)) {
                $fileStructs += $script:Structs[$structRefId]
            }
        }
        return $fileStructs
    }

    return @()
}

function Update-TestFunctionSequentialInfo {
    <#
    .SYNOPSIS
    Update an existing TestFunction record with sequential entry point information

    .PARAMETER TestFunctionRefId
    The TestFunctionRefId to update

    .PARAMETER SequentialEntryPointRefId
    Foreign key to the entry point function that calls this function
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$TestFunctionRefId,
        [Parameter(Mandatory = $false)]
        [int]$SequentialEntryPointRefId = 0
    )

    if ($script:TestFunctions.ContainsKey($TestFunctionRefId)) {
        $existingRecord = $script:TestFunctions[$TestFunctionRefId]
        $existingRecord.SequentialEntryPointRefId = $SequentialEntryPointRefId
    } else {
        Write-Warning "TestFunctionRefId $TestFunctionRefId not found in database"
    }
}

function Import-DatabaseFromCSV {
    <#
    .SYNOPSIS
    Import all database tables from CSV files for database-only mode

    .DESCRIPTION
    Loads a previously exported database from CSV files back into memory.
    This enables Database Mode where you can query and analyze data without
    re-running the expensive discovery phases.

    .PARAMETER DatabaseDirectory
    Directory path where CSV files are located

    .PARAMETER NumberColor
    Color for numbers in output messages

    .PARAMETER ItemColor
    Color for item types in output messages

    .PARAMETER BaseColor
    Color for base text in output messages

    .PARAMETER InfoColor
    Color for info prefix in output messages

    .RETURNS
    PSCustomObject with import statistics
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseDirectory,

        [Parameter(Mandatory = $false)]
        [string]$NumberColor = "Yellow",

        [Parameter(Mandatory = $false)]
        [string]$ItemColor = "Cyan",

        [Parameter(Mandatory = $false)]
        [string]$BaseColor = "Gray",

        [Parameter(Mandatory = $false)]
        [string]$InfoColor = "Cyan"
    )

    $importStart = Get-Date

    # Validate directory exists
    if (-not (Test-Path $DatabaseDirectory -PathType Container)) {
        throw "Database directory not found: $DatabaseDirectory"
    }

    # Set the export directory for future exports
    $script:ExportDirectory = $DatabaseDirectory

    # Resolve to absolute path
    $resolvedDir = Resolve-Path $DatabaseDirectory -ErrorAction Stop
    $DatabaseDirectory = $resolvedDir.Path

    Show-PhaseHeaderGeneric -Title "Database Initialization" -Description "Terra-Corder"
    Show-PhaseMessage -Message "Loading Database From CSV Files" -BaseColor $BaseColor -InfoColor $InfoColor

    # Clear all in-memory tables first
    $script:Resources.Clear()
    $script:Services.Clear()
    $script:Files.Clear()
    $script:Structs.Clear()
    $script:TestFunctions.Clear()
    $script:TestSteps.Clear()
    $script:DirectResourceReferences.Clear()
    $script:IndirectConfigReferences.Clear()
    $script:TemplateFunctions.Clear()
    $script:SequentialReferences.Clear()
    $script:TemplateReferences.Clear()

    # Clear performance indexes
    $script:FilePathToRefIdIndex.Clear()
    $script:TestFunctionStepIndex = $null
    $script:StructsByFileIndex.Clear()
    $script:StructsByNameIndex.Clear()
    $script:TestFunctionStepsByRefTypeIndex.Clear()
    $script:TestFunctionsByIdIndex.Clear()

    # Helper function to import CSV with proper type handling
    function Import-TableFromCSV {
        param(
            [string]$FilePath,
            [string]$TableName
        )

        if (-not (Test-Path $FilePath)) {
            Show-PhaseMessageHighlight -Message "Warning: $TableName.csv not found - skipping" -HighlightText "$TableName" -HighlightColor "Yellow" -BaseColor $BaseColor -InfoColor $InfoColor
            return @()
        }

        try {
            $data = Import-Csv -Path $FilePath
            return $data
        }
        catch {
            Show-PhaseMessageHighlight -Message "Error importing $TableName.csv: $($_.Exception.Message)" -HighlightText "$TableName" -HighlightColor "Red" -BaseColor $BaseColor -InfoColor $InfoColor
            return @()
        }
    }

    try {
        # Import Resources first (master table)
        $resourcesPath = Join-Path $DatabaseDirectory "Resources.csv"
        $resourcesData = Import-TableFromCSV -FilePath $resourcesPath -TableName "Resources"
        foreach ($row in $resourcesData) {
            $resourceRefId = [int]$row.ResourceRefId
            $script:Resources[$resourceRefId] = [PSCustomObject]@{
                ResourceRefId = $resourceRefId
                ResourceName = $row.ResourceName
            }
        }
        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} records)" -f "Loaded", "Resources", $script:Resources.Count) -HighlightTexts @("Resources", "$($script:Resources.Count)", "records") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

        # ReferenceTypes are statically initialized in the module at startup, no import needed
        # Just validate the file exists and show confirmation message
        $referenceTypesPath = Join-Path $DatabaseDirectory "ReferenceTypes.csv"
        if (Test-Path $referenceTypesPath) {
            Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} {3,-7})" -f "Validated", "ReferenceTypes", $script:ReferenceTypes.Count, "types") -HighlightTexts @("ReferenceTypes", "$($script:ReferenceTypes.Count)", "types") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor
        }

        # Import Services
        $servicesPath = Join-Path $DatabaseDirectory "Services.csv"
        $servicesData = Import-TableFromCSV -FilePath $servicesPath -TableName "Services"
        foreach ($row in $servicesData) {
            $serviceRefId = [int]$row.ServiceRefId
            $resourceRefId = if ($row.ResourceRefId) { [int]$row.ResourceRefId } else { 1 }
            $script:Services[$serviceRefId] = [PSCustomObject]@{
                ServiceRefId = $serviceRefId
                ResourceRefId = $resourceRefId
                Name = $row.Name
            }
            # Update counter
            if ($serviceRefId -ge $script:ServiceRefIdCounter) {
                $script:ServiceRefIdCounter = $serviceRefId + 1
            }
        }
        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} records)" -f "Loaded", "Services", $script:Services.Count) -HighlightTexts @("Services", "$($script:Services.Count)", "records") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

        # Import Files
        $filesPath = Join-Path $DatabaseDirectory "Files.csv"
        $filesData = Import-TableFromCSV -FilePath $filesPath -TableName "Files"
        foreach ($row in $filesData) {
            $fileRefId = [int]$row.FileRefId
            $serviceRefId = if ($row.ServiceRefId) { [int]$row.ServiceRefId } else { 0 }
            $script:Files[$fileRefId] = [PSCustomObject]@{
                FileRefId = $fileRefId
                FilePath = $row.FilePath
                ServiceRefId = $serviceRefId
            }
            # Update index
            $script:FilePathToRefIdIndex[$row.FilePath] = $fileRefId
            # Update counter
            if ($fileRefId -ge $script:FileRefIdCounter) {
                $script:FileRefIdCounter = $fileRefId + 1
            }
        }
        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} records)" -f "Loaded", "Files", $script:Files.Count) -HighlightTexts @("Files", "$($script:Files.Count)", "records") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

        # Import Structs
        $structsPath = Join-Path $DatabaseDirectory "Structs.csv"
        $structsData = Import-TableFromCSV -FilePath $structsPath -TableName "Structs"
        foreach ($row in $structsData) {
            $structRefId = [int]$row.StructRefId
            $resourceRefId = if ($row.ResourceRefId) { [int]$row.ResourceRefId } else { 1 }
            $fileRefId = [int]$row.FileRefId
            $line = if ($row.Line) { [int]$row.Line } else { 0 }

            $struct = [PSCustomObject]@{
                StructRefId = $structRefId
                ResourceRefId = $resourceRefId
                FileRefId = $fileRefId
                Line = $line
                StructName = $row.StructName
            }
            $script:Structs[$structRefId] = $struct

            # Update indexes
            if (-not $script:StructsByFileIndex.ContainsKey($fileRefId)) {
                $script:StructsByFileIndex[$fileRefId] = @()
            }
            $script:StructsByFileIndex[$fileRefId] += $structRefId

            if (-not $script:StructsByNameIndex.ContainsKey($row.StructName)) {
                $script:StructsByNameIndex[$row.StructName] = @()
            }
            $script:StructsByNameIndex[$row.StructName] += $structRefId

            # Update counter
            if ($structRefId -ge $script:StructRefIdCounter) {
                $script:StructRefIdCounter = $structRefId + 1
            }
        }
        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} records)" -f "Loaded", "Structs", $script:Structs.Count) -HighlightTexts @("Structs", "$($script:Structs.Count)", "records") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

        # Import TestFunctions
        $testFunctionsPath = Join-Path $DatabaseDirectory "TestFunctions.csv"
        $testFunctionsData = Import-TableFromCSV -FilePath $testFunctionsPath -TableName "TestFunctions"
        foreach ($row in $testFunctionsData) {
            $testFunctionRefId = [int]$row.TestFunctionRefId
            $resourceRefId = if ($row.ResourceRefId) { [int]$row.ResourceRefId } else { 1 }
            $fileRefId = [int]$row.FileRefId
            $structRefId = if ($row.StructRefId) { [int]$row.StructRefId } else { 0 }
            $line = if ($row.Line) { [int]$row.Line } else { 0 }
            $sequentialEntryPointRefId = if ($row.SequentialEntryPointRefId) { [int]$row.SequentialEntryPointRefId } else { 0 }

            $testFunc = [PSCustomObject]@{
                TestFunctionRefId = $testFunctionRefId
                ResourceRefId = $resourceRefId
                FileRefId = $fileRefId
                StructRefId = $structRefId
                Line = $line
                FunctionName = $row.FunctionName
                TestPrefix = $row.TestPrefix
                ReferenceTypeRefId = if ($row.ReferenceTypeRefId) { [int]$row.ReferenceTypeRefId } else { 0 }
                SequentialEntryPointRefId = $sequentialEntryPointRefId
            }
            $script:TestFunctions[$testFunctionRefId] = $testFunc

            # Update index
            $script:TestFunctionsByIdIndex[$testFunctionRefId] = $testFunc

            # Update counter
            if ($testFunctionRefId -ge $script:FunctionRefIdCounter) {
                $script:FunctionRefIdCounter = $testFunctionRefId + 1
            }
        }
        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} records)" -f "Loaded", "TestFunctions", $script:TestFunctions.Count) -HighlightTexts @("TestFunctions", "$($script:TestFunctions.Count)", "records") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

        # Import TestSteps (AST-optimized schema)
        $testStepsPath = Join-Path $DatabaseDirectory "TestFunctionSteps.csv"
        $testStepsData = Import-TableFromCSV -FilePath $testStepsPath -TableName "TestFunctionSteps"
        foreach ($row in $testStepsData) {
            $testStepRefId = [int]$row.TestStepRefId
            $testFunctionRefId = [int]$row.TestFunctionRefId
            $templateFunctionRefId = if ($row.TemplateFunctionRefId) { [int]$row.TemplateFunctionRefId } else { $null }
            $stepIndex = [int]$row.StepIndex
            $targetStructRefId = if ($row.TargetStructRefId) { [int]$row.TargetStructRefId } else { $null }
            $targetServiceRefId = if ($row.TargetServiceRefId) { [int]$row.TargetServiceRefId } else { $null }
            $referenceTypeId = if ($row.ReferenceTypeId) { [int]$row.ReferenceTypeId } else { $null }
            $line = if ($row.Line) { [int]$row.Line } else { $null }

            $step = [PSCustomObject]@{
                TestStepRefId = $testStepRefId
                TestFunctionRefId = $testFunctionRefId
                TemplateFunctionRefId = $templateFunctionRefId
                StepIndex = $stepIndex
                TargetStructRefId = $targetStructRefId
                TargetServiceRefId = $targetServiceRefId
                ReferenceTypeId = $referenceTypeId
                Line = $line
            }
            $script:TestSteps[$testStepRefId] = $step

            # Update index by ReferenceTypeId (if still needed for queries)
            if ($referenceTypeId) {
                if (-not $script:TestFunctionStepsByRefTypeIndex.ContainsKey($referenceTypeId)) {
                    $script:TestFunctionStepsByRefTypeIndex[$referenceTypeId] = @()
                }
                $script:TestFunctionStepsByRefTypeIndex[$referenceTypeId] += $testStepRefId
            }
        }
        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} records)" -f "Loaded", "TestSteps", $script:TestSteps.Count) -HighlightTexts @("TestSteps", "$($script:TestSteps.Count)", "records") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

        # Import DirectResourceReferences
        $directReferencesPath = Join-Path $DatabaseDirectory "DirectResourceReferences.csv"
        $directReferencesData = Import-TableFromCSV -FilePath $directReferencesPath -TableName "DirectResourceReferences"
        foreach ($row in $directReferencesData) {
            $directRefId = [int]$row.DirectRefId
            $templateFunctionRefId = [int]$row.TemplateFunctionRefId
            $resourceRefId = [int]$row.ResourceRefId
            $referenceTypeId = [int]$row.ReferenceTypeId
            $templateLine = if ($row.TemplateLine) { [int]$row.TemplateLine } else { 0 }
            $contextLine = if ($row.ContextLine) { [int]$row.ContextLine } else { 0 }

            $script:DirectResourceReferences[$directRefId] = [PSCustomObject]@{
                DirectRefId = $directRefId
                TemplateFunctionRefId = $templateFunctionRefId
                ResourceRefId = $resourceRefId
                ReferenceTypeId = $referenceTypeId
                TemplateLine = $templateLine
                ContextLine = $contextLine
                Context = $row.Context
            }
            # Update counter
            if ($directRefId -ge $script:DirectRefIdCounter) {
                $script:DirectRefIdCounter = $directRefId + 1
            }
        }
        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} records)" -f "Loaded", "DirectResourceReferences", $script:DirectResourceReferences.Count) -HighlightTexts @("DirectResourceReferences", "$($script:DirectResourceReferences.Count)", "records") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

        # Import IndirectConfigReferences
        $indirectReferencesPath = Join-Path $DatabaseDirectory "IndirectConfigReferences.csv"
        $indirectReferencesData = Import-TableFromCSV -FilePath $indirectReferencesPath -TableName "IndirectConfigReferences"
        foreach ($row in $indirectReferencesData) {
            $indirectRefId = [int]$row.IndirectRefId
            $templateReferenceRefId = if ($row.TemplateReferenceRefId) { [int]$row.TemplateReferenceRefId } else { 0 }
            $sourceTemplateFunctionRefId = if ($row.SourceTemplateFunctionRefId) { [int]$row.SourceTemplateFunctionRefId } else { 0 }
            $referenceTypeId = if ($row.ReferenceTypeId) { [int]$row.ReferenceTypeId } else { 0 }
            $serviceImpactTypeId = if ($row.ServiceImpactTypeId) { [int]$row.ServiceImpactTypeId } else { 0 }

            $script:IndirectConfigReferences[$indirectRefId] = [PSCustomObject]@{
                IndirectRefId = $indirectRefId
                TemplateReferenceRefId = $templateReferenceRefId
                SourceTemplateFunctionRefId = $sourceTemplateFunctionRefId
                ReferenceTypeId = $referenceTypeId
                ServiceImpactTypeId = $serviceImpactTypeId
            }
            # Update counter
            if ($indirectRefId -ge $script:IndirectRefIdCounter) {
                $script:IndirectRefIdCounter = $indirectRefId + 1
            }
        }
        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} records)" -f "Loaded", "IndirectConfigReferences", $script:IndirectConfigReferences.Count) -HighlightTexts @("IndirectConfigReferences", "$($script:IndirectConfigReferences.Count)", "records") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

        # Import TemplateFunctions
        $templateFunctionsPath = Join-Path $DatabaseDirectory "TemplateFunctions.csv"
        $templateFunctionsData = Import-TableFromCSV -FilePath $templateFunctionsPath -TableName "TemplateFunctions"
        foreach ($row in $templateFunctionsData) {
            $templateFunctionRefId = [int]$row.TemplateFunctionRefId
            $resourceRefId = if ($row.ResourceRefId) { [int]$row.ResourceRefId } else { 1 }
            $structRefId = if ($row.StructRefId) { [int]$row.StructRefId } else { 0 }
            $fileRefId = if ($row.FileRefId) { [int]$row.FileRefId } else { 0 }
            $line = if ($row.Line) { [int]$row.Line } else { 0 }

            $script:TemplateFunctions[$templateFunctionRefId] = [PSCustomObject]@{
                TemplateFunctionRefId = $templateFunctionRefId
                ResourceRefId = $resourceRefId
                TemplateFunctionName = $row.TemplateFunctionName
                StructRefId = $structRefId
                FileRefId = $fileRefId
                Line = $line
                ReceiverVariable = $row.ReceiverVariable
            }
            # Update counter
            if ($templateFunctionRefId -ge $script:TemplateFunctionRefIdCounter) {
                $script:TemplateFunctionRefIdCounter = $templateFunctionRefId + 1
            }
        }
        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} records)" -f "Loaded", "TemplateFunctions", $script:TemplateFunctions.Count) -HighlightTexts @("TemplateFunctions", "$($script:TemplateFunctions.Count)", "records") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

        # Import SequentialReferences
        $sequentialReferencesPath = Join-Path $DatabaseDirectory "SequentialReferences.csv"
        $sequentialReferencesData = Import-TableFromCSV -FilePath $sequentialReferencesPath -TableName "SequentialReferences"
        foreach ($row in $sequentialReferencesData) {
            $sequentialRefId = [int]$row.SequentialRefId
            $entryPointFunctionRefId = if ($row.EntryPointFunctionRefId) { [int]$row.EntryPointFunctionRefId } else { 0 }
            $referencedFunctionRefId = if ($row.ReferencedFunctionRefId) { [int]$row.ReferencedFunctionRefId } else { 0 }

            $script:SequentialReferences[$sequentialRefId] = [PSCustomObject]@{
                SequentialRefId = $sequentialRefId
                EntryPointFunctionRefId = $entryPointFunctionRefId
                ReferencedFunctionRefId = $referencedFunctionRefId
                SequentialGroup = [string]$row.SequentialGroup
                SequentialKey = [string]$row.SequentialKey
            }
            # Update counter
            if ($sequentialRefId -ge $script:SequentialRefIdCounter) {
                $script:SequentialRefIdCounter = $sequentialRefId + 1
            }
        }
        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} records)" -f "Loaded", "SequentialReferences", $script:SequentialReferences.Count) -HighlightTexts @("SequentialReferences", "$($script:SequentialReferences.Count)", "records") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

        # Import TemplateReferences
        $templateReferencesPath = Join-Path $DatabaseDirectory "TemplateReferences.csv"
        $templateReferencesData = Import-TableFromCSV -FilePath $templateReferencesPath -TableName "TemplateReferences"
        foreach ($row in $templateReferencesData) {
            $templateReferenceRefId = [int]$row.TemplateReferenceRefId
            $testFunctionRefId = if ($row.TestFunctionRefId) { [int]$row.TestFunctionRefId } else { 0 }
            $testFunctionStepRefId = if ($row.TestFunctionStepRefId) { [int]$row.TestFunctionStepRefId } else { 0 }
            $structRefId = if ($row.StructRefId) { [int]$row.StructRefId } else { 0 }

            $script:TemplateReferences[$templateReferenceRefId] = [PSCustomObject]@{
                TemplateReferenceRefId = $templateReferenceRefId
                TestFunctionRefId = $testFunctionRefId
                TestFunctionStepRefId = $testFunctionStepRefId
                StructRefId = $structRefId
                TemplateReference = $row.TemplateReference
                TemplateVariable = $row.TemplateVariable
                TemplateMethod = $row.TemplateMethod
            }
            # Update counter
            if ($templateReferenceRefId -ge $script:TemplateReferenceRefIdCounter) {
                $script:TemplateReferenceRefIdCounter = $templateReferenceRefId + 1
            }
        }
        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1,-30} ({2,6} records)" -f "Loaded", "TemplateReferences", $script:TemplateReferences.Count) -HighlightTexts @("TemplateReferences", "$($script:TemplateReferences.Count)", "records") -HighlightColors @($ItemColor, $NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor

        $importElapsed = (Get-Date) - $importStart

        # Build summary statistics
        $totalRecords = $script:Resources.Count + $script:ReferenceTypes.Count + $script:Services.Count +
                       $script:Files.Count + $script:Structs.Count + $script:TestFunctions.Count +
                       $script:TestFunctionSteps.Count + $script:DirectResourceReferences.Count +
                       $script:IndirectConfigReferences.Count + $script:TemplateFunctions.Count +
                       $script:SequentialReferences.Count + $script:TemplateReferences.Count

        Show-PhaseMessageMultiHighlight -Message ("{0,-9}: {1} Records" -f "Imported", $totalRecords) -HighlightTexts @("$totalRecords", "Records") -HighlightColors @($NumberColor, $ItemColor) -BaseColor $BaseColor -InfoColor $InfoColor
        Show-PhaseCompletionGeneric -Description "Database Initialization" -DurationMs $([math]::Round($importElapsed.TotalMilliseconds, 0))

        return [PSCustomObject]@{
            Success = $true
            TotalRecords = $totalRecords
            Services = $script:Services.Count
            Files = $script:Files.Count
            Structs = $script:Structs.Count
            TestFunctions = $script:TestFunctions.Count
            TestFunctionSteps = $script:TestFunctionSteps.Count
            DirectResourceReferences = $script:DirectResourceReferences.Count
            IndirectConfigReferences = $script:IndirectConfigReferences.Count
            TemplateFunctions = $script:TemplateFunctions.Count
            SequentialReferences = $script:SequentialReferences.Count
            TemplateReferences = $script:TemplateReferences.Count
            DurationMs = [math]::Round($importElapsed.TotalMilliseconds, 0)
        }
    }
    catch {
        Show-PhaseMessageHighlight -Message "Error importing database: $($_.Exception.Message)" -HighlightText "Error" -HighlightColor "Red" -BaseColor $BaseColor -InfoColor $InfoColor
        throw
    }
}

# Helper function to add service for newly discovered files
function Add-ServiceForFile {
    param([string]$FilePath)

    # Extract service name from file path: internal/services/SERVICE_NAME/file.go
    $pathParts = $FilePath -split '/'
    $serviceName = $pathParts[2]  # services is at index 1, service name at index 2

    # Check if service already exists
    $existingService = Get-Services | Where-Object { $_.ServiceName -eq $serviceName }
    if ($existingService) {
        return $existingService.ServiceRefId
    }

    # Add new service
    return Add-ServiceRecord -Name $serviceName
}

# Export only the functions that are actually used by the TerraCorder system
Export-ModuleMember -Function @(
    # Database lifecycle functions
    'Initialize-TerraDatabase',
    'Close-TerraDatabase',
    'Export-DatabaseToCSV',
    'Import-DatabaseFromCSV',
    'Get-DatabaseStats',
    'Get-ExportDirectory',
    'Invoke-TemplatePopulation',

    # Data insertion functions
    'Add-ServiceRecord',
    'Add-ResourceRecord',
    'Add-FileRecord',
    'Add-StructRecord',
    'Add-TestFunctionRecord',
    'Add-TestFunctionStepRecord',
    'Add-TestStepRecord',  # AST-based test step record
    'Get-TestFunctionStepsByFunctionId',
    'Get-AllTestFunctionSteps',
    'Get-TestFunctionStepsByReferenceType',
    'Update-TestFunctionStepStructRefId',
    'Update-TestFunctionStepReferenceType',
    'Update-TestFunctionStepStructVisibility',
    'Update-IndirectConfigReferenceServiceImpact',
    'Get-StructById',
    'Get-TestFunctionStepRefIdByIndex',
    'Add-DirectResourceReferenceRecord',
    'Add-IndirectConfigReferenceRecord',
    'Add-TemplateFunctionRecord',
    'Add-TemplateCallChainRecord',  # AST-based template call chain record
    'Add-SequentialReferenceRecord',
    'Add-TemplateReferenceRecord',
    'Update-TestFunctionSequentialInfo',
    'Add-ServiceForFile',

    # Data retrieval functions
    'Get-TestFunctions',
    'Get-TestFunctionById',
    'Get-TestFunctionByName',
    'Get-SequentialReferences',
    'Get-ReferenceTypes',
    'Get-Structs',
    'Get-StructRefIdByName',
    'Get-DirectResourceReferences',
    'Get-IndirectConfigReferences',
    'Get-Files',
    'Get-FileRefIdByPath',           # O(1) lookup by FilePath (indexed)
    'Get-FilePathByRefId',           # O(1) lookup by FileRefId
    'Get-FileRecordByRefId',         # O(1) lookup by FileRefId
    'Get-Services',
    'Get-ServiceRefIdByFilePath',
    'Get-TemplateFunctions',
    'Get-TemplateReferences',
    'Get-StructsByFileRefId',
    'Get-ReferenceTypeName',
    'Get-ReferenceTypeId'
) -Variable @(
    'ReferenceTypes'
)
