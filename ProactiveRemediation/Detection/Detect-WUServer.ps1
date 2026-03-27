# Detection Script
$wsusPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$wsusKeys = @("WUServer", "WUStatusServer")

$foundKeys = $wsusKeys | Where-Object { (Get-ItemProperty -Path $wsusPath -ErrorAction SilentlyContinue).$_ }

if ($foundKeys) {
    Write-Output "WSUS keys found: $($foundKeys -join ', ')"
    Exit 1  # Non-zero exit indicates a fix is needed
} else {
    Write-Output "No WSUS keys found"
    Exit 0  # Zero exit indicates no remediation needed
}
