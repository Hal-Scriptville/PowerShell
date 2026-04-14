# install.ps1 - Google Chrome Enterprise install (Intune Win32 app)
# Runs as SYSTEM under Intune Management Extension.

$ErrorActionPreference = 'Stop'
$log = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\Chrome-install.log"
Start-Transcript -Path $log -Append

try {
    $msi = Join-Path $PSScriptRoot "googlechromestandaloneenterprise64.msi"
    if (-not (Test-Path $msi)) { throw "MSI not found: $msi" }

    $args = @('/i', "`"$msi`"", '/qn', '/norestart', 'REBOOT=ReallySuppress')
    $proc = Start-Process -FilePath msiexec.exe -ArgumentList $args -Wait -PassThru

    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        throw "msiexec failed with exit code $($proc.ExitCode)"
    }

    Write-Host "Chrome install complete (exit $($proc.ExitCode))"
    exit 0
} catch {
    Write-Error $_
    exit 1
} finally {
    Stop-Transcript
}
