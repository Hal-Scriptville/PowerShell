# List of application IDs to check for updates
$apps = @(
    "Google.Chrome",
    "Mozilla.Firefox",
    "VideoLAN.VLC",
    "Adobe.Acrobat.Reader.64-bit"
)

# Initialize an array to store outdated apps
$outdatedApps = @()

# Get the list of applications with upgrades available
$upgradeList = winget list --upgrade-available

# Loop through each app and check if it's listed for upgrade
foreach ($app in $apps) {
    if ($upgradeList -match $app) {
        Write-Host "$app needs an update"
        $outdatedApps += $app
    } else {
        Write-Host "$app is up-to-date"
    }
}

# Output result for Intune detection
if ($outdatedApps.Count -gt 0) {
    Write-Host "Outdated applications detected: $($outdatedApps -join ', ')"
    exit 1  # Exit with 1 if outdated apps are found (indicating non-compliance)
} else {
    Write-Host "All applications are up-to-date"
    exit 0  # Exit with 0 if all apps are up-to-date (indicating compliance)
}
