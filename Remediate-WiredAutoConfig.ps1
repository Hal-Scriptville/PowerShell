# Remediation Script: Set Wired AutoConfig service to Automatic and ensure it is running.

# Get the service status
$service = Get-Service -Name dot3svc -ErrorAction SilentlyContinue

# Check if the service exists
if ($null -eq $service) {
    Write-Output "Service not found. Exiting remediation."
    Exit 1
}

# Set service to Automatic
Set-Service -Name dot3svc -StartupType Automatic

# Start the service if it is not running
if ($service.Status -ne 'Running') {
    Start-Service -Name dot3svc
}

Write-Output "Remediation completed: Service set to Automatic and started"
Exit 0
