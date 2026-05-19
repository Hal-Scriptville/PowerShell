# Detect-MappedDrives.ps1
# Proactive Remediation - Detection
#
# Detects disconnected mapped network drives in the current user's session.
# Reports the count of unavailable drives and their UNC paths.
#
# IMPORTANT: Deploy with "Run script in 64-bit PowerShell: Yes"
#            and "Run this script using the logged-on credentials: YES"
#            (must run in user context to see mapped drives)
#
# Exit 0 = compliant (all mapped drives connected or no drives mapped)
# Exit 1 = non-compliant (one or more drives disconnected)

try {
    # Get all mapped network drives via WMI (works in user context)
    $MappedDrives = Get-WmiObject -Class Win32_MappedLogicalDisk -ErrorAction Stop

    if (-not $MappedDrives) {
        Write-Output "COMPLIANT: No mapped drives configured"
        exit 0
    }

    $Disconnected = @()
    foreach ($Drive in $MappedDrives) {
        # Test if the UNC path is reachable
        $Available = Test-Path -Path $Drive.ProviderName -ErrorAction SilentlyContinue
        if (-not $Available) {
            $Disconnected += "$($Drive.DeviceID) → $($Drive.ProviderName)"
        }
    }

    if ($Disconnected.Count -gt 0) {
        Write-Output "NON-COMPLIANT: $($Disconnected.Count) disconnected mapped drive(s)"
        $Disconnected | ForEach-Object { Write-Output "  DISCONNECTED: $_" }
        exit 1
    }

    Write-Output "COMPLIANT: $($MappedDrives.Count) mapped drive(s) — all connected"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
