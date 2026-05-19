# Remediate-DefenderHealth.ps1
# Proactive Remediation - Remediation
#
# Restores Microsoft Defender to a healthy state:
#   - Re-enables real-time protection if disabled
#   - Updates signature definitions
#   - Initiates a quick scan
#
# Note: If Antivirus is fully disabled via policy (e.g., third-party AV),
# this script will not override that policy.
#
# Exit 0 = success
# Exit 1 = failure

try {
    $Status = Get-MpComputerStatus -ErrorAction Stop

    if (-not $Status.RealTimeProtectionEnabled) {
        Write-Output "Re-enabling real-time protection..."
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Write-Output "Real-time protection enabled"
    }

    Write-Output "Updating signature definitions..."
    Update-MpSignature -ErrorAction Stop
    Write-Output "Signatures updated"

    Write-Output "Starting quick scan..."
    Start-MpScan -ScanType QuickScan -ErrorAction Stop
    Write-Output "Quick scan initiated"

    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
