# Connect to Microsoft Graph
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All", "Directory.ReadWrite.All"

# Get all Intune devices
$devices = Get-MgDeviceManagementManagedDevice -All

# Current date
$currentDate = Get-Date

foreach ($device in $devices) {
    $enrollDate = [DateTime]$device.EnrolledDateTime
    $daysSinceEnrolled = ($currentDate - $enrollDate).Days
    $deviceObjectId = $device.AzureAdDeviceId

    if ($daysSinceEnrolled -ge 5 -and $daysSinceEnrolled -le 15) {
        # Set the attribute for devices enrolled between 5 and 15 days ago
        Update-MgDevice -DeviceId $deviceObjectId -ExtensionAttributes @{ "extensionAttribute1" = "DelaySoftwarePush" }
        Write-Host "Tagged device: $($device.DeviceName) for software push."
    }
    elseif ($daysSinceEnrolled -gt 15) {
        # Remove the attribute after 15 days
        Update-MgDevice -DeviceId $deviceObjectId -ExtensionAttributes @{ "extensionAttribute1" = $null }
        Write-Host "Removed tag from device: $($device.DeviceName)."
    }
}
