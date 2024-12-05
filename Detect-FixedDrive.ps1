# Get the fixed drives
$FixedDrives = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3"

# Get the OS drive letter
$OSDrive = (Get-WmiObject Win32_OperatingSystem).SystemDrive

# Filter out the OS drive
$NonOSFixedDrives = $FixedDrives | Where-Object { $_.DeviceID -ne $OSDrive }

# Check if there are any non-OS fixed drives
if ($NonOSFixedDrives) {
    Write-Host "The device has non-OS fixed drives."
    exit 1  # Non-zero exit code indicates non-OS fixed drives found
} else {
    Write-Host "No non-OS fixed drives found."
    exit 0  # Zero exit code indicates no non-OS fixed drives
}
