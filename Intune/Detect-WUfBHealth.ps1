<#
.SYNOPSIS
    Intune Proactive Remediation DETECTION — Windows Update for Business health.
    Reports WHY a device is behind on quality updates, as a single parseable line.

.DESCRIPTION
    Built 2026-07-31 from a live Whitsons session where 777 of 1055 devices (74%) showed
    "Not up to date" and no single per-device theory survived contact with the data.

    Everything obvious was eliminated one device at a time — not paused, not deferred, no
    stale WSUS, scanning daily, installing daily, modern OS, healthy hardware, every Intune
    policy reporting "Succeeded". The device was still two patch cycles behind.

    The lesson that shaped this script: the per-setting status view says a setting was
    DELIVERED, never what it was set to, and LastInstallationSuccessDate counts Defender
    definitions — so a stalled device looks green from every angle Intune shows you.

    This does NOT trust status. It reads state, and it reports the reason rather than a
    yes/no, so the fleet result is a ranked cause list instead of a count.

.OUTPUTS
    Exit 0 = healthy.  Exit 1 = at least one issue (triggers remediation / flags in report).
    STDOUT = one compact line. Intune surfaces this as "Pre-remediation detection output",
    which becomes the fleet report column — so it is deliberately short and greppable.

.NOTES
    Read-only. Changes nothing. Safe to deploy broadly.
    Run as SYSTEM, 64-bit.
#>

$ErrorActionPreference = 'SilentlyContinue'
$issues  = [System.Collections.Generic.List[string]]::new()
$facts   = [System.Collections.Generic.List[string]]::new()

# ── Build / servicing ────────────────────────────────────────────────────────
$cv    = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = "$($cv.CurrentBuild).$($cv.UBR)"
$disp  = $cv.DisplayVersion
$facts.Add("build=$disp/$build")

# ── Uptime + pending reboot ──────────────────────────────────────────────────
# The 5040 case: installs succeed, build never advances, nothing ever errors.
$boot   = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$upDays = if ($boot) { [int]((Get-Date) - $boot).TotalDays } else { -1 }
$facts.Add("uptimeDays=$upDays")

$rebootPending = $false
foreach ($k in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
    if (Test-Path $k) { $rebootPending = $true }
}
if ($rebootPending) {
    $issues.Add("REBOOT_PENDING")
    if ($upDays -gt 14) { $issues.Add("REBOOT_PENDING_STALE_${upDays}d") }
}

# ── Last successful scan / install ───────────────────────────────────────────
# NOTE: LastInstallationSuccessDate includes Defender definitions. It is NOT evidence
# that a cumulative landed — which is exactly why a stalled device reads healthy.
try {
    $au = (New-Object -ComObject Microsoft.Update.AutoUpdate).Results
    $scanAge = if ($au.LastSearchSuccessDate) { [int]((Get-Date) - $au.LastSearchSuccessDate).TotalDays } else { 999 }
    $facts.Add("scanAgeDays=$scanAge")
    if ($scanAge -gt 7) { $issues.Add("NO_SCAN_${scanAge}d") }
} catch { $issues.Add("WU_COM_UNAVAILABLE") }

# ── Actual cumulative recency — definitions excluded ─────────────────────────
# This is the signal that survives. Get-HotFix lists real KBs, not definitions.
$lastCu = Get-HotFix | Where-Object { $_.Description -match 'Security Update|Update' -and $_.InstalledOn } |
          Sort-Object InstalledOn -Descending | Select-Object -First 1
if ($lastCu) {
    $cuAge = [int]((Get-Date) - $lastCu.InstalledOn).TotalDays
    $facts.Add("lastKB=$($lastCu.HotFixID)@${cuAge}d")
    if ($cuAge -gt 45) { $issues.Add("NO_CUMULATIVE_${cuAge}d") }
} else {
    $issues.Add("NO_HOTFIX_HISTORY")
}

# ── Pause / defer / WSUS ─────────────────────────────────────────────────────
$wu = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$ux = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'

if ($ux.PauseQualityUpdatesStartTime) { $issues.Add("QUALITY_PAUSED") }
if ($ux.PauseFeatureUpdatesStartTime) { $issues.Add("FEATURE_PAUSED") }
if ([int]$wu.DeferQualityUpdatesPeriodInDays -gt 7) {
    $issues.Add("DEFER_QUALITY_$([int]$wu.DeferQualityUpdatesPeriodInDays)d")
}
# Stale WSUS is the classic silent killer — device gets nothing from WUfB, reports no error.
if ($wu.UseWUServer -eq 1 -or $wu.WUServer) { $issues.Add("WSUS_REDIRECT") }

# ── Automatic update settings ────────────────────────────────────────────────
# 344 devices carried "Automatic update settings misconfigured" in the 7/31 Whitsons export.
# That alert is tenant-side; this is the on-device shape of it.
$au2 = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
if ($au2.NoAutoUpdate -eq 1) { $issues.Add("AUTOUPDATE_DISABLED") }
if ($null -ne $au2.AUOptions -and [int]$au2.AUOptions -lt 3) { $issues.Add("AUOPTIONS_$([int]$au2.AUOptions)") }

# ── Service health ───────────────────────────────────────────────────────────
foreach ($svc in @('wuauserv','bits','cryptsvc')) {
    $s = Get-Service -Name $svc
    if (-not $s) { $issues.Add("SVC_MISSING_$svc") }
    elseif ($s.StartType -eq 'Disabled') { $issues.Add("SVC_DISABLED_$svc") }
}

# ── ⭐ WindowsUpdateClient event errors — the signal that actually found it ──
# On the 7/31 Whitsons device every other check came back clean; the event log was the
# only place the cause was visible. Transport errors (0x8024xxxx) mean the client could
# not complete its conversation with the update service — typically a proxy or SSL
# inspection layer, NOT a broken WU client. Store errors are separated out as noise.
try {
    $ev = Get-WinEvent -FilterHashtable @{
        LogName      = 'Microsoft-Windows-WindowsUpdateClient/Operational'
        ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
        Level        = 1,2,3
        StartTime    = (Get-Date).AddDays(-30)
    } -MaxEvents 200

    $codes = @{}
    foreach ($e in $ev) {
        foreach ($m in [regex]::Matches($e.Message,'0x[0-9A-Fa-f]{8}')) {
            $c = $m.Value.ToLower(); $codes[$c] = [int]$codes[$c] + 1
        }
    }
    # 0x80073D02 = ERROR_PACKAGES_IN_USE — Microsoft Store app updates, not cumulatives.
    # Loud, recurring, and irrelevant to the quality-update backlog. Reported, never alerted.
    $store     = @($codes.Keys | Where-Object { $_ -eq '0x80073d02' })
    $transport = @($codes.Keys | Where-Object { $_ -like '0x8024*' })

    if ($transport.Count -gt 0) {
        $top = ($transport | Sort-Object { -$codes[$_] } | Select-Object -First 3 |
                ForEach-Object { "$_ x$($codes[$_])" }) -join '/'
        $issues.Add("WU_TRANSPORT_ERR[$top]")
        $facts.Add("proxyOrInspectionSuspect=1")
    }
    if ($store.Count -gt 0) { $facts.Add("storeAppErrs=$($codes['0x80073d02'])") }
    $facts.Add("wuErrEvents30d=$($ev.Count)")
} catch { $facts.Add("wuEventLogUnavailable=1") }

# ── SoftwareDistribution bloat — a corruption tell ───────────────────────────
$sd = Get-Item "$env:SystemRoot\SoftwareDistribution\Download"
if ($sd) {
    $gb = [math]::Round((Get-ChildItem $sd -Recurse -Force |
          Measure-Object Length -Sum).Sum / 1GB, 1)
    $facts.Add("sdCacheGB=$gb")
    if ($gb -gt 10) { $issues.Add("SD_CACHE_${gb}GB") }
}

# ── Result ───────────────────────────────────────────────────────────────────
$factStr = ($facts -join ' ')
if ($issues.Count -eq 0) {
    Write-Host "OK $factStr"
    exit 0
} else {
    Write-Host "ISSUES=$($issues -join ',') $factStr"
    exit 1
}
