# Remediation Script
$wsusPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$wsusKeys = @("WUServer", "WUStatusServer")

if (Test-Path $wsusPath) {
    $wsusKeys | ForEach-Object {
        Remove-ItemProperty -Path $wsusPath -Name $_ -ErrorAction SilentlyContinue
    }
    Write-Output "WSUS registry keys removed"
} else {
    Write-Output "WSUS registry path not found"
}

# Optionally reset Windows Update service
Stop-Service -Name wuauserv -Force
Start-Service -Name wuauserv
