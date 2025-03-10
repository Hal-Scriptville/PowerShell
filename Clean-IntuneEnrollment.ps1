# Script to clean up Intune enrollment artifacts
# Run with elevated permissions

# Stop Intune Management Extension service
Stop-Service -Name IntuneManagementExtension -Force

# Remove Intune Management Extension directory
Remove-Item -Path "C:\Program Files (x86)\Microsoft Intune Management Extension" -Recurse -Force -ErrorAction SilentlyContinue

# Clean up registry keys
$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Enrollments\*",
    "HKLM:\SOFTWARE\Microsoft\Enrollments\Status\*",
    "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked\*",
    "HKLM:\SOFTWARE\Microsoft\PolicyManager\AdmxInstalled\*",
    "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\*",
    "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\*",
    "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Logger\*",
    "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Sessions\*"
)

foreach ($path in $registryPaths) {
    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
}

# Restart device enrollment service
Restart-Service -Name DeviceEnrollmentService

# Re-run device enrollment
Start-Process -FilePath "C:\Windows\System32\deviceenroller.exe" -ArgumentList "/c /AutoEnrollMDM" -Wait
