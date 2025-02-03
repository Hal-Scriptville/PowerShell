try {
    $cbService = Get-Service -Name "CbDefense" -ErrorAction SilentlyContinue
    $cbPath = "C:\Program Files\CarbonBlack\CbDefense"
    $cbReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\CarbonBlack" -ErrorAction SilentlyContinue

    if ($cbService -or (Test-Path $cbPath) -or $cbReg) {
        # Carbon Black found, return 1 to trigger remediation
        Write-Output "Carbon Black components detected"
        Exit 1
    } else {
        # No Carbon Black found, return 0
        Write-Output "No Carbon Black components found"
        Exit 0
    }
} catch {
    Write-Error "Error during Carbon Black detection: $_"
    Exit 1
}