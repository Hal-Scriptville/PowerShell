# Remediation script for Intune Proactive Remediation
$keyPath = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"
$serviceName = "wuauserv"

# Check if the registry key exists
if (Test-Path -Path $keyPath) {
    try {
        # Delete the registry key
        Remove-Item -Path $keyPath -Recurse -Force
        Write-Output "Registry key deleted successfully."

        # Restart the Windows Update service
        if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
            Restart-Service -Name $serviceName -Force
            Write-Output "Windows Update service restarted successfully."
        } else {
            Write-Output "Windows Update service not found, no action taken."
        }

        exit 0  # Successful remediation
    } catch {
        Write-Error "Failed to delete the registry key or restart the service: $_"
        exit 1  # Remediation failed
    }
} else {
    Write-Output "Registry key does not exist, no action required."

    # Ensure the service is running even if the key was not found
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Restart-Service -Name $serviceName -Force
        Write-Output "Windows Update service restarted successfully."
    } else {
        Write-Output "Windows Update service not found, no action taken."
    }

    exit 0  # Nothing to remediate
}
