# Detect-EventLogErrors.ps1
# Proactive Remediation - Detection
#
# Checks the System event log for an abnormal volume of Critical or Error
# events in the last 24 hours. A spike in errors often indicates hardware
# failure, driver issues, or service instability.
#
# Thresholds (adjust per environment):
#   - Critical events:  any count > 0 triggers non-compliant
#   - Error events:     count > 20 triggers non-compliant
#
# Exit 0 = compliant
# Exit 1 = non-compliant

$CriticalThreshold = 0   # Any Critical event = non-compliant
$ErrorThreshold    = 20  # More than this many Errors in 24h = non-compliant
$LookbackHours     = 24

try {
    $Since    = (Get-Date).AddHours(-$LookbackHours)
    $Filter   = @{ LogName = 'System'; Level = @(1, 2); StartTime = $Since }  # 1=Critical, 2=Error
    $Events   = Get-WinEvent -FilterHashtable $Filter -ErrorAction SilentlyContinue

    $Critical = @($Events | Where-Object { $_.Level -eq 1 })
    $Errors   = @($Events | Where-Object { $_.Level -eq 2 })

    $Issues = @()

    if ($Critical.Count -gt $CriticalThreshold) {
        $Issues += "$($Critical.Count) Critical event(s) in the last $LookbackHours hours"
        $Critical | Select-Object -First 3 | ForEach-Object {
            $Issues += "  CRITICAL [$($_.TimeCreated.ToString('HH:mm'))] $($_.ProviderName): $($_.Message.Split("`n")[0])"
        }
    }

    if ($Errors.Count -gt $ErrorThreshold) {
        $Issues += "$($Errors.Count) Error event(s) in the last $LookbackHours hours (threshold: $ErrorThreshold)"
    }

    if ($Issues.Count -gt 0) {
        Write-Output "NON-COMPLIANT: Abnormal System event log activity"
        $Issues | ForEach-Object { Write-Output "  $_" }
        exit 1
    }

    Write-Output "COMPLIANT: $($Critical.Count) Critical, $($Errors.Count) Error events in last $LookbackHours hours"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
