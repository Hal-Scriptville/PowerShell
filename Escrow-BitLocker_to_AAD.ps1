# Check if BitLocker is enabled on the C: drive
$bitLockerStatus = Get-BitLockerVolume -MountPoint C: | Select-Object -ExpandProperty ProtectionStatus

if ($bitLockerStatus -eq 'On') {
    # BitLocker is enabled, check if the recovery key is stored in Azure AD
    $recoveryKeyStored = Get-BitLockerVolume -MountPoint C: | Select-Object -ExpandProperty KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'}

    if (-not $recoveryKeyStored) {
        # Recovery key is not stored in Azure AD, attempt to upload it
        Write-Host "Recovery key not found in Azure AD, attempting to upload..."

        # Retrieve the BitLocker recovery password
        $recoveryKey = (Get-BitLockerVolume -MountPoint C:).KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'} | Select-Object -ExpandProperty RecoveryPassword

        if ($recoveryKey) {
            # Command to trigger backup of the key to Azure AD (requires appropriate modules and permissions)
            try {
                BackupToAAD-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $recoveryKey.KeyProtectorId
                Write-Host "BitLocker recovery key successfully uploaded to Azure AD."
            } catch {
                Write-Host "Failed to upload the BitLocker recovery key to Azure AD. Error: $_"
            }
        } else {
            Write-Host "Unable to retrieve the BitLocker recovery key."
        }
    } else {
        Write-Host "BitLocker recovery key is already stored in Azure AD."
    }
} else {
    Write-Host "BitLocker is not enabled on the C: drive."
}
