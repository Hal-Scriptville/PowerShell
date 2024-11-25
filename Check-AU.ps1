# Detection script for Intune Proactive Remediation
$keyPath = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"

if (Test-Path -Path $keyPath) {
    Write-Output "Key exists"
    exit 1  # Indicates a remediation is required
} else {
    Write-Output "Key does not exist"
    exit 0  # No remediation required
}
