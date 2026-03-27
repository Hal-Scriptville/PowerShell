# Detection Script

# Get the serial number of the device
$serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber

# Get the current computer name
$computerName = $env:COMPUTERNAME

# Construct the expected computer name
$expectedName = "AP-$serialNumber"

# Check if the current computer name matches the expected name
if ($computerName -eq $expectedName) {
    Write-Output "Device name is correct: $computerName"
    exit 0
} else {
    Write-Output "Device name is incorrect: $computerName. Expected: $expectedName"
    exit 1
}
