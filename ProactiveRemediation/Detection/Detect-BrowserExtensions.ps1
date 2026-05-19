# Detect-BrowserExtensions.ps1
# Proactive Remediation - Detection
#
# Inventories installed Chrome and Edge extensions for all user profiles
# on the device and flags any extensions on the block list.
#
# CUSTOMIZE: Add known-bad extension IDs to $BlockedExtensionIds.
#            Common sources: Google Safe Browsing, vendor threat intel feeds.
#
# Exit 0 = compliant (no blocked extensions found)
# Exit 1 = non-compliant (blocked extension detected)

# Add extension IDs to block. Format: 32-character lowercase string.
# Example blocked IDs shown below — replace/extend with your own list.
$BlockedExtensionIds = @(
    # Known malicious/adware extensions (examples — verify before deploying)
    # "ficfmibkjjnpogdcfnpnjqqcbkklnckc",   # Example: fake ad blocker
    # "ogpacbmhjgakodacnajkjflgbkjpbfhe"    # Example: credential stealer
)

$ProfilePaths = @(
    "$env:SystemDrive\Users\*\AppData\Local\Google\Chrome\User Data\*\Extensions",
    "$env:SystemDrive\Users\*\AppData\Local\Microsoft\Edge\User Data\*\Extensions"
)

function Get-ExtensionName($ExtPath) {
    # Try to read manifest.json for human-readable name
    try {
        $Manifest = Get-ChildItem -Path $ExtPath -Filter "manifest.json" -Recurse -ErrorAction SilentlyContinue |
                    Select-Object -First 1
        if ($Manifest) {
            $Json = Get-Content $Manifest.FullName -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
            return $Json.name
        }
    }
    catch { }
    return "(unknown)"
}

try {
    $Found   = @()
    $Blocked = @()

    foreach ($Pattern in $ProfilePaths) {
        $Browser = if ($Pattern -match 'Chrome') { 'Chrome' } else { 'Edge' }
        $ExtDirs = Get-ChildItem -Path $Pattern -Directory -ErrorAction SilentlyContinue

        foreach ($ExtDir in $ExtDirs) {
            $ExtId   = $ExtDir.Name
            $ExtName = Get-ExtensionName $ExtDir.FullName
            $Found  += [PSCustomObject]@{ Browser = $Browser; Id = $ExtId; Name = $ExtName }

            if ($ExtId -in $BlockedExtensionIds) {
                $Blocked += "$Browser extension BLOCKED: $ExtName ($ExtId)"
            }
        }
    }

    Write-Output "Inventoried $($Found.Count) extension(s) across Chrome and Edge"

    if ($Blocked.Count -gt 0) {
        Write-Output "NON-COMPLIANT: $($Blocked.Count) blocked extension(s) found"
        $Blocked | ForEach-Object { Write-Output "  $_" }
        exit 1
    }

    # Log inventory summary for visibility even when compliant
    $Found | Group-Object Browser | ForEach-Object {
        Write-Output "  $($_.Name): $($_.Count) extension(s)"
    }

    Write-Output "COMPLIANT: No blocked extensions detected"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
