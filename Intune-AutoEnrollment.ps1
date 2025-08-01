<#
.SYNOPSIS
    Automated Intune enrollment script for Entra-joined devices
.DESCRIPTION
    This script checks if a device is Entra-joined and triggers Intune enrollment.
    It includes robust error handling, diagnostics, and logging features.
.NOTES
    Version: 2.0
    Created: August 1, 2025
#>

# Script Configuration
$VerbosePreference = 'Continue'
$LogPath = "$env:ProgramData\IntuneEnrollment"
$LogFile = "$LogPath\EnrollmentLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Ensure log directory exists
if (-not (Test-Path $LogPath)) { 
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null 
}

# Logging Function
function Write-Log {
    param([string]$Message)
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    
    Write-Verbose $logEntry
    Add-Content -Path $LogFile -Value $logEntry
}

# Enhanced Device Information Collection
function Get-DeviceDetails {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $bios = Get-CimInstance -ClassName Win32_BIOS
    
    $props = @{
        ComputerName = $computerSystem.Name
        Manufacturer = $computerSystem.Manufacturer
        Model = $computerSystem.Model
        SerialNumber = $bios.SerialNumber
        EnrollmentStatus = "Unknown"
    }
    return New-Object -TypeName PSObject -Property $props
}

# Interactive User Detection
function Get-LoggedOnUserUpn {
    try {
        $sid = (Get-Process -IncludeUserName -ErrorAction SilentlyContinue |
                Where-Object { $_.SessionId -gt 0 } | Select-Object -First 1).UserName
        if ($sid) { return $sid }
    } catch {}
    return $null
}

# DeviceEnroller With Retry Logic
function Invoke-DeviceEnroller {
    param([int]$attempt=1)
    $enroller = "$env:WINDIR\System32\deviceenroller.exe"
    if (Test-Path $enroller) {
        Write-Log "Invoking DeviceEnroller (attempt $attempt)..."
        $p = Start-Process -FilePath $enroller -ArgumentList "/c /AutoEnrollMDM" -PassThru -WindowStyle Hidden -Wait
        return $p.ExitCode
    }
    return 2  # DeviceEnroller not found
}

# Main Script Logic
Write-Log "Starting Intune enrollment script..."

# Check if device is Entra-joined
$isEntraJoined = $false
$deviceDetails = Get-DeviceDetails

try {
    $dsregCmd = dsregcmd /status
    $isEntraJoined = $dsregCmd -match "AzureAdJoined : YES"
    
    if ($isEntraJoined) {
        Write-Log "Device is Entra-joined, proceeding with enrollment."
    } else {
        Write-Log "Device is not Entra-joined, cannot enroll in Intune."
        exit 1
    }
} catch {
    Write-Log "Error checking Entra join status: $_"
    exit 1
}

# Check for proxy configuration
$netsh = (netsh winhttp show proxy) 2>$null
if ($netsh -and ($netsh -match 'Proxy Server')) {
    Write-Log "WinHTTP proxy in use: $($netsh -replace '\s+',' ')"
}

# Check if already enrolled in Intune
$enrolled = $false
$alreadyEnrolled = $false

# Architecture-Agnostic Registry Operations
$base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, 
                                                  [Microsoft.Win32.RegistryView]::Registry64)
$enrollKey = $base.OpenSubKey("SOFTWARE\Microsoft\Enrollments")

if ($enrollKey) {
    foreach ($sub in $enrollKey.GetSubKeyNames()) {
        if ($sub -match '^\{[0-9A-F-]+\}$') {
            $prov = $enrollKey.OpenSubKey($sub).GetValue('ProviderID', $null)
            if ($prov -eq 'MS DM Server') { 
                $alreadyEnrolled = $true
                Write-Log "Device is already enrolled in Intune."
                break 
            }
        }
    }
}

if ($alreadyEnrolled) {
    $enrolled = $true
} else {
    # Check for interactive user
    $userPresent = [bool](Get-LoggedOnUserUpn)
    if (-not $userPresent) {
        Write-Log "No interactive user detected; enrollment may defer until next sign-in."
    }

    # Hardened MDM Policy Write
    $mdmKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
    try {
        New-Item -Path $mdmKey -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $mdmKey -Name 'AutoEnrollMDM' -PropertyType DWord -Value 1 -Force | Out-Null
        New-ItemProperty -Path $mdmKey -Name 'UseAADCredentialType' -PropertyType DWord -Value 1 -Force | Out-Null
        
        $ae = (Get-ItemProperty $mdmKey).AutoEnrollMDM
        $ct = (Get-ItemProperty $mdmKey).UseAADCredentialType
        
        if ($ae -ne 1 -or $ct -ne 1) {
            Write-Log "Policy write failed verification."
            exit 5
        }
    } catch {
        Write-Log "Policy write failed: $_"
        exit 5
    }

    # Improved Scheduled Task Discovery
    $emPath = "\Microsoft\Windows\EnterpriseMgmt\"
    $tasks = Get-ScheduledTask -TaskPath $emPath -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -match 'enrollment client|PushLaunch'
    }

    if ($tasks) {
        $toStart = $tasks | Sort-Object {[datetime]$_.LastRunTime} -Descending | Select-Object -First 1
        Write-Log "Starting enrollment task '$($toStart.TaskName)'."
        Start-ScheduledTask -TaskPath $emPath -TaskName $toStart.TaskName
    } else {
        # Fall back to DeviceEnroller.exe
        $enrollerExitCode = Invoke-DeviceEnroller -attempt 1
        if ($enrollerExitCode -ne 0) {
            Write-Log "First DeviceEnroller attempt returned $enrollerExitCode, retrying after delay..."
            Start-Sleep 10
            $enrollerExitCode = Invoke-DeviceEnroller -attempt 2
        }
    }

    # Wait for enrollment to complete
    Write-Log "Waiting for enrollment to process..."
    Start-Sleep -Seconds 30

    # Comprehensive Event Log Checking
    try {
        $dmLog = "Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin"
        $recentIds = 75, 76, 201, 202, 205, 207, 208, 209, 301, 305
        $events = Get-WinEvent -LogName $dmLog -MaxEvents 300 -ErrorAction SilentlyContinue |
                  Where-Object { $_.Id -in $recentIds -and $_.TimeCreated -gt (Get-Date).AddHours(-24) }
        
        if ($events -and $events.Count -gt 0) {
            Write-Log "Found $($events.Count) recent MDM events indicating enrollment activity."
            $enrolled = $true
        }
    } catch {
        Write-Log "Error checking event logs: $_"
        # Fallback with smaller query if the first one fails
        try {
            $events = Get-WinEvent -LogName $dmLog -Oldest -MaxEvents 50 -ErrorAction SilentlyContinue |
                      Where-Object { $_.Id -in $recentIds }
            if ($events -and $events.Count -gt 0) {
                Write-Log "Found $($events.Count) MDM events in fallback query."
                $enrolled = $true
            }
        } catch {
            Write-Log "Fallback event query also failed: $_"
        }
    }
}

# MDM Diagnostics Collection on Failure
if (-not $enrolled) {
    try {
        $diagPath = "$env:ProgramData\IntuneDiagnostics"
        if (-not (Test-Path $diagPath)) { New-Item -Path $diagPath -ItemType Directory -Force | Out-Null }
        
        $cab = Join-Path $diagPath ("MDMDiag_{0}.cab" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Start-Process -FilePath "$env:SystemRoot\System32\mdmdiagnosticstool.exe" `
            -ArgumentList "-area DeviceEnrollment;DeviceProvisioning;Autopilot -cab $cab" -Wait -WindowStyle Hidden
        Write-Log "Captured MDMDiagnostics to $cab"
    } catch {
        Write-Log "MDMDiagnostics failed: $_"
    }
}

# Improved Exit Code Handling
if ($enrolled) {
    $deviceDetails.EnrollmentStatus = "Enrolled"
    Write-Log "Device is successfully enrolled in Intune."
    $exitCode = 0  # Success
} elseif (-not $isEntraJoined) {
    $deviceDetails.EnrollmentStatus = "Not Entra Joined"
    Write-Log "Device is not Entra joined, cannot enroll."
    $exitCode = 1  # Not Entra joined
} elseif (-not (Test-Path "$env:WINDIR\System32\deviceenroller.exe")) {
    $deviceDetails.EnrollmentStatus = "Missing DeviceEnroller"
    Write-Log "DeviceEnroller.exe not found."
    $exitCode = 2  # DeviceEnroller missing
} elseif (-not $userPresent) {
    $deviceDetails.EnrollmentStatus = "Deferred - No User"
    Write-Log "Enrollment deferred until user login."
    $exitCode = 4  # No interactive user
} else {
    $deviceDetails.EnrollmentStatus = "Pending"
    Write-Log "Enrollment attempted but not yet complete."
    $exitCode = 3  # Pending
}

# Surface friendly result to Datto output
Write-Output "DATTO:EnrollmentStatus=$($deviceDetails.EnrollmentStatus);Computer=$($deviceDetails.ComputerName);Serial=$($deviceDetails.SerialNumber)"
exit $exitCode