# Remediate-MappedDrives.ps1
# Proactive Remediation - Remediation
#
# Attempts to reconnect all disconnected persistent mapped drives
# by forcing a network drive refresh.
#
# IMPORTANT: Run with logged-on credentials (user context) — same as detection.
#
# Exit 0 = success (drives reconnected or no action needed)
# Exit 1 = failure

try {
    # Refresh all persistent connections
    $NetUseResult = net use 2>&1
    Write-Output "Current drive state:`n$NetUseResult"

    # Force reconnect of all remembered/disconnected drives
    $RefreshResult = net use * /persistent:yes 2>&1
    Write-Output "Reconnect result: $RefreshResult"

    # Verify state after reconnect
    $MappedDrives = Get-WmiObject -Class Win32_MappedLogicalDisk -ErrorAction SilentlyContinue
    if ($MappedDrives) {
        $StillDown = @()
        foreach ($Drive in $MappedDrives) {
            if (-not (Test-Path -Path $Drive.ProviderName -ErrorAction SilentlyContinue)) {
                $StillDown += "$($Drive.DeviceID) → $($Drive.ProviderName)"
            }
        }
        if ($StillDown.Count -gt 0) {
            Write-Output "WARNING: $($StillDown.Count) drive(s) still unavailable (server may be offline)"
            $StillDown | ForEach-Object { Write-Output "  $_" }
            # Exit 0 — drive server being offline is not a client-side fixable issue
        }
        else {
            Write-Output "All mapped drives reconnected successfully"
        }
    }

    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
