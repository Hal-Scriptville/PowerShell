<#
.SYNOPSIS
    Builds multiple Intune Win32 app packages from a CSV of tokenized RMM agent URLs.

.DESCRIPTION
    For each row in the input CSV, downloads a tokenized agent MSI, scaffolds a
    Source/Detection/Output folder under an output root, copies shared template
    scripts (install/uninstall/detect) into place, and invokes IntuneWinAppUtil
    to produce a .intunewin package named for the location.

    Built for RMM agents with per-location tokenized download URLs
    (NinjaOne, Atera, Datto, etc.). One CSV row = one .intunewin output.

.PARAMETER CsvPath
    CSV with at least these columns:
      LocationName  — friendly name (used in logs)
      Slug          — filename-safe slug used in the download URL
      Token         — per-location token/GUID in the URL
      UrlTemplate   — URL format with {TOKEN} and {SLUG} placeholders
      DeployTarget  — filter column (only rows matching -FilterValue are processed)

.PARAMETER TemplatePath
    Folder containing template scripts to seed each package. Expected layout:
      {TemplatePath}\Source\install.ps1
      {TemplatePath}\Source\uninstall.ps1
      {TemplatePath}\Detection\detect.ps1

.PARAMETER OutputRoot
    Build root. Each location is built under {OutputRoot}\{PackagePrefix}-{Slug}\.
    Default: C:\Build\Intune

.PARAMETER ToolPath
    Path to IntuneWinAppUtil.exe. Required.

.PARAMETER PackagePrefix
    Prefix for per-location folders. Default: derived from template folder name.

.PARAMETER FilterColumn / FilterValue
    Only process rows where {FilterColumn} equals {FilterValue}.
    Default: DeployTarget = intune

.PARAMETER Force
    Overwrite existing package folders/files.

.PARAMETER UseCurl
    Use curl.exe for MSI downloads (EDR-friendly).

.EXAMPLE
    .\Build-TokenizedAgentPackages.ps1 `
      -CsvPath "C:\Build\Client-Scripts-Presidio\HealthTrackRx\Scripts\Intune\NinjaOne\locations.csv" `
      -TemplatePath "C:\Build\Client-Scripts-Presidio\HealthTrackRx\Scripts\Intune\NinjaOne" `
      -OutputRoot "C:\Build\Intune" `
      -ToolPath "C:\Build\Intune\IntuneWinAppUtil.exe" `
      -PackagePrefix "NinjaOne-HealthTrackRx"

.NOTES
    Version: 1.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CsvPath,
    [Parameter(Mandatory)][string]$TemplatePath,
    [string]$OutputRoot    = "C:\Build\Intune",
    [Parameter(Mandatory)][string]$ToolPath,
    [string]$PackagePrefix = (Split-Path $TemplatePath -Leaf),
    [string]$FilterColumn  = "DeployTarget",
    [string]$FilterValue   = "intune",
    [switch]$Force,
    [switch]$UseCurl
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- Validate inputs -------------------------------------------------------
if (-not (Test-Path $CsvPath))      { throw "CsvPath not found: $CsvPath" }
if (-not (Test-Path $TemplatePath)) { throw "TemplatePath not found: $TemplatePath" }
if (-not (Test-Path $ToolPath))     { throw "ToolPath not found: $ToolPath" }

$templates = @{
    'Source\install.ps1'      = Join-Path $TemplatePath "Source\install.ps1"
    'Source\uninstall.ps1'    = Join-Path $TemplatePath "Source\uninstall.ps1"
    'Detection\detect.ps1'    = Join-Path $TemplatePath "Detection\detect.ps1"
}
foreach ($k in $templates.Keys) {
    if (-not (Test-Path $templates[$k])) { throw "Template missing: $($templates[$k])" }
}

# ---- Load and filter CSV ---------------------------------------------------
$rows = Import-Csv -Path $CsvPath
$rows = $rows | Where-Object { $_.$FilterColumn -eq $FilterValue }
if (-not $rows) {
    Write-Warning "No rows in $CsvPath match $FilterColumn=$FilterValue"
    return
}

Write-Host "Building $($rows.Count) package(s) to $OutputRoot"
Write-Host ""

# ---- Per-location build loop ----------------------------------------------
$results = foreach ($row in $rows) {
    $slug     = $row.Slug
    $location = $row.LocationName
    $token    = $row.Token
    $url      = $row.UrlTemplate -replace '\{TOKEN\}', $token -replace '\{SLUG\}', $slug

    $pkgRoot = Join-Path $OutputRoot "$PackagePrefix-$slug"
    $srcDir  = Join-Path $pkgRoot "Source"
    $detDir  = Join-Path $pkgRoot "Detection"
    $outDir  = Join-Path $pkgRoot "Output"

    Write-Host "=== $location ($slug) ==="

    try {
        # Scaffold
        foreach ($d in @($pkgRoot, $srcDir, $detDir, $outDir)) {
            if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
        }

        # Copy templates
        Copy-Item $templates['Source\install.ps1']   (Join-Path $srcDir 'install.ps1')   -Force
        Copy-Item $templates['Source\uninstall.ps1'] (Join-Path $srcDir 'uninstall.ps1') -Force
        Copy-Item $templates['Detection\detect.ps1'] (Join-Path $detDir 'detect.ps1')    -Force

        # Download MSI (preserve filename from URL)
        $msiName = [System.IO.Path]::GetFileName([Uri]::new($url).AbsolutePath)
        $msiPath = Join-Path $srcDir $msiName

        if ((Test-Path $msiPath) -and -not $Force) {
            Write-Host "  MSI cached: $msiName"
        } else {
            Write-Host "  Downloading: $msiName"
            if ($UseCurl) {
                & curl.exe -sSL -o $msiPath $url
                if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" }
            } else {
                Invoke-WebRequest -Uri $url -OutFile $msiPath -UseBasicParsing
            }
        }

        # Build .intunewin
        Write-Host "  Packaging..."
        & $ToolPath -c $srcDir -s 'install.ps1' -o $outDir -q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "IntuneWinAppUtil exit $LASTEXITCODE" }

        # Rename output for clarity
        $built  = Get-ChildItem -Path $outDir -Filter 'install.intunewin' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $built) { throw "No .intunewin produced in $outDir" }

        $finalName = "$PackagePrefix-$slug.intunewin"
        $finalPath = Join-Path $outDir $finalName
        if (Test-Path $finalPath) { Remove-Item $finalPath -Force }
        Rename-Item $built.FullName -NewName $finalName
        Write-Host "  -> $finalPath"

        [pscustomobject]@{
            Location = $location
            Slug     = $slug
            Status   = 'OK'
            Output   = $finalPath
        }
    } catch {
        Write-Warning "  FAILED: $_"
        [pscustomobject]@{
            Location = $location
            Slug     = $slug
            Status   = "FAIL: $_"
            Output   = $null
        }
    }
    Write-Host ""
}

# ---- Summary ---------------------------------------------------------------
Write-Host "=== Build Summary ==="
$results | Format-Table Location, Slug, Status -AutoSize
$ok = ($results | Where-Object Status -eq 'OK').Count
Write-Host "$ok / $($results.Count) succeeded"
