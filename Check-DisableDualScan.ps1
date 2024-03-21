# Define the registry path and value
$registryPath = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate"
$valueName = "DisableDualScan"
$expectedValue = "0"


# Check if the registry path exists
if (Test-Path $registryPath) {
    # Get the current value
    $currentValue = Get-ItemPropertyValue -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue

    # Check if the value is as expected
    if ($currentValue -eq $expectedValue) {
        # Return non-compliant status if value is not as expected
        Write-Host "NonCompliant"
		exit 1
    } else {
        # Return compliant status if value is as expected
        Write-Host "Compliant"
		exit 0
    }
} else {
    # Return non-compliant status if registry path doesn't exist
    Write-Host "Compliant"
	exit 0
}
