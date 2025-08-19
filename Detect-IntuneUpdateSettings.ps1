<# 
  DETECTION SCRIPT: Intune WSUS Policy Cleanup
  Purpose: Detect any WSUS/Windows Update Group Policy settings that would conflict with Intune management
  Logic: If ANY WSUS-related policy registry values exist -> Non-compliant (needs cleanup)
  Exit 0 = compliant (Intune can manage), 1 = non-compliant (WSUS policies present)
#>

$ErrorActionPreference = 'Stop'

# Registry locations where Group Policy WSUS settings are stored
$wsusRegistryPaths = @(
    @{
        Path = 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate'
        Values = @(
            'WUServer', 'WUStatusServer', 'DoNotConnectToWindowsUpdateInternetLocations', 
            'ElevateNonAdmins', 'TargetGroup', 'TargetGroupEnabled', 'FillEmptyContentUrls',
            'SetProxyBehaviorForUpdateDetection', 'UpdateServiceUrlAlternate', 'UseUpdateClassPolicySource'
        )
    },
    @{
        Path = 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
        Values = @(
            'UseWUServer', 'AUOptions', 'AutoInstallMinorUpdates', 'DetectionFrequency', 
            'DetectionFrequencyEnabled', 'NoAutoUpdate', 'NoAutoRebootWithLoggedOnUsers', 
            'RebootRelaunchTimeout', 'RebootWarningTimeout', 'RescheduleWaitTime', 
            'ScheduledInstallDay', 'ScheduledInstallTime'
        )
    }
)

# Function to check for policy values
function Get-WSUSPolicyValues {
    $foundPolicies = @()
    
    foreach ($location in $wsusRegistryPaths) {
        if (Test-Path $location.Path) {
            try {
                $regProps = Get-ItemProperty -Path $location.Path -ErrorAction SilentlyContinue
                
                foreach ($valueName in $location.Values) {
                    if ($null -ne $regProps.$valueName) {
                        $foundPolicies += [PSCustomObject]@{
                            Path = $location.Path
                            Name = $valueName
                            Value = $regProps.$valueName
                        }
                    }
                }
            }
            catch {
                Write-Output "INFO: Could not read registry path $($location.Path): $($_.Exception.Message)"
            }
        }
    }
    
    return $foundPolicies
}

# Check for Windows Update policy values
$detectedPolicies = Get-WSUSPolicyValues

if ($detectedPolicies.Count -eq 0) {
    Write-Output "COMPLIANT: No WSUS/Windows Update Group Policy settings found. Device ready for Intune management."
    exit 0
}

# If we found policies, device is non-compliant
$policyList = $detectedPolicies | ForEach-Object { "$($_.Path)\$($_.Name) = $($_.Value)" }
$policyString = $policyList -join '; '

Write-Output "NON-COMPLIANT: Found $($detectedPolicies.Count) WSUS/Windows Update policy settings that will interfere with Intune management. Policies: $policyString"

# Additional check: Verify if device is Azure AD joined (good indicator it should use Intune)
try {
    $deviceInfo = Get-CimInstance -Class Win32_ComputerSystem
    if ($deviceInfo.PartOfDomain -and $deviceInfo.Domain -notlike "*.local") {
        Write-Output "INFO: Device appears to be Azure AD joined ($($deviceInfo.Domain)) - should use Intune for updates."
    }
}
catch {
    # Don't fail detection if we can't get this info
}

exit 1
