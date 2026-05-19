# Detect-TimeSync.ps1
# Proactive Remediation - Detection
#
# Verifies the Windows Time service is running and time offset is within
# the acceptable threshold. Time drift beyond 5 minutes breaks Kerberos
# authentication in Active Directory environments.
#
# Thresholds:
#   - W32Time service must be running
#   - Clock offset must be within +/- 120 seconds (2 minutes)
#     (Kerberos tolerance is 5 min; 2 min gives buffer before auth breaks)
#
# Exit 0 = compliant
# Exit 1 = non-compliant

$MaxOffsetSeconds = 120

try {
    # Check W32Time service state
    $Service = Get-Service -Name w32time -ErrorAction Stop
    if ($Service.Status -ne 'Running') {
        Write-Output "NON-COMPLIANT: Windows Time service is $($Service.Status)"
        exit 1
    }

    # Query current time offset via w32tm
    $W32tmOutput = w32tm /query /status 2>&1
    $OffsetLine  = $W32tmOutput | Where-Object { $_ -match '^Last Successful Sync Time|^(Time since last|Offset)' }

    # Parse offset value (format: "+0.0000000s" or "-12.3456789s")
    $OffsetRaw = ($W32tmOutput | Where-Object { $_ -match 'Offset|offset' } | Select-Object -First 1) -replace '.*:\s*', '' -replace 's.*', ''
    $OffsetSeconds = [math]::Abs([double]($OffsetRaw -replace '[^0-9.\-]', ''))

    if ($OffsetSeconds -gt $MaxOffsetSeconds) {
        Write-Output "NON-COMPLIANT: Clock offset is $([math]::Round($OffsetSeconds,1))s (threshold: $MaxOffsetSeconds s)"
        exit 1
    }

    # Check last sync time
    $SyncLine = $W32tmOutput | Where-Object { $_ -match 'Last Successful Sync Time' } | Select-Object -First 1
    Write-Output "COMPLIANT: W32Time running, offset $([math]::Round($OffsetSeconds,1))s — $SyncLine"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
