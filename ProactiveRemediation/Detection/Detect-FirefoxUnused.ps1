# Detect-FirefoxUnused.ps1
# Proactive Remediation — Detection Script
# Purpose: Detect if Firefox is installed but unused for more than $DaysThreshold days
# Exit 0 = Compliant (Firefox not installed, or used recently)
# Exit 1 = Non-compliant (Firefox installed but unused — trigger remediation)

$DaysThreshold = 30

# Firefox not installed — nothing to remediate
$firefoxExe = @(
    "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
    "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $firefoxExe) {
    Write-Output "Firefox not installed. Compliant."
    exit 0
}

$cutoff = (Get-Date).AddDays(-$DaysThreshold)
$mostRecentUse = $null

# Check places.sqlite (last modified = last browsing session) across all user profiles
$userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue

foreach ($profile in $userProfiles) {
    $ffProfiles = Get-ChildItem "$($profile.FullName)\AppData\Roaming\Mozilla\Firefox\Profiles" `
        -Directory -ErrorAction SilentlyContinue
    foreach ($ffProfile in $ffProfiles) {
        $places = Join-Path $ffProfile.FullName "places.sqlite"
        if (Test-Path $places) {
            $lastWrite = (Get-Item $places).LastWriteTime
            if (-not $mostRecentUse -or $lastWrite -gt $mostRecentUse) {
                $mostRecentUse = $lastWrite
            }
        }
    }
}

if (-not $mostRecentUse) {
    # Firefox installed but never launched by any user
    Write-Output "Firefox installed, no usage profile found. Non-compliant."
    exit 1
}

if ($mostRecentUse -lt $cutoff) {
    Write-Output "Firefox last used $mostRecentUse — exceeds $DaysThreshold day threshold. Non-compliant."
    exit 1
}

Write-Output "Firefox last used $mostRecentUse — within threshold. Compliant."
exit 0
