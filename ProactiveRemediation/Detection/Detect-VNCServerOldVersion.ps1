# Detect-VNCServerOldVersion.ps1
# Proactive Remediation - Detection Script
# Purpose: Detect when more than one RealVNC *Server* version is installed at once
#          (the old version left behind after winget deployed the new 7.x server).
#          New server = "RealVNC Server" 7.17.0; old = legacy "VNC Server" 6.x.
#
# Scope:   SERVER ONLY. The viewer product (RealVNC Connect / VNC Viewer) is a
#          separate install and is explicitly excluded - never flagged, never removed.
#          Detection only fires when TWO OR MORE server installs coexist, which is
#          exactly the "both versions installed" condition. A single server install
#          (old-only on a machine winget hasn't reached yet, or new-only) is compliant.
#
# Exit 0 = Compliant (0 or 1 RealVNC Server install present)
# Exit 1 = Non-compliant (2+ server installs - old version needs removal)

$ErrorActionPreference = 'SilentlyContinue'

$uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

$servers = foreach ($key in $uninstallKeys) {
    Get-ChildItem $key -ErrorAction SilentlyContinue |
        Get-ItemProperty -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -like '*VNC Server*' -and   # matches BOTH "VNC Server" (old) and "RealVNC Server" (new)
            $_.DisplayName -notlike '*Viewer*'  -and   # never the viewer
            $_.DisplayName -notlike '*Connect*'        # "RealVNC Connect" = the viewer product, leave it alone
        }
}

# De-dupe on the product code (uninstall subkey name) so the same install isn't counted twice.
$servers = @($servers | Sort-Object PSChildName -Unique)

if ($servers.Count -le 1) {
    Write-Output "RealVNC Server install count: $($servers.Count). Compliant."
    exit 0
}

$versions = ($servers | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" }) -join '; '
Write-Output "Multiple RealVNC Server installs detected ($($servers.Count)): $versions. Old version present. Non-compliant."
exit 1
