# Detect-DefenderHealth.ps1
# Proactive Remediation - Detection
#
# Verifies Microsoft Defender Antivirus health:
#   - Antivirus enabled and real-time protection active
#   - Signature definitions updated within the last 7 days
#   - A quick scan completed within the last 7 days
#
# Exit 0 = compliant
# Exit 1 = non-compliant, remediation will trigger

$SignatureAgeLimitDays = 7
$ScanAgeLimitDays      = 7

try {
    $Status = Get-MpComputerStatus -ErrorAction Stop

    $Issues = @()

    if (-not $Status.AntivirusEnabled) {
        $Issues += "Antivirus is disabled"
    }

    if (-not $Status.RealTimeProtectionEnabled) {
        $Issues += "Real-time protection is disabled"
    }

    if ($Status.AntivirusSignatureAge -gt $SignatureAgeLimitDays) {
        $Issues += "Signature definitions are $($Status.AntivirusSignatureAge) days old (limit: $SignatureAgeLimitDays)"
    }

    if ($Status.QuickScanAge -gt $ScanAgeLimitDays) {
        $Issues += "Last quick scan was $($Status.QuickScanAge) days ago (limit: $ScanAgeLimitDays)"
    }

    if ($Issues.Count -gt 0) {
        Write-Output "NON-COMPLIANT: $($Issues.Count) Defender issue(s) found"
        $Issues | ForEach-Object { Write-Output "  - $_" }
        exit 1
    }

    Write-Output "COMPLIANT: Defender enabled, RTP on, signatures $($Status.AntivirusSignatureAge)d old, last scan $($Status.QuickScanAge)d ago"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
