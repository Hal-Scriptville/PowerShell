# Connect to Microsoft Graph with the required scopes
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "BitLockerKey.Read.All"
Import-Module Microsoft.Graph.Beta.Identity.DirectoryManagement

# Get all managed devices
write-host "Getting device information"
$devices = Get-MgBetaDevice

# Get BitLocker Recovery Keys
write-host "Getting bitlocker key" 
$bitlockerKeys = Get-MgInformationProtectionBitlockerRecoveryKey -All | select Id,CreatedDateTime,DeviceId,@{n="Key";e={(Get-MgInformationProtectionBitlockerRecoveryKey -BitlockerRecoveryKeyId $_.Id -Property key).key}},VolumeType

# Combine the device details with their corresponding BitLocker recovery keys
$results = foreach ($key in $bitlockerKeys) {
	write-host "Checking on key $key" -foreground cyan
    $device = $devices | Where-Object { $_.DeviceId -eq $key.DeviceId }
    [PSCustomObject]@{
		DeviceName = $device.DisplayName  # Adjust based on actual property found
        DeviceId = $key.DeviceId
        RecoveryKey = $key.Key
        VolumeType = $key.VolumeType
        CreatedDateTime = $key.CreatedDateTime
    }
	write-host "Checking on $device.DisplayName"
}

# Display the results in a grid view
$results | Out-GridView
