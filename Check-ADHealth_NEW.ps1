$comp = $env:computername 
$org = "YourCompanyName" # Change this to your actual company name
$baseDir = "D:\Temp" # Base directory for script execution
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

# Collect FSMO Roles Information
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
    Write-Log "FSMO roles collected successfully and written to $FSMORolesFilePath"
} catch {
    Handle-Error $_.Exception.Message
}

# Handling domain controllers
$DCs = Get-ADDomainController -Filter *
foreach ($DC in $DCs) {
    $dcPath = Join-Path -Path $orgDir -ChildPath ($DC.Name -replace "[^a-zA-Z0-9]", "_")

    # Check and create directory for each DC
    if (-not (Test-Path -Path $dcPath)) {
        New-Item -Path $dcPath -ItemType Directory -Force | Out-Null
        Write-Log "Created directory for DC: $dcPath"
    }

    # Perform operations for each DC
    $filePath = Join-Path -Path $dcPath -ChildPath "info.txt"
    try {
        "Information for $DC" | Out-File -Path $filePath
        Write-Log "Successfully wrote information for $($DC.Name) to $filePath"
    } catch {
        Handle-Error $_.Exception.Message
    }
}

Stop-Transcript
Write-Log "Script execution completed and transcript stopped."
