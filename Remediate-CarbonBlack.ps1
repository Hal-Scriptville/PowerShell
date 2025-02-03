try {
    # Stop Carbon Black services
    Stop-Service -Name "CbDefense" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "CbDefenseSensor" -Force -ErrorAction SilentlyContinue

    # Uninstall Carbon Black using uninstall code
    $cbPath = "C:\Program Files\CarbonBlack\CbDefense\"
    $uninstallCode = "YOUR-UNINSTALL-CODE-HERE"  # Replace with actual uninstall code
    $uninstallCmd = "$cbPath\cbuninstall.exe /quiet /norestart /uninstall $uninstallCode"

    if (Test-Path "$cbPath\cbuninstall.exe") {
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninstallCmd" -Wait -NoNewWindow -PassThru
        if ($process.ExitCode -ne 0) {
            throw "Uninstall process failed with exit code: $($process.ExitCode)"
        }
    } else {
        throw "Carbon Black uninstaller not found"
    }

    # Clean up registry keys
    Remove-Item -Path "HKLM:\SOFTWARE\CarbonBlack" -Recurse -Force -ErrorAction SilentlyContinue

    # Clean up leftover files
    Remove-Item -Path "C:\Program Files\CarbonBlack" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Output "Carbon Black removal completed successfully"
    Exit 0
} catch {
    Write-Error "Error during Carbon Black removal: $_"
    Exit 1
}
