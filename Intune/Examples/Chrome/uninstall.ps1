# uninstall.ps1 - Google Chrome Enterprise uninstall (Intune Win32 app)

$ErrorActionPreference = 'Stop'
$log = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\Chrome-uninstall.log"
Start-Transcript -Path $log -Append

try {
    # Product code for Google Chrome Enterprise x64 (stable channel).
    # Verify against target MSI version before trusting in production:
    #   Get-Package | Where-Object Name -like 'Google Chrome*' | Select-Object -ExpandProperty PackageFilename
    $productCode = '{CHROME-PRODUCT-CODE-GUID}'

    $args = @('/x', $productCode, '/qn', '/norestart')
    $proc = Start-Process -FilePath msiexec.exe -ArgumentList $args -Wait -PassThru

    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010 -and $proc.ExitCode -ne 1605) {
        throw "msiexec failed with exit code $($proc.ExitCode)"
    }

    Write-Host "Chrome uninstall complete (exit $($proc.ExitCode))"
    exit 0
} catch {
    Write-Error $_
    exit 1
} finally {
    Stop-Transcript
}
