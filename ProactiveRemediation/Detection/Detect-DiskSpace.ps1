$threshold = 15
$drives = Get-PSDrive -PSProvider FileSystem

foreach ($drive in $drives) {
    $freeSpacePercent = ($drive.Free / $drive.Used) * 100
    if ($freeSpacePercent -lt $threshold) {
        Write-Output "Less than 15% free space on drive $($drive.Name)"
        exit 1
    }
}

Write-Output "More than 15% free space on all drives"
exit 0
