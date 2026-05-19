# Remediate-CertHealth.ps1
# Proactive Remediation - Remediation
#
# Removes expired certificates from LocalMachine\My and triggers
# autoenrollment to request replacements via SCEP/NDES/CA policy.
#
# Exit 0 = success
# Exit 1 = failure

$Now = Get-Date

try {
    $Store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
    $Store.Open("ReadWrite")
    $Expired = $Store.Certificates | Where-Object { $_.NotAfter -lt $Now }

    $Removed = 0
    foreach ($Cert in $Expired) {
        try {
            $Store.Remove($Cert)
            Write-Output "Removed expired cert: $($Cert.Subject) (expired $($Cert.NotAfter.ToString('yyyy-MM-dd')))"
            $Removed++
        }
        catch {
            Write-Output "WARNING: Could not remove $($Cert.Subject): $_"
        }
    }
    $Store.Close()

    if ($Removed -gt 0) {
        Write-Output "Removed $Removed expired certificate(s)"
    }
    else {
        Write-Output "No expired certificates to remove"
    }

    # Trigger autoenrollment to request replacements
    Write-Output "Triggering certificate autoenrollment..."
    $Result = certutil -pulse 2>&1
    Write-Output "Autoenrollment result: $Result"

    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
