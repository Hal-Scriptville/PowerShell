# Remediate-SecureBoot.ps1
# Proactive Remediation - Remediation
#
# Secure Boot cannot be enabled via script — it requires a BIOS/UEFI
# firmware change by a technician or end user.
#
# This script logs a diagnostic report to help the help desk
# identify and prioritize devices for manual remediation.
#
# Exit 0 = diagnostic logged (escalation required)

$LogDir  = "C:\ProgramData\IT\Diagnostics"
$LogFile = Join-Path $LogDir "SecureBoot-$(Get-Date -Format 'yyyyMMdd').txt"

try {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

    $Report = @(
        "Secure Boot Remediation Required",
        "================================",
        "Date:        $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Computer:    $env:COMPUTERNAME",
        "User:        $env:USERNAME",
        "",
        "ACTION REQUIRED: Secure Boot must be enabled in the device BIOS/UEFI firmware.",
        "",
        "Steps for technician:",
        "  1. Restart the device and enter BIOS/UEFI (typically Del, F2, or F10 at POST)",
        "  2. Locate the Secure Boot setting (usually under Security or Boot tab)",
        "  3. Enable Secure Boot",
        "  4. Save and exit",
        "",
        "Note: If the device uses Legacy BIOS boot mode, convert to UEFI before enabling Secure Boot.",
        "      This may require MBR-to-GPT conversion (mbr2gpt /convert) before the BIOS change.",
        ""
    )

    # Append firmware info for technician context
    try {
        $FirmwareType = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control" -Name "PEFirmwareType" -ErrorAction SilentlyContinue).PEFirmwareType
        $FirmwareDesc = switch ($FirmwareType) { 1 { "Legacy BIOS" } 2 { "UEFI" } default { "Unknown ($FirmwareType)" } }
        $Report += "Firmware type: $FirmwareDesc"
    }
    catch { }

    $Report | Out-File -FilePath $LogFile -Encoding UTF8
    Write-Output "Diagnostic logged to $LogFile — manual remediation required"
    Write-Output "Computer: $env:COMPUTERNAME | Firmware: $FirmwareDesc"
    exit 0
}
catch {
    Write-Output "ERROR logging diagnostic: $_"
    exit 0
}
