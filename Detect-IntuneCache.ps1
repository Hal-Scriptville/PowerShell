# Detection Script

$msiFiles = Get-ChildItem -Path 'C:\Windows\System32\config\systemprofile\AppData\Local\mdm' -Filter *.msi -File -ErrorAction SilentlyContinue

if ($msiFiles.Count -gt 0) {
    exit 1  # Remediation needed
} else {
    exit 0  # No remediation needed
}
