Install-Module -Name Microsoft.Graph.DeviceManagement.Actions -Force  -AllowClobber

Install-Module -Name Microsoft.Graph.DeviceManagement -Force -AllowClobber

# Importing the SDK Module

Import-Module -Name Microsoft.Graph.DeviceManagement.Actions

Connect-MgGraph -scope DeviceManagementManagedDevices.PrivilegedOperations.All, DeviceManagementManagedDevices.ReadWrite.All,DeviceManagementManagedDevices.Read.All

#### Gets All devices

$Devices = Get-MgDeviceManagementManagedDevice -All

Foreach ($Device in $Devices)

{

Sync-MgDeviceManagementManagedDevice -ManagedDeviceId $Device.Id

Write-Host "Sending Sync request to Device with Device name $($Device.DeviceName)" -ForegroundColor Yellow

}

Disconnect-Graph
 
# Device = Get-MgDeviceManagementManagedDevice -Filter "contains(deviceName,'VIA9999')"

# Sync-MgDeviceManagementManagedDevice -ManagedDeviceId $device.Id
 