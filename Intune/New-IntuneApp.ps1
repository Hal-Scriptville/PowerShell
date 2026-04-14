<#
.SYNOPSIS
    Scaffolds a new Intune Win32 app folder under a shared build root.

.DESCRIPTION
    Creates <BuildRoot>\<AppName>\{Source,Detection,Output} and, on first
    use, downloads IntuneWinAppUtil.exe to <BuildRoot> so it is shared by
    every app in that root. Prints next-step commands.

.PARAMETER AppName
    Name of the app (drives folder naming). Required.

.PARAMETER BuildRoot
    Shared build directory. Default: C:\Build\Intune

.PARAMETER UseCurl
    Use curl.exe for the tool download (EDR-friendly fallback).

.EXAMPLE
    .\New-IntuneApp.ps1 -AppName Chrome

.EXAMPLE
    .\New-IntuneApp.ps1 -AppName JavaPin -BuildRoot D:\Packaging -UseCurl
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppName,
    [string]$BuildRoot = "C:\Build\Intune",
    [switch]$UseCurl
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$appRoot = Join-Path $BuildRoot $AppName
$folders = @(
    $appRoot,
    (Join-Path $appRoot "Source"),
    (Join-Path $appRoot "Detection"),
    (Join-Path $appRoot "Output")
)

foreach ($f in $folders) {
    if (-not (Test-Path $f)) {
        New-Item -Path $f -ItemType Directory | Out-Null
        Write-Host "Created: $f"
    } else {
        Write-Host "Exists:  $f"
    }
}

# Shared IntuneWinAppUtil.exe at BuildRoot (one per build host, not per app)
$tool = Join-Path $BuildRoot "IntuneWinAppUtil.exe"
if (-not (Test-Path $tool)) {
    $url = "https://raw.githubusercontent.com/microsoft/Microsoft-Win32-Content-Prep-Tool/master/IntuneWinAppUtil.exe"
    Write-Host "Downloading IntuneWinAppUtil.exe to $tool..."
    if ($UseCurl) {
        & curl.exe -sSL -o $tool $url
        if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" }
    } else {
        Invoke-WebRequest -Uri $url -OutFile $tool -UseBasicParsing
    }
    Unblock-File $tool
    Write-Host "SHA256: $((Get-FileHash $tool -Algorithm SHA256).Hash)"
} else {
    Write-Host "Tool (shared): $tool"
}

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Drop install.ps1 + binaries into: $appRoot\Source"
Write-Host "  2. Drop detect.ps1 into:             $appRoot\Detection"
Write-Host "  3. Build the .intunewin:"
Write-Host "       & `"$tool`" -c `"$appRoot\Source`" -s install.ps1 -o `"$appRoot\Output`" -q"
Write-Host "     Or use Build-IntuneAppBuilder.ps1 with -ToolPath `"$tool`""
