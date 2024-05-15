# Define the base directory
$baseDir = "C:\Temp"
$orgDir = Join-Path -Path $baseDir -ChildPath $org

# Check and create the base directory if it does not exist
if (-not (Test-Path -Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
    Write-Host "Created base directory: $baseDir"
}

# Now use $orgDir as the base for all other file operations
$comp = $env:computername 
$org = "YourCompanyName" # Change this to your actual company name
$orgDir = Join-Path -Path "." -ChildPath $org

# Function to log messages
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

# Check and create directory
if (-not (Test-Path -Path $orgDir)) {
    New-Item -Path $orgDir -ItemType Directory -Force | Out-Null
    Write-Log "Created directory: $orgDir"
}

# Start the transcript with a new file name
$transcriptFileName = Join-Path -Path $orgDir -ChildPath "${comp}_transcript.txt"
Start-Transcript -Path $transcriptFileName -ErrorAction Continue

# Collect FSMO Roles Information
function Collect-FSMORoles {
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
        Write-Log "FSMO roles collected successfully."
    } catch {
        Handle-Error $_.Exception.Message
    }
}

# Run FSMO roles collection
Collect-FSMORoles

# Collecting data using Invoke-Command for better performance
$DCs = Get-ADDomainController -Filter *
foreach ($DC in $DCs) {
    $scriptBlock = {
        param($org)
        # Replication information
        $replicationInfoPath = Join-Path -Path $org -ChildPath ("ReplicationInfo_$env:COMPUTERNAME.txt")
        repadmin /showrepl | Out-File -FilePath $replicationInfoPath
        
        # HotFix information
        $hotFixesPath = Join-Path -Path $org -ChildPath ("HotFixes_$env:COMPUTERNAME.txt")
        $hotfixes = Get-WmiObject -Class Win32_QuickFixEngineering
        $hotfixes | Select-Object Description, HotFixID, InstalledOn | Out-File -FilePath $hotFixesPath
        
        # System and Application logs
        $appLogPath = Join-Path -Path $org -ChildPath ("AppLog_$env:COMPUTERNAME.csv")
        $sysLogPath = Join-Path -Path $org -ChildPath ("SysLog_$env:COMPUTERNAME.csv")
        Get-EventLog -LogName application -Newest 5000 | Export-Csv -Path $appLogPath -NoTypeInformation
        Get-EventLog -LogName system -Newest 5000 | Export-Csv -Path $sysLogPath -NoTypeInformation
    }
    Invoke-Command -ComputerName $DC.Name -ScriptBlock $scriptBlock -ArgumentList $orgDir -ErrorAction Continue
}

Stop-Transcript
Write-Log "Script execution completed."
