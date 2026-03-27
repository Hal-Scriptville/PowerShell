# Remediation Script

# Get the serial number of the device
$serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber

# Construct the new computer name
$newComputerName = "AP-$serialNumber"

# Rename the computer
Rename-Computer -NewName $newComputerName -Force -Restart
