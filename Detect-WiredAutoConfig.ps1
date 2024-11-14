# Detection Script: Check if the Wired AutoConfig service is running and set to Automatic.

# Get the service status
$service = Get-Service -Name dot3svc -ErrorAction SilentlyContinue

# Check if the service exists and its configuration
if ($null -eq $service) {
    Write-Output "Service not found"
    Exit 1
}

if ($service.StartType -ne 'Automatic' -or $service.Status -ne 'Running') {
    Write-Output "Service is not configured correctly or not running"
    Exit 1
}

Write-Output "Service is configured correctly and running"
Exit 0
