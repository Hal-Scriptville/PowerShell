# SUPERSEDED 2026-08-12 -- BROKEN: Set-ItemProperty references $correctValue, which
# is never defined anywhere in this script (only $expectedValue is set). Would
# throw or write garbage. Use Remediate-WUfBHealth.ps1 instead.

# Define the registry path and value
$registryPath = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"
$valueName = "NoAutoUpdate"
$expectedValue = "0"


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
