# Detect-CertHealth.ps1
# Proactive Remediation - Detection
#
# Checks LocalMachine\My certificate store for expired certificates
# and certificates expiring within the next 30 days.
# Relevant for NDES/SCEP, WHfB, and smart card environments.
#
# Exit 0 = compliant (no expired or near-expiry certs)
# Exit 1 = non-compliant (action required)

$WarningDays = 30
$Now = Get-Date

try {
    $Store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
    $Store.Open("ReadOnly")
    $Certs = $Store.Certificates
    $Store.Close()

    $Expired  = $Certs | Where-Object { $_.NotAfter -lt $Now }
    $Expiring = $Certs | Where-Object { $_.NotAfter -ge $Now -and $_.NotAfter -lt $Now.AddDays($WarningDays) }

    if ($Expired.Count -gt 0) {
        Write-Output "NON-COMPLIANT: $($Expired.Count) expired certificate(s) in LocalMachine\My"
        $Expired | ForEach-Object {
            Write-Output "  EXPIRED: $($_.Subject) — expired $($_.NotAfter.ToString('yyyy-MM-dd'))"
        }
        exit 1
    }

    if ($Expiring.Count -gt 0) {
        Write-Output "NON-COMPLIANT: $($Expiring.Count) certificate(s) expiring within $WarningDays days"
        $Expiring | ForEach-Object {
            Write-Output "  EXPIRING: $($_.Subject) — expires $($_.NotAfter.ToString('yyyy-MM-dd'))"
        }
        exit 1
    }

    Write-Output "COMPLIANT: $($Certs.Count) certificate(s) checked — none expired or expiring within $WarningDays days"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
