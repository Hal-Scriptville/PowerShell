# Script parameters
param(
    [Parameter(Mandatory=$true)]
    [string]$UserPrincipalName,
    [switch]$WhatIf
)

# Function for logging
function Write-Log {
    param($Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Write-Host $logMessage
    Add-Content -Path "RetentionPolicy_Changes.log" -Value $logMessage
}

try {
    # Connect to Exchange Online with error handling
    Write-Log "Attempting to connect to Exchange Online..."
    Connect-ExchangeOnline -UserPrincipalName $UserPrincipalName -ErrorAction Stop

    # Get all user mailboxes with rate limiting
    Write-Log "Retrieving mailboxes..."
    $Mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox
    $totalMailboxes = $Mailboxes.Count
    $counter = 0

    foreach ($Mailbox in $Mailboxes) {
        $counter++
        $MailboxIdentity = $Mailbox.PrimarySmtpAddress
        Write-Log "Processing mailbox ($counter/$totalMailboxes): $MailboxIdentity"

        try {
            # Get the mailbox retention policy
            $RetentionPolicy = Get-Mailbox $MailboxIdentity | 
                Select-Object -ExpandProperty RetentionPolicy

            if ($RetentionPolicy) {
                Write-Log "Current Retention Policy: $RetentionPolicy"

                # Get the retention tags with error handling
                $RetentionTags = Get-RetentionPolicy $RetentionPolicy -ErrorAction Stop | 
                    Select-Object -ExpandProperty RetentionPolicyTagLinks

                # Filter out Notes and Tasks tags
                $UpdatedTags = @()
                foreach ($Tag in $RetentionTags) {
                    $TagDetails = Get-RetentionPolicyTag $Tag
                    if ($TagDetails.Type -ne "Notes" -and $TagDetails.Type -ne "Tasks") {
                        $UpdatedTags += $TagDetails.Name
                    } else {
                        Write-Log "Excluding tag: $($TagDetails.Name)"
                    }
                }

                # Create a new retention policy without Notes and Tasks
                $NewPolicyName = "$RetentionPolicy - No Notes/Tasks"
                if (-not (Get-RetentionPolicy -Identity $NewPolicyName -ErrorAction SilentlyContinue)) {
                    if ($WhatIf) {
                        Write-Log "WhatIf: Would create new policy: $NewPolicyName"
                    } else {
                        New-RetentionPolicy -Name $NewPolicyName -RetentionPolicyTagLinks $UpdatedTags
                        Write-Log "Created new policy: $NewPolicyName"
                    }
                }

                # Backup current policy settings
                $BackupFile = "RetentionPolicy_Backup_$(Get-Date -Format 'yyyyMMdd').json"
                $CurrentSettings = Get-Mailbox $MailboxIdentity | 
                    Select-Object PrimarySmtpAddress, RetentionPolicy
                $CurrentSettings | ConvertTo-Json | Add-Content -Path $BackupFile

                # Assign the new retention policy with confirmation
                if ($WhatIf) {
                    Write-Log "WhatIf: Would update mailbox $MailboxIdentity with policy $NewPolicyName"
                } else {
                    $confirmation = Read-Host "Update retention policy for $MailboxIdentity? (Y/N)"
                    if ($confirmation -eq 'Y') {
                        Set-Mailbox $MailboxIdentity -RetentionPolicy $NewPolicyName
                        Write-Log "Updated mailbox $MailboxIdentity with retention policy $NewPolicyName"

                        # Verify the change
                        $verificationPolicy = (Get-Mailbox $MailboxIdentity).RetentionPolicy
                        if ($verificationPolicy -eq $NewPolicyName) {
                            Write-Log "Verification successful for $MailboxIdentity"
                        } else {
                            Write-Log "WARNING: Verification failed for $MailboxIdentity"
                        }
                    } else {
                        Write-Log "Skipped updating $MailboxIdentity based on user input"
                    }
                }
            } else {
                Write-Log "No retention policy found for $MailboxIdentity"
            }

            # Add delay to avoid throttling
            Start-Sleep -Milliseconds 500

        } catch {
            Write-Log "ERROR processing $MailboxIdentity: $($_.Exception.Message)"
            continue
        }
    }

} catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)"
} finally {
    # Disconnect from Exchange Online
    Write-Log "Disconnecting from Exchange Online..."
    Disconnect-ExchangeOnline -Confirm:$false
    Write-Log "Script execution completed"
}
