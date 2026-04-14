<#
.SYNOPSIS
    Scaffolds an Intune Win32 app package and optionally builds the .intunewin file.

.DESCRIPTION
    Creates the standard folder structure (Source, Detection, Output, Intune),
    downloads IntuneWinAppUtil.exe, seeds install/uninstall/detect script stubs,
    and (optionally) invokes the Content Prep Tool to produce the .intunewin.

.PARAMETER AppName
    Name of the app being packaged. Drives folder naming. Default: "App".

.PARAMETER BasePath
    Root directory where the package scaffold is created.
    Default: <script_root>\<AppName>

.PARAMETER SetupFile
    Name of the install script inside Source\ (passed to -s flag of IntuneWinAppUtil).
    Default: install.ps1

.PARAMETER Build
    If specified, invokes IntuneWinAppUtil.exe after scaffolding to produce the .intunewin.

.PARAMETER Force
    Overwrite existing stub scripts. By default, existing files are preserved.

.PARAMETER UseCurl
    Use curl.exe for the IntuneWinAppUtil.exe download instead of Invoke-WebRequest.
    Useful when EDR (e.g., FortiEDR) blocks PowerShell web requests.

.EXAMPLE
    .\Build-IntuneAppBuilder.ps1 -AppName "Chrome" -Build

.EXAMPLE
    .\Build-IntuneAppBuilder.ps1 -AppName "Chrome" -UseCurl -Build

.NOTES
    Stub scripts are templates only. Edit install.ps1, uninstall.ps1, and detect.ps1
    before running -Build for a real deployment.

    See Examples\Chrome\ for a complete reference package.
#>
[CmdletBinding()]
param(
    [string]$AppName   = "App",
    [string]$BasePath  = (Join-Path -Path $PSScriptRoot -ChildPath $AppName),
    [string]$SetupFile = "install.ps1",
    [switch]$Build,
    [switch]$Force,
    [switch]$UseCurl
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- Folder scaffold -------------------------------------------------------
$folders = @(
    $BasePath,
    (Join-Path $BasePath "Intune"),
    (Join-Path $BasePath "Source"),
    (Join-Path $BasePath "Detection"),
    (Join-Path $BasePath "Output")
)

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory | Out-Null
        Write-Host "Created: $folder"
    } else {
        Write-Host "Exists:  $folder"
    }
}

# ---- IntuneWinAppUtil.exe download ----------------------------------------
$toolUrl = "https://raw.githubusercontent.com/microsoft/Microsoft-Win32-Content-Prep-Tool/master/IntuneWinAppUtil.exe"
$toolPath = Join-Path $BasePath "IntuneWinAppUtil.exe"

if ((Test-Path $toolPath) -and -not $Force) {
    Write-Host "Tool already present: $toolPath (use -Force to re-download)"
} else {
    Write-Host "Downloading IntuneWinAppUtil.exe..."
    try {
        if ($UseCurl) {
            $curl = Get-Command curl.exe -ErrorAction Stop
            & $curl.Source -sSL -o $toolPath $toolUrl
            if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" }
        } else {
            Invoke-WebRequest -Uri $toolUrl -OutFile $toolPath -UseBasicParsing
        }
        Unblock-File -Path $toolPath
        $hash = (Get-FileHash -Path $toolPath -Algorithm SHA256).Hash
        Write-Host "Download complete."
        Write-Host "SHA256: $hash"
    } catch {
        throw "Failed to download IntuneWinAppUtil.exe: $_"
    }
}

# ---- Stub scripts ---------------------------------------------------------
$installStub = @'
# install.ps1 - Intune Win32 app install script
# Runs as SYSTEM under Intune Management Extension.
# Log to C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ for visibility.

$ErrorActionPreference = 'Stop'
$log = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\<AppName>-install.log"
Start-Transcript -Path $log -Append

try {
    # TODO: Replace with actual install command
    # Example (MSI):
    #   Start-Process msiexec.exe -ArgumentList '/i','installer.msi','/qn','/norestart' -Wait
    # Example (EXE):
    #   Start-Process .\setup.exe -ArgumentList '/S' -Wait
    Write-Host "Install placeholder - edit install.ps1"
    exit 0
} catch {
    Write-Error $_
    exit 1
} finally {
    Stop-Transcript
}
'@

$uninstallStub = @'
# uninstall.ps1 - Intune Win32 app uninstall script
$ErrorActionPreference = 'Stop'
$log = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\<AppName>-uninstall.log"
Start-Transcript -Path $log -Append

try {
    # TODO: Replace with actual uninstall command
    Write-Host "Uninstall placeholder - edit uninstall.ps1"
    exit 0
} catch {
    Write-Error $_
    exit 1
} finally {
    Stop-Transcript
}
'@

$detectStub = @'
# detect.ps1 - Intune Win32 app detection script
# Intune considers the app installed if this script:
#   - Exits 0 AND writes output to STDOUT.
# Exit 0 with no output = not installed.

# TODO: Replace with real detection (registry key, file path, service, or version check).
# Example - service presence:
#   if (Get-Service -Name 'NinjaRMMAgent' -ErrorAction SilentlyContinue) {
#       Write-Output "Installed"; exit 0
#   }
#   exit 0

exit 0
'@

$stubs = @{
    (Join-Path $BasePath "Source\$SetupFile")        = $installStub
    (Join-Path $BasePath "Source\uninstall.ps1")     = $uninstallStub
    (Join-Path $BasePath "Detection\detect.ps1")     = $detectStub
}

foreach ($path in $stubs.Keys) {
    if ((Test-Path $path) -and -not $Force) {
        Write-Host "Stub exists (preserved): $path"
    } else {
        $stubs[$path] -replace '<AppName>', $AppName | Set-Content -Path $path -Encoding UTF8
        Write-Host "Wrote stub: $path"
    }
}

# ---- Build .intunewin ------------------------------------------------------
if ($Build) {
    $sourceDir  = Join-Path $BasePath "Source"
    $setupPath  = Join-Path $sourceDir $SetupFile
    $outputDir  = Join-Path $BasePath "Output"

    if (-not (Test-Path $setupPath)) {
        throw "Setup file not found: $setupPath. Edit $SetupFile before building."
    }

    Write-Host ""
    Write-Host "Building .intunewin..."
    & $toolPath -c $sourceDir -s $SetupFile -o $outputDir -q
    if ($LASTEXITCODE -ne 0) {
        throw "IntuneWinAppUtil failed with exit code $LASTEXITCODE"
    }

    $pkg = Get-ChildItem -Path $outputDir -Filter *.intunewin | Select-Object -First 1
    if ($pkg) {
        Write-Host "Build complete: $($pkg.FullName)"
    } else {
        Write-Warning "Build reported success but no .intunewin found in $outputDir"
    }
} else {
    Write-Host ""
    Write-Host "Scaffold complete. Next steps:"
    Write-Host "  1. Drop installer binary into: $BasePath\Source"
    Write-Host "  2. Edit $SetupFile, uninstall.ps1, and Detection\detect.ps1"
    Write-Host "  3. Re-run with -Build to produce the .intunewin"
}
