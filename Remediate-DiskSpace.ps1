$threshold = 15
$drives = Get-PSDrive -PSProvider FileSystem

foreach ($drive in $drives) {
    $freeSpacePercent = ($drive.Free / $drive.Used) * 100
    if ($freeSpacePercent -lt $threshold) {
        # Example cleanup actions
        Write-Output "Cleaning up drive $($drive.Name)"
        
        # Delete temporary files
        Remove-Item -Path "$($env:TEMP)\*" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Empty Recycle Bin
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        
        # Add more cleanup actions as needed
    }
}

Write-Output "Remediation completed"
