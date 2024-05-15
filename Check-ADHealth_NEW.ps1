$comp = $env:computername 
$org = "YourCompanyName"  # Update with your organization's name
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

# Ensure base and organization directories exist
if (-not (Test-Path -Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
    Write-Log "Created base directory: $baseDir"
}
if (-not (Test-Path -Path $orgDir)) {
    New-Item -Path $orgDir -ItemType Directory -Force | Out-Null
    Write-Log "Created organization directory: $orgDir"
}

# Start transcript
$transcriptFileName = Join-Path -Path $orgDir -ChildPath "${comp}_transcript.txt"
Start-Transcript -Path $transcriptFileName -ErrorAction Continue
Write-Log "Started transcript at $transcriptFileName"

# Collect FSMO Roles
try {
    $forest = Get-ADForest
    $domain = Get-ADDomain

    $FSMORoles = @{
        "Schema Master" = $forest.SchemaMaster;
        "Domain Naming Master" = $forest.DomainNamingMaster;
        "Infrastructure Master" = $domain.InfrastructureMaster;
        "RID Master" = $domain.RIDMaster;
        "PDC Emulator" = $domain.PDCEmulator;
    }

    $FSMORolesFilePath = Join-Path -Path $orgDir -ChildPath "FSMORoles.txt"
    $FSMORoles | Out-File -FilePath $FSMORolesFilePath
    Write-Log "FSMO roles collected and written to $FSMORolesFilePath"
} catch {
    Handle-Error $_.Exception.Message
}

# Collect AD Sites Information
try {
    $sitesInfo = Get-ADReplicationSite -Filter * | Format-Table -AutoSize
    $sitesFilePath = Join-Path -Path $orgDir -ChildPath "ADSites.txt"
    $sitesInfo | Out-File -FilePath $sitesFilePath
    Write-Log "Active Directory sites information collected and written to $sitesFilePath"
} catch {
    Handle-Error $_.Exception.Message
}

# Collect Global Catalog Servers
try {
    $gcs = Get-ADDomainController -Filter {IsGlobalCatalog -eq $true} | Select-Object Name, HostName, Site
    $gcsFilePath = Join-Path -Path $orgDir -ChildPath "GlobalCatalogs.txt"
    $gcs | Out-File -FilePath $gcsFilePath
    Write-Log "Global Catalog servers information collected and written to $gcsFilePath"
} catch {
    Handle-Error $_.Exception.Message
}

# Collect DC List
try {
    $DCs = Get-ADDomainController -Filter *
    $DCsFilePath = Join-Path -Path $orgDir -ChildPath "DomainControllers.txt"
    $DCs | Select-Object Name, HostName, Site | Out-File -FilePath $DCsFilePath
    Write-Log "Domain controllers list collected and written to $DCsFilePath"
} catch {
    Handle-Error $_.Exception.Message
}

# Operations for each Domain Controller
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
        repadmin /showrepl $DC.HostName | Out-File -FilePath $replicationFilePath
        Write-Log "Replication info for $($DC.Name) written to $replicationFilePath"

        # HotFix information
        $hotFixFilePath = Join-Path -Path $dcPath -ChildPath "hotfixes.txt"
        Get-HotFix -ComputerName $DC.Name | Format-List | Out-File -FilePath $hotFixFilePath
        Write-Log "Hotfix info for $($DC.Name) written to $hotFixFilePath"

        # Application and System logs
        $appLogPath = Join-Path -Path $dcPath -ChildPath "app_log.csv"
        Get-EventLog -LogName Application -Newest 50 -ComputerName $DC.Name | Select-Object TimeGenerated, Source, InstanceID, Message | Export-Csv -Path $appLogPath -NoTypeInformation
        $sysLogPath = Join-Path -Path $dcPath -ChildPath "sys_log.csv"
        Get-EventLog -LogName System -Newest 50 -ComputerName $DC.Name | Select-Object TimeGenerated, Source, InstanceID, Message | Export-Csv -Path $sysLogPath -NoTypeInformation
        Write-Log "Application and system logs for $($DC.Name) written to $appLogPath and $sysLogPath"

        # Copy netlogon.log
        $netlogonSource = "\\$($DC.HostName)\c$\Windows\debug\netlogon.log"
        $netlogonDest = Join-Path -Path $dcPath -ChildPath "netlogon.log"
        Copy-Item -Path $netlogonSource -Destination $netlogonDest -ErrorAction Continue
        Write-Log "Netlogon log for $($DC.Name) copied to $netlogonDest"
    } catch {
        Handle-Error $_.Exception.Message
    }
}

Stop-Transcript
Write-Log "Script execution completed and transcript stopped."
