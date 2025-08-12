# Optimized Remediation Script for Windows Update Policy Conflicts
# Removes conflicting GPO/WSUS registry entries to allow Intune Windows Update management
# Optimized for speed to avoid Proactive Remediation timeouts

#Requires -RunAsAdministrator

try {
    # Set execution timeout tracking
    $ScriptStartTime = Get-Date
    $MaxExecutionMinutes = 25  # Leave 5 minutes buffer before 30-min timeout
    
    $RemediationApplied = $false
    $RemovedEntries = @()
    
    Write-Output "Starting optimized Windows Update policy conflict remediation..."
    Write-Output "Script start time: $ScriptStartTime"
    
    # Define registry paths to clean
    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\WindowsUpdate",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    )
    
    # Define problematic registry values to remove
    $ProblematicValues = @(
        "WUServer",
        "WUStatusServer", 
        "TargetGroup",
        "TargetGroupEnabled",
        "AcceptTrustedPublisherCerts",
        "ElevateNonAdmins",
        "AUOptions",
        "NoAutoUpdate",
        "DisableDualScan"
    )
    
    # Quick function to check if we're approaching timeout
    function Test-TimeoutApproaching {
        $ElapsedMinutes = ((Get-Date) - $ScriptStartTime).TotalMinutes
        return $ElapsedMinutes -gt $MaxExecutionMinutes
    }
    
    # Optimized service stop - don't wait for full stop
    Write-Output "Stopping Windows Update service (non-blocking)..."
    try {
        Stop-Service -Name "wuauserv" -Force -NoWait -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2  # Brief pause instead of waiting for full stop
    }
    catch {
        Write-Warning "Service stop warning: $($_.Exception.Message)"
    }
    
    # Clean main registry paths - optimized loop
    foreach ($Path in $RegistryPaths) {
        if (Test-TimeoutApproaching) {
            Write-Warning "Approaching timeout, stopping registry cleanup early"
            break
        }
        
        if (Test-Path $Path) {
            Write-Output "Processing registry path: $Path"
            
            # Get all properties at once for efficiency
            try {
                $RegItem = Get-Item -Path $Path -ErrorAction SilentlyContinue
                if ($RegItem) {
                    foreach ($Value in $ProblematicValues) {
                        try {
                            if ($RegItem.GetValue($Value, $null) -ne $null) {
                                Write-Output "Removing: $Path\$Value"
                                Remove-ItemProperty -Path $Path -Name $Value -Force -ErrorAction Stop
                                $RemovedEntries += "$Path\$Value"
                                $RemediationApplied = $true
                            }
                        }
                        catch {
                            Write-Warning "Failed to remove $Path\$Value : $($_.Exception.Message)"
                        }
                    }
                }
            }
            catch {
                Write-Warning "Failed to access $Path : $($_.Exception.Message)"
            }
        }
    }
    
    # Clean AU (Automatic Updates) specific entries - optimized
    if (-not (Test-TimeoutApproaching)) {
        $AUPath = "HKLM:\SOFTWARE\Microsoft\Windows\WindowsUpdate\AU"
        if (Test-Path $AUPath) {
            Write-Output "Processing AU registry path: $AUPath"
            
            $AUValues = @("UseWUServer", "NoAutoUpdate", "AUOptions", "ScheduledInstallDay", "ScheduledInstallTime")
            
            try {
                $AUItem = Get-Item -Path $AUPath -ErrorAction SilentlyContinue
                if ($AUItem) {
                    foreach ($Value in $AUValues) {
                        try {
                            if ($AUItem.GetValue($Value, $null) -ne $null) {
                                Write-Output "Removing AU value: $AUPath\$Value"
                                Remove-ItemProperty -Path $AUPath -Name $Value -Force -ErrorAction Stop
                                $RemovedEntries += "$AUPath\$Value"
                                $RemediationApplied = $true
                            }
                        }
                        catch {
                            Write-Warning "Failed to remove $AUPath\$Value : $($_.Exception.Message)"
                        }
                    }
                }
            }
            catch {
                Write-Warning "Failed to access AU path: $($_.Exception.Message)"
            }
        }
    }
    
    # Remove empty registry keys if they exist and are empty - quick check only
    if (-not (Test-TimeoutApproaching)) {
        $PathsToCleanup = @(
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
            "HKLM:\SOFTWARE\Microsoft\Windows\WindowsUpdate\AU"
        )
        
        foreach ($CleanupPath in $PathsToCleanup) {
            if (Test-Path $CleanupPath) {
                try {
                    $SubKeys = @(Get-ChildItem -Path $CleanupPath -ErrorAction SilentlyContinue)
                    $Properties = Get-ItemProperty -Path $CleanupPath -ErrorAction SilentlyContinue
                    
                    # Quick check - if no subkeys and minimal properties, remove
                    if ($SubKeys.Count -eq 0 -and $Properties.PSObject.Properties.Name.Count -le 4) {
                        Write-Output "Removing empty registry key: $CleanupPath"
                        Remove-Item -Path $CleanupPath -Force -ErrorAction Stop
                        $RemovedEntries += "$CleanupPath (empty key)"
                        $RemediationApplied = $true
                    }
                }
                catch {
                    Write-Warning "Failed to remove empty key $CleanupPath : $($_.Exception.Message)"
                }
            }
        }
    }
    
    # OPTIMIZED: Skip gpupdate and complex service restarts if approaching timeout
    if ($RemediationApplied) {
        if (Test-TimeoutApproaching) {
            Write-Output "Timeout approaching - skipping GP refresh and service restarts"
            Write-Output "Registry changes applied. Device restart recommended for full effect."
        }
        else {
            # LIGHTWEIGHT service restart only
            Write-Output "Performing lightweight service restart..."
            try {
                # Just restart Windows Update service, skip others to save time
                Restart-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                Write-Output "Windows Update service restarted"
            }
            catch {
                Write-Warning "Service restart had issues: $($_.Exception.Message)"
            }
            
            # REMOVED: gpupdate /force (major timeout cause)
            # REMOVED: Complex service stop/start sequence
            Write-Output "Note: Group Policy refresh skipped to avoid timeout. Changes will apply on next GP refresh or reboot."
        }
    }
    else {
        # Always ensure service is running
        try {
            Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Could not start Windows Update service: $($_.Exception.Message)"
        }
    }
    
    # Calculate execution time
    $ExecutionTime = ((Get-Date) - $ScriptStartTime).TotalMinutes
    Write-Output "Script execution time: $([math]::Round($ExecutionTime, 2)) minutes"
    
    # Log results
    if ($RemediationApplied) {
        Write-Output "REMEDIATION SUCCESSFUL: Removed $($RemovedEntries.Count) conflicting entries:"
        $RemovedEntries | ForEach-Object { Write-Output "  - $_" }
        Write-Output "Windows Update policy conflicts have been resolved."
        Write-Output "Intune can now manage updates. A device restart is recommended."
        exit 0
    }
    else {
        Write-Output "REMEDIATION RESULT: No conflicting entries found to remove."
        exit 0
    }
}
catch {
    # Calculate execution time even on error
    $ExecutionTime = ((Get-Date) - $ScriptStartTime).TotalMinutes
    Write-Output "Script execution time at error: $([math]::Round($ExecutionTime, 2)) minutes"
    
    # Ensure Windows Update service is running even if script fails
    try {
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Could not start Windows Update service after error"
    }
    
    Write-Error "Remediation script failed: $($_.Exception.Message)"
    exit 1
}
