$comp = $env:computername 
$org = "Change to Company Name"
$FormatEnumerationLimit = -1
Import-Module -Name ActiveDirectory -ErrorAction Stop

Write-Output "Creating directory for $org"
New-Item -Path . -Name $org -ItemType Directory -ErrorAction Continue


# Start the transcript with a new file name including "transcript"
$transcriptFileName = ".\$org\${comp}_transcript.txt"

Start-Transcript -Path $transcriptFileName -ErrorAction Continue


# List of Active Directory sites
Write-Output "Collecting list of Active Directory sites"
Get-ADReplicationSite -Filter * | Format-Table -AutoSize | Out-File -FilePath .\$org\Sites.txt

# List replication information for each domain controller
Write-Output "Collecting replication information for each domain controller"
$DCs = Get-ADDomainController -Filter *
foreach ($DC in $DCs) {
    Write-Output "Replication information for $DC"
    repadmin /showrepl $DC.HostName | Out-File -FilePath .\$org\ReplicationInfo_$($DC.Name).txt
}

# List all domain controllers
Write-Output "Collecting list of all domain controllers"
$DCs | Select-Object Name | Out-File -FilePath .\$org\AllDCs.txt

# Get list of global catalog servers
Write-Output "Collecting list of global catalog servers"
Get-ADDomainController -Filter {IsGlobalCatalog -eq $true} | Select-Object Name | Out-File -FilePath .\$org\GlobalCatalogs.txt

# Find primary DC and Time Service host
Write-Output "Finding primary DC and Time Service host"
Get-ADDomainController -Discover -Service "PrimaryDC","TimeService" | Out-File -FilePath .\$org\PrimaryDCTimeService.txt

# Collect HotFix information for each DC
Write-Output "Collecting HotFix information for each DC"
foreach ($DC in $DCs) {
    Write-Output "Collecting HotFixes for $($DC.Name)"
    $hotfixes = Get-WmiObject -Class Win32_QuickFixEngineering -ComputerName $DC.Name
    $hotfixes | Select-Object Description, HotFixID, InstalledOn | Out-File -FilePath .\$org\HotFixes_$($DC.Name).txt
}


# Collect Application and System Log for each DC
foreach ($DC in $DCs) {
    Write-Output "Collecting Application and System Log for $DC"

    # Collect and export the Application log
    Get-EventLog -LogName application -ComputerName $DC.Name -Newest 5000 |
        Select-Object TimeGenerated, Source, EventID, EntryType, Message |
        Export-Csv -Path ".\$org\AppLog_$($DC.Name).csv" -NoTypeInformation

    # Collect and export the System log
    Get-EventLog -LogName system -ComputerName $DC.Name -Newest 5000 |
        Select-Object TimeGenerated, Source, EventID, EntryType, Message |
        Export-Csv -Path ".\$org\SysLog_$($DC.Name).csv" -NoTypeInformation
}


# Create computer subdirectory for each DC
foreach ($DC in $DCs) {
    Write-Output "Creating subdirectory for $DC"
    New-Item -Path .\$org -Name $DC.Name -ItemType Directory
}

# Copy netlogon.log to each DC's subdirectory
foreach ($DC in $DCs) {
    Write-Output "Copying netlogon.log for $($DC.Name)"
    $remoteNetlogonPath = "\\" + $DC.Name + "\c$\windows\debug\netlogon.log"
    $localNetlogonPath = ".\$org\$($DC.Name)\netlogon.log"
    Copy-Item -Path $remoteNetlogonPath -Destination $localNetlogonPath -ErrorAction Continue
}


Stop-Transcript
