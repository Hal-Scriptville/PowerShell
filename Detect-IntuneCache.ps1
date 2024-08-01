# Detection Script

$msiFiles = Get-ChildItem -Path 'C:\Windows\System32\config\systemprofile\AppData\Local\mdm' -Filter *.msi -File -ErrorAction SilentlyContinue

if ($msiFiles.Count -gt 0) {
    write-host "Remediation needed" -foregroundcolor red
    exit 1  # Remediation needed
} else {
    write-host "No remediation needed" -foregroundcolor green
    exit 0  # No remediation needed
}
