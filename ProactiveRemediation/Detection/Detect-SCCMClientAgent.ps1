<#
.SYNOPSIS
    Detects orphaned SCCM/ConfigMgr client agent installations.

.DESCRIPTION
    Intune Proactive Remediation - Detection Script

    Checks for SCCM client artifacts (services, registry keys, directories, installed
    programs) that may remain after SCCM infrastructure has been decommissioned or
    when devices are being migrated away from SCCM/co-management to Intune-only.

    Useful when:
    - Migrating from SCCM co-management to Intune-only management
    - SCCM infrastructure has been retired but agents remain on endpoints
    - Cleaning up endpoints before deploying a new RMM or management agent

    Exit Codes:
    - 0 = Compliant (no SCCM agent artifacts found)
    - 1 = Non-compliant (SCCM artifacts detected — remediation required)

.NOTES
    Author:  Hal Kurz
    Version: 2.0
    Updated: 2026-04-02
    Repo:    https://github.com/Hal-Scriptville/PowerShell
#>

$ErrorActionPreference = "SilentlyContinue"

$found = $false
$reasons = @()

# 1. CCMExec service (primary indicator)
$svc = Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue
if ($svc) {
    $found = $true
    $reasons += "CcmExec service present (Status: $($svc.Status), StartType: $($svc.StartType))"
}

# 2. SMS Task Sequence Manager service
$smsTsm = Get-Service -Name "smstsmgr" -ErrorAction SilentlyContinue
if ($smsTsm) {
    $found = $true
    $reasons += "smstsmgr (SMS Task Sequence Manager) service present"
}

# 3. CCMSetup installer service
$ccmSetupSvc = Get-Service -Name "ccmsetup" -ErrorAction SilentlyContinue
if ($ccmSetupSvc) {
    $found = $true
    $reasons += "ccmsetup service present"
}

# 4. CCM registry key
if (Test-Path "HKLM:\SOFTWARE\Microsoft\CCM") {
    $found = $true
    $reasons += "SCCM registry key present: HKLM:\SOFTWARE\Microsoft\CCM"
}

# 5. CCM install directory
if (Test-Path "$env:SystemRoot\CCM") {
    $found = $true
    $reasons += "CCM directory present: $env:SystemRoot\CCM"
}

# 6. CCMSetup directory
if (Test-Path "$env:SystemRoot\ccmsetup") {
    $found = $true
    $reasons += "CCMSetup directory present: $env:SystemRoot\ccmsetup"
}

# 7. SCCM client in Add/Remove Programs
$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
foreach ($path in $uninstallPaths) {
    if (Test-Path $path) {
        Get-ChildItem -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            $name = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).DisplayName
            if ($name -like "*Configuration Manager Client*" -or $name -like "*SMS Client*") {
                $found = $true
                $reasons += "SCCM client in installed programs: $name"
            }
        }
    }
}

# Output and exit
if ($found) {
    Write-Output "NON-COMPLIANT: SCCM agent artifacts detected"
    $reasons | ForEach-Object { Write-Output "  - $_" }
    exit 1
}
else {
    Write-Output "COMPLIANT: No SCCM agent artifacts found"
    exit 0
}
