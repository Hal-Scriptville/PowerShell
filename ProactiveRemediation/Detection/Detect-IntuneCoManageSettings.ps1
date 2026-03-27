# Intune Proactive Remediation - Detection Script
# Purpose: Detect co-management Windows Update workload issues that prevent Windows 10 to 11 upgrades
# Target: Co-managed devices with Windows Update workload set to Pilot/Intune

$exitCode = 0
$issues = @()

try {
    # Check if device is co-managed
    $coMgmtPath = "HKLM:\SOFTWARE\Microsoft\DeviceManageabilityCSP\Provider\MS DM Server\FirstSyncStatus"
    # if (-not (Test-Path $coMgmtPath)) {
    #    Write-Output "Device is not co-managed. Skipping remediation."
    #    exit 0
    # }

    # Check Windows Update workload capability (bit 3 = Windows Update Policies)
    $capabilityPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
    $capability = Get-ItemProperty -Path $capabilityPath -Name "CoMgmtCapability" -ErrorAction SilentlyContinue
    
    if ($capability -and ($capability.CoMgmtCapability -band 4)) {
        Write-Host "Windows Update workload is assigned to Intune (capability: $($capability.CoMgmtCapability))"
        
        # Issue 1: Check DisableDualScan setting (should be 0 when workload is moved to Intune)
        $dualscanPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $disableDualScan = Get-ItemProperty -Path $dualscanPath -Name "DisableDualScan" -ErrorAction SilentlyContinue
        
        if ($disableDualScan -and $disableDualScan.DisableDualScan -eq 1) {
            $issues += "DisableDualScan is set to 1 (should be 0 for Intune workload)"
        }

        # Issue 2: Check for tattooed NoAutoUpdate policy
        $noAutoUpdatePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        $noAutoUpdate = Get-ItemProperty -Path $noAutoUpdatePath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
        
        if ($noAutoUpdate -and $noAutoUpdate.NoAutoUpdate -eq 1) {
            $issues += "NoAutoUpdate is enabled (will disable automatic updates)"
        }

        # Issue 3: Check Windows 11 Scan Source policies (if Windows 11)
        $osVersion = [System.Environment]::OSVersion.Version
        $buildNumber = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
        
        if ($buildNumber -ge 22000) { # Windows 11
            Write-Host "Windows 11 detected - checking Scan Source policies"
            
            # Check if UseUpdateClassPolicySource is properly configured
            $useUpdateClassPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
            $useUpdateClass = Get-ItemProperty -Path $useUpdateClassPath -Name "UseUpdateClassPolicySource" -ErrorAction SilentlyContinue
            
            if (-not $useUpdateClass -or $useUpdateClass.UseUpdateClassPolicySource -ne 1) {
                $issues += "UseUpdateClassPolicySource is not properly configured for Windows 11"
            }

            # Check Scan Source policies - these should be 0 when workload is moved to Intune
            $scanSourcePolicies = @(
                "PolicyDrivenUpdateSourceForFeatureUpdates",
                "PolicyDrivenUpdateSourceForQualityUpdates", 
                "PolicyDrivenUpdateSourceForDriverUpdates",
                "PolicyDrivenUpdateSourceForOtherUpdates"
            )

            foreach ($policy in $scanSourcePolicies) {
                $value = Get-ItemProperty -Path $dualscanPath -Name $policy -ErrorAction SilentlyContinue
                if ($value -and $value.$policy -ne 0) {
                    $issues += "$policy is set to $($value.$policy) (should be 0 for cloud updates)"
                }
            }
        }

        # Issue 4: Check for conflicting WSUS server configuration when workload is moved to Intune
        $wsusServer = Get-ItemProperty -Path $noAutoUpdatePath -Name "WUServer" -ErrorAction SilentlyContinue
        $useWUServer = Get-ItemProperty -Path $noAutoUpdatePath -Name "UseWUServer" -ErrorAction SilentlyContinue
        
        if ($wsusServer -and $useWUServer -and $useWUServer.UseWUServer -eq 1) {
            # This might be intentional for 3rd party updates, but flag for review
            $issues += "WSUS server configuration detected - verify this is intentional for 3rd party updates only"
        }

        # Issue 5: Check for Windows Update service disabled
        $wuauserv = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        if ($wuauserv -and $wuauserv.StartType -eq "Disabled") {
            $issues += "Windows Update service (wuauserv) is disabled"
        }

        # Issue 6: Check for Feature Update deferral that might prevent Win11 upgrade
        $featureUpdateDefer = Get-ItemProperty -Path $dualscanPath -Name "DeferFeatureUpdates" -ErrorAction SilentlyContinue
        $deferDays = Get-ItemProperty -Path $dualscanPath -Name "DeferFeatureUpdatesPeriodInDays" -ErrorAction SilentlyContinue
        
        if ($featureUpdateDefer -and $featureUpdateDefer.DeferFeatureUpdates -eq 1 -and $deferDays -and $deferDays.DeferFeatureUpdatesPeriodInDays -gt 365) {
            $issues += "Feature Updates deferred for more than 365 days (may prevent Windows 11 upgrade)"
        }

    } else {
        Write-Host "Windows Update workload is not assigned to Intune - will remediate"
        exit 1
    }

    # Report findings
    if ($issues.Count -gt 0) {
        Write-Host "Found $($issues.Count) issues that may prevent Windows 10 to 11 upgrade:"
        foreach ($issue in $issues) {
            Write-Host "- $issue"
        }
        $exitCode = 1
    } else {
        Write-Host "No Windows Update workload issues detected"
        $exitCode = 0
    }

} catch {
    Write-Error "Error during detection: $($_.Exception.Message)"
    $exitCode = 1
}


exit $exitCode

