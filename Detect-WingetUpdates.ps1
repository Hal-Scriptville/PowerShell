# Paths to check for the winget executable
$possibleWingetPaths = @(
    "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe",
    "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe",
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
)

# Function to check if winget is installed
function Get-WingetPath {
    foreach ($path in $possibleWingetPaths) {
        $resolvedPaths = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
        if ($resolvedPaths) {
            return $resolvedPaths.FullName
        }
    }
    return $null
}

$wingetPath = Get-WingetPath

if ($null -eq $wingetPath) {
    Write-Error "Winget is not installed or the path is incorrect."
    exit 1
}

# Check if there are updates available
$updates = & $wingetPath list --upgrade
if ($updates) {
    Write-Output "Updates available"
    exit 1
} else {
    Write-Output "No updates available"
    exit 0
}
