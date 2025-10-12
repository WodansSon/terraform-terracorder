#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick smoke test for AST integration with Database.psm1

.DESCRIPTION
    Tests the new hash table functions by importing one AST JSON file
#>

# Import modules
Import-Module ".\modules\UI.psm1" -Force
Import-Module ".\modules\Database.psm1" -Force
Import-Module ".\modules\ASTImport.psm1" -Force

Write-Host "`n=== AST Integration Smoke Test ===" -ForegroundColor Cyan

# Initialize database
Write-Host "`n[1/4] Initializing database..." -ForegroundColor Yellow
Initialize-TerraDatabase -ExportDirectory ".\test-output" -ResourceName "azurerm_network_manager"

# Test AST analyzer path
$astPath = ".\tools\ast-analyzer\ast-analyzer.exe"
if (-not (Test-Path $astPath)) {
    Write-Host "ERROR: AST analyzer not found at $astPath" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ AST analyzer found" -ForegroundColor Green

# Find a test file
$testFile = Get-ChildItem -Path "C:\terraform-provider-azurerm\internal\services\network\*_test.go" -Filter "*network_manager*" | Select-Object -First 1
if (-not $testFile) {
    Write-Host "ERROR: No network_manager test file found" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Test file: $($testFile.Name)" -ForegroundColor Green

# Run AST analyzer
Write-Host "`n[2/4] Running AST analyzer..." -ForegroundColor Yellow
$astOutput = & $astPath -file $testFile.FullName -reporoot "C:\terraform-provider-azurerm" 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: AST analyzer failed" -ForegroundColor Red
    Write-Host $astOutput
    exit 1
}

# Parse JSON
$astData = $astOutput | ConvertFrom-Json
Write-Host "  ✓ Parsed JSON: $($astData.test_functions.Count) test functions" -ForegroundColor Green

# Import data using new functions
Write-Host "`n[3/4] Importing AST data into hash tables..." -ForegroundColor Yellow

try {
    # Get/create service
    $serviceId = Get-OrCreateServiceId -ServiceName $astData.service_name
    Write-Host "  ✓ Service created: ID=$serviceId" -ForegroundColor Green

    # Get/create file
    $fileId = Add-FileRecord -FilePath $astData.file_path -ServiceRefId $serviceId
    Write-Host "  ✓ File created: ID=$fileId" -ForegroundColor Green

    # Import test functions
    foreach ($testFunc in $astData.test_functions) {
        $structId = Get-OrCreateStructId -StructName $testFunc.struct_name -ServiceRefId $serviceId -FileRefId $fileId

        $funcId = Add-TestFunctionRecord `
            -TestFunctionName $testFunc.function_name `
            -StructRefId $structId `
            -FileRefId $fileId `
            -Line $testFunc.line

        Write-Host "    - Test function '$($testFunc.function_name)': ID=$funcId" -ForegroundColor Gray
    }

    # Import template functions
    foreach ($templateFunc in $astData.template_functions) {
        $structId = Get-OrCreateStructId -StructName $templateFunc.struct_name -ServiceRefId $serviceId -FileRefId $fileId

        $templateId = Add-TemplateFunctionRecord `
            -TemplateFunctionName $templateFunc.function_name `
            -StructRefId $structId `
            -FileRefId $fileId `
            -ReceiverType $templateFunc.receiver_type `
            -ReturnsString $templateFunc.returns_string `
            -Line $templateFunc.line

        Write-Host "    - Template function '$($templateFunc.function_name)': ID=$templateId ReceiverType=$($templateFunc.receiver_type) ReturnsString=$($templateFunc.returns_string)" -ForegroundColor Gray
    }

    Write-Host "`n  ✓ Import complete!" -ForegroundColor Green

} catch {
    Write-Host "ERROR during import: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}

# Verify data
Write-Host "`n[4/4] Verifying hash tables..." -ForegroundColor Yellow
Write-Host "  Services: $($script:Services.Count)" -ForegroundColor Gray
Write-Host "  Files: $($script:Files.Count)" -ForegroundColor Gray
Write-Host "  Structs: $($script:Structs.Count)" -ForegroundColor Gray
Write-Host "  TestFunctions: $($script:TestFunctions.Count)" -ForegroundColor Gray
Write-Host "  TemplateFunctions: $($script:TemplateFunctions.Count)" -ForegroundColor Gray

# Show a template function to verify ReceiverType and ReturnsString
if ($script:TemplateFunctions.Count -gt 0) {
    $sampleTemplate = $script:TemplateFunctions.Values | Select-Object -First 1
    Write-Host "`n  Sample Template Function:" -ForegroundColor Cyan
    Write-Host "    Name: $($sampleTemplate.TemplateFunctionName)" -ForegroundColor Gray
    Write-Host "    ReceiverType: $($sampleTemplate.ReceiverType)" -ForegroundColor Gray
    Write-Host "    ReturnsString: $($sampleTemplate.ReturnsString)" -ForegroundColor Gray
    Write-Host "    Line: $($sampleTemplate.Line)" -ForegroundColor Gray
}

Write-Host "`n=== ✓ SMOKE TEST PASSED ===" -ForegroundColor Green
Write-Host ""
