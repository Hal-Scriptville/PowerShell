$FolderPath = "D:\profiles"
$BackupFile = "D:\profile_permissions_backup.csv"

# Get ACL information for all folders recursively
Get-ChildItem -Path $FolderPath -Directory -Recurse | 
ForEach-Object {
    $Acl = Get-Acl $_.FullName
    $Acl | Select-Object @{Name="Path";Expression={$_.Path}},
        @{Name="Owner";Expression={$_.Owner}},
        @{Name="Access";Expression={$_.Access}} |
    Export-Csv -Path $BackupFile -Append -NoTypeInformation
}
