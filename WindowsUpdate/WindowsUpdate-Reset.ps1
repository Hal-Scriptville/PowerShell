# Windows Update Reset Script
# Use when Feature Updates are failing to install through SCCM or Intune

# Run with Administrative privileges
# Stop Windows Update related services
Write-Host "Stopping Windows Update related services..." -ForegroundColor Yellow
Stop-Service -Name wuauserv, cryptSvc, bits, msiserver -Force

# Delete Windows Update cache folders
Write-Host "Cleaning Windows Update cache..." -ForegroundColor Yellow
Get-Item "$env:SystemRoot\SoftwareDistribution*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-Item "$env:SystemRoot\System32\catroot2*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Clear pending update entries in registry
Write-Host "Clearing pending update entries in registry..." -ForegroundColor Yellow
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
    Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -Force -ErrorAction SilentlyContinue
}

# Reset Windows Update components
Write-Host "Resetting Windows Update components..." -ForegroundColor Yellow
cmd /c "sc.exe sdset bits D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)"
cmd /c "sc.exe sdset wuauserv D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)"

# Re-register DLL files
Write-Host "Re-registering Windows Update DLLs..." -ForegroundColor Yellow
$dllFiles = @(
    "$env:SystemRoot\System32\wuaueng.dll",
    "$env:SystemRoot\System32\wuapi.dll",
    "$env:SystemRoot\System32\wups.dll",
    "$env:SystemRoot\System32\wups2.dll"
)

foreach ($dll in $dllFiles) {
    if (Test-Path $dll) {
        cmd /c "regsvr32.exe /s $dll"
    }
}

# Reset Windows Update policies
Write-Host "Resetting Windows Update policies..." -ForegroundColor Yellow
cmd /c "netsh winhttp reset proxy"
cmd /c "netsh winsock reset"

# Clear SCCM/Intune client cache if client exists
if (Test-Path "$env:WinDir\CCM\CcmExec.exe") {
    Write-Host "Clearing SCCM client cache..." -ForegroundColor Yellow
    cmd /c "$env:WinDir\CCM\CcmExec.exe /ClearCache"
}

# Restart Windows Update related services
Write-Host "Restarting Windows Update related services..." -ForegroundColor Yellow
Start-Service -Name bits
Start-Service -Name cryptSvc
Start-Service -Name wuauserv
Start-Service -Name msiserver

# Force Windows Update detection cycle
Write-Host "Forcing Windows Update detection cycle..." -ForegroundColor Yellow
cmd /c "wuauclt /detectnow"
cmd /c "wuauclt /reportnow"

Write-Host "Windows Update reset completed. The system may need to be rebooted before attempting the feature update again." -ForegroundColor Green
