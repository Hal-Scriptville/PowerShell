# Ensure Microsoft Graph PowerShell SDK is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"

# Get Group Policy Analytics reports
$reports = Get-MgDeviceManagementGroupPolicyMigrationReport

# Display the reports in a grid view for selection
$selectedReports = $reports | Out-GridView -Title "Select Group Policy Analytics Reports to Delete" -PassThru

# Delete the selected reports
foreach ($report in $selectedReports) {
    try {
        Remove-MgDeviceManagementGroupPolicyMigrationReport -GroupPolicyMigrationReportId $report.Id
        Write-Output "Successfully deleted report with ID: $($report.Id)"
    } catch {
        Write-Error "Failed to delete report with ID: $($report.Id) - $_"
    }
}
