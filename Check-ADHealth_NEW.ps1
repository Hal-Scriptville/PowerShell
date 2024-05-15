$comp = $env:computername 
$org = "YourCompanyName"  # Change this to your actual company name
$baseDir = "D:\Temp"  # Base directory for script execution
$orgDir = Join-Path -Path $baseDir -ChildPath $org

# Function to write logs
function Write-Log {
    param([string]$message)
    $logPath = Join-Path -Path $orgDir -ChildPath "script_log.txt"
    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')): $message" | Out-File -FilePath $logPath -Append
}

# Function to handle errors
function Handle-Error {
    param($error)
    Write-Log "ERROR: $error"
}

# Check and create the base and organization directories
if (-not (Test-Path -Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
    Write-Log "Created base directory: $baseDir"
}
if (-not (Test-Path -Path $orgDir)) {
    New-Item -Path $orgDir -ItemType Directory -Force | Out-Null
    Write-Log "Created organization directory: $orgDir"
}

# Start the transcript
$transcriptFileName = Join-Path -Path $orgDir -ChildPath "${comp}_transcript.txt"
Start-Transcript -Path $transcriptFileName -ErrorAction Continue
Write-Log "Started transcript at $transcriptFileName"

# Collecting data for each Domain Controller
$DCs = Get-ADDomainController -Filter *
foreach ($DC in $DCs) {
    $dcPath = Join-Path -Path $orgDir -ChildPath ($DC.Name -replace "[^a-zA-Z0-9]", "_")

    # Ensure directory for each DC
    if (-not (Test-Path -Path $dcPath)) {
        New-Item -Path $dcPath -ItemType Directory -Force | Out-Null
        Write-Log "Created directory for DC: $dcPath"
    }

    try {
        # Replication information
        $replicationFilePath = Join-Path -Path $dcPath -ChildPath "replication_info.txt"
        repadmin /showrepl $DC.HostName | Out-File -Path $replicationFilePath
        Write-Log "Replication info written for $($DC.Name)"

        # HotFix information
        $hotFixFilePath = Join-Path -Path $dcPath -ChildPath "hotfixes.txt"
        Get-HotFix -ComputerName $DC.Name | Format-List | Out-File -Path $hotFixFilePath
        Write-Log "Hotfix info written for $($DC.Name)"

        # System and Application logs
        $appLogPath = Join-Path -Path $dcPath -ChildPath "app_log.csv"
        Get-EventLog -LogName Application -Newest 50 -ComputerName $DC.Name | Select-Object TimeGenerated, Source, InstanceID, Message | Export-Csv -Path $appLogPath -NoTypeInformation
        $sysLogPath = Join-Path -Path $dcPath -ChildPath "sys_log.csv"
        Get-EventLog -LogName System -Newest 50 -ComputerName $DC.Name | Select-Object TimeGenerated, Source, InstanceID, Message | Export-Csv -Path $sysLogPath -NoTypeInformation
        Write-Log "Event logs written for $($DC.Name)"
    } catch {
        Handle-Error $_.Exception.Message
    }
}

Stop-Transcript
Write-Log "Script execution completed and transcript stopped."
