# Get the fixed drives
$FixedDrives = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3"

# Check if there are any fixed drives
if ($FixedDrives) {
    Write-Host "The device has a fixed drive."
    exit 1  # Non-zero exit code indicates fixed drives found
} else {
    Write-Host "No fixed drive found."
    exit 0  # Zero exit code indicates no fixed drives
}
