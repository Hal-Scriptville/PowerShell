# Detection Script
$basePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\LastOnlineScanTimeForAppCategory"

# Specify the scan threshold in hours (e.g., 24 hours)
$thresholdHours = 24
$thresholdTime = (Get-Date).AddHours(-$thresholdHours)

# Check all subkeys under LastOnlineScanTimeForAppCategory
if (Test-Path $basePath) {
    $recentScanFound = $false

    # Iterate through all subkeys
    Get-ChildItem -Path $basePath | ForEach-Object {
        $properties = Get-ItemProperty -Path $_.PSPath
        
        # Check each property value in the subkey
        foreach ($property in $properties.PSObject.Properties) {
            try {
                $scanTime = [datetime]::Parse($property.Value)
                if ($scanTime -ge $thresholdTime) {
                    Write-Output "Recent scan found: $($scanTime)"
                    $recentScanFound = $true
                }
            } catch {
                # Ignore properties that cannot be parsed as datetime
                Write-Output "Skipping non-datetime value: $($property.Name)"
            }
        }
    }

    # Determine the result based on the scans found
    if ($recentScanFound) {
        Write-Output "At least one scan occurred within the acceptable time range."
        Exit 0  # No remediation needed
    } else {
        Write-Output "No recent scan found within the acceptable time range."
        Exit 1  # Trigger remediation
    }
} else {
    Write-Output "Registry path not found, assuming no recent scan."
    Exit 1  # Trigger remediation
}
