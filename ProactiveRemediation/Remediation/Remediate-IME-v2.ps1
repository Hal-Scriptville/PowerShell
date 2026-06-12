<#
.SYNOPSIS
    Proactive Remediation — ensure the Intune Management Extension (IME) service is healthy.
.DESCRIPTION
    Hardened v2 of Remediate-IME.ps1. Improvements over v1:
      - Sets exit codes (0 = success, 1 = failure) so Intune reports remediation status correctly.
      - try/catch around all service calls (clean failure reporting instead of an unhandled throw).
      - Forces StartupType = Automatic first (recovers a service left Disabled).
      - Restart-Service (stop->start) instead of Start-Service, so it also recovers a HUNG/wedged
        IME that is "Running" but no longer processing policy — the most common real-world failure.
    Deploy as SYSTEM (not logged-on user); 64-bit PowerShell; no signature enforcement.
.NOTES
    Pairs with Detection/Detect-IME.ps1.
#>

$svc = 'IntuneManagementExtension'
try {
    $s = Get-Service -Name $svc -ErrorAction Stop
    if ((Get-Service $svc).StartType -eq 'Disabled') { Set-Service $svc -StartupType Automatic }
    Restart-Service -Name $svc -Force -ErrorAction Stop   # stop->start: fixes stopped AND wedged
    Write-Output "IME service restarted and set to Automatic."
    exit 0
} catch {
    Write-Output "IME remediation failed: $($_.Exception.Message)"
    exit 1
}
