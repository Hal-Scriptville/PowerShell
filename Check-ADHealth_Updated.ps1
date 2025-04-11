<#
.SYNOPSIS
  Gathers AD-related data and stores the output in the specified directory structure.

.DESCRIPTION
  By default, this script logs to "C:\Temp\YourCompanyName". You can override these
  defaults by specifying -BaseDir and -Org parameters.

.PARAMETER BaseDir
  The parent directory under which all files will be stored.

.PARAMETER Org
  The organization or folder name used under BaseDir.

.EXAMPLE
  .\Collect-ADInfo.ps1

  Uses the default values for BaseDir and Org.

.EXAMPLE
  .\Collect-ADInfo.ps1 -BaseDir "D:\Temp" -Org "MyCo"

  Writes all logs and data to D:\Temp\MyCo.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$BaseDir = "C:\Temp",

    [Parameter(Mandatory = $false)]
    [string]$Org = "YourCompanyName"
)

# Build our working directory from the parameters
$orgDir = Join-Path -Path $BaseDir -ChildPath $Org

# A function for logging
function Write-Log {
    param([string]$message)
    $logPath = Join-Path -Path $orgDir -ChildPath "script_log.txt"
    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')): $message" | Out-File -FilePath $logPath -Append
}

# A function for handling errors
function Handle-Error {
    param($error)
    Write-Log "ERROR: $error"
}

function Check-ADBackup {
    param(
        [string]$DCName,
        [string]$dcPath
    )
    try {
        # Attempt to retrieve the 'lastBackup' property
        $backupCheck = Get-ADObject -Identity "CN=NTDS Settings,CN=$DCName,CN=Servers,CN=Default-First-Site-Name,CN=Sites,CN=Configuration,$((Get-ADDomain).DistinguishedName)" -Properties lastBackup -Server $DCName -ErrorAction Stop
        
        if ($backupCheck.PSObject.Properties.Name -contains 'lastBackup') {
            if ($backupCheck.lastBackup) {
                $lastBackupTime = [DateTime]::FromFileTime($backupCheck.lastBackup)
                $message = "Last backup of AD on DC $DCName was at $lastBackupTime"
            } else {
                $message = "No backup information found for AD on DC $DCName"
            }
        }
        else {
            $message = "lastBackup attribute is not present on DC $DCName."
        }

        Write-Log $message
        $backupFilePath = Join-Path -Path $dcPath -ChildPath "ADBackupStatus.txt"
        $message | Out-File -FilePath $backupFilePath
    }
    catch {
        Handle-Error "Failed to check AD backup status for $DCName $_"
    }
}

# Ensure base and organization directories exist
if (-not (Test-Path -Path $BaseDir)) {
    New-Item -Path $BaseDir -ItemType Directory -Force | Out-Null
    Write-Log "Created base directory: $BaseDir"
}
if (-not (Test-Path -Path $orgDir)) {
    New-Item -Path $orgDir -ItemType Directory -Force | Out-Null
    Write-Log "Created organization directory: $orgDir"
}

# Start transcript
$comp = $env:computername
$transcriptFileName = Join-Path -Path $orgDir -ChildPath "${comp}_transcript.txt"
Start-Transcript -Path $transcriptFileName -ErrorAction Continue
Write-Log "Started transcript at $transcriptFileName"

# Collect FSMO Roles
try {
    $forest = Get-ADForest
    $domain = Get-ADDomain

    $FSMORoles = @{
        "Schema Master"         = $forest.SchemaMaster
        "Domain Naming Master"  = $forest.DomainNamingMaster
        "Infrastructure Master" = $domain.InfrastructureMaster
        "RID Master"            = $domain.RIDMaster
        "PDC Emulator"          = $domain.PDCEmulator
    }

    $FSMORolesFilePath = Join-Path -Path $orgDir -ChildPath "FSMORoles.txt"
    $FSMORoles | Out-File -FilePath $FSMORolesFilePath
    Write-Log "FSMO roles collected and written to $FSMORolesFilePath"
}
catch {
    Handle-Error $_.Exception.Message
}

# Collect AD Sites Information
try {
    $sitesInfo = Get-ADReplicationSite -Filter * | Format-Table -AutoSize
    $sitesFilePath = Join-Path -Path $orgDir -ChildPath "ADSites.txt"
    $sitesInfo | Out-File -FilePath $sitesFilePath
    Write-Log "Active Directory sites information collected and written to $sitesFilePath"
}
catch {
    Handle-Error $_.Exception.Message
}

# Collect Global Catalog Servers
try {
    $gcs = Get-ADDomainController -Filter {IsGlobalCatalog -eq $true} | Select-Object Name, HostName, Site
    $gcsFilePath = Join-Path -Path $orgDir -ChildPath "GlobalCatalogs.txt"
    $gcs | Out-File -FilePath $gcsFilePath
    Write-Log "Global Catalog servers information collected and written to $gcsFilePath"
}
catch {
    Handle-Error $_.Exception.Message
}

# Collect DC List
try {
    $DCs = Get-ADDomainController -Filter *
    $DCsFilePath = Join-Path -Path $orgDir -ChildPath "DomainControllers.txt"
    $DCs | Select-Object Name, HostName, Site | Out-File -FilePath $DCsFilePath
    Write-Log "Domain controllers list collected and written to $DCsFilePath"
}
catch {
    Handle-Error $_.Exception.Message
}

# Collect Forest and Domain Functional Levels
try {
    $forestLevel = (Get-ADForest).ForestMode
    $domainLevel = (Get-ADDomain).DomainMode

    # Option A: Write both to one file if that's all you need
    # "Forest Functional Level: $forestLevel`nDomain Functional Level: $domainLevel" | Out-File (Join-Path $orgDir "FunctionalLevels.txt")

    # Option B: Write them separately if your report script checks these files individually
    $forestLevelPath = Join-Path -Path $orgDir -ChildPath "ForestLevel.txt"
    $domainLevelPath = Join-Path -Path $orgDir -ChildPath "DomainLevel.txt"

    "Forest Functional Level: $forestLevel"  | Out-File -FilePath $forestLevelPath
    "Domain Functional Level: $domainLevel"  | Out-File -FilePath $domainLevelPath

    Write-Log "Forest level written to $forestLevelPath"
    Write-Log "Domain level written to $domainLevelPath"
}
catch {
    Handle-Error $_.Exception.Message
}

# Collect Active Directory Schema Version
try {
    $schema = Get-ADObject (Get-ADRootDSE).schemaNamingContext -Property objectVersion
    $schemaVersion = $schema.objectVersion
    $schemaVersionPath = Join-Path -Path $orgDir -ChildPath "SchemaVersion.txt"
    "Active Directory Schema Version: $schemaVersion" | Out-File -FilePath $schemaVersionPath
    Write-Log "Schema version collected and written to $schemaVersionPath"
}
catch {
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
        # Replication info
        $replicationFilePath = Join-Path -Path $dcPath -ChildPath "replication_info.txt"
        repadmin /showrepl $DC.HostName | Out-File -FilePath $replicationFilePath
        Write-Log "Replication info for $($DC.Name) written to $replicationFilePath"

        # HotFix info
        $hotFixFilePath = Join-Path -Path $dcPath -ChildPath "hotfixes.txt"
        Get-HotFix -ComputerName $DC.Name | Format-List | Out-File -FilePath $hotFixFilePath
        Write-Log "Hotfix info for $($DC.Name) written to $hotFixFilePath"

        # Check AD backup status
        Check-ADBackup -DCName $DC.Name -dcPath $dcPath

        # Application and System logs
        $appLogPath = Join-Path -Path $dcPath -ChildPath "app_log.csv"
        Get-EventLog -LogName Application -Newest 50 -ComputerName $DC.Name |
            Select-Object TimeGenerated, Source, InstanceID, Message |
            Export-Csv -Path $appLogPath -NoTypeInformation

        $sysLogPath = Join-Path -Path $dcPath -ChildPath "sys_log.csv"
        Get-EventLog -LogName System -Newest 50 -ComputerName $DC.Name |
            Select-Object TimeGenerated, Source, InstanceID, Message |
            Export-Csv -Path $sysLogPath -NoTypeInformation

        Write-Log "Application and system logs for $($DC.Name) written to $appLogPath and $sysLogPath"

        # Copy netlogon.log
        $netlogonSource = "\\$($DC.HostName)\c$\Windows\debug\netlogon.log"
        $netlogonDest = Join-Path -Path $dcPath -ChildPath "netlogon.log"
        Copy-Item -Path $netlogonSource -Destination $netlogonDest -ErrorAction Continue
        Write-Log "Netlogon log for $($DC.Name) copied to $netlogonDest"
    }
    catch {
        Handle-Error $_.Exception.Message
    }
}

Stop-Transcript
Write-Log "Script execution completed and transcript stopped."
