# Detection script for Intune Proactive Remediation

# Path to the SCCM client agent executable
$SCCMClientExecutable = "C:\Windows\CCM\CcmExec.exe"

if (Test-Path -Path $SCCMClientExecutable) {
    Write-Output "SCCM client agent executable detected."
    exit 1
} else {
    Write-Output "SCCM client agent executable not detected."
    exit 0
}
