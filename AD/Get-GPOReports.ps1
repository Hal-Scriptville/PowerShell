<#
.SYNOPSIS
Export GPO reports from Active Directory domains
.DESCRIPTION
Exports all GPOs to XML (for Group Policy Analytics) and HTML (for review)
Supports multi-domain environments
.PARAMETER Domain
Target domain FQDN. If not specified, uses current domain.
.PARAMETER OutputPath
Base output directory. Domain subfolder created automatically.
.PARAMETER ReportType
XML, HTML, or Both (default: Both)
.EXAMPLE
.\Get-GPOReports.ps1 -Domain "contoso.com" -OutputPath "C:\GPOReports"
.\Get-GPOReports.ps1 -Domain "dom.contoso.com" -OutputPath "C:\GPOReports"
#>

param(
[string]$Domain = $env:USERDNSDOMAIN,
[string]$OutputPath = "C:\GPOReports",
[ValidateSet("XML", "HTML", "Both")]
[string]$ReportType = "Both"
)

# Create domain-specific subfolder
$domainFolder = Join-Path $OutputPath ($Domain -replace '\.', '_')
if (!(Test-Path $domainFolder)) {
New-Item -ItemType Directory -Path $domainFolder -Force | Out-Null
}

# Get all GPOs from specified domain
try {
$allGPOs = Get-GPO -All -Domain $Domain -ErrorAction Stop
Write-Host "Found $($allGPOs.Count) GPOs in $Domain" -ForegroundColor Cyan
}
catch {
Write-Error "Failed to retrieve GPOs from $Domain : $_"
exit 1
}

$exported = 0
foreach ($gpo in $allGPOs) {
# Sanitize filename (remove invalid characters)
$safeName = $gpo.DisplayName -replace '[\\/:*?"<>|]', '_'

try {
if ($ReportType -in @("XML", "Both")) {
$xmlPath = Join-Path $domainFolder "$safeName.xml"
Get-GPOReport -Guid $gpo.Id -Domain $Domain -ReportType XML |
Out-File -FilePath $xmlPath -Encoding UTF8
}

if ($ReportType -in @("HTML", "Both")) {
$htmlPath = Join-Path $domainFolder "$safeName.html"
Get-GPOReport -Guid $gpo.Id -Domain $Domain -ReportType HTML |
Out-File -FilePath $htmlPath -Encoding UTF8
}

$exported++
Write-Host "[$exported/$($allGPOs.Count)] $($gpo.DisplayName)" -ForegroundColor Green
}
catch {
Write-Warning "Failed to export '$($gpo.DisplayName)': $_"
}
}

Write-Host "`nExported $exported GPOs to $domainFolder" -ForegroundColor Cyan

