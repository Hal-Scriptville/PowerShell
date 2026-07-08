<#
.SYNOPSIS
    Removes existing VNC products, installs RealVNC Server, and optionally joins RealVNC Cloud.

.DESCRIPTION
    Stops and uninstalls RealVNC / TightVNC / UltraVNC (per Uninstall registry keys),
    installs RealVNC Server from a provided MSI, and — if a join token is supplied and the
    device is not already cloud-joined — joins RealVNC Cloud. Designed to run as SYSTEM via
    Intune / ConfigMgr. Writes a transcript and returns a proper exit code.

.PARAMETER MsiPath
    Path to the RealVNC Server MSI. Defaults to an MSI alongside this script.

.PARAMETER JoinToken
    RealVNC Cloud join token (a secret). Supply at runtime; do not commit it.

.PARAMETER JoinGroup
    RealVNC Cloud group name to join the device into.

.PARAMETER LogDir
    Directory for the transcript log. Defaults to %ProgramData%\VNC-Deploy.

.NOTES
    Run elevated / as SYSTEM. TightVNC process name is tvnserver.exe (not tvncserver.exe).
#>
[CmdletBinding()]
param(
    [string]$MsiPath   = (Join-Path $PSScriptRoot 'VNC-Server-Windows-64bit.msi'),
    [string]$JoinToken = '',
    [string]$JoinGroup = '',
    [string]$LogDir    = (Join-Path $env:ProgramData 'VNC-Deploy')
)

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'Reinstall-VNCServer.log') -Append -Force | Out-Null
$ErrorActionPreference = 'Continue'

# --- Notify (msg.exe is unreliable as SYSTEM) ---
try { msg * /time:30 "VNC Server is being updated. Please close any VNC Server applications." } catch {}
Start-Sleep -Seconds 30

# --- Stop running VNC processes (RealVNC / TightVNC / UltraVNC) ---
foreach ($proc in 'vncserver','tvnserver','winvnc') {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# --- Uninstall existing VNC apps (HKLM:\ is the built-in registry drive) ---
$AppNames = @('RealVNC Server','TightVNC','UltraVNC')
$UninstallKeys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($AppName in $AppNames) {
    Get-ItemProperty -Path $UninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*$AppName*" } |
        ForEach-Object {
            $u = $_.UninstallString
            if (-not $u) { return }
            Write-Output "Uninstalling: $($_.DisplayName)"
            if ($u -match 'msiexec' -and $_.PSChildName -match '^\{[0-9A-Fa-f\-]+\}$') {
                Start-Process msiexec.exe -ArgumentList "/x $($_.PSChildName) /qn /norestart" -Wait -NoNewWindow
            }
            else {
                if ($u -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $matches[1]; $exArgs = $matches[2] }
                else { $exe = ($u -split '\s+')[0]; $exArgs = ($u.Substring($exe.Length)).Trim() }
                Start-Process -FilePath $exe -ArgumentList (("$exArgs /S").Trim()) -Wait -NoNewWindow -ErrorAction SilentlyContinue
            }
        }
}

# --- Install RealVNC Server ---
Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /qn /norestart" -Wait -NoNewWindow

# --- Cloud-join if a token/group are supplied and not already joined ---
$vnc = 'C:\Program Files\RealVNC\VNC Server\vncserver.exe'
if ($JoinToken -and $JoinGroup) {
    $cloudJoined = $false
    try { $cloudJoined = [bool](& $vnc -service -cloudstatus | ConvertFrom-Json).CloudJoined } catch {}
    if (-not $cloudJoined) {
        & $vnc -service -joinCloud $JoinToken -joinGroup $JoinGroup
    }
}

try { msg * /time:30 "VNC Server update is complete. OK to open VNC Server applications." } catch {}

Stop-Transcript | Out-Null
exit 0
