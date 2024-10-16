# Get the list of applications with upgrades available
$upgradeList = winget list --upgrade-available

# Check if any upgrades are available
if ($upgradeList) {
    # If any applications have updates available, list them
    Write-Host "Applications with updates available:"
    Write-Host $upgradeList
    exit 1  # Exit with 1 indicating updates are available (non-compliance)
} else {
    # No upgrades available, all apps are up-to-date
    Write-Host "All applications are up-to-date"
    exit 0  # Exit with 0 indicating compliance
}
