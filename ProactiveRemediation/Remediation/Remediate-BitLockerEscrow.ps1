# Remediate-BitLockerEscrow.ps1
# Proactive Remediation - Remediation
#
# Ensures a recovery password protector exists on C: and backs it up
# to Azure AD. Also attempts on-premises AD DS backup for hybrid environments.
#
# Note: This script does not enable BitLocker — that is handled by Intune
# BitLocker policy or SCCM task sequence. This script only handles key escrow
# for machines that are already encrypted but missing a backup.
#
# Exit 0 = success
# Exit 1 = failure

try {
    $MountPoint = "C:"
    $BLV = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop

    if ($BLV.ProtectionStatus -ne "On") {
        Write-Output "ERROR: BitLocker is not enabled on $MountPoint — escrow not possible"
        exit 1
    }

    # Add a recovery password protector if one does not exist
    $RecoveryProtector = $BLV.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
    if (-not $RecoveryProtector) {
        Write-Output "No recovery password protector found — adding one"
        Add-BitLockerKeyProtector -MountPoint $MountPoint -RecoveryPasswordProtector -ErrorAction Stop
        $BLV = Get-BitLockerVolume -MountPoint $MountPoint
        $RecoveryProtector = $BLV.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
    }

    $KeyProtectorId = $RecoveryProtector.KeyProtectorId

    # Backup to Azure AD
    BackupToAAD-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $KeyProtectorId -ErrorAction Stop
    Write-Output "SUCCESS: Recovery key escrowed to Azure AD (protector: $KeyProtectorId)"

    # Backup to on-premises AD DS (for hybrid environments with GPO AD escrow requirement)
    $ADBackup = manage-bde -protectors -adbackup $MountPoint -id $KeyProtectorId 2>&1
    Write-Output "AD DS backup result: $ADBackup"

    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
