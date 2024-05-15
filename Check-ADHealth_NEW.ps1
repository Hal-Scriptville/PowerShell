$comp = $env:computername 
$org = "Change to Company Name"
$FormatEnumerationLimit = -1

# Logging function
function Write-Log {
    param([string]$message)
    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')): $message" | Out-File -FilePath ".\$org\script_log.txt" -Append
}

# Error handling function
function Handle-Error {
    param($error)
    Write-Log "ERROR: $error"
}

# Ensure the ActiveDirectory module is available
if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
    Write-Host "ActiveDirectory module is not installed. Exiting script."
    exit
}

Import-Module -Name ActiveDirectory -ErrorAction Stop

Write-Log "Creating directory for $org"
New-Item -Path . -Name $org -ItemType Directory -ErrorAction Continue

# Start the transcript with a new file name including "transcript"
$transcriptFileName = ".\$org\${comp}_transcript.txt"
Start-Transcript -Path $transcriptFileName -ErrorAction Continue

# Collecting various AD information using modular functions
function Collect-ADInformation {
    Write-Log "Collecting list of Active Directory sites"
    Get-ADReplicationSite -Filter * | Format-Table -AutoSize | Out-File -FilePath ".\$org\Sites.txt"

    Write-Log "Collecting FSMO Roles Information"
    $forest = Get-ADForest
    $domain = Get-ADDomain

    $FSMORoles = @{
        "Schema Master" = $forest.SchemaMaster;
        "Domain Naming Master" = $forest.DomainNamingMaster;
        "Infrastructure Master" = $domain.InfrastructureMaster;
        "RID Master" = $domain.RIDMaster;
        "PDC Emulator" = $domain.PDCEmulator;
    }

    $FSMORoles | Out-File -FilePath ".\$org\FSMORoles.txt"
}

# Run the Collect-ADInformation function
Collect-ADInformation

# Collecting data using Invoke-Command for better performance
$DCs = Get-ADDomainController -Filter *

foreach ($DC in $DCs) {
    $scriptBlock = {
        param($org)
        # Replication information
        repadmin /showrepl $env:COMPUTERNAME | Out-File -FilePath ".\$org\ReplicationInfo_$env:COMPUTERNAME.txt"
        
        # HotFix information
        $hotfixes = Get-WmiObject -Class Win32_QuickFixEngineering
        $hotfixes | Select-Object Description, HotFixID, InstalledOn | Out-File -FilePath ".\$org\HotFixes_$env:COMPUTERNAME.txt"
        
        # System and Application logs
        Get-EventLog -LogName application -Newest 5000 |
            Export-Csv -Path ".\$org\AppLog_$env:COMPUTERNAME.csv" -NoTypeInformation

        Get-EventLog -LogName system -Newest 5000 |
            Export-Csv -Path ".\$org\SysLog_$env:COMPUTERNAME.csv" -NoTypeInformation
    }
    Invoke-Command -ComputerName $DC.Name -ScriptBlock $scriptBlock -ArgumentList $org -ErrorAction Continue
}

Stop-Transcript
Write-Log "Script execution completed"
