# Detection Script
$folderPath = 'C:\Windows\System32\config\systemprofile\AppData\Local\mdm'
$folderSize = (Get-ChildItem -Path $folderPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
$maxSize = 100MB

if ($folderSize -gt $maxSize) {
    write-host "Remediation needed" -foregroundcolor red
    exit 1  # Remediation needed
} else {
    write-host "No remediation needed" -foregroundcolor green
    exit 0  # No remediation needed
}
