# Intune Proactive Remediation - Remediation Script
# Purpose: Fix co-management Windows Update workload issues that prevent Windows 10 to 11 upgrades
# Target: Co-managed devices with Windows Update workload set to Pilot/Intune

$exitCode = 0
$remediationActions = @()

try {
    # Verify device is co-managed and workload is assigned to Intune
    $coMgmtPath = "HKLM:\SOFTWARE\Microsoft\DeviceManageabilityCSP\Provider\MS DM Server\FirstSyncStatus"
    if (-not (Test-Path $coMgmtPath)) {
        Write-Output "Device is not co-managed. Exiting."
        exit 0
    }

    $capabilityPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
    $capability = Get-ItemProperty -Path $capabilityPath -Name "CoMgmtCapability" -ErrorAction SilentlyContinue
    
    if (-not $capability -or -not ($capability.CoMgmtCapability -band 4)) {
        Write-Output "Windows Update workload is not assigned to Intune. Exiting."
        exit 0
    }

    Write-Host "Starting remediation for co-managed device with Windows Update workload assigned to Intune"

    # Registry paths
    $dualscanPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    # Ensure registry paths exist
    if (-not (Test-Path $dualscanPath)) {
        New-Item -Path $dualscanPath -Force | Out-Null
    }
    if (-not (Test-Path $auPath)) {
        New-Item -Path $auPath -Force | Out-Null
    }

    # Remediation 1: Fix DisableDualScan setting
    $disableDualScan = Get-ItemProperty -Path $dualscanPath -Name "DisableDualScan" -ErrorAction SilentlyContinue
    if ($disableDualScan -and $disableDualScan.DisableDualScan -eq 1) {
        Set-ItemProperty -Path $dualscanPath -Name "DisableDualScan" -Value 0 -Type DWord
        $remediationActions += "Set DisableDualScan to 0 (enabled dual scan for Intune workload)"
    }

    # Remediation 2: Remove tattooed NoAutoUpdate policy
    $noAutoUpdate = Get-ItemProperty -Path $auPath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
    if ($noAutoUpdate -and $noAutoUpdate.NoAutoUpdate -eq 1) {
        Remove-ItemProperty -Path $auPath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
        $remediationActions += "Removed NoAutoUpdate registry setting"
    }

    # Get OS version info
    $buildNumber = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
    
    if ($buildNumber -ge 22000) { # Windows 11
        Write-Host "Applying Windows 11 specific remediations"
        
        # Remediation 3: Configure UseUpdateClassPolicySource for Windows 11
        Set-ItemProperty -Path $auPath -Name "UseUpdateClassPolicySource" -Value 1 -Type DWord
        $remediationActions += "Set UseUpdateClassPolicySource to 1 for Windows 11"

        # Remediation 4: Configure Scan Source policies for cloud updates
        $scanSourcePolicies = @(
            "PolicyDrivenUpdateSourceForFeatureUpdates",
            "PolicyDrivenUpdateSourceForQualityUpdates", 
            "PolicyDrivenUpdateSourceForDriverUpdates",
            "PolicyDrivenUpdateSourceForOtherUpdates"
        )

        foreach ($policy in $scanSourcePolicies) {
            $currentValue = Get-ItemProperty -Path $dualscanPath -Name $policy -ErrorAction SilentlyContinue
            if (-not $currentValue -or $currentValue.$policy -ne 0) {
                Set-ItemProperty -Path $dualscanPath -Name $policy -Value 0 -Type DWord
                $remediationActions += "Set $policy to 0 (cloud source)"
            }
        }

        # Remediation 5: Remove any Group Policy tattooed scan source policies
        $gpRegPath = "C:\Windows\System32\GroupPolicy\Machine\Registry.pol"
        if (Test-Path $gpRegPath) {
            try {
                # Force a group policy refresh to clear any local computer policies
                & gpupdate /force /target:computer
                $remediationActions += "Forced Group Policy refresh to clear local computer policies"
            } catch {
                Write-Warning "Could not force Group Policy refresh: $($_.Exception.Message)"
            }
        }
    } else { # Windows 10
        Write-Host "Applying Windows 10 specific remediations"
        
        # For Windows 10, ensure dual scan is properly enabled when workload is moved to Intune
        # The DisableDualScan should already be set to 0 above
    }

    # Remediation 6: Ensure Windows Update service is properly configured
    $wuauserv = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    if ($wuauserv) {
        if ($wuauserv.StartType -eq "Disabled") {
            Set-Service -Name "wuauserv" -StartupType Manual
            $remediationActions += "Changed Windows Update service startup type from Disabled to Manual"
        }
        
        if ($wuauserv.Status -ne "Running") {
            try {
                Start-Service -Name "wuauserv" -ErrorAction Stop
                $remediationActions += "Started Windows Update service"
            } catch {
                Write-Warning "Could not start Windows Update service: $($_.Exception.Message)"
            }
        }
    }

    # Remediation 7: Reset Windows Update components if needed
    if ($remediationActions.Count -gt 0) {
        try {
            # Stop Windows Update services
            Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
            Stop-Service -Name "cryptSvc" -Force -ErrorAction SilentlyContinue
            Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue
            Stop-Service -Name "msiserver" -Force -ErrorAction SilentlyContinue

            # Clear Windows Update cache
            if (Test-Path "$env:WINDIR\SoftwareDistribution") {
                Remove-Item "$env:WINDIR\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Restart services
            Start-Service -Name "cryptSvc" -ErrorAction SilentlyContinue
            Start-Service -Name "bits" -ErrorAction SilentlyContinue
            Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
            
            $remediationActions += "Reset Windows Update components and cache"
        } catch {
            Write-Warning "Could not reset Windows Update components: $($_.Exception.Message)"
        }
    }

    # Remediation 8: Trigger Configuration Manager client actions to re-evaluate policies
    try {
        $ccmClient = Get-WmiObject -Namespace "root\ccm" -Class "SMS_Client" -ErrorAction SilentlyContinue
        if ($ccmClient) {
            # Trigger co-management policy evaluation
            Invoke-WmiMethod -Namespace "root\ccm" -Class "SMS_Client" -Name "TriggerSchedule" -ArgumentList "{00000000-0000-0000-0000-000000000032}" -ErrorAction SilentlyContinue
            # Trigger Windows Update policy evaluation  
            Invoke-WmiMethod -Namespace "root\ccm" -Class "SMS_Client" -Name "TriggerSchedule" -ArgumentList "{00000000-0000-0000-0000-000000000113}" -ErrorAction SilentlyContinue
            $remediationActions += "Triggered Configuration Manager policy evaluation"
        }
    } catch {
        Write-Warning "Could not trigger Configuration Manager policy evaluation: $($_.Exception.Message)"
    }

    # Remediation 9: Force Windows Update detection cycle
    try {
        $updateSession = New-Object -ComObject "Microsoft.Update.Session"
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $updateSearcher.Online = $true
        $searchResult = $updateSearcher.Search("IsInstalled=0")
        $remediationActions += "Forced Windows Update detection cycle"
    } catch {
        Write-Warning "Could not force Windows Update detection: $($_.Exception.Message)"
    }

    # Report remediation actions taken
    if ($remediationActions.Count -gt 0) {
        Write-Host "Remediation completed. Actions taken:"
        foreach ($action in $remediationActions) {
            Write-Host "- $action"
        }
        Write-Host ""
        Write-Host "Recommendations:"
        Write-Host "1. Monitor Windows Update logs for proper functionality"
        Write-Host "2. Verify Windows 11 upgrade eligibility in Windows Update settings"
        Write-Host "3. Check Intune Windows Update policies are properly targeted"
        Write-Host "4. Consider using Windows Update for Business deployment service for better control"
        $exitCode = 0
    } else {
        Write-Host "No remediation actions were needed"
        $exitCode = 0
    }

} catch {
    Write-Error "Error during remediation: $($_.Exception.Message)"
    $exitCode = 1
}

exit $exitCode
