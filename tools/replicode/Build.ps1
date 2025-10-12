# Build.ps1
# PowerShell build script for Replicode (Windows alternative to Make)

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("build", "clean", "rebuild", "test", "help")]
    [string]$Target = "build"
)

$BinaryName = "replicode.exe"
$ErrorActionPreference = "Stop"

function Show-Help {
    Write-Host "TerraCorder Replicode - Build Script" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  .\Build.ps1 [target]"
    Write-Host ""
    Write-Host "TARGETS:" -ForegroundColor Yellow
    Write-Host "  build    - Build the Replicode binary (default)"
    Write-Host "  clean    - Remove build artifacts"
    Write-Host "  rebuild  - Clean and rebuild"
    Write-Host "  test     - Run tests"
    Write-Host "  help     - Show this help message"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  .\Build.ps1              # Build the binary"
    Write-Host "  .\Build.ps1 -Target clean   # Clean build artifacts"
    Write-Host "  .\Build.ps1 rebuild      # Clean and rebuild"
    Write-Host ""
}

function Invoke-Build {
    Write-Host "Building Replicode..." -ForegroundColor Cyan

    try {
        go build -o $BinaryName -v

        if (Test-Path $BinaryName) {
            $fileInfo = Get-Item $BinaryName
            $sizeKB = [Math]::Round($fileInfo.Length / 1KB, 2)
            Write-Host "Build complete: " -NoNewline -ForegroundColor Green
            Write-Host "$BinaryName " -NoNewline -ForegroundColor White
            Write-Host "($sizeKB KB)" -ForegroundColor Gray
        } else {
            throw "Binary not created"
        }
    } catch {
        Write-Host "Build failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

function Invoke-Clean {
    Write-Host "Cleaning build artifacts..." -ForegroundColor Cyan

    try {
        go clean

        if (Test-Path $BinaryName) {
            Remove-Item $BinaryName -Force
            Write-Host "Removed $BinaryName" -ForegroundColor Yellow
        }

        Write-Host "Clean complete" -ForegroundColor Green
    } catch {
        Write-Host "Clean failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

function Invoke-Test {
    Write-Host "Running tests..." -ForegroundColor Cyan

    try {
        go test -v ./...
        Write-Host "Tests complete" -ForegroundColor Green
    } catch {
        Write-Host "Tests failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

function Invoke-Rebuild {
    Invoke-Clean
    Write-Host ""
    Invoke-Build
}

# Main execution
switch ($Target) {
    "build" {
        Invoke-Build
    }
    "clean" {
        Invoke-Clean
    }
    "rebuild" {
        Invoke-Rebuild
    }
    "test" {
        Invoke-Test
    }
    "help" {
        Show-Help
    }
    default {
        Write-Host "Unknown target: $Target" -ForegroundColor Red
        Show-Help
        exit 1
    }
}
