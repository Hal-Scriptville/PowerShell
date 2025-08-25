# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.Read.All", "Device.ReadWrite.All", "GroupMember.Read.All"

# Configuration
$GroupName = "Stale Device Records"
$DryRun = $true  # Set to $false to actually delete devices

# Get the stale device group
$StaleGroup = Get-MgGroup -Filter "displayName eq '$GroupName'"
if (-not $StaleGroup) {
    Write-Error "Group '$GroupName' not found!"
    exit 1
}

Write-Host "Found group: $($StaleGroup.DisplayName) (ID: $($StaleGroup.Id))"

# Get all device members of the group
$GroupMembers = Get-MgGroupMember -GroupId $StaleGroup.Id -All
$DeviceMembers = $GroupMembers | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.device' }

Write-Host "Found $($DeviceMembers.Count) devices in the group"

# Process each device
$SuccessCount = 0
$FailCount = 0

foreach ($Member in $DeviceMembers) {
    try {
        $Device = Get-MgDevice -DeviceId $Member.Id
        Write-Host "Processing: $($Device.DisplayName) | OS: $($Device.OperatingSystem) | Last Seen: $($Device.ApproximateLastSignInDateTime)"
        
        if (-not $DryRun) {
            # Delete the device from Entra ID
            Remove-MgDevice -DeviceId $Device.Id -Confirm:$false
            Write-Host "Deleted: $($Device.DisplayName)" -ForegroundColor Green
            $SuccessCount++
        } else {
            Write-Host "[DRY RUN] Would delete: $($Device.DisplayName)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Failed to delete: $($Device.DisplayName) - $($_.Exception.Message)" -ForegroundColor Red
        $FailCount++
    }
}

# Summary
if ($DryRun) {
    Write-Host "`n DRY RUN SUMMARY: Would delete $($DeviceMembers.Count) devices"
} else {
    Write-Host "`n DELETION SUMMARY:"
    Write-Host " Successfully deleted: $SuccessCount devices"
    Write-Host " Failed to delete: $FailCount devices"
}
