<#
.SYNOPSIS
    Scheduled task to automatically assign ALL users to security groups based on OU membership.

.DESCRIPTION
    This script runs on a schedule (e.g., daily) and processes all users in Active Directory,
    assigning them to the appropriate security group based on their OU location.
    Groups are prefixed with "SG-" to indicate they are derived from OU membership.

    Version 2.0 adds a CLEANUP PHASE to remove orphaned group memberships:
    - Removes disabled users from security groups
    - Removes users no longer in any mapped OU
    - Removes users from incorrect groups

    Version 2.1 changes OU matching logic:
    - Only checks immediate parent OU (no longer walks up DN tree)
    - Allows root OU to be mapped without affecting sub-OU users

.NOTES
    Author: HK
    Date: 2025-10-24
    Version: 2.1 (Fixed OU matching to check immediate parent only)

    Requirements:
    - ActiveDirectory PowerShell module
    - Domain-joined computer
    - Service account with permissions to read AD users and modify group membership
    - Scheduled Task configured to run this script
    - PowerShell 5.1+ (Windows PowerShell compatible)

.EXAMPLE
    .\Sync-OUToSecurityGroups-Scheduled.ps1

    Processes all users and assigns them to appropriate security groups, then cleans up orphaned memberships.

.EXAMPLE
    .\Sync-OUToSecurityGroups-Scheduled.ps1 -WhatIf

    Shows what changes would be made without actually making them.

.EXAMPLE
    .\Sync-OUToSecurityGroups-Scheduled.ps1 -SearchBase "OU=Users,DC=contoso,DC=com"

    Only processes users within the specified OU.

.EXAMPLE
    .\Sync-OUToSecurityGroups-Scheduled.ps1 -SkipCleanup

    Runs sync but skips cleanup phase (faster, but may leave orphaned memberships).
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\Windows\Temp\OUToSecurityGroupsSync.log",

    [Parameter(Mandatory=$false)]
    [string]$SearchBase = "OU=Users,DC=contoso,DC=com",

    [Parameter(Mandatory=$false)]
    [string]$SecurityGroupsOU = "",

    [Parameter(Mandatory=$false)]
    [switch]$SkipCleanup
)

# Function to write to log file
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARNING","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    $logDir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path $logDir)) { 
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null 
    }
    
    Add-Content -Path $LogPath -Value $LogMessage
    switch ($Level) {
        "ERROR"   { Write-Error $Message }
        "WARNING" { Write-Warning $Message }
        "DEBUG"   { Write-Verbose $Message }
        default   { Write-Verbose $Message }
    }
}

# Start logging
Write-Log "=========================================="
Write-Log "OU to Security Groups Sync - SCHEDULED TASK v2.1"
Write-Log "=========================================="
Write-Log "Script started"
Write-Log "Search Base: $SearchBase"
Write-Log "Cleanup Phase: $(-not $SkipCleanup)"
Write-Log ("WhatIf Mode: {0}" -f ([bool]$WhatIfPreference))

# Statistics tracking
$Stats = @{
    TotalUsers       = 0
    ProcessedUsers   = 0
    UsersAdded       = 0
    UsersRemoved     = 0
    UsersSkipped     = 0
    OrphanedRemoved  = 0
    Errors           = 0
}

try {
    # Import Active Directory module
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "Active Directory module imported successfully"

    # --- Resolve & validate Security Groups OU (PowerShell 5.1 compatible) ---
    # FIXED: Replaced ?? operator with standard PowerShell 5.1 syntax
    if (-not $SecurityGroupsOU) {
        $SecurityGroupsOU = "OU=Security Groups,OU=Groups,$((Get-ADDomain).DistinguishedName)"
        Write-Log "SecurityGroupsOU not provided; defaulting to $SecurityGroupsOU"
    } else {
        $SecurityGroupsOU = $SecurityGroupsOU.Trim()
    }

    try {
        $securityOuObj = Get-ADOrganizationalUnit -Identity $SecurityGroupsOU -ErrorAction Stop
        $securityOuDN  = $securityOuObj.DistinguishedName
        Write-Log "Security Groups OU resolved: $securityOuDN"
    } catch {
        $msg = "Security Groups OU not found: '$SecurityGroupsOU'. It must be an OU DN (e.g., OU=Security Groups,OU=Groups,DC=contoso,DC=com)"
        Write-Log $msg "ERROR"
        throw $msg
    }

    # Define OU to Group mapping (keys are OU names)
    $OUGroupMap = @{
        "Finance"            = "SG-Finance"
        "IT"                 = "SG-IT"
        "HR"                 = "SG-HR"
        "Sales"              = "SG-Sales"
        "Marketing"          = "SG-Marketing"
        "Test OU"            = "SG-Test_OU"
        "Executives"         = "SG-Executives"
        "Contractors"        = "SG-Contractors"
        "Support"            = "SG-Support"
        "Development"        = "SG-Development"
    }

    Write-Log "OU to Group mappings loaded: $($OUGroupMap.Count) mappings"

    # Get all enabled users
    Write-Log "Retrieving all enabled users from: $SearchBase"
    $Users = Get-ADUser -Filter { Enabled -eq $true } `
                        -SearchBase $SearchBase `
                        -Properties DistinguishedName, MemberOf, SamAccountName `
                        -ResultPageSize 2000 `
                        -ErrorAction Stop

    $Stats.TotalUsers = $Users.Count
    Write-Log "Found $($Stats.TotalUsers) enabled users to process"

    # Check if no users were found
    if ($Stats.TotalUsers -eq 0) {
        Write-Log "No enabled users found in SearchBase: $SearchBase" "WARNING"
    }

    # Ensure Security Groups OU exists (create if missing)
    try {
        $null = Get-ADOrganizationalUnit -Identity $SecurityGroupsOU -ErrorAction Stop
        Write-Log "Security Groups OU exists: $SecurityGroupsOU"
    } catch {
        Write-Log "Security Groups OU not found: $SecurityGroupsOU" "WARNING"
        # Attempt to derive parent path & name from provided DN
        if ($SecurityGroupsOU -match '^OU=([^,]+),(.*)$') {
            $ouName = $Matches[1]
            $parentPath = $Matches[2]
            $action = "Create OU '$ouName' at '$parentPath'"
            if ($PSCmdlet.ShouldProcess($SecurityGroupsOU, $action)) {
                New-ADOrganizationalUnit -Name $ouName `
                    -Path $parentPath `
                    -Description "Security groups for OU-based access policies" `
                    -ProtectedFromAccidentalDeletion $true `
                    -ErrorAction Stop
                Write-Log "Security Groups OU created successfully"
            } else {
                Write-Log "Skipped: $action (WhatIf/Confirm)" "WARNING"
            }
        } else {
            $msg = "Unable to parse SecurityGroupsOU DN '$SecurityGroupsOU' for creation. It must be an OU DN (e.g., OU=Security Groups,OU=Groups,DC=contoso,DC=com)"
            Write-Log $msg "ERROR"
            throw $msg
        }
    }

    # Pre-create all groups if they don't exist
    Write-Log "Ensuring all security groups exist under $securityOuDN ..."
    $AllSecurityGroups = $OUGroupMap.Values | Select-Object -Unique

    foreach ($GroupName in $AllSecurityGroups) {
        try {
            # Search for group anywhere in domain with proper quote escaping
            $escaped = $GroupName -replace "'", "''"
            $existing = Get-ADGroup -Filter "Name -eq '$escaped'" -ErrorAction SilentlyContinue
            
            # Alternative: Scoped search
            # $existing = Get-ADGroup -LDAPFilter "(name=$escaped)" -SearchBase $securityOuDN -SearchScope Subtree -ErrorAction SilentlyContinue

            if (-not $existing) {
                $action = "Create security group '$GroupName' in '$securityOuDN'"
                Write-Log $action
                if ($PSCmdlet.ShouldProcess($GroupName, $action)) {
                    New-ADGroup -Name $GroupName -Path $securityOuDN `
                                -GroupScope Global -GroupCategory Security `
                                -Description "OU-based security group (Auto-managed by scheduled task)" `
                                -ErrorAction Stop
                    Write-Log "Group created: $GroupName"
                } else {
                    Write-Log "Skipped: $action (WhatIf/Confirm)" "WARNING"
                }
            } else {
                Write-Log "Group already exists: $GroupName at $($existing.DistinguishedName)"
            }
        } catch {
            Write-Log "Error creating or checking group '$GroupName' : $($_.Exception.Message)" "ERROR"
            $Stats.Errors++
        }
    }

    # ========================================
    # PHASE 1: PROCESS USERS (Add to groups)
    # ========================================
    Write-Log "=========================================="
    Write-Log "PHASE 1: Processing users for group assignment"
    Write-Log "=========================================="

    foreach ($User in $Users) {
        $Stats.ProcessedUsers++
        try {
            $DN = $User.DistinguishedName

            # Check ONLY the immediate parent OU (don't recurse up the tree)
            $PrimaryOU = $null
            $dnParts = $DN -split ','
            foreach ($part in $dnParts) {
                if ($part -like 'OU=*') {
                    $ouName = $part.Substring(3)  # drop 'OU='
                    # Only check immediate parent OU, don't walk up the tree
                    if ($OUGroupMap.ContainsKey($ouName)) {
                        $PrimaryOU = $ouName
                    }
                    # Always break after first OU check
                    break
                }
            }

            if (-not $PrimaryOU) {
                Write-Log "User $($User.SamAccountName) not in any mapped OU (DN: $DN)" "DEBUG"
                $Stats.UsersSkipped++
                continue
            }

            # Determine target group
            $TargetGroup = $OUGroupMap[$PrimaryOU]
            if (-not $TargetGroup) {
                Write-Log "User $($User.SamAccountName) in unmapped OU: $PrimaryOU" "WARNING"
                $Stats.UsersSkipped++
                continue
            }

            # Get target group DN (ensure exists)
            try {
                $TargetGroupObj = Get-ADGroup -Identity $TargetGroup -ErrorAction Stop
            } catch {
                Write-Log "Target group '$TargetGroup' not found for user $($User.SamAccountName). Group may have failed to create." "ERROR"
                $Stats.Errors++
                continue
            }

            # Normalize memberOf to array
            $memberOf = @()
            if ($null -ne $User.MemberOf) { $memberOf = @($User.MemberOf) }

            # Add to target group if not already a member
            if (-not ($memberOf -contains $TargetGroupObj.DistinguishedName)) {
                $action = "Add $($User.SamAccountName) to '$TargetGroup'"
                Write-Log $action
                if ($PSCmdlet.ShouldProcess($TargetGroup, $action)) {
                    Add-ADGroupMember -Identity $TargetGroup -Members $User -ErrorAction Stop
                    $Stats.UsersAdded++  # Only increment if action was taken
                } else {
                    Write-Log "Skipped: $action (WhatIf/Confirm)" "WARNING"
                }
            }

            # Remove from other security groups
            $OtherSecurityGroups = $AllSecurityGroups | Where-Object { $_ -ne $TargetGroup }
            foreach ($OtherGroup in $OtherSecurityGroups) {
                try {
                    $OtherGroupObj = Get-ADGroup -Identity $OtherGroup -ErrorAction SilentlyContinue
                    if ($OtherGroupObj -and ($memberOf -contains $OtherGroupObj.DistinguishedName)) {
                        $action = "Remove $($User.SamAccountName) from '$OtherGroup'"
                        Write-Log $action
                        if ($PSCmdlet.ShouldProcess($OtherGroup, $action)) {
                            Remove-ADGroupMember -Identity $OtherGroup -Members $User -Confirm:$false -ErrorAction Stop
                            $Stats.UsersRemoved++  # Only increment if action was taken
                        } else {
                            Write-Log "Skipped: $action (WhatIf/Confirm)" "WARNING"
                        }
                    }
                } catch {
                    # Group might not exist; log at DEBUG level
                    Write-Log "Lookup issue for group '$OtherGroup': $($_.Exception.Message)" "DEBUG"
                }
            }

        } catch {
            Write-Log "Error processing user $($User.SamAccountName): $($_.Exception.Message)" "ERROR"
            $Stats.Errors++
        }

        # Progress indicator every 50 users
        if ($Stats.ProcessedUsers % 50 -eq 0) {
            Write-Log "Progress: $($Stats.ProcessedUsers) / $($Stats.TotalUsers) users processed"
        }
    }

    Write-Log "Phase 1 completed: $($Stats.ProcessedUsers) users processed"

    # ========================================
    # PHASE 2: CLEANUP ORPHANED MEMBERSHIPS
    # ========================================

    if (-not $SkipCleanup) {
        Write-Log "=========================================="
        Write-Log "PHASE 2: Cleanup - Removing orphaned memberships"
        Write-Log "=========================================="

        foreach ($GroupName in $AllSecurityGroups) {
            try {
                $Group = Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue
                if (-not $Group) {
                    Write-Log "Group '$GroupName' not found, skipping cleanup" "WARNING"
                    continue
                }

                # Get all current members of this security group - ONLY USER OBJECTS
                $GroupMembers = Get-ADGroupMember -Identity $GroupName -ErrorAction SilentlyContinue | 
                                Where-Object { $_.objectClass -eq 'user' }

                if (-not $GroupMembers) {
                    Write-Log "Group '$GroupName' has no user members, skipping"
                    continue
                }

                Write-Log "Checking $($GroupMembers.Count) user members in group '$GroupName'"

                foreach ($Member in $GroupMembers) {
                    try {
                        # Get member's current OU and status - use DistinguishedName for clarity
                        $MemberUser = Get-ADUser -Identity $Member.DistinguishedName `
                                      -Properties DistinguishedName, Enabled -ErrorAction SilentlyContinue

                        if (-not $MemberUser) {
                            Write-Log "Member '$($Member.SamAccountName)' not found in AD, removing from '$GroupName'" "WARNING"
                            if ($PSCmdlet.ShouldProcess($GroupName, "Remove deleted user $($Member.SamAccountName)")) {
                                Remove-ADGroupMember -Identity $GroupName -Members $Member -Confirm:$false -ErrorAction Stop
                                $Stats.OrphanedRemoved++
                            }
                            continue
                        }

                        # Check if user is disabled
                        if (-not $MemberUser.Enabled) {
                            Write-Log "User '$($MemberUser.SamAccountName)' is disabled, removing from '$GroupName'"
                            if ($PSCmdlet.ShouldProcess($GroupName, "Remove disabled user $($MemberUser.SamAccountName)")) {
                                Remove-ADGroupMember -Identity $GroupName -Members $Member -Confirm:$false -ErrorAction Stop
                                $Stats.OrphanedRemoved++
                            }
                            continue
                        }

                        # Check if user is still in a mapped OU (immediate parent only)
                        $DN = $MemberUser.DistinguishedName
                        $dnParts = $DN -split ','
                        $UserPrimaryOU = $null

                        foreach ($part in $dnParts) {
                            if ($part -like 'OU=*') {
                                $ouName = $part.Substring(3)
                                # Only check immediate parent OU
                                if ($OUGroupMap.ContainsKey($ouName)) {
                                    $UserPrimaryOU = $ouName
                                }
                                # Always break after first OU check
                                break
                            }
                        }

                        # If user not in any mapped OU, remove from group
                        if (-not $UserPrimaryOU) {
                            Write-Log "User '$($MemberUser.SamAccountName)' not in any mapped OU, removing from '$GroupName'"
                            if ($PSCmdlet.ShouldProcess($GroupName, "Remove unmapped user $($MemberUser.SamAccountName)")) {
                                Remove-ADGroupMember -Identity $GroupName -Members $Member -Confirm:$false -ErrorAction Stop
                                $Stats.OrphanedRemoved++
                            }
                            continue
                        }

                        # If user should be in a different group, remove from this one
                        $CorrectGroup = $OUGroupMap[$UserPrimaryOU]
                        if ($CorrectGroup -ne $GroupName) {
                            Write-Log "User '$($MemberUser.SamAccountName)' should be in '$CorrectGroup', not '$GroupName', removing"
                            if ($PSCmdlet.ShouldProcess($GroupName, "Remove misplaced user $($MemberUser.SamAccountName)")) {
                                Remove-ADGroupMember -Identity $GroupName -Members $Member -Confirm:$false -ErrorAction Stop
                                $Stats.OrphanedRemoved++
                            }
                        }

                    } catch {
                        Write-Log "Error checking member $($Member.SamAccountName) in group '$GroupName': $($_.Exception.Message)" "ERROR"
                        $Stats.Errors++
                    }
                }

            } catch {
                Write-Log "Error during cleanup for group '$GroupName': $($_.Exception.Message)" "ERROR"
                $Stats.Errors++
            }
        }

        Write-Log "Phase 2 completed: $($Stats.OrphanedRemoved) orphaned memberships removed"
    } else {
        Write-Log "Cleanup phase skipped (-SkipCleanup parameter used)"
    }

    # Final summary
    Write-Log "=========================================="
    Write-Log "SYNC COMPLETED"
    Write-Log "=========================================="
    Write-Log "Total Users Found: $($Stats.TotalUsers)"
    Write-Log "Users Processed: $($Stats.ProcessedUsers)"
    Write-Log "Users Added to Groups: $($Stats.UsersAdded)"
    Write-Log "Users Removed from Groups: $($Stats.UsersRemoved)"
    Write-Log "Users Skipped: $($Stats.UsersSkipped)"
    Write-Log "Orphaned Memberships Removed: $($Stats.OrphanedRemoved)"
    Write-Log "Errors: $($Stats.Errors)"
    Write-Log "=========================================="

    if ($Stats.Errors -gt 0) {
        Write-Log "Script completed with errors" "WARNING"
        exit 1
    } else {
        Write-Log "Script completed successfully"
        exit 0
    }

} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
