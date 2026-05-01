<#
.SYNOPSIS
    Removes duplicate Entra Registered records where a Hybrid Azure AD Joined record already exists.
.DESCRIPTION
    Devices can end up with two Entra registrations:
      - Entra Registered (trustType: Workplace) — user-initiated, often predates hybrid join setup
      - Hybrid Azure AD Joined (trustType: ServerAd) — the correct, domain-backed record

    This script finds devices with both types (matched by display name), reports the stale
    Entra Registered record, and optionally deletes it.

    Always run without -DryRun:$false first to review the report.

.PARAMETER DryRun
    Report duplicates without deleting. Default: $true

.PARAMETER ExportCsv
    Optional path to export results as CSV for review.

.EXAMPLE
    # Audit only (default)
    .\Remove-DuplicateEntraRegistrations.ps1

    # Export audit report
    .\Remove-DuplicateEntraRegistrations.ps1 -ExportCsv C:\Temp\duplicate-devices.csv

    # Delete stale records (after reviewing dry run output)
    .\Remove-DuplicateEntraRegistrations.ps1 -DryRun:$false

.NOTES
    Version:  1.0
    Requires: Microsoft.Graph.Authentication, Microsoft.Graph.Identity.DirectoryManagement
    Scope:    Device.ReadWrite.All
    
    trustType reference:
      Workplace = Entra Registered (stale duplicate — this is what we remove)
      ServerAd  = Hybrid Azure AD Joined (correct — this is what we keep)
      AzureAd   = Entra Joined (cloud-only, not targeted by this script)
#>

param(
    [bool]$DryRun = $true,
    [string]$ExportCsv = ""
)

# Connect to Graph
Connect-MgGraph -Scopes "Device.ReadWrite.All" -NoWelcome

Write-Host "`nFetching all Entra device records..." -ForegroundColor Cyan
$allDevices = Get-MgDevice -All -Property `
    DisplayName, TrustType, OperatingSystem, `
    ApproximateLastSignInDateTime, RegistrationDateTime, `
    IsCompliant, Id

Write-Host "Total records: $($allDevices.Count)"

# Group by display name — each group = one hostname
$grouped = $allDevices | Group-Object -Property DisplayName
$duplicates = [System.Collections.Generic.List[PSObject]]::new()

foreach ($group in $grouped) {
    if ($group.Count -lt 2) { continue }

    $registered = $group.Group | Where-Object { $_.TrustType -eq "Workplace" }
    $hybrid     = $group.Group | Where-Object { $_.TrustType -eq "ServerAd" }

    # Only flag if there's at least one of each type
    if (-not $registered -or -not $hybrid) { continue }

    $keepDevice = $hybrid | Sort-Object ApproximateLastSignInDateTime -Descending | Select-Object -First 1

    foreach ($stale in $registered) {
        $duplicates.Add([PSCustomObject]@{
            DeviceName       = $group.Name
            Action           = "DELETE (stale Entra Registered)"
            StaleId          = $stale.Id
            StaleLastSeen    = $stale.ApproximateLastSignInDateTime
            StaleRegistered  = $stale.RegistrationDateTime
            KeepId           = $keepDevice.Id
            KeepType         = "Hybrid Azure AD Joined"
            KeepLastSeen     = $keepDevice.ApproximateLastSignInDateTime
            KeepCompliant    = $keepDevice.IsCompliant
        })
    }
}

Write-Host "`nDevices with duplicate registrations found: $($duplicates.Count)" -ForegroundColor Yellow

if ($duplicates.Count -eq 0) {
    Write-Host "No duplicates found. Environment is clean." -ForegroundColor Green
    Disconnect-MgGraph | Out-Null
    exit 0
}

# Display summary table
$duplicates | Format-Table DeviceName, StaleLastSeen, KeepLastSeen, KeepCompliant -AutoSize

if ($ExportCsv) {
    $duplicates | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Report exported to: $ExportCsv" -ForegroundColor Cyan
}

if ($DryRun) {
    Write-Host "`n[DRY RUN] Would delete $($duplicates.Count) stale Entra Registered records." -ForegroundColor Yellow
    Write-Host "Re-run with -DryRun:`$false to execute deletions.`n" -ForegroundColor Yellow
    Disconnect-MgGraph | Out-Null
    exit 0
}

# Confirm before executing live deletions
$confirm = Read-Host "`nAbout to delete $($duplicates.Count) stale records. Type YES to confirm"
if ($confirm -ne "YES") {
    Write-Host "Aborted." -ForegroundColor Red
    Disconnect-MgGraph | Out-Null
    exit 0
}

$deleted = 0
$failed  = 0

foreach ($dup in $duplicates) {
    try {
        Remove-MgDevice -DeviceId $dup.StaleId -Confirm:$false
        Write-Host "  Deleted: $($dup.DeviceName)  [$($dup.StaleId)]" -ForegroundColor Green
        $deleted++
    } catch {
        Write-Host "  Failed:  $($dup.DeviceName) — $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host "`n========================================" 
Write-Host " Deleted: $deleted  |  Failed: $failed"
Write-Host "========================================"

Disconnect-MgGraph | Out-Null
