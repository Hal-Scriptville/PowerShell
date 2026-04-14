# detect.ps1 - Google Chrome detection for Intune Win32 app.
# Intune rule: exit 0 + STDOUT = installed; exit 0 + no output = not installed.
#
# Detection strategy: version check against chrome.exe. Change $minVersion to
# whatever minimum you want the Win32 app to treat as "installed".

$minVersion = [Version]'120.0.0.0'
$chromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
)

foreach ($path in $chromePaths) {
    if (Test-Path $path) {
        $version = [Version](Get-Item $path).VersionInfo.FileVersion
        if ($version -ge $minVersion) {
            Write-Output "Chrome $version detected at $path"
            exit 0
        }
    }
}

exit 0
