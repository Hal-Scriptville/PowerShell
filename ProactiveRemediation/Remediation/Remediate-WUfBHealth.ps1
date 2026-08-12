<#
.SYNOPSIS
    Intune Proactive Remediation REMEDIATION — pairs with Detect-WUfBHealth.ps1.
    Clears the orphaned Windows Update policy values that disable automatic updates
    and restrict the Update UI, without touching any currently-legitimate policy.

.DESCRIPTION
    Built 2026-08-12 from a live Whitsons session (005-WPC-5040 / elsters) that traced
    "Not up to date" / AUTOUPDATE_DISABLED back to leftover registry values under
    HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate — a path that is normally
    only ever written by Group Policy or MDM/CSP policy processing, yet:
      - RSoP showed NO Windows Update GPO applying to the device
      - The Intune Update CSP diagnostic (cspAllowAutoUpdate) reported OK

    That combination is the signature of tattooing: a GPO that used to apply this
    setting was unlinked/deleted without Windows reverting the registry values it left
    behind. Confirmed on 005-WPC-5040: deleted the AU subkey, rebooted (which forces
    both a GPO refresh and an MDM/CSP sync), and it did NOT come back — proving nothing
    was actively re-applying it on that device.

    ⚠️ NOT YET PROVEN FLEET-WIDE. On a second device (Brian's) in the SAME session, the
    AU key WAS re-added after reboot — meaning on at least some devices something IS
    still actively writing it (a still-linked GPO on a different OU/security-group
    scope, or an Intune profile not yet identified). This is why this script is a
    REMEDIATION for a recurring Proactive Remediation deployment, not a one-time push:
    it is safe to run repeatedly (idempotent, no-op if nothing to fix), so if a device
    has an active re-applier it will just get cleaned again next cycle rather than
    silently drifting back to broken. The active source on those devices should still
    be found and dealt with directly — this script treats the symptom, not that cause.

    Removes (backing up each key to .reg first):
      - NoAutoUpdate, AUOptions under ...\WindowsUpdate\AU
        (NoAutoUpdate=1 is what actually blocks updates; confirmed by the reboot test)
      - SetDisableUXWUAccess, SetDisablePauseUXAccess under ...\WindowsUpdate directly
        (observed live 8/12 blocking the "Install all" / "Pause updates" UI controls
        on the same device, once AU was already cleared)

    Deliberately NOT touched: DeferFeatureUpdates, DeferQualityUpdates,
    ExcludeWUDriversInQualityUpdate, SetActiveHours — these were also present but
    showed benign/default-looking values (0, or a single flag) and are not confirmed
    part of the same orphaned pattern. Don't widen the blast radius on a guess.

.OUTPUTS
    Exit 0 = ran successfully (whether or not there was anything to remediate).
    Exit 1 = a removal failed. STDOUT is transcript-logged.

.NOTES
    Requires: Run as SYSTEM, 64-bit (matches Detect-WUfBHealth.ps1 deployment context).
    Backups: C:\ProgramData\WUfBRemediation\Backup\*.reg (reg export before each delete).
    Rollback: reg import any backup file to restore that key/value.
#>

$ErrorActionPreference = 'Stop'
$LogPath    = 'C:\ProgramData\WUfBRemediation'
$BackupPath = "$LogPath\Backup"
foreach ($p in @($LogPath, $BackupPath)) {
    if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
}
Start-Transcript -Path (Join-Path $LogPath "remediate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log") -Append | Out-Null

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','SUCCESS')][string]$Level = 'INFO')
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
}

function Backup-RegValue {
    param([string]$KeyPath, [string]$Label)   # PowerShell-style HKLM:\...
    if (-not (Test-Path $KeyPath)) { return }
    $safe = ($Label -replace '[\\:]', '_')
    $file = Join-Path $BackupPath "$safe`_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
    $native = $KeyPath -replace 'HKLM:\\', 'HKLM\'
    $null = reg export $native $file /y 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Log "Backed up $KeyPath -> $file" -Level SUCCESS }
    else { Write-Log "Backup warning for $KeyPath (exit $LASTEXITCODE)" -Level WARN }
}

$failed = $false
$didWork = $false

# ── 1. AU subkey: NoAutoUpdate / AUOptions ───────────────────────────────────
$auKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
if (Test-Path $auKey) {
    $props = Get-ItemProperty -Path $auKey -ErrorAction SilentlyContinue
    if ($props.NoAutoUpdate -eq 1 -or $null -ne $props.AUOptions) {
        Write-Log "Found AU policy values (NoAutoUpdate=$($props.NoAutoUpdate) AUOptions=$($props.AUOptions)) on $auKey"
        Backup-RegValue -KeyPath $auKey -Label 'WindowsUpdate_AU'
        try {
            Remove-Item -Path $auKey -Recurse -Force -ErrorAction Stop
            Write-Log "Removed $auKey" -Level SUCCESS
            $didWork = $true
        } catch {
            Write-Log "FAILED to remove $auKey : $_" -Level ERROR
            $failed = $true
        }
    } else {
        Write-Log "AU key present but no blocking values found - leaving as-is."
    }
} else {
    Write-Log "AU key not present - nothing to do."
}

# ── 2. UX-restriction values on the parent WindowsUpdate key ────────────────
$wuKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
if (Test-Path $wuKey) {
    Backup-RegValue -KeyPath $wuKey -Label 'WindowsUpdate_parent'
    foreach ($valueName in @('SetDisableUXWUAccess', 'SetDisablePauseUXAccess')) {
        $val = (Get-ItemProperty -Path $wuKey -Name $valueName -ErrorAction SilentlyContinue).$valueName
        if ($val -eq 1) {
            try {
                Remove-ItemProperty -Path $wuKey -Name $valueName -Force -ErrorAction Stop
                Write-Log "Removed $valueName from $wuKey" -Level SUCCESS
                $didWork = $true
            } catch {
                Write-Log "FAILED to remove $valueName : $_" -Level ERROR
                $failed = $true
            }
        }
    }
}

# ── Result ─────────────────────────────────────────────────────────────────
if ($failed) {
    Write-Log "Completed with errors - see above." -Level ERROR
    Stop-Transcript | Out-Null
    exit 1
} elseif ($didWork) {
    Write-Log "Remediation applied. Device should be re-evaluated by Detect-WUfBHealth.ps1 next cycle." -Level SUCCESS
    Stop-Transcript | Out-Null
    exit 0
} else {
    Write-Log "Nothing to remediate - device already clean." -Level SUCCESS
    Stop-Transcript | Out-Null
    exit 0
}
