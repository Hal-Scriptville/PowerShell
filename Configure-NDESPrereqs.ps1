# Function to install a Windows feature
function Install-Feature {
    param (
        [string]$featureName
    )
    Write-Host "Installing $featureName..."
    Install-WindowsFeature -Name $featureName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$featureName installed successfully."
    } else {
        Write-Host "Failed to install $featureName."
    }
}

# Ensure the script is running with administrative privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Host "Please run this script as an Administrator!"
    exit
}

# Check if IIS is installed
$iisInstalled = Get-WindowsFeature -Name Web-Server
if (-not $iisInstalled.Installed) {
    Install-Feature -featureName "Web-Server"
} else {
    Write-Host "IIS is already installed."
}

# Array of required features
$requiredFeatures = @("Web-Filtering", "NET-Framework-Core", "Web-Asp-Net45", "Web-Mgmt-Compat", "Web-Metabase", "Web-WMI", "NET-Framework-Features", "NET-HTTP-Activation", "NET-WCF-HTTP-Activation45")

# Check and install each required feature
foreach ($feature in $requiredFeatures) {
    $featureStatus = Get-WindowsFeature -Name $feature
    if (-not $featureStatus.Installed) {
        Write-Host "$feature is not installed."
        Install-Feature -featureName $feature
    } else {
        Write-Host "$feature is already installed."
    }
}

Write-Host "IIS configuration check and installation script completed."
