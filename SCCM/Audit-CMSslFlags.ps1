<#
.SYNOPSIS
    Audit (and optionally remediate) "Require SSL" / client-certificate enforcement across every
    IIS virtual directory on a Configuration Manager site system (Distribution Point, Management
    Point, or Software Update Point). READ-ONLY by default.

.DESCRIPTION
    On a ConfigMgr site system configured for HTTP or Enhanced HTTP (eHTTP) client communication,
    none of the CM-managed IIS virtual directories should require SSL or a client certificate -
    clients reach content and policy over anonymous HTTP (with a CM-issued token for eHTTP).

    A common failure: a security-hardening GPO, a vulnerability-scan remediation, or a manual
    "force HTTPS" change stamps the IIS "Require SSL" flag (and sometimes "Client certificates =
    Require") onto the CM virtual directories. IIS then answers the client's anonymous HTTP
    request with:

        HTTP Error 403.4 - Forbidden  ("SSL required")

    The client-side symptom is usually indirect and easy to misdiagnose - for example:
      * Content won't download from a Distribution Point:
          [CCMHTTP] ERROR ... StatusCode=403 StatusText=Forbidden
          GetDirectoryList failed ... 0x87d0027e  (SMS_DP_SMSPKG$ / SMS_DP_SMSSIG$)
      * An OS deployment task sequence fails at a later step (the real cause is that a package
        couldn't be pulled, not the step that reported the error).
      * "Client is not allowed to use or doesn't have PKI cert while talking to HTTPS server"
        spam in ccmsetup.log / ClientIDManagerStartup.log (Management Point vdirs).

    This script enumerates the site root plus every application and virtual directory under the
    target IIS site, decodes the sslFlags attribute into a human-readable Require SSL /
    client-certificate state, flags the CM-managed vdirs that are enforcing SSL or a client cert,
    and writes a CSV evidence file. With -Fix it clears those flags (sslFlags = None) on the CM
    vdirs so they serve over HTTP/eHTTP again.

    Healthy eHTTP state for a CM vdir:  Require SSL = off, Client certificates = Ignore
    (sslFlags = None).

.PARAMETER SiteName
    IIS site to scan. Default 'Default Web Site'.

.PARAMETER Fix
    Clear Require SSL + client-certificate enforcement (sslFlags = None) on the flagged CM vdirs.
    Prompts per change unless -Force is also supplied.

.PARAMETER Force
    Skip the per-change confirmation (use with -Fix).

.PARAMETER OutDir
    Directory for the CSV evidence file. Default: %USERPROFILE%\cm-iis-ssl-audit

.EXAMPLE
    # Audit only - makes no changes
    powershell -ExecutionPolicy Bypass -File .\Audit-CMSslFlags.ps1

.EXAMPLE
    # Audit, then clear SSL/cert enforcement on the flagged CM vdirs, then apply
    powershell -ExecutionPolicy Bypass -File .\Audit-CMSslFlags.ps1 -Fix -Force
    iisreset

.EXAMPLE
    # Re-audit after a fix to confirm every CM vdir shows None
    powershell -ExecutionPolicy Bypass -File .\Audit-CMSslFlags.ps1

.NOTES
    Run this ELEVATED, on the site system itself. Requires the IIS WebAdministration module
    (Install-WindowsFeature Web-Scripting-Tools). After -Fix, run 'iisreset' and re-audit.

    IMPORTANT: only run -Fix if this site system is intended to use HTTP / Enhanced HTTP. If your
    site legitimately runs HTTPS with PKI, the flags are correct and should be left in place.
    Test in your environment first; the CSV gives you a before/after record either way.

    Durable fix: if the flags were set by a GPO or a recurring security scan, they will be
    re-applied. Find and scope out the source (exclude the site system, or move to HTTPS/PKI
    properly) so the change sticks.

    MIT licensed. Read-only unless -Fix is passed.
#>
[CmdletBinding()]
param(
    [string]$SiteName = 'Default Web Site',
    [switch]$Fix,
    [switch]$Force,
    [string]$OutDir = "$env:USERPROFILE\cm-iis-ssl-audit"
)

$ErrorActionPreference = 'Stop'

try { Import-Module WebAdministration -ErrorAction Stop }
catch { throw "WebAdministration module not available. Install with: Install-WindowsFeature Web-Scripting-Tools" }

# CM-managed vdir name patterns that run over HTTP / eHTTP (should not require SSL or a client cert)
$cmPattern = '^(SMS_DP_|SMS_MP|CCM_|CCMTOKENAUTH_|CMUserService|BGB|NOTIFICATION)'

function Convert-SslFlags($flags) {
    $raw = [string]$flags
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = 'None' }
    $tokens = $raw -split '[,\s]+' | Where-Object { $_ }
    $requireSsl = ($tokens -contains 'Ssl') -or ($tokens -contains 'Ssl128')
    $cc = 'Ignore'
    if     ($tokens -contains 'SslRequireCert')   { $cc = 'Require' }   # IIS UI: Client certs = Require
    elseif ($tokens -contains 'SslNegotiateCert') { $cc = 'Accept'  }   # IIS UI: Client certs = Accept
    [pscustomobject]@{ RequireSSL = [bool]$requireSsl; ClientCert = $cc; Raw = $raw }
}

# Enumerate the site root + every application + every virtual directory
$paths  = @('/')
$paths += (Get-WebApplication      -Site $SiteName | Select-Object -ExpandProperty path)
$paths += (Get-WebVirtualDirectory -Site $SiteName | Select-Object -ExpandProperty path)
$paths  = $paths | Sort-Object -Unique

$rows = foreach ($p in $paths) {
    $rel    = if ($p -eq '/') { '' } else { $p }
    $pspath = "MACHINE/WEBROOT/APPHOST/$SiteName$rel"
    try {
        $val = Get-WebConfigurationProperty -PSPath $pspath -Filter 'system.webServer/security/access' -Name sslFlags -ErrorAction Stop
        $raw = if ($null -ne $val.Value) { [string]$val.Value } else { [string]$val }
    } catch { $raw = 'None' }
    $d = Convert-SslFlags $raw
    [pscustomobject]@{
        Vdir       = $p
        IsCM       = ([bool]($p.TrimStart('/') -match $cmPattern))
        RequireSSL = $d.RequireSSL
        ClientCert = $d.ClientCert
        sslFlags   = $d.Raw
        Problem    = ($d.RequireSSL -or $d.ClientCert -ne 'Ignore')
    }
}

# Report
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp  = Get-Date -Format 'yyyy-MM-dd_HHmm'
$suffix = if ($Fix) { 'after-fix' } else { 'audit' }
$csv    = Join-Path $OutDir "cm-iis-ssl-$suffix`_$stamp.csv"
$rows | Sort-Object IsCM, Vdir | Export-Csv -NoTypeInformation -Path $csv

Write-Host "`n=== ConfigMgr IIS SSL / client-cert audit: $SiteName on $env:COMPUTERNAME  ($stamp) ===`n" -ForegroundColor Cyan
$rows | Sort-Object @{Expression='Problem';Descending=$true}, @{Expression='IsCM';Descending=$true}, Vdir |
    Format-Table Vdir, IsCM, RequireSSL, ClientCert, sslFlags -AutoSize

$bad   = @($rows | Where-Object { $_.IsCM -and $_.Problem })
$color = if ($bad.Count) { 'Red' } else { 'Green' }
Write-Host ("CM vdirs enforcing SSL/client-cert (should be None for HTTP/eHTTP): {0}" -f $bad.Count) -ForegroundColor $color
$bad | ForEach-Object { Write-Host ("  ! {0}  ->  {1}" -f $_.Vdir, $_.sslFlags) -ForegroundColor Yellow }
Write-Host "`nEvidence CSV: $csv`n" -ForegroundColor Green

# Optional fix
if ($Fix) {
    if (-not $bad.Count) { Write-Host "Nothing to fix - all CM vdirs already None.`n" -ForegroundColor Green; return }
    foreach ($b in $bad) {
        $rel    = if ($b.Vdir -eq '/') { '' } else { $b.Vdir }
        $pspath = "MACHINE/WEBROOT/APPHOST/$SiteName$rel"
        if ($Force -or $PSCmdlet.ShouldContinue("Clear Require SSL + client-cert on '$($b.Vdir)'?", "Fix HTTP/eHTTP vdir")) {
            Set-WebConfigurationProperty -PSPath $pspath -Filter 'system.webServer/security/access' -Name sslFlags -Value 'None'
            Write-Host ("  fixed {0}  ->  None" -f $b.Vdir) -ForegroundColor Green
        }
    }
    Write-Host "`nDone. Now run:  iisreset" -ForegroundColor Cyan
    Write-Host "Then re-run this script WITHOUT -Fix to confirm every CM vdir shows None.`n" -ForegroundColor Cyan
}
