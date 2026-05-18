# Remediate-FirefoxUnused.ps1
# Proactive Remediation — Remediation Script
# Purpose: Silently uninstall Firefox when detection script returns non-compliant
# Exit 0 = Remediation succeeded
# Exit 1 = Remediation failed

function Uninstall-ViaWinGet {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { return $false }
    $result = & winget uninstall --id Mozilla.Firefox --silent --accept-source-agreements 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Uninstall-ViaHelper {
    $helpers = @(
        "$env:ProgramFiles\Mozilla Firefox\uninstall\helper.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\uninstall\helper.exe"
    ) | Where-Object { Test-Path $_ }

    foreach ($helper in $helpers) {
        & $helper /S 2>&1 | Out-Null
        Start-Sleep -Seconds 10
        if (-not (Test-Path (Split-Path $helper -Parent | Split-Path -Parent | Join-Path -ChildPath "firefox.exe"))) {
            return $true
        }
    }
    return $false
}

function Uninstall-ViaRegistry {
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($key in $uninstallKeys) {
        $firefox = Get-ChildItem $key -ErrorAction SilentlyContinue |
            Get-ItemProperty -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*Mozilla Firefox*" } |
            Select-Object -First 1
        if ($firefox -and $firefox.UninstallString) {
            $uninstallCmd = $firefox.UninstallString -replace '"', ''
            & $uninstallCmd /S 2>&1 | Out-Null
            Start-Sleep -Seconds 10
            return $true
        }
    }
    return $false
}

# Try methods in order
$success = Uninstall-ViaWinGet
if (-not $success) { $success = Uninstall-ViaHelper }
if (-not $success) { $success = Uninstall-ViaRegistry }

# Confirm Firefox binary is gone
$stillInstalled = @(
    "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
    "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
) | Where-Object { Test-Path $_ }

if ($stillInstalled) {
    Write-Output "Uninstall attempted but firefox.exe still present. Failed."
    exit 1
}

Write-Output "Firefox uninstalled successfully."
exit 0
