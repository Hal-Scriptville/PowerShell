# Connect to Microsoft Graph

Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All", "Directory.ReadWrite.All"

# Get all Intune devices
$devices = Get-MgDeviceManagementManagedDevice -All

#Current date
$currentDate = Get-Date

foreach ($device in $devices) {
$enrollDate = [DateTime]$device.EnrolledDateTime
$daysSinceEnrolled = ($currentDate - $enrollDate).Days
if ($daysSinceEnrolled -ge 5) {
    # Update Azure AD device object with custom attribute
    $deviceObjectId = $device.AzureAdDeviceId
    Update-MgDevice -DeviceId $deviceObjectId -ExtensionAttributes @{ "extensionAttribute15" = "DelaySoftwarePush" }
    Write-Host "Tagged device: $($device.DeviceName) for software push."
}
}
