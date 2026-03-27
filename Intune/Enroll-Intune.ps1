# Function to get Tenant ID
function Get-TenantID {
    param (
        [string]$KeyPath
    )
    
    try {
        $keyinfo = Get-Item "HKLM:\$KeyPath"
        return $keyinfo.name.Split("\")[-1]
    } catch {
        Write-Error "Tenant ID is not found!"
        exit 1001
    }
}

# Function to set MDM Enrollment URLs
function Set-MDMEnrollmentURLs {
    param (
        [string]$Path
    )

    if (!(Test-Path $Path)) {
        Write-Error "KEY $Path not found!"
        exit 1002
    } else {
        try {
            Get-ItemProperty $Path -Name MdmEnrollmentUrl
        } catch {
            Write-Host "MDM Enrollment registry keys not found. Registering now..."
            New-ItemProperty -LiteralPath $Path -Name 'MdmEnrollmentUrl' -Value 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc' -PropertyType String -Force -ErrorAction SilentlyContinue
            New-ItemProperty -LiteralPath $Path -Name 'MdmTermsOfUseUrl' -Value 'https://portal.manage.microsoft.com/TermsofUse.aspx' -PropertyType String -Force -ErrorAction SilentlyContinue
            New-ItemProperty -LiteralPath $Path -Name 'MdmComplianceUrl' -Value 'https://portal.manage.microsoft.com/?portalAction=Compliance' -PropertyType String -Force -ErrorAction SilentlyContinue
        } finally {
            # Trigger AutoEnroll with the deviceenroller
            try {
                & C:\Windows\system32\deviceenroller.exe /c /AutoEnrollMDM
                Write-Host "Device is performing the MDM enrollment!"
                exit 0
            } catch {
                Write-Error "Something went wrong (C:\Windows\system32\deviceenroller.exe)"
                exit 1003
            }
        }
    }
}

# Main script logic
$key = 'SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\*'
$tenantID = Get-TenantID -KeyPath $key
$path = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\$tenantID"
Set-MDMEnrollmentURLs -Path $path
exit 0
