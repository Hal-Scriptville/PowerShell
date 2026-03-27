# BitLocker Recovery Key Escrow Audit Script
# Identifies devices reporting as encrypted but missing escrowed recovery keys

#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement, Microsoft.Graph.Identity.DirectoryManagement

# Connect to Microsoft Graph with required permissions
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "BitLockerKey.Read.All", "Device.Read.All"

# Get all managed devices
Write-Host "Retrieving managed devices from Intune..." -ForegroundColor Cyan
$managedDevices = Get-MgDeviceManagementManagedDevice -All | Where-Object { $_.OperatingSystem -eq "Windows" }

Write-Host "Found $($managedDevices.Count) Windows devices. Checking BitLocker status..." -ForegroundColor Green

# Initialize results array
$results = @()

foreach ($device in $managedDevices) {
    Write-Host "Checking device: $($device.DeviceName)" -ForegroundColor Yellow
    
    # Get the Azure AD device ID
    $azureAdDeviceId = $device.AzureAdDeviceId
    
    if ($azureAdDeviceId) {
        # Check for BitLocker recovery keys
        try {
            $uri = "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$azureAdDeviceId'"
            $recoveryKeys = Invoke-MgGraphRequest -Uri $uri -Method GET
            
            $keyCount = $recoveryKeys.value.Count
            
            # Get encryption state from Intune
            $encryptionState = $device.IsEncrypted
            
            # Create result object
            $deviceInfo = [PSCustomObject]@{
                DeviceName = $device.DeviceName
                UserPrincipalName = $device.UserPrincipalName
                AzureAdDeviceId = $azureAdDeviceId
                IntuneDeviceId = $device.Id
                OperatingSystem = $device.OperatingSystem
                OSVersion = $device.OsVersion
                IsEncrypted = $encryptionState
                RecoveryKeysCount = $keyCount
                HasRecoveryKey = ($keyCount -gt 0)
                ComplianceState = $device.ComplianceState
                LastSyncDateTime = $device.LastSyncDateTime
                Status = if ($encryptionState -and $keyCount -eq 0) { "MISSING KEYS" } 
                        elseif ($encryptionState -and $keyCount -gt 0) { "OK" }
                        elseif (-not $encryptionState) { "NOT ENCRYPTED" }
                        else { "UNKNOWN" }
            }
            
            $results += $deviceInfo
            
        } catch {
            Write-Warning "Error checking device $($device.DeviceName): $($_.Exception.Message)"
        }
    }
}

# Display summary
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
$missingKeys = $results | Where-Object { $_.Status -eq "MISSING KEYS" }
$encrypted = $results | Where-Object { $_.IsEncrypted -eq $true }
$withKeys = $results | Where-Object { $_.HasRecoveryKey -eq $true }

Write-Host "Total devices checked: $($results.Count)" -ForegroundColor White
Write-Host "Encrypted devices: $($encrypted.Count)" -ForegroundColor Green
Write-Host "Devices with escrowed keys: $($withKeys.Count)" -ForegroundColor Green
Write-Host "Encrypted devices MISSING keys: $($missingKeys.Count)" -ForegroundColor Red

# Display devices missing keys
if ($missingKeys.Count -gt 0) {
    Write-Host "`n=== DEVICES ENCRYPTED BUT MISSING RECOVERY KEYS ===" -ForegroundColor Red
    $missingKeys | Format-Table DeviceName, UserPrincipalName, OSVersion, LastSyncDateTime -AutoSize
}

# Export results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$exportPath = ".\BitLocker_Audit_$timestamp.csv"
$results | Export-Csv -Path $exportPath -NoTypeInformation
Write-Host "`nFull results exported to: $exportPath" -ForegroundColor Green

# Disconnect
Disconnect-MgGraph
Write-Host "`nScript completed!" -ForegroundColor Cyan
