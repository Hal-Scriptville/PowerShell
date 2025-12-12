<#
.SYNOPSIS
    Automated Intune enrollment script for Hybrid Azure AD joined devices
.DESCRIPTION
    This script checks if a device is Hybrid Azure AD joined (both domain-joined and Azure AD joined)
    and triggers Intune MDM enrollment. Adapted from Entra-joined enrollment script.
    It includes robust error handling, diagnostics, and logging features.
.NOTES
    Version: 1.0
    Created: December 12, 2025
    Based on: Intune-AutoEnrollment.ps1 (Entra-joined version)
    Target: Hybrid Azure AD joined devices
#>

# Script Configuration
$VerbosePreference = 'Continue'
$LogPath = "$env:ProgramData\IntuneEnrollment"
$LogFile = "$LogPath\HybridEnrollmentLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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
        JoinType = "Unknown"
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

# Parse dsregcmd output for specific value
function Get-DsRegValue {
    param(
        [string[]]$DsRegOutput,
        [string]$Key
    )
    $line = $DsRegOutput | Where-Object { $_ -match "^\s*$Key\s*:" }
    if ($line) {
        return ($line -split ":\s*", 2)[1].Trim()
    }
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
Write-Log "=========================================="
Write-Log "Starting Hybrid Azure AD Intune enrollment script..."
Write-Log "=========================================="

$deviceDetails = Get-DeviceDetails
Write-Log "Computer: $($deviceDetails.ComputerName)"
Write-Log "Serial: $($deviceDetails.SerialNumber)"

# Get dsregcmd output
try {
    $dsregCmd = dsregcmd /status
} catch {
    Write-Log "ERROR: Failed to run dsregcmd: $_"
    exit 1
}

# Parse join status
$azureAdJoined = Get-DsRegValue -DsRegOutput $dsregCmd -Key "AzureAdJoined"
$domainJoined = Get-DsRegValue -DsRegOutput $dsregCmd -Key "DomainJoined"
$tenantId = Get-DsRegValue -DsRegOutput $dsregCmd -Key "TenantId"
$deviceId = Get-DsRegValue -DsRegOutput $dsregCmd -Key "DeviceId"
$tenantName = Get-DsRegValue -DsRegOutput $dsregCmd -Key "TenantName"

Write-Log "Join Status:"
Write-Log "  AzureAdJoined: $azureAdJoined"
Write-Log "  DomainJoined: $domainJoined"
Write-Log "  TenantId: $tenantId"
Write-Log "  TenantName: $tenantName"
Write-Log "  DeviceId: $deviceId"

# Check if device is Hybrid Azure AD joined
$isHybridJoined = ($azureAdJoined -eq "YES") -and ($domainJoined -eq "YES")

if ($isHybridJoined) {
    $deviceDetails.JoinType = "Hybrid Azure AD Joined"
    Write-Log "Device is Hybrid Azure AD joined, proceeding with enrollment."
} elseif ($domainJoined -eq "YES" -and $azureAdJoined -ne "YES") {
    $deviceDetails.JoinType = "Domain Joined Only"
    Write-Log "ERROR: Device is domain-joined but NOT Azure AD joined."
    Write-Log "Hybrid join may not be complete. Check Entra Connect sync and SCP configuration."

    # Additional diagnostics for hybrid join issues
    $workplaceJoined = Get-DsRegValue -DsRegOutput $dsregCmd -Key "WorkplaceJoined"
    Write-Log "  WorkplaceJoined: $workplaceJoined"

    # Check for pending registration
    $dsregCmd | Where-Object { $_ -match "ngc|KeyId|KeySignTest" } | ForEach-Object {
        Write-Log "  $_"
    }

    exit 1
} else {
    $deviceDetails.JoinType = "Not Properly Joined"
    Write-Log "ERROR: Device is not properly joined (AzureAD: $azureAdJoined, Domain: $domainJoined)"
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
$userPresent = $false

# Architecture-Agnostic Registry Operations
$base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,
                                                  [Microsoft.Win32.RegistryView]::Registry64)
$enrollKey = $base.OpenSubKey("SOFTWARE\Microsoft\Enrollments")

if ($enrollKey) {
    foreach ($sub in $enrollKey.GetSubKeyNames()) {
        if ($sub -match '^\{[0-9A-Fa-f-]+\}$') {
            $subKey = $enrollKey.OpenSubKey($sub)
            $prov = $subKey.GetValue('ProviderID', $null)
            if ($prov -eq 'MS DM Server') {
                $alreadyEnrolled = $true
                $upn = $subKey.GetValue('UPN', 'Unknown')
                Write-Log "Device is already enrolled in Intune (UPN: $upn)"
                break
            }
        }
    }
}

if ($alreadyEnrolled) {
    $enrolled = $true
    $deviceDetails.EnrollmentStatus = "Already Enrolled"
} else {
    Write-Log "Device is not currently enrolled in Intune. Attempting enrollment..."

    # Check for interactive user
    $userPresent = [bool](Get-LoggedOnUserUpn)
    $loggedOnUser = Get-LoggedOnUserUpn
    Write-Log "Interactive user present: $userPresent"
    if ($loggedOnUser) {
        Write-Log "Logged on user: $loggedOnUser"
    }

    if (-not $userPresent) {
        Write-Log "WARNING: No interactive user detected; enrollment may defer until next sign-in."
    }

    # Hardened MDM Policy Write
    $mdmKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
    try {
        if (-not (Test-Path $mdmKey)) {
            New-Item -Path $mdmKey -Force -ErrorAction Stop | Out-Null
            Write-Log "Created MDM policy key"
        }

        New-ItemProperty -Path $mdmKey -Name 'AutoEnrollMDM' -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $mdmKey -Name 'UseAADCredentialType' -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null

        $ae = (Get-ItemProperty $mdmKey -ErrorAction Stop).AutoEnrollMDM
        $ct = (Get-ItemProperty $mdmKey -ErrorAction Stop).UseAADCredentialType

        Write-Log "MDM Policy values - AutoEnrollMDM: $ae, UseAADCredentialType: $ct"

        if ($ae -ne 1 -or $ct -ne 1) {
            Write-Log "ERROR: Policy write failed verification."
            exit 5
        }
        Write-Log "MDM policy keys configured successfully"
    } catch {
        Write-Log "ERROR: Policy write failed: $_"
        exit 5
    }

    # Improved Scheduled Task Discovery
    $emPath = "\Microsoft\Windows\EnterpriseMgmt\"
    $tasks = Get-ScheduledTask -TaskPath $emPath -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -match 'enrollment|PushLaunch|Schedule'
    }

    if ($tasks) {
        $toStart = $tasks | Sort-Object {
            try { [datetime]$_.LastRunTime } catch { [datetime]::MinValue }
        } -Descending | Select-Object -First 1
        Write-Log "Found enrollment task: '$($toStart.TaskName)' - Starting..."
        try {
            Start-ScheduledTask -TaskPath $emPath -TaskName $toStart.TaskName -ErrorAction Stop
            Write-Log "Enrollment task started successfully"
        } catch {
            Write-Log "WARNING: Failed to start scheduled task: $_"
        }
    } else {
        Write-Log "No enrollment scheduled tasks found. Using DeviceEnroller.exe..."

        # Fall back to DeviceEnroller.exe
        $enrollerExitCode = Invoke-DeviceEnroller -attempt 1
        Write-Log "DeviceEnroller attempt 1 exit code: $enrollerExitCode"

        if ($enrollerExitCode -ne 0) {
            Write-Log "First DeviceEnroller attempt returned $enrollerExitCode, retrying after delay..."
            Start-Sleep 10
            $enrollerExitCode = Invoke-DeviceEnroller -attempt 2
            Write-Log "DeviceEnroller attempt 2 exit code: $enrollerExitCode"
        }
    }

    # Wait for enrollment to process
    Write-Log "Waiting 30 seconds for enrollment to process..."
    Start-Sleep -Seconds 30

    # Comprehensive Event Log Checking
    try {
        $dmLog = "Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin"
        $recentIds = 75, 76, 201, 202, 205, 207, 208, 209, 301, 305
        $events = Get-WinEvent -LogName $dmLog -MaxEvents 300 -ErrorAction SilentlyContinue |
                  Where-Object { $_.Id -in $recentIds -and $_.TimeCreated -gt (Get-Date).AddHours(-1) }

        if ($events -and $events.Count -gt 0) {
            Write-Log "Found $($events.Count) recent MDM events indicating enrollment activity:"
            $events | Select-Object -First 5 | ForEach-Object {
                Write-Log "  Event $($_.Id): $($_.Message.Substring(0, [Math]::Min(100, $_.Message.Length)))..."
            }
            $enrolled = $true
        } else {
            Write-Log "No recent MDM enrollment events found in the last hour."
        }
    } catch {
        Write-Log "WARNING: Error checking event logs: $_"
        # Fallback with smaller query if the first one fails
        try {
            $events = Get-WinEvent -LogName $dmLog -MaxEvents 50 -ErrorAction SilentlyContinue |
                      Where-Object { $_.Id -in $recentIds }
            if ($events -and $events.Count -gt 0) {
                Write-Log "Found $($events.Count) MDM events in fallback query."
                $enrolled = $true
            }
        } catch {
            Write-Log "WARNING: Fallback event query also failed: $_"
        }
    }

    # Double-check enrollment status in registry after waiting
    $enrollKey = $base.OpenSubKey("SOFTWARE\Microsoft\Enrollments")
    if ($enrollKey) {
        foreach ($sub in $enrollKey.GetSubKeyNames()) {
            if ($sub -match '^\{[0-9A-Fa-f-]+\}$') {
                $subKey = $enrollKey.OpenSubKey($sub)
                $prov = $subKey.GetValue('ProviderID', $null)
                if ($prov -eq 'MS DM Server') {
                    $enrolled = $true
                    Write-Log "Confirmed: Device is now enrolled in Intune (registry check)"
                    break
                }
            }
        }
    }
}

# MDM Diagnostics Collection on Failure
if (-not $enrolled) {
    Write-Log "Enrollment not confirmed. Collecting MDM diagnostics..."
    try {
        $diagPath = "$env:ProgramData\IntuneDiagnostics"
        if (-not (Test-Path $diagPath)) { New-Item -Path $diagPath -ItemType Directory -Force | Out-Null }

        $cab = Join-Path $diagPath ("MDMDiag_Hybrid_{0}.cab" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $diagTool = "$env:SystemRoot\System32\mdmdiagnosticstool.exe"

        if (Test-Path $diagTool) {
            Start-Process -FilePath $diagTool `
                -ArgumentList "-area DeviceEnrollment;DeviceProvisioning;Autopilot -cab `"$cab`"" -Wait -WindowStyle Hidden
            Write-Log "Captured MDMDiagnostics to $cab"
        } else {
            Write-Log "WARNING: MDMDiagnosticsTool.exe not found"
        }
    } catch {
        Write-Log "WARNING: MDMDiagnostics collection failed: $_"
    }
}

# Improved Exit Code Handling
if ($enrolled -or $alreadyEnrolled) {
    $deviceDetails.EnrollmentStatus = "Enrolled"
    Write-Log "=========================================="
    Write-Log "SUCCESS: Device is enrolled in Intune."
    Write-Log "=========================================="
    $exitCode = 0  # Success
} elseif (-not $isHybridJoined) {
    $deviceDetails.EnrollmentStatus = "Not Hybrid Joined"
    Write-Log "FAILED: Device is not Hybrid Azure AD joined."
    $exitCode = 1  # Not properly joined
} elseif (-not (Test-Path "$env:WINDIR\System32\deviceenroller.exe")) {
    $deviceDetails.EnrollmentStatus = "Missing DeviceEnroller"
    Write-Log "FAILED: DeviceEnroller.exe not found."
    $exitCode = 2  # DeviceEnroller missing
} elseif (-not $userPresent) {
    $deviceDetails.EnrollmentStatus = "Deferred - No User"
    Write-Log "DEFERRED: Enrollment deferred until user login."
    $exitCode = 4  # No interactive user
} else {
    $deviceDetails.EnrollmentStatus = "Pending"
    Write-Log "PENDING: Enrollment attempted but not yet confirmed."
    Write-Log "Device may appear in Intune within the next few minutes."
    Write-Log "Check: https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesMenu/~/allDevices"
    $exitCode = 3  # Pending
}

Write-Log "Log file: $LogFile"

# Output summary for ManageEngine/RMM tools
$output = @"
========================================
HYBRID INTUNE ENROLLMENT SUMMARY
========================================
Computer:         $($deviceDetails.ComputerName)
Serial:           $($deviceDetails.SerialNumber)
Join Type:        $($deviceDetails.JoinType)
Enrollment Status: $($deviceDetails.EnrollmentStatus)
Tenant:           $tenantName
Device ID:        $deviceId
Exit Code:        $exitCode
Log File:         $LogFile
========================================
"@

Write-Output $output
Write-Log "Script completed with exit code: $exitCode"

exit $exitCode
