# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.ReadWrite.All", "Device.Read.All", "GroupMember.ReadWrite.All"

# Configuration
$DaysInactive = 90
$CutoffDate = (Get-Date).AddDays(-$DaysInactive)
$GroupName = "Stale Device Records"
$GroupDescription = "Devices inactive for $DaysInactive+ days - Created $(Get-Date -Format 'yyyy-MM-dd')"

# Check if group already exists
$ExistingGroup = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction SilentlyContinue

if ($ExistingGroup) {
    Write-Host "Using existing group: $GroupName" -ForegroundColor Yellow
    $StaleDeviceGroup = $ExistingGroup
} else {
    # Create new security group
    $GroupParams = @{
        DisplayName = $GroupName
        Description = $GroupDescription
        GroupTypes = @()  # Empty array creates security group
        MailEnabled = $false
        SecurityEnabled = $true
        MailNickname = "StaleDeviceRecords"
    }
    
    $StaleDeviceGroup = New-MgGroup @GroupParams
    Write-Host "Created group: $GroupName (ID: $($StaleDeviceGroup.Id))" -ForegroundColor Green
}

# Get stale devices
$StaleDevices = Get-MgDevice -All | Where-Object {
    ($_.ApproximateLastSignInDateTime -lt $CutoffDate) -or
    ($_.ApproximateLastSignInDateTime -eq $null -and $_.RegistrationDateTime -lt $CutoffDate)
}

Write-Host "Found $($StaleDevices.Count) stale devices"

# Get current group members to avoid duplicates
$CurrentMembers = Get-MgGroupMember -GroupId $StaleDeviceGroup.Id -All

# Add devices to group
$AddedCount = 0
foreach ($Device in $StaleDevices) {
    # Check if device is already a member
    if ($CurrentMembers.Id -notcontains $Device.Id) {
        try {
            New-MgGroupMember -GroupId $StaleDeviceGroup.Id -DirectoryObjectId $Device.Id
            Write-Host "➕ Added: $($Device.DisplayName)" -ForegroundColor Green
            $AddedCount++
        }
        catch {
            Write-Host "Failed to add: $($Device.DisplayName) - $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "Already member: $($Device.DisplayName)" -ForegroundColor Gray
    }
}

Write-Host "Added $AddedCount new devices to group '$GroupName'"
