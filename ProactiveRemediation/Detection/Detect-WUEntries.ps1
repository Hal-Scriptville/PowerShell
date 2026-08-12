# SUPERSEDED 2026-08-12 -- checks HKLM:\SOFTWARE\Microsoft\Windows\WindowsUpdate\AU
# (missing \Policies\) for NoAutoUpdate/AUOptions -- that is NOT the policy-enforcing
# path. Would report clean on a device where those values ARE set under the correct
# HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU path (confirmed live,
# Whitsons 8/12 -- see Detect-WUfBHealth.ps1). Use that instead.

# Detection Script for Windows Update Policy Conflicts
# Checks for conflicting GPO/WSUS registry entries that prevent Intune Windows Update management

try {
    $ConflictFound = $false
    $ConflictingEntries = @()
    
    # Define registry paths to check
    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\WindowsUpdate",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    )
    
    # Define problematic registry values that indicate GPO/WSUS control
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
    
    # Check each registry path
    foreach ($Path in $RegistryPaths) {
        if (Test-Path $Path) {
            Write-Output "Checking registry path: $Path"
            
            # Get all properties in the registry key
            $RegKey = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
            
            if ($RegKey) {
                # Check for problematic values
                foreach ($Value in $ProblematicValues) {
                    if ($RegKey.PSObject.Properties.Name -contains $Value) {
                        $ConflictFound = $true
                        $ConflictingEntries += "$Path\$Value"
                        Write-Output "CONFLICT FOUND: $Path\$Value = $($RegKey.$Value)"
                    }
                }
            }
        }
    }
    
    # Additional check for AU (Automatic Updates) registry entries
    $AUPath = "HKLM:\SOFTWARE\Microsoft\Windows\WindowsUpdate\AU"
    if (Test-Path $AUPath) {
        $AURegKey = Get-ItemProperty -Path $AUPath -ErrorAction SilentlyContinue
        if ($AURegKey) {
            $AUValues = @("UseWUServer", "NoAutoUpdate", "AUOptions", "ScheduledInstallDay", "ScheduledInstallTime")
            foreach ($Value in $AUValues) {
                if ($AURegKey.PSObject.Properties.Name -contains $Value) {
                    $ConflictFound = $true
                    $ConflictingEntries += "$AUPath\$Value"
                    Write-Output "CONFLICT FOUND: $AUPath\$Value = $($AURegKey.$Value)"
                }
            }
        }
    }
    
    # Log results
    if ($ConflictFound) {
        Write-Output "DETECTION RESULT: Conflicts detected. Found $($ConflictingEntries.Count) conflicting entries:"
        $ConflictingEntries | ForEach-Object { Write-Output "  - $_" }
        Write-Output "Remediation required to allow Intune Windows Update management."
        exit 1  # Exit with error code to trigger remediation
    }
    else {
        Write-Output "DETECTION RESULT: No Windows Update policy conflicts found. Intune can manage updates properly."
        exit 0  # Exit success - no remediation needed
    }
}
catch {
    Write-Error "Detection script failed: $($_.Exception.Message)"
    exit 1
}
