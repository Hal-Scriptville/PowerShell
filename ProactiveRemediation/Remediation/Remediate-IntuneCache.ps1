# Remediation Script

Invoke-Command -ScriptBlock {
    Get-ChildItem -File -Filter *.msi -Path 'C:\Windows\System32\config\systemprofile\AppData\Local\mdm' -Force -ErrorAction SilentlyContinue | Where-Object {$_.length -gt 1KB} | Remove-Item -Force
}
