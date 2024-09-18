$BLV = Get-BitLockerVolume -MountPoint "C:"
if ($BLV.VolumeStatus -eq "FullyDecrypted") {
    Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector
    Enable-BitLocker -MountPoint "C:" -TpmProtector
}
