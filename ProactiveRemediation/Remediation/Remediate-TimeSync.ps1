# Remediate-TimeSync.ps1
# Proactive Remediation - Remediation
#
# Starts the Windows Time service if stopped and forces
# a time resynchronization with the configured NTP source.
#
# Exit 0 = success
# Exit 1 = failure

try {
    $Service = Get-Service -Name w32time -ErrorAction Stop

    if ($Service.Status -ne 'Running') {
        Write-Output "Starting Windows Time service..."
        Start-Service -Name w32time -ErrorAction Stop
        Write-Output "Windows Time service started"
    }

    # Ensure w32time is configured for automatic startup
    Set-Service -Name w32time -StartupType Automatic -ErrorAction SilentlyContinue

    # Register with time service infrastructure (safe to re-run)
    $RegResult = w32tm /register 2>&1
    Write-Output "Registration: $RegResult"

    # Force immediate resync
    Write-Output "Forcing time resynchronization..."
    $ResyncResult = w32tm /resync /force 2>&1
    Write-Output "Resync result: $ResyncResult"

    # Confirm new offset
    $StatusOutput = w32tm /query /status 2>&1
    $OffsetLine   = $StatusOutput | Where-Object { $_ -match 'Offset' } | Select-Object -First 1
    Write-Output "Post-remediation: $OffsetLine"

    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
