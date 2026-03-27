<#
.SYNOPSIS
    Pre-Intune MDM Enrollment Remediation Script

.DESCRIPTION
    Removes policy-backed registry values that block MDM/Intune enrollment.
    Designed for deployment via GPO Startup Script or ManageEngine Endpoint Central.

    Targets:
    - DisableRegistration (hard block to MDM enrollment)
    - BlockAADWorkplaceJoin (blocks Azure AD workplace join)
    - Legacy enrollment artifacts under Policies key

.PARAMETER DetectOnly
    Run in detection/audit mode without making changes.

.PARAMETER IncludeWmiCleanup
    Also check for and remove orphaned WMI MDM authority records.

.PARAMETER Force
    Skip confirmation prompts (for unattended execution).

.NOTES
    Version:        1.0
    Author:         HK
    Creation Date:  2026-01-22
    Purpose:        Pre-enrollment remediation for Intune

    CHANGE RECORD:
    --------------
    CR#:            [TBD]
    Requested By:   Scott Klander / Paul
    Approved By:    [TBD]
    Implementation: GPO Startup Script / ManageEngine
    Rollback:       Restore from backup in C:\ProgramData\MdmEnrollmentRemediation\Backup\

.EXAMPLE
    .\Remediate-MdmEnrollmentBlock.ps1 -DetectOnly
    Audit mode - reports findings without changes.

.EXAMPLE
    .\Remediate-MdmEnrollmentBlock.ps1 -Force
    Full remediation, unattended.

.EXAMPLE
    .\Remediate-MdmEnrollmentBlock.ps1 -Force -IncludeWmiCleanup
    Full remediation including WMI MDM authority cleanup.
#>

[CmdletBinding()]
param(
    [switch]$DetectOnly,
    [switch]$IncludeWmiCleanup,
    [switch]$Force
)

#Requires -RunAsAdministrator

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:Config = @{
    LogPath       = "C:\ProgramData\MdmEnrollmentRemediation"
    BackupPath    = "C:\ProgramData\MdmEnrollmentRemediation\Backup"
    LogFile       = "Remediation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    EventLogName  = "Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin"

    # Registry paths to remediate (Policy keys - GPO/MDM controlled)
    RegistryTargets = @(
        @{
            Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
            Values = @(
                @{ Name = "DisableRegistration"; BlockingValue = 1; Description = "MDM Registration Disabled" }
            )
        },
        @{
            Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin"
            Values = @(
                @{ Name = "BlockAADWorkplaceJoin"; BlockingValue = 1; Description = "AAD Workplace Join Blocked" }
                @{ Name = "autoWorkplaceJoin"; BlockingValue = 0; Description = "Auto Workplace Join Disabled" }
            )
        }
    )
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Initialize-Logging {
    if (-not (Test-Path $Script:Config.LogPath)) {
        New-Item -Path $Script:Config.LogPath -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $Script:Config.BackupPath)) {
        New-Item -Path $Script:Config.BackupPath -ItemType Directory -Force | Out-Null
    }

    $Script:LogFilePath = Join-Path $Script:Config.LogPath $Script:Config.LogFile
    Start-Transcript -Path $Script:LogFilePath -Append
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DETECT")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"

    switch ($Level) {
        "ERROR"   { Write-Host $LogEntry -ForegroundColor Red }
        "WARN"    { Write-Host $LogEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $LogEntry -ForegroundColor Green }
        "DETECT"  { Write-Host $LogEntry -ForegroundColor Cyan }
        default   { Write-Host $LogEntry }
    }
}

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

function Backup-RegistryKey {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Log "Registry path does not exist, skipping backup: $Path" -Level INFO
        return $null
    }

    $KeyName = ($Path -replace "HKLM:\\", "" -replace "\\", "_")
    $BackupFile = Join-Path $Script:Config.BackupPath "$KeyName`_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"

    try {
        # Convert PowerShell path to reg.exe format
        $RegPath = $Path -replace "HKLM:\\", "HKLM\"
        $Result = reg export $RegPath $BackupFile /y 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Backed up: $Path -> $BackupFile" -Level SUCCESS
            return $BackupFile
        } else {
            Write-Log "Backup warning for $Path : $Result" -Level WARN
            return $null
        }
    }
    catch {
        Write-Log "Failed to backup $Path : $_" -Level ERROR
        return $null
    }
}

function Export-EventLog {
    $ExportFile = Join-Path $Script:Config.BackupPath "DMEDP_Events_$(Get-Date -Format 'yyyyMMdd_HHmmss').evtx"

    try {
        wevtutil epl $Script:Config.EventLogName $ExportFile 2>$null
        if (Test-Path $ExportFile) {
            Write-Log "Exported DMEDP event log to: $ExportFile" -Level SUCCESS
        }
    }
    catch {
        Write-Log "Could not export DMEDP event log (may not exist): $_" -Level WARN
    }
}

# ============================================================================
# DETECTION FUNCTIONS
# ============================================================================

function Get-BlockingRegistryValues {
    $Findings = @()

    foreach ($Target in $Script:Config.RegistryTargets) {
        $Path = $Target.Path

        if (-not (Test-Path $Path)) {
            Write-Log "Path does not exist: $Path" -Level INFO
            continue
        }

        foreach ($Value in $Target.Values) {
            try {
                $CurrentValue = Get-ItemProperty -Path $Path -Name $Value.Name -ErrorAction SilentlyContinue

                if ($null -ne $CurrentValue) {
                    $ActualValue = $CurrentValue.($Value.Name)

                    if ($ActualValue -eq $Value.BlockingValue) {
                        $Finding = [PSCustomObject]@{
                            Path         = $Path
                            Name         = $Value.Name
                            Value        = $ActualValue
                            BlockingValue = $Value.BlockingValue
                            Description  = $Value.Description
                            IsBlocking   = $true
                        }
                        $Findings += $Finding
                        Write-Log "BLOCKING: $($Value.Description) - $Path\$($Value.Name) = $ActualValue" -Level DETECT
                    }
                    else {
                        Write-Log "OK: $Path\$($Value.Name) = $ActualValue (not blocking)" -Level INFO
                    }
                }
            }
            catch {
                Write-Log "Error reading $Path\$($Value.Name): $_" -Level WARN
            }
        }
    }

    return $Findings
}

function Get-WmiMdmAuthority {
    try {
        $MdmAuthority = Get-CimInstance -Namespace "root/cimv2/mdm" -ClassName MDM_MgmtAuthority -ErrorAction SilentlyContinue
        if ($MdmAuthority) {
            Write-Log "WMI MDM Authority found: $($MdmAuthority | ConvertTo-Json -Compress)" -Level DETECT
            return $MdmAuthority
        }
        else {
            Write-Log "No WMI MDM Authority records found" -Level INFO
            return $null
        }
    }
    catch {
        Write-Log "WMI MDM namespace not accessible (expected if never enrolled): $_" -Level INFO
        return $null
    }
}

function Get-LegacyScheduledTasks {
    $LegacyTasks = @()

    try {
        $EntMgmtPath = "\Microsoft\Windows\EnterpriseMgmt\"
        $Tasks = Get-ScheduledTask -TaskPath "$EntMgmtPath*" -ErrorAction SilentlyContinue

        foreach ($Task in $Tasks) {
            Write-Log "Legacy scheduled task found: $($Task.TaskPath)$($Task.TaskName)" -Level DETECT
            $LegacyTasks += $Task
        }

        if ($LegacyTasks.Count -eq 0) {
            Write-Log "No legacy EnterpriseMgmt scheduled tasks found" -Level INFO
        }
    }
    catch {
        Write-Log "Error checking scheduled tasks: $_" -Level WARN
    }

    return $LegacyTasks
}

# ============================================================================
# REMEDIATION FUNCTIONS
# ============================================================================

function Remove-BlockingRegistryValue {
    param(
        [PSCustomObject]$Finding
    )

    if ($DetectOnly) {
        Write-Log "DETECT-ONLY: Would remove $($Finding.Path)\$($Finding.Name)" -Level DETECT
        return $true
    }

    try {
        Remove-ItemProperty -Path $Finding.Path -Name $Finding.Name -Force -ErrorAction Stop
        Write-Log "REMOVED: $($Finding.Path)\$($Finding.Name)" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "FAILED to remove $($Finding.Path)\$($Finding.Name): $_" -Level ERROR
        return $false
    }
}

function Remove-WmiMdmAuthority {
    param(
        $MdmAuthority
    )

    if ($DetectOnly) {
        Write-Log "DETECT-ONLY: Would remove WMI MDM Authority record" -Level DETECT
        return $true
    }

    try {
        $MdmAuthority | Remove-CimInstance -ErrorAction Stop
        Write-Log "REMOVED: WMI MDM Authority record" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "FAILED to remove WMI MDM Authority: $_" -Level ERROR
        return $false
    }
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

function Get-DsregStatus {
    Write-Log "Running dsregcmd /status for validation..." -Level INFO

    $DsregOutput = dsregcmd /status 2>&1
    $OutputFile = Join-Path $Script:Config.LogPath "dsregcmd_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $DsregOutput | Out-File -FilePath $OutputFile -Encoding UTF8

    Write-Log "dsregcmd output saved to: $OutputFile" -Level INFO

    # Parse key values
    $AzureAdJoined = $DsregOutput | Select-String "AzureAdJoined\s*:\s*(\w+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    $DomainJoined = $DsregOutput | Select-String "DomainJoined\s*:\s*(\w+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    $WorkplaceJoined = $DsregOutput | Select-String "WorkplaceJoined\s*:\s*(\w+)" | ForEach-Object { $_.Matches.Groups[1].Value }

    Write-Log "Device State - DomainJoined: $DomainJoined | AzureAdJoined: $AzureAdJoined | WorkplaceJoined: $WorkplaceJoined" -Level INFO

    return @{
        AzureAdJoined = $AzureAdJoined
        DomainJoined = $DomainJoined
        WorkplaceJoined = $WorkplaceJoined
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Invoke-MdmEnrollmentRemediation {
    Write-Log "============================================================" -Level INFO
    Write-Log "MDM Enrollment Remediation Started" -Level INFO
    Write-Log "Mode: $(if ($DetectOnly) { 'DETECT-ONLY' } else { 'REMEDIATION' })" -Level INFO
    Write-Log "Computer: $env:COMPUTERNAME" -Level INFO
    Write-Log "User Context: $env:USERNAME" -Level INFO
    Write-Log "============================================================" -Level INFO

    # Capture initial state
    Write-Log "--- INITIAL STATE ---" -Level INFO
    $InitialState = Get-DsregStatus

    # Export event log before changes
    Export-EventLog

    # Backup registry keys
    Write-Log "--- BACKUP PHASE ---" -Level INFO
    foreach ($Target in $Script:Config.RegistryTargets) {
        Backup-RegistryKey -Path $Target.Path
    }

    # Detection phase
    Write-Log "--- DETECTION PHASE ---" -Level INFO
    $BlockingValues = Get-BlockingRegistryValues
    $WmiAuthority = if ($IncludeWmiCleanup) { Get-WmiMdmAuthority } else { $null }
    $LegacyTasks = Get-LegacyScheduledTasks

    # Summary of findings
    Write-Log "--- FINDINGS SUMMARY ---" -Level INFO
    Write-Log "Blocking registry values found: $($BlockingValues.Count)" -Level $(if ($BlockingValues.Count -gt 0) { "WARN" } else { "SUCCESS" })
    Write-Log "WMI MDM Authority present: $(if ($WmiAuthority) { 'Yes' } else { 'No' })" -Level INFO
    Write-Log "Legacy scheduled tasks found: $($LegacyTasks.Count)" -Level $(if ($LegacyTasks.Count -gt 0) { "WARN" } else { "INFO" })

    if ($DetectOnly) {
        Write-Log "--- DETECT-ONLY MODE - NO CHANGES MADE ---" -Level DETECT
        $ExitCode = if ($BlockingValues.Count -gt 0) { 1 } else { 0 }
    }
    else {
        # Remediation phase
        Write-Log "--- REMEDIATION PHASE ---" -Level INFO
        $RemediationResults = @()

        foreach ($Finding in $BlockingValues) {
            $Result = Remove-BlockingRegistryValue -Finding $Finding
            $RemediationResults += @{ Finding = $Finding; Success = $Result }
        }

        if ($IncludeWmiCleanup -and $WmiAuthority) {
            $WmiResult = Remove-WmiMdmAuthority -MdmAuthority $WmiAuthority
            $RemediationResults += @{ Finding = "WMI MDM Authority"; Success = $WmiResult }
        }

        # Note about scheduled tasks (manual review recommended)
        if ($LegacyTasks.Count -gt 0) {
            Write-Log "Legacy scheduled tasks require manual review - not auto-removed" -Level WARN
        }

        # Post-remediation validation
        Write-Log "--- POST-REMEDIATION VALIDATION ---" -Level INFO
        $FinalState = Get-DsregStatus

        # Re-check for blocking values
        $RemainingBlocks = Get-BlockingRegistryValues

        $SuccessCount = ($RemediationResults | Where-Object { $_.Success }).Count
        $FailCount = ($RemediationResults | Where-Object { -not $_.Success }).Count

        Write-Log "--- REMEDIATION SUMMARY ---" -Level INFO
        Write-Log "Successful remediations: $SuccessCount" -Level SUCCESS
        Write-Log "Failed remediations: $FailCount" -Level $(if ($FailCount -gt 0) { "ERROR" } else { "INFO" })
        Write-Log "Remaining blocks: $($RemainingBlocks.Count)" -Level $(if ($RemainingBlocks.Count -gt 0) { "ERROR" } else { "SUCCESS" })

        $ExitCode = if ($FailCount -gt 0 -or $RemainingBlocks.Count -gt 0) { 1 } else { 0 }
    }

    Write-Log "============================================================" -Level INFO
    Write-Log "MDM Enrollment Remediation Completed - Exit Code: $ExitCode" -Level INFO
    Write-Log "Log file: $Script:LogFilePath" -Level INFO
    Write-Log "============================================================" -Level INFO

    return $ExitCode
}

# ============================================================================
# ENTRY POINT
# ============================================================================

try {
    Initialize-Logging
    $ExitCode = Invoke-MdmEnrollmentRemediation
    Stop-Transcript
    exit $ExitCode
}
catch {
    Write-Log "FATAL ERROR: $_" -Level ERROR
    Write-Log $_.ScriptStackTrace -Level ERROR
    Stop-Transcript
    exit 99
}
