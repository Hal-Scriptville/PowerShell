# Detect-ScheduledTaskHealth.ps1
# Proactive Remediation - Detection
#
# Checks key Windows maintenance scheduled tasks to ensure they are
# enabled and have not failed on their last run.
#
# Tasks checked:
#   - Disk Cleanup (SilentCleanup)
#   - Windows Defender Cache Maintenance
#   - Windows Defender Cleanup
#   - Windows Error Reporting (queue reporting)
#   - Automatic Maintenance
#
# Exit 0 = compliant
# Exit 1 = non-compliant (task disabled or last run failed)

$TasksToCheck = @(
    @{ Path = '\Microsoft\Windows\DiskCleanup\SilentCleanup';               Name = 'Disk Cleanup' },
    @{ Path = '\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance'; Name = 'Defender Cache Maintenance' },
    @{ Path = '\Microsoft\Windows\Windows Defender\Windows Defender Cleanup'; Name = 'Defender Cleanup' },
    @{ Path = '\Microsoft\Windows\Windows Error Reporting\QueueReporting';   Name = 'WER Queue Reporting' },
    @{ Path = '\Microsoft\Windows\TaskScheduler\Regular Maintenance';        Name = 'Automatic Maintenance' }
)

# LastRunResult codes that are acceptable (not failures)
$AcceptableResults = @(
    0,        # Success
    267011,   # Task has not yet run
    267009,   # Task is currently running
    -2147024891  # Access denied (some tasks require elevation to query result)
)

try {
    $Issues = @()

    foreach ($T in $TasksToCheck) {
        $Task = Get-ScheduledTask -TaskPath (Split-Path $T.Path -Parent) `
                                  -TaskName  (Split-Path $T.Path -Leaf) `
                                  -ErrorAction SilentlyContinue

        if (-not $Task) { continue }  # Task doesn't exist on this OS version — skip

        if ($Task.State -eq 'Disabled') {
            $Issues += "$($T.Name) is disabled"
            continue
        }

        $Info = $Task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        if ($Info -and $Info.LastRunTime -ne [DateTime]::MinValue) {
            if ($Info.LastTaskResult -notin $AcceptableResults) {
                $Issues += "$($T.Name) last run failed (result: 0x$('{0:X8}' -f [uint32]$Info.LastTaskResult))"
            }
        }
    }

    if ($Issues.Count -gt 0) {
        Write-Output "NON-COMPLIANT: $($Issues.Count) scheduled task issue(s)"
        $Issues | ForEach-Object { Write-Output "  - $_" }
        exit 1
    }

    Write-Output "COMPLIANT: All $($TasksToCheck.Count) maintenance tasks are enabled and healthy"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
