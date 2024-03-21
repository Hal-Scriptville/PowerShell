# Define the registry path and value
$registryPath = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate"
$valueName = "DisableDualScan"
$expectedValue = "1"


# Set the registry value
try {
    Set-ItemProperty -Path $registryPath -Name $valueName -Value $correctValue
    Write-Host "Registry value corrected."
} catch {
    Write-Error "Error occurred while setting registry value."
    exit 1
}

# Exit codes:
# 0 - Remediation successful
# 1 - Remediation failed
