<#
.SYNOPSIS
    DETECTION — Location Services + automatic time zone (Intune Remediations)
.DESCRIPTION
    Reports NON-COMPLIANT (exit 1 -> triggers remediation) when any of:
      - Master Location consent is not "Allow"
      - "Set time zone automatically" (tzautoupdate) is not ON (Start=3)
      - Geolocation service (lfsvc) is Disabled/missing
    Reports COMPLIANT (exit 0) otherwise.
    NOTE: the ConsentStore registry value REFLECTS the CapabilityConsentStorage DB,
    so it is a valid signal to READ for detection (it is not reliable to WRITE — that
    is why remediation uses SystemSettingsAdminFlows.exe).
.CONTEXT
    Run as SYSTEM, 64-bit PowerShell.  Context: Intune Remediations (Windows).
#>

$ErrorActionPreference = 'SilentlyContinue'
$reasons = @()

# 1. Master Location consent (registry reflects CapabilityConsentStorage DB)
$loc = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -Name Value).Value
if ([string]::IsNullOrEmpty($loc)) { $loc = 'Missing' }
if ($loc -ne 'Allow') { $reasons += "Location=$loc" }

# 2. Automatic time zone  (tzautoupdate Start: 3 = On, 4 = Off)
$tz = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate' -Name Start).Start
if ($null -eq $tz) { $tz = 'Missing' }
if ($tz -ne 3) { $reasons += "AutoTimeZone(Start)=$tz" }

# 3. Geolocation service (lfsvc) must be able to run
$lfsvc = Get-Service -Name lfsvc
if ($null -eq $lfsvc)              { $reasons += "lfsvc=Missing" }
elseif ($lfsvc.StartType -eq 'Disabled') { $reasons += "lfsvc=Disabled" }

if ($reasons.Count -gt 0) {
    Write-Output ("NON-COMPLIANT: " + ($reasons -join '; '))
    exit 1
}
Write-Output "COMPLIANT: Location=Allow; AutoTimeZone=On; lfsvc OK"
exit 0
