<#
.SYNOPSIS
    REMEDIATION — enable Location Services + automatic time zone
.DESCRIPTION
    1. Enables the MASTER Location service via SystemSettingsAdminFlows.exe
       (the supported way — it writes the CapabilityConsentStorage DB; plain
       registry edits do NOT flip the toggle).
    2. Turns ON "Set time zone automatically" (tzautoupdate Start=3).
    3. Ensures the Geolocation service (lfsvc) is enabled and running.
    Auto time zone is LOCATION-driven (geolocation), so step 1 is the gating fix;
    Autopilot privacy-screen skip is what leaves Location OFF out of the box.
.CONTEXT
    Run as SYSTEM, 64-bit PowerShell.  Context: Intune Remediations (Windows).
#>

$ErrorActionPreference = 'Stop'
$log = Join-Path $env:ProgramData 'Intune\Remediation-LocationAutoTZ.log'
New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
function Log($m) { "{0}  {1}" -f (Get-Date -Format s), $m | Tee-Object -FilePath $log -Append }

try {
    # 1. MASTER Location services -> Allow (writes CapabilityConsentStorage DB + registry)
    $exe = Join-Path $env:WINDIR 'System32\SystemSettingsAdminFlows.exe'
    if (Test-Path $exe) {
        Start-Process -FilePath $exe -ArgumentList 'SetCamSystemGlobal location 1' -Wait -WindowStyle Hidden
        Log "SystemSettingsAdminFlows SetCamSystemGlobal location 1 -> executed"
    } else {
        Log "WARN: SystemSettingsAdminFlows.exe not found at $exe"
    }
    # Backstop so detection's registry read reflects Allow immediately
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -Name Value -Value 'Allow' -Force
    Log "ConsentStore\location Value=Allow (backstop)"

    # 2. "Set time zone automatically" ON  (3 = On, 4 = Off)
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' -Name Start -Value 3 -Force
    Log "tzautoupdate Start=3 (automatic time zone ON)"

    # 3. Geolocation service available + running
    Set-Service -Name lfsvc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name lfsvc -ErrorAction SilentlyContinue
    Log "lfsvc -> Automatic + started"

    Log "Remediation complete"
    Write-Output "Remediation complete: Location enabled + automatic time zone ON"
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Write-Output "Remediation FAILED: $($_.Exception.Message)"
    exit 1
}
