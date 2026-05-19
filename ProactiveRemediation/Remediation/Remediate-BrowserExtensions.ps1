# Remediate-BrowserExtensions.ps1
# Proactive Remediation - Remediation
#
# Removes blocked browser extensions from all Chrome and Edge user profiles
# by deleting the extension directory and adding it to the ExtensionInstallBlocklist
# policy registry key to prevent reinstallation.
#
# Exit 0 = success
# Exit 1 = failure

# Must match the block list in Detect-BrowserExtensions.ps1
$BlockedExtensionIds = @(
    # "ficfmibkjjnpogdcfnpnjqqcbkklnckc",
    # "ogpacbmhjgakodacnajkjflgbkjpbfhe"
)

$ProfilePaths = @(
    @{ Pattern = "$env:SystemDrive\Users\*\AppData\Local\Google\Chrome\User Data\*\Extensions"; Browser = 'Chrome';
       PolicyKey = 'HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallBlocklist' },
    @{ Pattern = "$env:SystemDrive\Users\*\AppData\Local\Microsoft\Edge\User Data\*\Extensions"; Browser = 'Edge';
       PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist' }
)

try {
    $Removed = 0

    foreach ($Config in $ProfilePaths) {
        # Add to browser policy block list to prevent reinstall
        if (-not (Test-Path $Config.PolicyKey)) {
            New-Item -Path $Config.PolicyKey -Force | Out-Null
        }
        $ExistingValues = (Get-Item $Config.PolicyKey).Property
        $NextIndex = if ($ExistingValues) { ($ExistingValues | Measure-Object -Maximum).Maximum + 1 } else { 1 }

        foreach ($ExtId in $BlockedExtensionIds) {
            if ($ExtId -notin $ExistingValues) {
                Set-ItemProperty -Path $Config.PolicyKey -Name "$NextIndex" -Value $ExtId -ErrorAction SilentlyContinue
                Write-Output "Added $ExtId to $($Config.Browser) block list policy"
                $NextIndex++
            }
        }

        # Remove extension directories
        $ExtDirs = Get-ChildItem -Path $Config.Pattern -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -in $BlockedExtensionIds }

        foreach ($Dir in $ExtDirs) {
            try {
                Remove-Item -Path $Dir.FullName -Recurse -Force -ErrorAction Stop
                Write-Output "Removed $($Config.Browser) extension: $($Dir.Name) from $($Dir.Parent.Parent.Name)"
                $Removed++
            }
            catch {
                Write-Output "WARNING: Could not remove $($Dir.FullName): $_"
            }
        }
    }

    Write-Output "Remediation complete — $Removed extension director(ies) removed"
    Write-Output "Note: Browser must be restarted for changes to take effect"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
