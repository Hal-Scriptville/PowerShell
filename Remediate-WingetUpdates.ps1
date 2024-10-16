# Attempt to update all applications with updates available
$upgradeResult = winget upgrade --all --silent

# Log the result of the upgrade attempt
if ($upgradeResult) {
    Write-Host "Applications updated successfully or updates in progress."
} else {
    Write-Host "No applications needed updates."
}
