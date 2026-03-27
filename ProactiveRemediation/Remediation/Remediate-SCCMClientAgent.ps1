# Remediation script for Intune Proactive Remediation

# Path to the SCCM client agent executable and uninstall program
$SCCMClientExecutable = "C:\Windows\CCM\CcmExec.exe"
$UninstallCommand = "C:\Windows\CCMSetup\CCMSetup.exe /uninstall"

# Check if the SCCM client agent executable is present
if (Test-Path -Path $SCCMClientExecutable) {
    Write-Output "SCCM client agent executable detected. Initiating uninstall process."
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $UninstallCommand -Wait -NoNewWindow
    Write-Output "SCCM client agent uninstall process completed."
} else {
    Write-Output "SCCM client agent executable not detected. No action needed."
}
