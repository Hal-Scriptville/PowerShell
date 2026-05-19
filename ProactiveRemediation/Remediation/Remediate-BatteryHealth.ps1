# Remediate-BatteryHealth.ps1
# Proactive Remediation - Remediation
#
# Battery degradation cannot be resolved programmatically.
# This script generates a battery report and logs a diagnostic
# for help desk prioritization and hardware refresh planning.
#
# Exit 0 = diagnostic generated

$LogDir   = "C:\ProgramData\IT\Diagnostics"
$Report   = Join-Path $LogDir "BatteryHealth-$(Get-Date -Format 'yyyyMMdd').txt"
$HtmlReport = Join-Path $LogDir "BatteryReport-$(Get-Date -Format 'yyyyMMdd').html"

try {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

    $BatteryStatic = Get-WmiObject -Namespace root\wmi -Class BatteryStaticData -ErrorAction SilentlyContinue
    $BatteryFull   = Get-WmiObject -Namespace root\wmi -Class BatteryFullChargedCapacity -ErrorAction SilentlyContinue

    $DesignCapacity     = if ($BatteryStatic) { $BatteryStatic.DesignedCapacity } else { 0 }
    $FullChargeCapacity = if ($BatteryFull)   { $BatteryFull.FullChargedCapacity } else { 0 }
    $HealthPct          = if ($DesignCapacity -gt 0) {
        [math]::Round(($FullChargeCapacity / $DesignCapacity) * 100, 1)
    } else { 0 }

    $Lines = @(
        "Battery Health Diagnostic",
        "=========================",
        "Computer:             $env:COMPUTERNAME",
        "Date:                 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Design Capacity:      $DesignCapacity mWh",
        "Full Charge Capacity: $FullChargeCapacity mWh",
        "Health:               $HealthPct%",
        "",
        "ACTION REQUIRED: Battery health is below threshold. Schedule hardware replacement.",
        ""
    )
    $Lines | Out-File -FilePath $Report -Encoding UTF8

    # Generate Windows battery report (detailed HTML)
    $BatResult = powercfg /batteryreport /output $HtmlReport 2>&1
    Write-Output "Battery report: $BatResult"

    Write-Output "Diagnostic logged — $env:COMPUTERNAME battery at $HealthPct%"
    Write-Output "Full report: $HtmlReport"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 0
}
