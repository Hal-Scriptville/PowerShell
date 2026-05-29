<#
.SYNOPSIS
    Removes an existing third-party MDM enrollment (e.g. ManageEngine Endpoint Central)
    so a Windows device can auto-enroll into Microsoft Intune.

.DESCRIPTION
    Windows allows only ONE active MDM enrollment per device. When a device is already
    enrolled in a third-party MDM (such as ManageEngine / "MEMDM"), Intune auto-enrollment
    silently fails ("Auto MDM Enroll: ... Failed", and the device never appears in Intune)
    because the single MDM slot is occupied.

    This script locates the existing MDM enrollment, backs up every registry key it will
    touch, removes the enrollment artifacts (registry + the EnterpriseMgmt scheduled-task
    folder), and optionally uninstalls the third-party agent. After it runs, the MDM slot
    is free and Intune auto-enrollment (GPO / "Access work or school" / deviceenroller)
    can proceed.

    It is deliberately GENERIC: by default it targets the well-known ManageEngine provider
    id ("MEMDM") and discovery host ("manageengine.com"), but you can point it at any
    provider via -ProviderId / -DiscoveryUrlMatch. It will NOT touch a Microsoft Intune
    enrollment (ProviderID "MS DM Server") unless you explicitly name it.

    Everything is backed up to C:\ProgramData\MDMRemoval\Backup before deletion, and the
    run is fully transcript-logged. Re-runnable (idempotent).

.PARAMETER ProviderId
    The enrollment ProviderID to remove. Default: "MEMDM" (ManageEngine).
    The Intune provider "MS DM Server" is protected and will be skipped unless it is the
    value you explicitly pass here.

.PARAMETER DiscoveryUrlMatch
    Optional additional safety match. If set, an enrollment is only removed when its
    DiscoveryServiceFullURL contains this substring. Default: "manageengine.com".
    Pass an empty string ("") to match on ProviderID alone.

.PARAMETER RemoveAgent
    Also attempt to uninstall the third-party management agent after removing the
    enrollment. Searches the uninstall registry for products matching -AgentNameMatch
    and runs their QuietUninstallString / UninstallString.

.PARAMETER AgentNameMatch
    Display-name substring used to find the agent to uninstall when -RemoveAgent is set.
    Default: "ManageEngine".

.PARAMETER DetectOnly
    Report what would be removed without making any changes.

.PARAMETER Force
    Skip the confirmation prompt (for unattended GPO / RMM execution).

.NOTES
    Version:        1.0
    Author:         Hal Kurz (The Intune Pros)
    Creation Date:  2026-05-29
    Requires:       Run as SYSTEM or elevated Administrator.

    Registry artifacts removed (for the matched {EnrollmentGUID}):
        HKLM\SOFTWARE\Microsoft\Enrollments\{GUID}
        HKLM\SOFTWARE\Microsoft\Enrollments\Status\{GUID}
        HKLM\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked\{GUID}
        HKLM\SOFTWARE\Microsoft\PolicyManager\AdmxInstalled\{GUID}   (if present)
        HKLM\SOFTWARE\Microsoft\PolicyManager\Providers\{GUID}       (if present)
    Scheduled tasks removed:
        \Microsoft\Windows\EnterpriseMgmt\{GUID}\*  (and the {GUID} task folder)

    Rollback: import the .reg files from C:\ProgramData\MDMRemoval\Backup.

.EXAMPLE
    .\Remove-ManageEngineMDM.ps1 -DetectOnly
    Show the matched ManageEngine enrollment and what would be removed. No changes.

.EXAMPLE
    .\Remove-ManageEngineMDM.ps1 -Force
    Back up and remove the ManageEngine MDM enrollment, unattended.

.EXAMPLE
    .\Remove-ManageEngineMDM.ps1 -Force -RemoveAgent
    Remove the enrollment and uninstall the ManageEngine agent.

.EXAMPLE
    .\Remove-ManageEngineMDM.ps1 -ProviderId "SomeOtherMDM" -DiscoveryUrlMatch "vendor.com" -Force
    Target a different third-party MDM by provider id + discovery host.
#>

[CmdletBinding()]
param(
    [string]$ProviderId        = "MEMDM",
    [string]$DiscoveryUrlMatch = "manageengine.com",
    [switch]$RemoveAgent,
    [string]$AgentNameMatch    = "ManageEngine",
    [switch]$DetectOnly,
    [switch]$Force
)

#Requires -RunAsAdministrator

# ============================================================================
# CONFIGURATION
# ============================================================================
$Script:Config = @{
    LogPath    = "C:\ProgramData\MDMRemoval"
    BackupPath = "C:\ProgramData\MDMRemoval\Backup"
    LogFile    = "MDMRemoval_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
}

# Provider we must never remove unless explicitly named (Intune).
$Script:ProtectedProvider = "MS DM Server"

$Script:EnrollmentsRoot = "HKLM:\SOFTWARE\Microsoft\Enrollments"
$Script:TaskFolderRoot  = "\Microsoft\Windows\EnterpriseMgmt"

# ============================================================================
# LOGGING
# ============================================================================
function Initialize-Logging {
    foreach ($p in @($Script:Config.LogPath, $Script:Config.BackupPath)) {
        if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
    }
    $Script:LogFilePath = Join-Path $Script:Config.LogPath $Script:Config.LogFile
    Start-Transcript -Path $Script:LogFilePath -Append | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS","DETECT")]
        [string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    switch ($Level) {
        "ERROR"   { Write-Host $line -ForegroundColor Red }
        "WARN"    { Write-Host $line -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $line -ForegroundColor Green }
        "DETECT"  { Write-Host $line -ForegroundColor Cyan }
        default   { Write-Host $line }
    }
}

# ============================================================================
# DISCOVERY
# ============================================================================
function Get-TargetEnrollments {
    # NOTE: do not use $matches here - it is the automatic variable set by -match.
    $results = @()
    if (-not (Test-Path $Script:EnrollmentsRoot)) {
        Write-Log "No Enrollments key present - device has no MDM enrollment." -Level INFO
        return $results
    }

    # foreach STATEMENT (not ForEach-Object) so += persists in this scope.
    $subKeys = Get-ChildItem $Script:EnrollmentsRoot -ErrorAction SilentlyContinue |
               Where-Object { $_.PSChildName -match '^\{?[0-9A-Fa-f-]{36}\}?$' }

    foreach ($key in $subKeys) {
        $guid  = $key.PSChildName
        $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        $prov  = $props.ProviderID
        $disc  = $props.DiscoveryServiceFullURL
        $upn   = $props.UPN

        if (-not $prov) { continue }

        # Never remove Intune unless the caller explicitly asked for that provider id.
        if ($prov -eq $Script:ProtectedProvider -and $ProviderId -ne $Script:ProtectedProvider) {
            Write-Log "Skipping protected Intune enrollment {$guid} (ProviderID '$prov')." -Level INFO
            continue
        }

        $provMatch = ($prov -eq $ProviderId)
        $urlMatch  = [string]::IsNullOrEmpty($DiscoveryUrlMatch) -or
                     ($disc -and $disc -match [regex]::Escape($DiscoveryUrlMatch))

        if ($provMatch -and $urlMatch) {
            $results += [PSCustomObject]@{
                Guid         = $guid
                ProviderID   = $prov
                UPN          = $upn
                DiscoveryUrl = $disc
            }
            Write-Log "MATCH: enrollment {$guid} ProviderID='$prov' UPN='$upn'" -Level DETECT
        } else {
            Write-Log "No match: {$guid} ProviderID='$prov'" -Level INFO
        }
    }
    return ,$results
}

# ============================================================================
# BACKUP
# ============================================================================
function Backup-Key {
    param([string]$RegPath)   # PowerShell-style HKLM:\...
    if (-not (Test-Path $RegPath)) { return }
    $name = ($RegPath -replace 'HKLM:\\','' -replace '[\\:]','_')
    $file = Join-Path $Script:Config.BackupPath "$name`_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
    $regExe = $RegPath -replace 'HKLM:\\','HKLM\'
    $null = reg export $regExe $file /y 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Log "Backed up $RegPath -> $file" -Level SUCCESS }
    else { Write-Log "Backup warning for $RegPath (exit $LASTEXITCODE)" -Level WARN }
}

# ============================================================================
# REMOVAL
# ============================================================================
function Remove-EnrollmentArtifacts {
    param([Parameter(Mandatory)][string]$Guid)

    $regTargets = @(
        "HKLM:\SOFTWARE\Microsoft\Enrollments\$Guid",
        "HKLM:\SOFTWARE\Microsoft\Enrollments\Status\$Guid",
        "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked\$Guid",
        "HKLM:\SOFTWARE\Microsoft\PolicyManager\AdmxInstalled\$Guid",
        "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$Guid"
    )

    # Backup first (always, even in DetectOnly we skip - backup only when changing).
    foreach ($t in $regTargets) { Backup-Key -RegPath $t }

    foreach ($t in $regTargets) {
        if (Test-Path $t) {
            if ($DetectOnly) {
                Write-Log "DETECT-ONLY: would remove $t" -Level DETECT
            } else {
                try {
                    Remove-Item -Path $t -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed $t" -Level SUCCESS
                } catch {
                    Write-Log "FAILED to remove $t : $_" -Level ERROR
                }
            }
        }
    }

    # Scheduled task folder \Microsoft\Windows\EnterpriseMgmt\{GUID}\
    $taskPath = "$Script:TaskFolderRoot\$Guid\"
    $tasks = Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue
    if ($tasks) {
        if ($DetectOnly) {
            Write-Log "DETECT-ONLY: would remove $($tasks.Count) scheduled task(s) under $taskPath" -Level DETECT
        } else {
            foreach ($tk in $tasks) {
                try {
                    Unregister-ScheduledTask -TaskName $tk.TaskName -TaskPath $taskPath -Confirm:$false -ErrorAction Stop
                    Write-Log "Removed scheduled task $taskPath$($tk.TaskName)" -Level SUCCESS
                } catch {
                    Write-Log "FAILED to remove task $($tk.TaskName): $_" -Level ERROR
                }
            }
            # Remove the now-empty task folder via the Schedule.Service COM object.
            try {
                $svc = New-Object -ComObject "Schedule.Service"
                $svc.Connect()
                $root = $svc.GetFolder($Script:TaskFolderRoot)
                $root.DeleteFolder($Guid, 0)
                Write-Log "Removed task folder $taskPath" -Level SUCCESS
            } catch {
                Write-Log "Task folder $taskPath not removed (may be non-empty or absent): $_" -Level WARN
            }
        }
    }
}

# ============================================================================
# AGENT UNINSTALL (optional)
# ============================================================================
function Remove-Agent {
    param([string]$NameMatch)

    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $found = foreach ($r in $uninstallRoots) {
        Get-ItemProperty $r -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.DisplayName -match [regex]::Escape($NameMatch) }
    }

    if (-not $found) {
        Write-Log "No installed product matching '$NameMatch' found to uninstall." -Level INFO
        return
    }

    foreach ($app in $found) {
        $cmd = $app.QuietUninstallString
        if (-not $cmd) { $cmd = $app.UninstallString }
        if (-not $cmd) {
            Write-Log "No uninstall string for '$($app.DisplayName)' - skipping." -Level WARN
            continue
        }

        if ($DetectOnly) {
            Write-Log "DETECT-ONLY: would uninstall '$($app.DisplayName)' via: $cmd" -Level DETECT
            continue
        }

        Write-Log "Uninstalling '$($app.DisplayName)'..." -Level INFO
        try {
            if ($cmd -match 'msiexec') {
                # Normalise MSI uninstall to quiet/no-restart.
                $guid = if ($cmd -match '\{[0-9A-Fa-f-]{36}\}') { $matches[0] } else { $null }
                if ($guid) {
                    Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -Wait -NoNewWindow
                } else {
                    Start-Process cmd.exe -ArgumentList "/c $cmd /qn /norestart" -Wait -NoNewWindow
                }
            } else {
                Start-Process cmd.exe -ArgumentList "/c $cmd" -Wait -NoNewWindow
            }
            Write-Log "Uninstall command completed for '$($app.DisplayName)'." -Level SUCCESS
        } catch {
            Write-Log "FAILED to uninstall '$($app.DisplayName)': $_" -Level ERROR
        }
    }
}

# ============================================================================
# MAIN
# ============================================================================
function Invoke-Removal {
    Write-Log "============================================================"
    Write-Log "ManageEngine / third-party MDM removal"
    Write-Log "Mode: $(if ($DetectOnly) {'DETECT-ONLY'} else {'REMOVE'}) | ProviderId: '$ProviderId' | UrlMatch: '$DiscoveryUrlMatch'"
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "============================================================"

    $targets = Get-TargetEnrollments
    if (-not $targets -or $targets.Count -eq 0) {
        Write-Log "No matching third-party MDM enrollment found. Nothing to do." -Level SUCCESS
        return 0
    }

    Write-Log "Found $($targets.Count) matching enrollment(s)." -Level $(if ($targets.Count) {'WARN'} else {'INFO'})

    if (-not $DetectOnly -and -not $Force) {
        Write-Host ""
        $ans = Read-Host "Remove the above enrollment(s) and free the MDM slot? [y/N]"
        if ($ans -notmatch '^[Yy]') { Write-Log "Cancelled by operator." -Level WARN; return 2 }
    }

    foreach ($t in $targets) {
        Write-Log "--- Processing enrollment {$($t.Guid)} (ProviderID '$($t.ProviderID)') ---"
        Remove-EnrollmentArtifacts -Guid $t.Guid
    }

    if ($RemoveAgent) {
        Write-Log "--- Agent uninstall phase (match '$AgentNameMatch') ---"
        Remove-Agent -NameMatch $AgentNameMatch
    }

    # Validation
    Write-Log "--- Validation ---"
    $remaining = Get-TargetEnrollments
    if ($DetectOnly) {
        Write-Log "DETECT-ONLY complete. $($targets.Count) enrollment(s) would be removed." -Level DETECT
        return 0
    }
    if ($remaining.Count -gt 0) {
        Write-Log "WARNING: $($remaining.Count) matching enrollment(s) still present." -Level ERROR
        return 1
    }

    Write-Log "MDM slot is now free. Trigger Intune enrollment with:" -Level SUCCESS
    Write-Log "  deviceenroller.exe /c /AutoEnrollMDM   (in the logged-on user's context, valid PRT required)" -Level INFO
    return 0
}

# ============================================================================
# ENTRY POINT
# ============================================================================
try {
    Initialize-Logging
    $code = Invoke-Removal
    Write-Log "Done. Exit code: $code  | Log: $Script:LogFilePath"
    Stop-Transcript | Out-Null
    exit $code
} catch {
    Write-Log "FATAL: $_" -Level ERROR
    Write-Log $_.ScriptStackTrace -Level ERROR
    try { Stop-Transcript | Out-Null } catch {}
    exit 99
}
