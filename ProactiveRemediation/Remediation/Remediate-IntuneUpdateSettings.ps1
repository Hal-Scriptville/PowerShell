<# 
  REMEDIATION SCRIPT: Intune WSUS Policy Cleanup
  Purpose: Remove ALL WSUS/Windows Update Group Policy settings to allow Intune management
  This script forcibly removes WSUS policies regardless of their source (GPO/Local Policy)
#>

$ErrorActionPreference = 'Stop'

# Registry paths to clean up - process both parent and child paths
$cleanupPaths = @(
    'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU',
    'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate'
)

# Function to safely remove registry values and keys
function Remove-WSUSRegistry {
    param (
        [string]$RegistryPath
    )
    
    if (-not (Test-Path $RegistryPath)) {
        Write-Output "Path not present: $RegistryPath"
        return $true
    }
    
    try {
        # Get all properties first for logging
        $properties = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue
        $wsusProperties = @()
        
        # List of WSUS-related property names to remove
        $wsusValueNames = @(
            'WUServer', 'WUStatusServer', 'DoNotConnectToWindowsUpdateInternetLocations',
            'ElevateNonAdmins', 'TargetGroup', 'TargetGroupEnabled', 'UseWUServer',
            'AUOptions', 'AutoInstallMinorUpdates', 'DetectionFrequency', 
            'DetectionFrequencyEnabled', 'NoAutoUpdate', 'NoAutoRebootWithLoggedOnUsers',
            'RebootRelaunchTimeout', 'RebootWarningTimeout', 'RescheduleWaitTime',
            'ScheduledInstallDay', 'ScheduledInstallTime', 'FillEmptyContentUrls',
            'SetProxyBehaviorForUpdateDetection', 'UpdateServiceUrlAlternate',
            'UseUpdateClassPolicySource'
        )
        
        # Check which WSUS properties exist
        foreach ($valueName in $wsusValueNames) {
            if ($null -ne $properties.$valueName) {
                $wsusProperties += "$valueName = $($properties.$valueName)"
            }
        }
        
        if ($wsusProperties.Count -gt 0) {
            Write-Output "Found WSUS properties in ${RegistryPath}: $($wsusProperties -join '; ')"
            
            # Remove individual WSUS properties
            foreach ($valueName in $wsusValueNames) {
                if ($null -ne $properties.$valueName) {
                    try {
                        Remove-ItemProperty -Path $RegistryPath -Name $valueName -Force -ErrorAction Stop
                        Write-Output "Removed property: $RegistryPath\$valueName"
                    }
                    catch {
                        Write-Output "Could not remove property $RegistryPath\$valueName - $($_.Exception.Message)"
                    }
                }
            }
        }
        
        # Check if the key is now empty (only has default properties), if so remove it
        $remainingProperties = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue
        $nonDefaultProps = ($remainingProperties.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }).Name
        
        if (-not $nonDefaultProps -or $nonDefaultProps.Count -eq 0) {
            # Key is empty, remove it entirely
            Remove-Item -Path $RegistryPath -Recurse -Force -ErrorAction Stop
            Write-Output "Removed empty registry key: $RegistryPath"
        }
        
        return $true
    }
    catch {
        Write-Output "ERROR: Failed to process $RegistryPath - $($_.Exception.Message)"
        return $false
    }
}

# Function to reset Windows Update components
function Reset-WindowsUpdateComponents {
    try {
        Write-Output "Resetting Windows Update components..."
        
        # Stop Windows Update services
        $services = @('wuauserv', 'cryptsvc', 'bits', 'msiserver')
        foreach ($service in $services) {
            try {
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                Write-Output "Stopped service: $service"
            }
            catch {
                Write-Output "Could not stop service $service (may not be running): $($_.Exception.Message)"
            }
        }
        
        # Clear Windows Update cache
        $cacheLocations = @(
            "$env:SystemRoot\SoftwareDistribution\Download",
            "$env:SystemRoot\System32\catroot2"
        )
        
        foreach ($location in $cacheLocations) {
            if (Test-Path $location) {
                try {
                    Remove-Item -Path "$location\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Output "Cleared cache: $location"
                }
                catch {
                    Write-Output "Could not clear cache $location (files may be in use) - $($_.Exception.Message)"
                }
            }
        }
        
        # Restart Windows Update services
        foreach ($service in $services) {
            try {
                Start-Service -Name $service -ErrorAction SilentlyContinue
                Write-Output "Started service: $service"
            }
            catch {
                Write-Output "Could not start service $service - $($_.Exception.Message)"
            }
        }
        
        return $true
    }
    catch {
        Write-Output "WARNING: Error during Windows Update component reset - $($_.Exception.Message)"
        return $false
    }
}

# Main remediation logic
Write-Output "Starting WSUS policy cleanup for Intune management transition..."

$allSuccess = $true

# Remove WSUS registry policies
foreach ($path in $cleanupPaths) {
    $result = Remove-WSUSRegistry -RegistryPath $path
    if (-not $result) {
        $allSuccess = $false
    }
}

# Reset Windows Update components to ensure clean state
$resetResult = Reset-WindowsUpdateComponents

# Verify cleanup was successful
Write-Output "`nVerifying cleanup..."
$verificationPaths = @(
    'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate',
    'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
)

$remainingPolicies = @()
foreach ($path in $verificationPaths) {
    if (Test-Path $path) {
        $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        $nonPSProps = ($props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }).Name
        if ($nonPSProps) {
            $remainingPolicies += "$path : $($nonPSProps -join ', ')"
        }
    }
}

if ($remainingPolicies.Count -eq 0) {
    Write-Output "SUCCESS: All WSUS policies removed. Device is now ready for Intune Windows Update management."
    Write-Output "INFO: It may take up to 24 hours for Intune policies to fully take effect."
} else {
    Write-Output "WARNING: Some policies may still remain: $($remainingPolicies -join '; ')"
    $allSuccess = $false
}

# Force a Group Policy refresh to clear any cached policy
try {
    Write-Output "Refreshing Group Policy..."
    & gpupdate /force /wait:0
} catch {
    Write-Output "Could not refresh Group Policy - $($_.Exception.Message)"
}

if ($allSuccess) {
    Write-Output "Remediation completed successfully."
    exit 0
} else {
    Write-Output "Remediation completed with warnings. Manual verification may be required."
    exit 1
}
