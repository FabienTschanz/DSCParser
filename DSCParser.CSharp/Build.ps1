# Build and Deploy Script for DSCParser.CSharp

param(
    [Parameter()]
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [Parameter()]
    [switch]$SkipBuild,

    [Parameter()]
    [switch]$Import
)

$ErrorActionPreference = 'Stop'

# Paths
$rootPath = $PSScriptRoot
$srcPath = Join-Path $rootPath 'src'
$modulePath = Join-Path $rootPath 'PowerShellModule'
$binPath = Join-Path $modulePath 'bin'

Write-Host "DSCParser.CSharp Build and Deploy Script" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Build the C# project
if (-not $SkipBuild)
{
    Write-Host "[1/3] Building C# project for netstandard2.0..." -ForegroundColor Yellow

    Push-Location $srcPath
    try
    {
        $buildOutput = dotnet build -c $Configuration 2>&1
        if ($LASTEXITCODE -ne 0)
        {
            Write-Error "Build failed with exit code $LASTEXITCODE"
            Write-Host $buildOutput -ForegroundColor Red
            exit 1
        }
        Write-Host "✓ Build completed successfully for netstandard2.0" -ForegroundColor Green
    }
    finally
    {
        Pop-Location
    }
}
else
{
    Write-Host "[1/3] Skipping build (using existing binaries)" -ForegroundColor Yellow
}

# Step 2: Copy assemblies to PowerShell module directory
Write-Host "[2/3] Copying assemblies to module directory..." -ForegroundColor Yellow

# Create directory structure for netstandard2.0
$binPathNetStandard = Join-Path $binPath 'netstandard2.0'

if (-not (Test-Path $binPathNetStandard))
{
    New-Item -ItemType Directory -Path $binPathNetStandard -Force | Out-Null
}

# Files to copy
$filesToCopy = @(
    'DSCParser.CSharp.dll',
    'DSCParser.CSharp.pdb',
    'DSCParser.CSharp.deps.json'
)

# Copy .NET Standard 2.0 assemblies
$sourceBinPathNetStandard = Join-Path $srcPath "bin\$Configuration\netstandard2.0"
Write-Host "  Copying .NET Standard 2.0 assemblies..." -ForegroundColor Gray
foreach ($file in $filesToCopy)
{
    $sourceFile = Join-Path $sourceBinPathNetStandard $file
    if (Test-Path $sourceFile)
    {
        Copy-Item $sourceFile -Destination $binPathNetStandard -Force
        Write-Host "    [.NET Standard 2.0] $file" -ForegroundColor DarkGray
    }
    else
    {
        Write-Warning "File not found: $sourceFile"
    }
}

Write-Host "✓ Assembly copy completed" -ForegroundColor Green

Write-Host "  Copying PowerShell module files..." -ForegroundColor Gray
foreach ($item in Get-ChildItem -Path (Join-Path "$modulePath\..\..\" 'Modules\DSCParser') -Recurse -File)
{
    $destination = Join-Path $modulePath $item.Name
    Copy-Item $item.FullName -Destination $destination -Recurse -Force
    Write-Host "    $($item.Name)" -ForegroundColor DarkGray
}

# Step 3: Import module (optional)
if ($Import) {
    Write-Host "[3/3] Importing module..." -ForegroundColor Yellow

    $manifestPath = Join-Path $modulePath 'DSCParser.CSharp.psd1'

    # Remove existing module if loaded
    if (Get-Module DSCParser.CSharp) {
        Remove-Module DSCParser.CSharp -Force
        Write-Host "  Removed existing module" -ForegroundColor Gray
    }

    # Import new module
    Import-Module $manifestPath -Force -Verbose
    Write-Host "✓ Module imported successfully" -ForegroundColor Green

    # Show available commands
    Write-Host ""
    Write-Host "Available Commands:" -ForegroundColor Cyan
    Get-Command -Module DSCParser.CSharp | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor White
    }
}
else
{
    Write-Host "[3/3] Skipping module import" -ForegroundColor Yellow
    Write-Host "  To import the module, run:" -ForegroundColor Gray
    Write-Host "  Import-Module '$modulePath\DSCParser.CSharp.psd1'" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Build and deployment completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. Import the module:" -ForegroundColor White
Write-Host "   Import-Module '$modulePath\DSCParser.CSharp.psd1'" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Test the functionality:" -ForegroundColor White
Write-Host '   $resources = ConvertTo-DSCObject -Path "path\to\config.ps1"' -ForegroundColor Gray
Write-Host '   ConvertFrom-DSCObject -DSCResources $resources' -ForegroundColor Gray
