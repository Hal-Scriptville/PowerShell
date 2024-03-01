$processName = "YourProcessName" # Replace with the name of your process

# Check if the process is running
$process = Get-Process | Where-Object { $_.ProcessName -eq $processName } -ErrorAction SilentlyContinue

if ($process) {
    Write-Host "Process found."
    exit 0 # Success code
} else {
    Write-Host "Process not found."
    exit 1 # Failure code
}
