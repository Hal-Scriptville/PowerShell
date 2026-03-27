<#
.SYNOPSIS
    Detection-only script for MDM enrollment blockers.

.DESCRIPTION
    Lightweight assessment script to identify policy-backed registry values
    that may block MDM/Intune enrollment. Makes no changes.

    Exit Codes:
    0 = No blocking values found
    1 = Blocking values detected
    2 = Error during detection

.NOTES
    Version:        1.0
    Author:         HK
    Creation Date:  2026-01-22
#>

[CmdletBinding()]
param()

$BlockersFound = $false
$Results = @()

Write-Host "MDM Enrollment Block Detection" -ForegroundColor Cyan
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "=" * 60

# Check DisableRegistration
$MdmPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
if (Test-Path $MdmPath) {
    $DisableReg = (Get-ItemProperty -Path $MdmPath -Name "DisableRegistration" -ErrorAction SilentlyContinue).DisableRegistration
    if ($DisableReg -eq 1) {
        Write-Host "[BLOCKED] DisableRegistration = 1" -ForegroundColor Red
        $Results += "DisableRegistration=1 (BLOCKED)"
        $BlockersFound = $true
    }
    elseif ($null -ne $DisableReg) {
        Write-Host "[OK] DisableRegistration = $DisableReg" -ForegroundColor Green
    }
}
else {
    Write-Host "[OK] MDM policy key does not exist" -ForegroundColor Green
}

# Check BlockAADWorkplaceJoin
$WpjPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin"
if (Test-Path $WpjPath) {
    $BlockWpj = (Get-ItemProperty -Path $WpjPath -Name "BlockAADWorkplaceJoin" -ErrorAction SilentlyContinue).BlockAADWorkplaceJoin
    if ($BlockWpj -eq 1) {
        Write-Host "[BLOCKED] BlockAADWorkplaceJoin = 1" -ForegroundColor Red
        $Results += "BlockAADWorkplaceJoin=1 (BLOCKED)"
        $BlockersFound = $true
    }
    elseif ($null -ne $BlockWpj) {
        Write-Host "[OK] BlockAADWorkplaceJoin = $BlockWpj" -ForegroundColor Green
    }

    $AutoWpj = (Get-ItemProperty -Path $WpjPath -Name "autoWorkplaceJoin" -ErrorAction SilentlyContinue).autoWorkplaceJoin
    if ($AutoWpj -eq 0) {
        Write-Host "[WARN] autoWorkplaceJoin = 0 (disabled)" -ForegroundColor Yellow
        $Results += "autoWorkplaceJoin=0 (disabled)"
    }
}
else {
    Write-Host "[OK] WorkplaceJoin policy key does not exist" -ForegroundColor Green
}

# Check WMI MDM Authority
Write-Host ""
Write-Host "Checking WMI MDM Authority..." -ForegroundColor Cyan
try {
    $MdmAuth = Get-CimInstance -Namespace "root/cimv2/mdm" -ClassName MDM_MgmtAuthority -ErrorAction Stop
    if ($MdmAuth) {
        Write-Host "[WARN] WMI MDM Authority record exists (possible stale enrollment)" -ForegroundColor Yellow
        $Results += "WMI MDM Authority present"
    }
}
catch {
    Write-Host "[OK] No WMI MDM Authority (namespace not present or empty)" -ForegroundColor Green
}

# Check for legacy scheduled tasks
Write-Host ""
Write-Host "Checking legacy scheduled tasks..." -ForegroundColor Cyan
$LegacyTasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\EnterpriseMgmt\*" -ErrorAction SilentlyContinue
if ($LegacyTasks) {
    Write-Host "[WARN] Legacy EnterpriseMgmt tasks found: $($LegacyTasks.Count)" -ForegroundColor Yellow
    $LegacyTasks | ForEach-Object { Write-Host "       - $($_.TaskPath)$($_.TaskName)" -ForegroundColor Yellow }
    $Results += "Legacy scheduled tasks: $($LegacyTasks.Count)"
}
else {
    Write-Host "[OK] No legacy EnterpriseMgmt scheduled tasks" -ForegroundColor Green
}

# Quick dsregcmd status
Write-Host ""
Write-Host "Device registration status:" -ForegroundColor Cyan
$Dsreg = dsregcmd /status 2>&1
$AzureAdJoined = ($Dsreg | Select-String "AzureAdJoined\s*:\s*(\w+)").Matches.Groups[1].Value
$DomainJoined = ($Dsreg | Select-String "DomainJoined\s*:\s*(\w+)").Matches.Groups[1].Value
$WorkplaceJoined = ($Dsreg | Select-String "WorkplaceJoined\s*:\s*(\w+)").Matches.Groups[1].Value
$MdmUrl = ($Dsreg | Select-String "MdmUrl\s*:\s*(.+)").Matches.Groups[1].Value

Write-Host "  DomainJoined:     $DomainJoined"
Write-Host "  AzureAdJoined:    $AzureAdJoined"
Write-Host "  WorkplaceJoined:  $WorkplaceJoined"
Write-Host "  MdmUrl:           $(if ($MdmUrl) { $MdmUrl } else { '(not enrolled)' })"

# Summary
Write-Host ""
Write-Host "=" * 60
if ($BlockersFound) {
    Write-Host "RESULT: BLOCKERS DETECTED" -ForegroundColor Red
    Write-Host "Findings:" -ForegroundColor Red
    $Results | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
else {
    Write-Host "RESULT: NO BLOCKERS FOUND" -ForegroundColor Green
    if ($Results.Count -gt 0) {
        Write-Host "Warnings:" -ForegroundColor Yellow
        $Results | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
    exit 0
}
