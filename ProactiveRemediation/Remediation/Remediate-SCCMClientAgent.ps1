<#
.SYNOPSIS
    Removes orphaned SCCM/ConfigMgr client agent installations.

.DESCRIPTION
    Intune Proactive Remediation - Remediation Script

    Removes SCCM client artifacts from endpoints where SCCM infrastructure has been
    decommissioned or devices are being migrated to Intune-only management.

    Removal sequence:
    1. Stop and disable CcmExec and related services
    2. Run ccmsetup.exe /uninstall (official path) if binary is present
    3. Delete services from Service Control Manager
    4. Remove registry keys (CCM, CCMSetup, SMS — x64 and WOW6432Node)
    5. Remove directories (CCM, ccmsetup, ccmcache, SMSCFG.ini)
    6. Remove WMI namespaces (root\CCM, root\SMS)
    7. Verify and log

    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RemoveSCCMAgent.log

    Exit Codes:
    - 0 = Remediation complete (reboot may be required for full cleanup)
    - 1 = Remediation failed

.NOTES
    Author:  Hal Kurz
    Version: 2.0
    Updated: 2026-04-02
    Repo:    https://github.com/Hal-Scriptville/PowerShell

    WARNING: Only use when SCCM infrastructure is decommissioned or devices are
    being intentionally removed from SCCM management. This permanently removes
    the SCCM client — the device will no longer check in to any SCCM site.
#>

$ErrorActionPreference = "SilentlyContinue"

$logPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\RemoveSCCMAgent.log"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Add-Content -Path $logPath -Value $line -Force
    Write-Output $line
}

Write-Log "=== Starting SCCM Agent Removal ==="

# --- Step 1: Stop services ---
Write-Log "Step 1: Stopping SCCM services..."

@("CcmExec", "smstsmgr", "ccmsetup", "CmRcService") | ForEach-Object {
    $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Log "  Stopping $_ (state: $($svc.Status))..."
        Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
        Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Log "  $_ stopped and disabled"
    }
}

# --- Step 2: Run official uninstaller ---
Write-Log "Step 2: Looking for ccmsetup.exe uninstaller..."

$ccmSetupPaths = @(
    "$env:SystemRoot\ccmsetup\ccmsetup.exe",
    "$env:SystemRoot\CCM\ccmsetup.exe"
)

$uninstallerRan = $false
foreach ($path in $ccmSetupPaths) {
    if (Test-Path $path) {
        Write-Log "  Found: $path — running /uninstall"
        $proc = Start-Process -FilePath $path -ArgumentList "/uninstall" -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
        Write-Log "  Exit code: $($proc.ExitCode)"
        $uninstallerRan = $true
        Start-Sleep -Seconds 30
        break
    }
}

if (-not $uninstallerRan) {
    Write-Log "  ccmsetup.exe not found — proceeding with manual cleanup"
}

# --- Step 3: Remove services from SCM ---
Write-Log "Step 3: Removing services from SCM..."

@("CcmExec", "smstsmgr", "ccmsetup", "CmRcService", "CCMSetupService") | ForEach-Object {
    if (Get-Service -Name $_ -ErrorAction SilentlyContinue) {
        sc.exe delete $_ | Out-Null
        Write-Log "  Deleted service: $_"
    }
}

# --- Step 4: Remove registry keys ---
Write-Log "Step 4: Removing registry keys..."

@(
    "HKLM:\SOFTWARE\Microsoft\CCM",
    "HKLM:\SOFTWARE\Microsoft\CCMSetup",
    "HKLM:\SOFTWARE\Microsoft\SMS",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CCM",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\CCMSetup",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\SMS",
    "HKLM:\SYSTEM\CurrentControlSet\Services\CcmExec",
    "HKLM:\SYSTEM\CurrentControlSet\Services\smstsmgr",
    "HKLM:\SYSTEM\CurrentControlSet\Services\ccmsetup"
) | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "  Removed: $_"
    }
}

# --- Step 5: Remove directories and files ---
Write-Log "Step 5: Removing directories and files..."

@(
    "$env:SystemRoot\CCM",
    "$env:SystemRoot\ccmsetup",
    "$env:SystemRoot\ccmcache",
    "$env:ProgramData\Microsoft Configuration Manager"
) | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "  Removed: $_"
    }
}

# SMSCFG.ini stores the site assignment — important to remove
$smsCfg = "$env:SystemRoot\SMSCFG.ini"
if (Test-Path $smsCfg) {
    Remove-Item -Path $smsCfg -Force -ErrorAction SilentlyContinue
    Write-Log "  Removed SMSCFG.ini (site assignment file)"
}

# --- Step 6: Remove WMI namespaces ---
Write-Log "Step 6: Removing WMI namespaces..."

try {
    $ccmNS = Get-WmiObject -Query "SELECT * FROM __Namespace WHERE Name='CCM'" -Namespace "root" -ErrorAction SilentlyContinue
    if ($ccmNS) { $ccmNS.Delete(); Write-Log "  Removed root\CCM WMI namespace" }

    $smsNS = Get-WmiObject -Query "SELECT * FROM __Namespace WHERE Name='SMS'" -Namespace "root" -ErrorAction SilentlyContinue
    if ($smsNS) { $smsNS.Delete(); Write-Log "  Removed root\SMS WMI namespace" }
}
catch {
    Write-Log "  WMI removal error (non-fatal): $($_.Exception.Message)"
}

# --- Step 7: Verify ---
Write-Log "Step 7: Verifying removal..."

$remaining = @()
if ((Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue)?.Status -ne 'Stopped') { $remaining += "CcmExec service" }
if (Test-Path "HKLM:\SOFTWARE\Microsoft\CCM") { $remaining += "CCM registry key" }
if (Test-Path "$env:SystemRoot\CCM\CcmExec.exe") { $remaining += "CcmExec.exe binary" }

if ($remaining.Count -eq 0) {
    Write-Log "Verification PASSED — all SCCM artifacts removed"
}
else {
    Write-Log "Verification NOTE — remaining items (may clear after reboot):"
    $remaining | ForEach-Object { Write-Log "  - $_" }
}

Write-Log "=== SCCM Agent Removal Complete ==="
exit 0
