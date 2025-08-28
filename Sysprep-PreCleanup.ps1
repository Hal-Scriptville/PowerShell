# Windows 11 Sysprep Cleanup Script
# This script removes problematic AppX packages that commonly cause Sysprep failures
# Run as Administrator

#Requires -RunAsAdministrator

param(
    [switch]$WhatIf,
    [switch]$Verbose,
    [string]$LogPath = "$env:TEMP\SysprepCleanup.log"
)

# Initialize logging
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    Add-Content -Path $LogPath -Value $logEntry
}

Write-Log "Starting Sysprep cleanup process" "INFO"
Write-Log "Log file: $LogPath" "INFO"

if ($WhatIf) {
    Write-Log "Running in WhatIf mode - no changes will be made" "WARN"
}

# List of problematic AppX packages that commonly cause Sysprep failures
$ProblematicApps = @(
    "Microsoft.XboxApp",
    "Microsoft.XboxGameOverlay", 
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxGameCallableUI",
    "Microsoft.549981C3F5F10",  # Cortana
    "Cortana",
    "Microsoft.BingWeather",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.People",
    "Microsoft.WindowsCamera",
    "Microsoft.windowscommunicationsapps",  # Mail and Calendar
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.WindowsMaps",
    "Microsoft.WindowsSoundRecorder",
    "Microsoft.YourPhone",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Microsoft.SkypeApp",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.MSPaint",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.MixedReality.Portal",
    "Microsoft.OneConnect",
    "Microsoft.Print3D",
    "Microsoft.Wallet"
)

# Function to remove AppX packages for all users
function Remove-AppXPackages {
    param([string[]]$AppList)
    
    Write-Log "Removing AppX packages for all users..." "INFO"
    
    foreach ($app in $AppList) {
        try {
            Write-Log "Processing: $app" "INFO"
            
            # Get all AppX packages for current user
            $userPackages = Get-AppxPackage -Name "*$app*" -ErrorAction SilentlyContinue
            foreach ($package in $userPackages) {
                if ($WhatIf) {
                    Write-Log "WhatIf: Would remove user package: $($package.Name)" "WARN"
                } else {
                    Write-Log "Removing user package: $($package.Name)" "INFO"
                    Remove-AppxPackage -Package $package.PackageFullName -ErrorAction SilentlyContinue
                }
            }
            
            # Get all AppX packages for all users
            $allUserPackages = Get-AppxPackage -AllUsers -Name "*$app*" -ErrorAction SilentlyContinue
            foreach ($package in $allUserPackages) {
                if ($WhatIf) {
                    Write-Log "WhatIf: Would remove all-users package: $($package.Name)" "WARN"
                } else {
                    Write-Log "Removing all-users package: $($package.Name)" "INFO"
                    Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                }
            }
            
        } catch {
            Write-Log "Error processing $app : $($_.Exception.Message)" "ERROR"
        }
    }
}

# Function to remove provisioned AppX packages
function Remove-ProvisionedPackages {
    param([string[]]$AppList)
    
    Write-Log "Removing provisioned AppX packages..." "INFO"
    
    foreach ($app in $AppList) {
        try {
            $provisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*$app*" }
            foreach ($package in $provisionedPackages) {
                if ($WhatIf) {
                    Write-Log "WhatIf: Would remove provisioned package: $($package.DisplayName)" "WARN"
                } else {
                    Write-Log "Removing provisioned package: $($package.DisplayName)" "INFO"
                    Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Log "Error processing provisioned package $app : $($_.Exception.Message)" "ERROR"
        }
    }
}

# Function to clean up Windows capabilities that might cause issues
function Remove-ProblematicCapabilities {
    Write-Log "Checking for problematic Windows capabilities..." "INFO"
    
    $ProblematicCapabilities = @(
        "XPS.Viewer~~~~0.0.1.0",
        "Print.Fax.Scan~~~~0.0.1.0"
    )
    
    foreach ($capability in $ProblematicCapabilities) {
        try {
            $cap = Get-WindowsCapability -Online -Name $capability -ErrorAction SilentlyContinue
            if ($cap -and $cap.State -eq "Installed") {
                if ($WhatIf) {
                    Write-Log "WhatIf: Would remove capability: $capability" "WARN"
                } else {
                    Write-Log "Removing capability: $capability" "INFO"
                    Remove-WindowsCapability -Online -Name $capability -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Log "Error processing capability $capability : $($_.Exception.Message)" "ERROR"
        }
    }
}

# Function to clean up Edge WebView2 issues
function Fix-EdgeWebView {
    Write-Log "Checking Edge WebView2 installations..." "INFO"
    
    try {
        # Remove Edge WebView2 from all users if it exists
        $webViewPackages = Get-AppxPackage -AllUsers -Name "*WebExperience*" -ErrorAction SilentlyContinue
        foreach ($package in $webViewPackages) {
            if ($WhatIf) {
                Write-Log "WhatIf: Would remove WebView package: $($package.Name)" "WARN"
            } else {
                Write-Log "Removing WebView package: $($package.Name)" "INFO"
                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Log "Error processing Edge WebView: $($_.Exception.Message)" "ERROR"
    }
}

# Function to clean up Windows Update medic service cache
function Clear-UpdateMedicCache {
    Write-Log "Clearing Windows Update Medic Service cache..." "INFO"
    
    try {
        $serviceName = "WaaSMedicSvc"
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        
        if ($service) {
            if ($WhatIf) {
                Write-Log "WhatIf: Would stop $serviceName service" "WARN"
            } else {
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                Write-Log "Stopped $serviceName service" "INFO"
            }
        }
        
        # Clear CBS logs that can cause issues
        $cbsLogPath = "$env:SystemRoot\Logs\CBS"
        if (Test-Path $cbsLogPath) {
            if ($WhatIf) {
                Write-Log "WhatIf: Would clear CBS logs at $cbsLogPath" "WARN"
            } else {
                Get-ChildItem -Path $cbsLogPath -Filter "*.log" | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Log "Cleared CBS logs" "INFO"
            }
        }
        
    } catch {
        Write-Log "Error clearing Update Medic cache: $($_.Exception.Message)" "ERROR"
    }
}

# Function to run DISM cleanup
function Invoke-DismCleanup {
    Write-Log "Running DISM cleanup operations..." "INFO"
    
    try {
        if ($WhatIf) {
            Write-Log "WhatIf: Would run DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase" "WARN"
        } else {
            Write-Log "Running DISM component cleanup..." "INFO"
            & dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
            Write-Log "DISM cleanup completed" "INFO"
        }
    } catch {
        Write-Log "Error running DISM cleanup: $($_.Exception.Message)" "ERROR"
    }
}

# Main execution
try {
    Write-Log "=== STARTING SYSPREP CLEANUP ===" "INFO"
    
    # Remove problematic AppX packages
    Remove-AppXPackages -AppList $ProblematicApps
    
    # Remove provisioned packages
    Remove-ProvisionedPackages -AppList $ProblematicApps
    
    # Handle Edge WebView issues
    Fix-EdgeWebView
    
    # Remove problematic capabilities
    Remove-ProblematicCapabilities
    
    # Clear Windows Update Medic cache
    Clear-UpdateMedicCache
    
    # Run DISM cleanup
    Invoke-DismCleanup
    
    Write-Log "=== SYSPREP CLEANUP COMPLETED ===" "INFO"
    Write-Log "Please review the log for any errors before running Sysprep" "WARN"
    Write-Log "Recommended: Restart the system before running Sysprep" "WARN"
    
    # Display summary
    Write-Host "`n" -ForegroundColor Green
    Write-Host "Sysprep Cleanup Summary:" -ForegroundColor Green
    Write-Host "- Removed problematic AppX packages" -ForegroundColor Yellow
    Write-Host "- Cleaned provisioned app packages" -ForegroundColor Yellow
    Write-Host "- Addressed Edge WebView2 issues" -ForegroundColor Yellow
    Write-Host "- Removed problematic Windows capabilities" -ForegroundColor Yellow
    Write-Host "- Cleared Windows Update caches" -ForegroundColor Yellow
    Write-Host "- Ran DISM component cleanup" -ForegroundColor Yellow
    Write-Host "`nLog file saved to: $LogPath" -ForegroundColor Cyan
    Write-Host "`nIMPORTANT: Restart the system before running Sysprep!" -ForegroundColor Red
    
} catch {
    Write-Log "Critical error during cleanup: $($_.Exception.Message)" "ERROR"
    Write-Host "Critical error occurred. Check the log file: $LogPath" -ForegroundColor Red
    exit 1
}

# Usage examples:
# .\SysprepCleanup.ps1                    # Run normally
# .\SysprepCleanup.ps1 -WhatIf            # Preview what would be done
# .\SysprepCleanup.ps1 -Verbose           # Verbose output
# .\SysprepCleanup.ps1 -LogPath "C:\Logs\cleanup.log"  # Custom log location
