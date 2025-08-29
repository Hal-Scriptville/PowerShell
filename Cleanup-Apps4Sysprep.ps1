# Enhanced AppX Cleanup Script for Sysprep Preparation
# Removes all AppX packages and provisioned packages that can block sysprep
# Run as Administrator

# Set execution policy and error handling
Set-ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = "Continue"

# Create log file
$LogPath = "C:\Windows\Temp\AppX_Cleanup.log"
$StartTime = Get-Date
Write-Output "=== AppX Cleanup Script Started: $StartTime ===" | Tee-Object -FilePath $LogPath -Append

function Write-LogMessage {
    param([string]$Message)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] $Message"
    Write-Output $LogEntry | Tee-Object -FilePath $LogPath -Append
}

Write-LogMessage "Starting comprehensive AppX package removal..."

# Stop Windows Update service to prevent interference
Write-LogMessage "Stopping Windows Update service..."
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue

# Remove ALL AppX packages for current user (except critical system components)
Write-LogMessage "Removing AppX packages for current user..."
$CriticalPackages = @(
    "Microsoft.WindowsStore",
    "Microsoft.DesktopAppInstaller",
    "Microsoft.VCLibs*",
    "Microsoft.NET.Native*",
    "Microsoft.UI.Xaml*"
)

try {
    $AllPackages = Get-AppxPackage | Where-Object { 
        $package = $_
        -not ($CriticalPackages | Where-Object { $package.Name -like $_ })
    }
    
    foreach ($Package in $AllPackages) {
        try {
            Write-LogMessage "Removing package: $($Package.Name)"
            Remove-AppxPackage -Package $Package.PackageFullName -ErrorAction Stop
            Write-LogMessage "Successfully removed: $($Package.Name)"
        }
        catch {
            Write-LogMessage "Failed to remove $($Package.Name): $($_.Exception.Message)"
        }
    }
}
catch {
    Write-LogMessage "Error getting AppX packages: $($_.Exception.Message)"
}

# Remove ALL AppX packages for ALL users
Write-LogMessage "Removing AppX packages for all users..."
try {
    $AllUserPackages = Get-AppxPackage -AllUsers | Where-Object { 
        $package = $_
        -not ($CriticalPackages | Where-Object { $package.Name -like $_ })
    }
    
    foreach ($Package in $AllUserPackages) {
        try {
            Write-LogMessage "Removing package for all users: $($Package.Name)"
            Remove-AppxPackage -Package $Package.PackageFullName -AllUsers -ErrorAction Stop
            Write-LogMessage "Successfully removed for all users: $($Package.Name)"
        }
        catch {
            Write-LogMessage "Failed to remove for all users $($Package.Name): $($_.Exception.Message)"
        }
    }
}
catch {
    Write-LogMessage "Error getting AppX packages for all users: $($_.Exception.Message)"
}

# Remove ALL provisioned AppX packages
Write-LogMessage "Removing provisioned AppX packages..."
try {
    $ProvisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object { 
        $package = $_
        -not ($CriticalPackages | Where-Object { $package.DisplayName -like $_ })
    }
    
    foreach ($Package in $ProvisionedPackages) {
        try {
            Write-LogMessage "Removing provisioned package: $($Package.DisplayName)"
            Remove-AppxProvisionedPackage -Online -PackageName $Package.PackageName -ErrorAction Stop
            Write-LogMessage "Successfully removed provisioned: $($Package.DisplayName)"
        }
        catch {
            Write-LogMessage "Failed to remove provisioned $($Package.DisplayName): $($_.Exception.Message)"
        }
    }
}
catch {
    Write-LogMessage "Error getting provisioned packages: $($_.Exception.Message)"
}

# Clean up AppX deployment cache
Write-LogMessage "Cleaning AppX deployment cache..."
try {
    $AppXCachePaths = @(
        "$env:LOCALAPPDATA\Packages",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:TEMP\*.appx",
        "C:\Windows\System32\AppLocker\*.appx"
    )
    
    foreach ($Path in $AppXCachePaths) {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogMessage "Cleaned cache path: $Path"
        }
    }
}
catch {
    Write-LogMessage "Error cleaning cache: $($_.Exception.Message)"
}

# Clean Windows Store cache
Write-LogMessage "Cleaning Windows Store cache..."
try {
    Start-Process wsreset.exe -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
    Write-LogMessage "Windows Store cache reset completed"
}
catch {
    Write-LogMessage "Error resetting Windows Store cache: $($_.Exception.Message)"
}

# Remove AppX maintenance tasks that can interfere with sysprep
Write-LogMessage "Disabling AppX maintenance tasks..."
$TasksToDisable = @(
    "\Microsoft\Windows\AppxDeploymentClient\*",
    "\Microsoft\Windows\ApplicationData\*"
)

foreach ($TaskPath in $TasksToDisable) {
    try {
        Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
        Write-LogMessage "Disabled scheduled tasks: $TaskPath"
    }
    catch {
        Write-LogMessage "Could not disable tasks: $TaskPath"
    }
}

# Restart Windows Update service
Write-LogMessage "Restarting Windows Update service..."
Start-Service -Name wuauserv -ErrorAction SilentlyContinue

# Final verification
Write-LogMessage "Performing final verification..."
$RemainingPackages = Get-AppxPackage -AllUsers | Measure-Object
$RemainingProvisioned = Get-AppxProvisionedPackage -Online | Measure-Object

Write-LogMessage "Remaining AppX packages: $($RemainingPackages.Count)"
Write-LogMessage "Remaining provisioned packages: $($RemainingProvisioned.Count)"

$EndTime = Get-Date
$Duration = $EndTime - $StartTime
Write-LogMessage "=== AppX Cleanup Script Completed: $EndTime ==="
Write-LogMessage "Total execution time: $($Duration.TotalMinutes.ToString('F2')) minutes"

# Display summary
Write-Host "`n=== CLEANUP SUMMARY ===" -ForegroundColor Green
Write-Host "Log file: $LogPath" -ForegroundColor Yellow
Write-Host "Remaining packages: $($RemainingPackages.Count)" -ForegroundColor Cyan
Write-Host "Remaining provisioned: $($RemainingProvisioned.Count)" -ForegroundColor Cyan
Write-Host "Ready for sysprep!" -ForegroundColor Green
