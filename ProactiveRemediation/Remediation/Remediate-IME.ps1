# Remediation Script for Intune Management Engine

$serviceName = "IntuneManagementExtension" # Service name for Intune Management Engine
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($service) {
    if ($service.Status -ne 'Running') {
        Start-Service -Name $serviceName
        Write-Output "Service started"
    } else {
        Write-Output "Service already running"
    }
} else {
    Write-Output "Service not found"
}
