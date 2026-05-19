# Remediate-ScheduledTaskHealth.ps1
# Proactive Remediation - Remediation
#
# Re-enables disabled Windows maintenance scheduled tasks
# and triggers an immediate run for tasks that have failed.
#
# Exit 0 = success
# Exit 1 = failure

$TasksToCheck = @(
    @{ Path = '\Microsoft\Windows\DiskCleanup\SilentCleanup';               Name = 'Disk Cleanup' },
    @{ Path = '\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance'; Name = 'Defender Cache Maintenance' },
    @{ Path = '\Microsoft\Windows\Windows Defender\Windows Defender Cleanup'; Name = 'Defender Cleanup' },
    @{ Path = '\Microsoft\Windows\Windows Error Reporting\QueueReporting';   Name = 'WER Queue Reporting' },
    @{ Path = '\Microsoft\Windows\TaskScheduler\Regular Maintenance';        Name = 'Automatic Maintenance' }
)

$AcceptableResults = @(0, 267011, 267009, -2147024891)

try {
    $Fixed  = 0
    $Errors = 0

    foreach ($T in $TasksToCheck) {
        $Task = Get-ScheduledTask -TaskPath (Split-Path $T.Path -Parent) `
                                  -TaskName  (Split-Path $T.Path -Leaf) `
                                  -ErrorAction SilentlyContinue

        if (-not $Task) { continue }

        if ($Task.State -eq 'Disabled') {
            try {
                Enable-ScheduledTask -TaskPath (Split-Path $T.Path -Parent) `
                                     -TaskName  (Split-Path $T.Path -Leaf) -ErrorAction Stop
                Write-Output "Enabled: $($T.Name)"
                $Fixed++
            }
            catch {
                Write-Output "WARNING: Could not enable $($T.Name): $_"
                $Errors++
            }
            continue
        }

        $Info = $Task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        if ($Info -and $Info.LastRunTime -ne [DateTime]::MinValue -and
            $Info.LastTaskResult -notin $AcceptableResults) {
            try {
                Start-ScheduledTask -TaskPath (Split-Path $T.Path -Parent) `
                                    -TaskName  (Split-Path $T.Path -Leaf) -ErrorAction Stop
                Write-Output "Restarted: $($T.Name)"
                $Fixed++
            }
            catch {
                Write-Output "WARNING: Could not restart $($T.Name): $_"
                $Errors++
            }
        }
    }

    if ($Errors -gt 0 -and $Fixed -eq 0) {
        exit 1
    }

    Write-Output "Remediation complete — $Fixed task(s) fixed, $Errors warning(s)"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
