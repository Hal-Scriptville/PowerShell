# Check-ADHealth.ps1
<#
.SYNOPSIS
PowerShell script for comprehensive Active Directory health monitoring and reporting.

.DESCRIPTION
This script performs comprehensive diagnostics on Active Directory environment by collecting
critical information from domain controllers, including replication status, FSMO roles,
event logs, and system information.

.PARAMETER org
Organization name used for creating output directories and file naming.

.PARAMETER baseDir
Base directory where all output files will be stored. Defaults to D:\Temp.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$org,
    [Parameter(Mandatory=$false)]
    [string]$baseDir = "D:\Temp"
)

# Create base directory structure
$orgDir = Join-Path -Path $baseDir -ChildPath $org
if (-not (Test-Path -Path $orgDir)) {
    New-Item -Path $orgDir -ItemType Directory -Force
}

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

# Start transcript logging
$transcriptPath = Join-Path -Path $orgDir -ChildPath "transcript.log"
Start-Transcript -Path $transcriptPath

try {
    # Get all Domain Controllers
    Write-Log "Getting Domain Controllers"
    $DCs = Get-ADDomainController -Filter *

    foreach ($DC in $DCs) {
        # Create DC-specific directory
        $dcDir = Join-Path -Path $orgDir -ChildPath $DC.Name
        if (-not (Test-Path -Path $dcDir)) {
            New-Item -Path $dcDir -ItemType Directory -Force
        }

        # Collect DC specific information
        Write-Log "Collecting information for $($DC.Name)"

        # System Information
        Write-Log "Getting system information for $($DC.Name)"
        $sysInfoPath = Join-Path -Path $dcDir -ChildPath "SystemInfo.txt"
        systeminfo /S $DC.Name > $sysInfoPath

        # Event Logs
        Write-Log "Getting event logs for $($DC.Name)"
        $appLogPath = Join-Path -Path $dcDir -ChildPath "AppLog.csv"
        $sysLogPath = Join-Path -Path $dcDir -ChildPath "SysLog.csv"
        Get-EventLog -LogName Application -Newest 5000 -ComputerName $DC.Name | Export-Csv -Path $appLogPath -NoTypeInformation
        Get-EventLog -LogName System -Newest 5000 -ComputerName $DC.Name | Export-Csv -Path $sysLogPath -NoTypeInformation

        # Hotfixes
        Write-Log "Getting hotfixes for $($DC.Name)"
        $hotfixPath = Join-Path -Path $dcDir -ChildPath "Hotfixes.csv"
        Get-HotFix -ComputerName $DC.Name | Export-Csv -Path $hotfixPath -NoTypeInformation

        # Netlogon log
        Write-Log "Copying netlogon.log for $($DC.Name)"
        $remoteNetlogonPath = "\\$($DC.Name)\c$\windows\debug\netlogon.log"
        $localNetlogonPath = Join-Path -Path $dcDir -ChildPath "netlogon.log"
        Copy-Item -Path $remoteNetlogonPath -Destination $localNetlogonPath -ErrorAction Continue
    }

    # Collect AD-wide information
    Write-Log "Collecting AD-wide information"

    # FSMO Roles
    Write-Log "Getting FSMO roles"
    $fsmoPath = Join-Path -Path $orgDir -ChildPath "FSMORoles.txt"
    netdom query fsmo > $fsmoPath

    # Replication Status
    Write-Log "Getting replication status"
    $replPath = Join-Path -Path $orgDir -ChildPath "ReplicationStatus.txt"
    repadmin /showrepl * /csv > $replPath

    # Sites and Services
    Write-Log "Getting sites and services information"
    $sitesPath = Join-Path -Path $orgDir -ChildPath "ADSites.txt"
    nltest /server:$env:COMPUTERNAME /dsgetsite > $sitesPath

    Write-Log "Script completed successfully"
}
catch {
    Handle-Error $_
    Write-Log "Script terminated with errors"
}
finally {
    Stop-Transcript
}
