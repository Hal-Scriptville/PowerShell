# Remediate-VNCServerOldVersion.ps1
# Proactive Remediation - Remediation Script
# Purpose: Force-remove the OLD RealVNC Server when more than one server version is
#          installed. Keeps the HIGHEST version (the winget-deployed 7.17.0) and
#          removes every lower-versioned server install.
#
# Scope:   SERVER ONLY. The viewer (RealVNC Connect / VNC Viewer) is never touched.
#          "Keep highest version" guarantees the new server is never the one removed.
#
# Exit 0 = Remediation succeeded (one server remains)
# Exit 1 = Remediation failed (an old server is still present)

$ErrorActionPreference = 'SilentlyContinue'

function Get-VncServers {
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $found = foreach ($key in $uninstallKeys) {
        Get-ChildItem $key -ErrorAction SilentlyContinue |
            Get-ItemProperty -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -like '*VNC Server*' -and
                $_.DisplayName -notlike '*Viewer*' -and
                $_.DisplayName -notlike '*Connect*'
            }
    }
    @($found | Sort-Object PSChildName -Unique)
}

function ConvertTo-VersionSafe([string]$v) {
    # RealVNC DisplayVersion is normally clean (e.g. 7.17.0), but guard against junk.
    $parsed = $null
    $clean  = ($v -replace '[^0-9.]', '').Trim('.')
    if ($clean -and [version]::TryParse($clean, [ref]$parsed)) { return $parsed }
    return [version]'0.0'
}

$servers = Get-VncServers
if ($servers.Count -le 1) {
    Write-Output "One or zero RealVNC Server installs present - nothing to remediate."
    exit 0
}

# Keep the highest version; everything else is the old version to remove.
$keep = $servers | Sort-Object { ConvertTo-VersionSafe $_.DisplayVersion } -Descending | Select-Object -First 1
$old  = @($servers | Where-Object { $_.PSChildName -ne $keep.PSChildName })

Write-Output "Keeping $($keep.DisplayName) $($keep.DisplayVersion). Removing $($old.Count) older install(s)."

# Stop the running server and tray/agent so the uninstaller is not blocked (the "force" part).
Get-Service -Name 'vncserver' -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
Get-Process -Name 'vncserver','vncserverui','vncagent' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

foreach ($app in $old) {
    $removed = $false

    # RealVNC ships as MSI - the uninstall subkey name is the ProductCode GUID. Prefer a
    # direct, fully silent msiexec removal with -Wait so we can verify the result below.
    if ($app.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') {
        Start-Process msiexec.exe -ArgumentList "/x $($app.PSChildName) /qn /norestart" -Wait -NoNewWindow
        $removed = $true
    }
    elseif ($app.QuietUninstallString) {
        Start-Process cmd.exe -ArgumentList "/c `"$($app.QuietUninstallString)`"" -Wait -NoNewWindow
        $removed = $true
    }
    elseif ($app.UninstallString) {
        $u    = $app.UninstallString
        $guid = ([regex]::Match($u, '\{[0-9A-Fa-f-]+\}')).Value
        if ($u -match 'msiexec' -and $guid) {
            Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -Wait -NoNewWindow
            $removed = $true
        }
        else {
            Start-Process cmd.exe -ArgumentList "/c `"$u`" /S" -Wait -NoNewWindow
            $removed = $true
        }
    }

    if (-not $removed) {
        Write-Output "No usable uninstall method for $($app.DisplayName) $($app.DisplayVersion)."
    }
}

Start-Sleep -Seconds 5

# Confirm only the kept (newest) server remains.
$after = Get-VncServers
if ($after.Count -le 1) {
    $remaining = ($after | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" }) -join '; '
    Write-Output "Cleanup succeeded. Remaining: $remaining."
    exit 0
}

$remaining = ($after | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" }) -join '; '
Write-Output "Old RealVNC Server still present after remediation: $remaining. Failed."
exit 1
