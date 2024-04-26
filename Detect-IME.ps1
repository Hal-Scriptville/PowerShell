# Detection Script for Intune Management Engine with Exit Codes

$serviceName = "IntuneManagementExtension" # Service name for Intune Management Engine
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($service) {
    if ($service.Status -eq 'Running') {
        Write-Host "Service is running."
        exit 0 # Exit code 0 for success, no remediation needed
    } else {
        Write-Host "Service is not running."
        exit 1 # Exit code 1 for failure, trigger remediation
    }
} else {
    Write-Host "Service not found."
    exit 1 # Exit code 1 for failure, trigger remediation
}
