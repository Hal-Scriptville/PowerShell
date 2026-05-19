# Remediate-EventLogErrors.ps1
# Proactive Remediation - Remediation
#
# Exports Critical and Error events from the last 24 hours to a local
# diagnostic file for help desk review. Does not auto-resolve errors —
# the root cause requires human triage.
#
# Exit 0 = diagnostic exported

$LogDir   = "C:\ProgramData\IT\Diagnostics"
$LogFile  = Join-Path $LogDir "EventLogErrors-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
$LookbackHours = 24

try {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

    $Since  = (Get-Date).AddHours(-$LookbackHours)
    $Filter = @{ LogName = 'System'; Level = @(1, 2); StartTime = $Since }
    $Events = Get-WinEvent -FilterHashtable $Filter -ErrorAction SilentlyContinue

    $Lines = @(
        "System Event Log Diagnostic Report",
        "===================================",
        "Computer:  $env:COMPUTERNAME",
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Period:    Last $LookbackHours hours",
        "Events:    $(@($Events).Count) Critical/Error",
        ""
    )

    if ($Events) {
        $Lines += $Events | Sort-Object TimeCreated -Descending | ForEach-Object {
            $LevelName = if ($_.Level -eq 1) { "CRITICAL" } else { "ERROR" }
            "$LevelName  $($_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))  [$($_.ProviderName)]  $($_.Message.Split("`n")[0].Trim())"
        }
    }
    else {
        $Lines += "(No Critical or Error events found)"
    }

    $Lines | Out-File -FilePath $LogFile -Encoding UTF8
    Write-Output "Diagnostic exported to $LogFile ($(@($Events).Count) events)"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 0
}
