# Detect-SecureBoot.ps1
# Proactive Remediation - Detection
#
# Verifies that Secure Boot is enabled on UEFI systems.
# Non-UEFI (legacy BIOS) machines are flagged as non-compliant
# since they cannot support Secure Boot.
#
# Exit 0 = compliant (Secure Boot enabled)
# Exit 1 = non-compliant (disabled or legacy BIOS)

try {
    $SecureBootStatus = Confirm-SecureBootUEFI -ErrorAction Stop

    if ($SecureBootStatus -eq $true) {
        Write-Output "COMPLIANT: Secure Boot is enabled"
        exit 0
    }
    else {
        Write-Output "NON-COMPLIANT: Secure Boot is supported but disabled"
        exit 1
    }
}
catch [System.PlatformNotSupportedException] {
    Write-Output "NON-COMPLIANT: System is not UEFI — Secure Boot not supported on this firmware"
    exit 1
}
catch [System.UnauthorizedAccessException] {
    Write-Output "NON-COMPLIANT: Access denied querying Secure Boot status"
    exit 1
}
catch {
    Write-Output "NON-COMPLIANT: Could not determine Secure Boot status — $_"
    exit 1
}
