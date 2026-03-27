# Remediation Script

# Initiate Windows Update Scan
try {
    Write-Output "Initiating Windows Update scan..."
    Start-Process -FilePath "usoclient.exe" -ArgumentList "StartScan" -NoNewWindow -Wait
    Write-Output "Windows Update scan initiated successfully."
} catch {
    Write-Output "Failed to initiate Windows Update scan: $_"
}

# Log the action to the Event Viewer
$logName = "Application"
$eventSource = "Custom Windows Update"

# Check if the source exists, and create it if it doesn't
if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
    try {
        New-EventLog -LogName $logName -Source $eventSource
        Write-Output "Event source '$eventSource' created successfully."
    } catch {
        Write-Output "Failed to create event source: $_"
        Exit 1
    }
}

# Write the event log entry
try {
    Write-EventLog -LogName $logName -Source $eventSource -EntryType Information -EventId 1000 -Message "Forced Windows Update scan initiated by Intune remediation script."
    Write-Output "Event log entry created successfully."
} catch {
    Write-Output "Failed to write to event log: $_"
}
