<#
.SYNOPSIS
    Adds device authentication claim rules to ADFS for hybrid Azure AD join with MDM auto-enrollment.

.DESCRIPTION
    This script adds the required device claim rules to the Microsoft Office 365 Identity Platform
    relying party trust in ADFS. These rules are required for:
    - Hybrid Azure AD device registration
    - MDM auto-enrollment via Intune

    Without these rules, devices register as hybrid Azure AD joined but MDM URLs remain blank,
    preventing Intune enrollment.

.PARAMETER FederatedDomain
    Your organization's federated domain (e.g., contoso.com). This must match a verified
    federated domain in Entra ID. Check Entra ID > Custom domain names to find yours.

.PARAMETER RelyingPartyName
    The name of the ADFS relying party trust. Default: "Microsoft Office 365 Identity Platform"

.PARAMETER WhatIf
    Shows what changes would be made without applying them.

.EXAMPLE
    .\Add-ADFSDeviceClaimRules.ps1 -FederatedDomain "contoso.com"

    Adds device claim rules using contoso.com as the federated domain.

.EXAMPLE
    .\Add-ADFSDeviceClaimRules.ps1 -FederatedDomain "contoso.com" -WhatIf

    Shows what would be changed without making changes.

.NOTES
    Requirements:
    - Must run on ADFS server as Administrator
    - ADFS service must be running
    - Federated domain must be verified in Entra ID

    References:
    - https://learn.microsoft.com/en-us/azure/active-directory/devices/hybrid-azuread-join-federated-domains
    - https://learn.microsoft.com/en-us/azure/active-directory/devices/hybrid-azuread-join-manual


#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Your federated domain (e.g., contoso.com)")]
    [ValidateNotNullOrEmpty()]
    [string]$FederatedDomain,

    [Parameter(Mandatory = $false)]
    [string]$RelyingPartyName = "Microsoft Office 365 Identity Platform"
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "ADFS Device Claim Rules - MDM Enrollment Fix" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Relying Party:    $RelyingPartyName" -ForegroundColor Yellow
Write-Host "Federated Domain: $FederatedDomain" -ForegroundColor Yellow
Write-Host ""

# Validate federated domain format
if ($FederatedDomain -notmatch "^[a-zA-Z0-9][a-zA-Z0-9-]*\.[a-zA-Z]{2,}$") {
    Write-Host "ERROR: Invalid domain format. Expected format: contoso.com" -ForegroundColor Red
    exit 1
}

# Step 1: Get current relying party trust
Write-Host "[1/5] Getting current relying party trust..." -ForegroundColor Green
try {
    $rp = Get-AdfsRelyingPartyTrust -Name $RelyingPartyName
    if (-not $rp) {
        throw "Relying party trust '$RelyingPartyName' not found. Verify ADFS is configured for Office 365."
    }
    Write-Host "      Found relying party trust." -ForegroundColor Gray
}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  - Ensure you're running this on the ADFS server" -ForegroundColor Gray
    Write-Host "  - Verify ADFS service is running: Get-Service adfssrv" -ForegroundColor Gray
    Write-Host "  - List relying parties: Get-AdfsRelyingPartyTrust | Select Name" -ForegroundColor Gray
    exit 1
}

# Step 2: Backup current rules
Write-Host "[2/5] Backing up current rules..." -ForegroundColor Green
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupPath = ".\ADFS_ClaimRules_Backup_$timestamp.txt"
$rp.IssuanceTransformRules | Out-File -FilePath $backupPath -Encoding UTF8
Write-Host "      Backup saved to: $backupPath" -ForegroundColor Gray

# Step 3: Check if device rules already exist
Write-Host "[3/5] Checking for existing device claim rules..." -ForegroundColor Green
$existingRules = $rp.IssuanceTransformRules

$hasAccountType = $existingRules -match "accounttype.*DJ"
$hasObjectGuid = $existingRules -match "onpremobjectguid"
$hasPrimarySid = $existingRules -match "primarysid.*issue\(claims"
$hasIssuerId = $existingRules -match "issuerid.*adfs/services/trust"

if ($hasAccountType -or $hasObjectGuid -or $hasPrimarySid -or $hasIssuerId) {
    Write-Host "      WARNING: Some device claim rules may already exist:" -ForegroundColor Yellow
    if ($hasAccountType) { Write-Host "        - Account type rule found" -ForegroundColor Yellow }
    if ($hasObjectGuid) { Write-Host "        - ObjectGUID rule found" -ForegroundColor Yellow }
    if ($hasPrimarySid) { Write-Host "        - PrimarySID rule found" -ForegroundColor Yellow }
    if ($hasIssuerId) { Write-Host "        - IssuerID rule found" -ForegroundColor Yellow }
    Write-Host ""
    $continue = Read-Host "      Continue anyway? (y/N)"
    if ($continue -ne "y") {
        Write-Host "      Aborted by user." -ForegroundColor Yellow
        exit 0
    }
}
else {
    Write-Host "      No existing device rules found. Proceeding..." -ForegroundColor Gray
}

# Step 4: Define new device claim rules
Write-Host "[4/5] Preparing device claim rules..." -ForegroundColor Green

$deviceClaimRules = @"

@RuleName = "Issue account type for domain-joined computers"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/groupsid", Value =~ "-515$", Issuer =~ "^(AD AUTHORITY|SELF AUTHORITY|LOCAL AUTHORITY)$"]
 => issue(Type = "http://schemas.microsoft.com/ws/2012/01/accounttype", Value = "DJ");

@RuleName = "Issue objectGUID for domain-joined computers"
c1:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/groupsid", Value =~ "-515$", Issuer =~ "^(AD AUTHORITY|SELF AUTHORITY|LOCAL AUTHORITY)$"]
 && c2:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer =~ "^(AD AUTHORITY|SELF AUTHORITY|LOCAL AUTHORITY)$"]
 => issue(store = "Active Directory", types = ("http://schemas.microsoft.com/identity/claims/onpremobjectguid"), query = ";objectguid;{0}", param = c2.Value);

@RuleName = "Issue primarySID for domain-joined computers"
c1:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/groupsid", Value =~ "-515$", Issuer =~ "^(AD AUTHORITY|SELF AUTHORITY|LOCAL AUTHORITY)$"]
 && c2:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/primarysid", Issuer =~ "^(AD AUTHORITY|SELF AUTHORITY|LOCAL AUTHORITY)$"]
 => issue(claim = c2);

@RuleName = "Issue issuerID for domain-joined computers"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/groupsid", Value =~ "-515$", Issuer =~ "^(AD AUTHORITY|SELF AUTHORITY|LOCAL AUTHORITY)$"]
 => issue(Type = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/issuerid", Value = "http://$FederatedDomain/adfs/services/trust/");

"@

Write-Host "      Device claim rules prepared:" -ForegroundColor Gray
Write-Host "        - Account type (DJ)" -ForegroundColor Gray
Write-Host "        - On-premises objectGUID" -ForegroundColor Gray
Write-Host "        - Primary SID" -ForegroundColor Gray
Write-Host "        - Issuer ID (http://$FederatedDomain/adfs/services/trust/)" -ForegroundColor Gray

# Step 5: Apply new rules
Write-Host "[5/5] Applying updated claim rules..." -ForegroundColor Green

$newRules = $existingRules + $deviceClaimRules

if ($PSCmdlet.ShouldProcess($RelyingPartyName, "Update IssuanceTransformRules with device claims")) {
    try {
        Set-AdfsRelyingPartyTrust -TargetName $RelyingPartyName -IssuanceTransformRules $newRules
        Write-Host "      Rules applied successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR applying rules: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Attempting to restore from backup..." -ForegroundColor Yellow
        try {
            $backupRules = Get-Content $backupPath -Raw
            Set-AdfsRelyingPartyTrust -TargetName $RelyingPartyName -IssuanceTransformRules $backupRules
            Write-Host "Backup restored successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "ERROR restoring backup: $_" -ForegroundColor Red
            Write-Host "Manual restore required from: $backupPath" -ForegroundColor Red
        }
        exit 1
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Restart ADFS service (recommended):" -ForegroundColor White
Write-Host "     Restart-Service adfssrv" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. On a test device, re-register with Azure AD:" -ForegroundColor White
Write-Host "     dsregcmd /leave" -ForegroundColor Gray
Write-Host "     Start-Sleep -Seconds 30" -ForegroundColor Gray
Write-Host "     dsregcmd /join" -ForegroundColor Gray
Write-Host "     Restart-Computer" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. After reboot, verify MDM URLs are populated:" -ForegroundColor White
Write-Host "     dsregcmd /status" -ForegroundColor Gray
Write-Host ""
Write-Host "     Expected output:" -ForegroundColor Gray
Write-Host "       MdmUrl : https://enrollment.manage.microsoft.com/..." -ForegroundColor DarkGray
Write-Host "       MdmTouUrl : https://portal.manage.microsoft.com/..." -ForegroundColor DarkGray
Write-Host "       MdmComplianceUrl : https://portal.manage.microsoft.com/..." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  4. Check Intune portal for device enrollment (may take 5-15 min)" -ForegroundColor White
Write-Host ""
Write-Host "Rollback:" -ForegroundColor Yellow
Write-Host "  If issues occur, restore the backup:" -ForegroundColor White
Write-Host "  `$backup = Get-Content '$backupPath' -Raw" -ForegroundColor Gray
Write-Host "  Set-AdfsRelyingPartyTrust -TargetName '$RelyingPartyName' -IssuanceTransformRules `$backup" -ForegroundColor Gray
Write-Host "  Restart-Service adfssrv" -ForegroundColor Gray
Write-Host ""
Write-Host "Backup location: $backupPath" -ForegroundColor Cyan
Write-Host ""
