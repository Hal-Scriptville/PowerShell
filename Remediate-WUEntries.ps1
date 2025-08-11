# Remediation Script for Windows Update Policy Conflicts
# Removes conflicting GPO/WSUS registry entries to allow Intune Windows Update management

try {
    $RemediationApplied = $false
    $RemovedEntries = @()
    
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
    
    Write-Output "Starting Windows Update policy conflict remediation..."
    
    # Stop Windows Update service before making changes
    Write-Output "Stopping Windows Update service..."
    Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
    
    # Clean main registry paths
    foreach ($Path in $RegistryPaths) {
        if (Test-Path $Path) {
            Write-Output "Processing registry path: $Path"
            
            foreach ($Value in $ProblematicValues) {
                try {
                    $RegProperty = Get-ItemProperty -Path $Path -Name $Value -ErrorAction SilentlyContinue
                    if ($RegProperty) {
                        Write-Output "Removing conflicting value: $Path\$Value"
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
    
    # Clean AU (Automatic Updates) specific entries
    $AUPath = "HKLM:\SOFTWARE\Microsoft\Windows\WindowsUpdate\AU"
    if (Test-Path $AUPath) {
        Write-Output "Processing AU registry path: $AUPath"
        
        $AUValues = @("UseWUServer", "NoAutoUpdate", "AUOptions", "ScheduledInstallDay", "ScheduledInstallTime")
        foreach ($Value in $AUValues) {
            try {
                $RegProperty = Get-ItemProperty -Path $AUPath -Name $Value -ErrorAction SilentlyContinue
                if ($RegProperty) {
                    Write-Output "Removing AU conflicting value: $AUPath\$Value"
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
    
    # Remove empty registry keys if they exist and are empty
    $PathsToCleanup = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate",
        "HKLM:\SOFTWARE\Microsoft\Windows\WindowsUpdate\AU"
    )
    
    foreach ($CleanupPath in $PathsToCleanup) {
        if (Test-Path $CleanupPath) {
            $SubKeys = Get-ChildItem -Path $CleanupPath -ErrorAction SilentlyContinue
            $Properties = Get-ItemProperty -Path $CleanupPath -ErrorAction SilentlyContinue
            
            # If no subkeys and no properties (except default PS properties), remove the key
            if ((-not $SubKeys) -and ($Properties.PSObject.Properties.Name.Count -le 4)) {
                try {
                    Write-Output "Removing empty registry key: $CleanupPath"
                    Remove-Item -Path $CleanupPath -Force -ErrorAction Stop
                    $RemovedEntries += "$CleanupPath (empty key)"
                    $RemediationApplied = $true
                }
                catch {
                    Write-Warning "Failed to remove empty key $CleanupPath : $($_.Exception.Message)"
                }
            }
        }
    }
    
    # Force Group Policy refresh to clear cached policies
    if ($RemediationApplied) {
        Write-Output "Forcing Group Policy refresh..."
        & gpupdate /force /wait:0 2>&1 | Out-String | Write-Output
        
        # Restart Windows Update service
        Write-Output "Restarting Windows Update service..."
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        
        # Reset Windows Update components
        Write-Output "Resetting Windows Update components..."
        & net stop wuauserv 2>&1 | Out-Null
        & net stop cryptSvc 2>&1 | Out-Null  
        & net stop bits 2>&1 | Out-Null
        & net stop msiserver 2>&1 | Out-Null
        
        Start-Sleep -Seconds 2
        
        & net start wuauserv 2>&1 | Out-Null
        & net start cryptSvc 2>&1 | Out-Null
        & net start bits 2>&1 | Out-Null
        & net start msiserver 2>&1 | Out-Null
    }
    else {
        # Start the service back up even if no changes were made
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    }
    
    # Log results
    if ($RemediationApplied) {
        Write-Output "REMEDIATION SUCCESSFUL: Removed $($RemovedEntries.Count) conflicting entries:"
        $RemovedEntries | ForEach-Object { Write-Output "  - $_" }
        Write-Output "Windows Update policy conflicts have been resolved. Intune can now manage updates."
        Write-Output "A device restart may be required for all changes to take effect."
        exit 0
    }
    else {
        Write-Output "REMEDIATION RESULT: No conflicting entries found to remove."
        exit 0
    }
}
catch {
    # Ensure Windows Update service is running even if script fails
    Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    
    Write-Error "Remediation script failed: $($_.Exception.Message)"
    exit 1
}
