# Detect-BitLockerEscrow.ps1
# Proactive Remediation - Detection
#
# Verifies BitLocker is enabled on C: with a recovery password protector
# and that a successful Azure AD backup event exists in the last 90 days.
#
# Exit 0 = compliant
# Exit 1 = non-compliant, remediation will trigger

try {
    $BLV = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop

    if ($BLV.ProtectionStatus -ne "On") {
        Write-Output "NON-COMPLIANT: BitLocker protection is off on C:"
        exit 1
    }

    $RecoveryProtector = $BLV.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
    if (-not $RecoveryProtector) {
        Write-Output "NON-COMPLIANT: No recovery password protector found"
        exit 1
    }

    # Event ID 845 = BitLocker recovery key successfully backed up to Azure AD
    $CutoffDate = (Get-Date).AddDays(-90)
    $BackupEvent = Get-WinEvent -FilterHashtable @{
        LogName   = "Microsoft-Windows-BitLocker/BitLocker Management"
        Id        = 845
        StartTime = $CutoffDate
    } -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $BackupEvent) {
        Write-Output "NON-COMPLIANT: No Azure AD key backup event found in last 90 days"
        exit 1
    }

    Write-Output "COMPLIANT: BitLocker on, recovery password present, AAD backup confirmed $($BackupEvent.TimeCreated)"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
