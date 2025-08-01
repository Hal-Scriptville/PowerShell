# Intune AutoEnrollment Script - Usage Instructions

## Overview
This script provides automated Intune enrollment for Entra-joined devices with comprehensive error handling, logging, and diagnostic capabilities.

## Usage Instructions

To use this script effectively:

- **1. Prerequisites Check** - Ensure all users have appropriate Intune licenses and enrollment permissions.
- **2. Configure Auto-Enrollment** - In Entra ID admin center, set up MDM User Scope and MDM URLs.
- **3. Deployment** - Deploy via Datto RMM or other management platform
- **4. Monitoring** - Track results with the standardized exit codes:
  - 0 = Success (enrolled)
  - 1 = Not Entra-joined
  - 2 = DeviceEnroller missing
  - 3 = Pending enrollment
  - 4 = Deferred (no interactive user)
  - 5 = Policy write failure

## Modular Design

The script is designed with modularity in mind, allowing for flexible implementation:

- **Enhanced Device Information** - Uses CIM instead of WMI for better performance and compatibility.
- **Scheduled Task Discovery** - Robustly identifies and triggers the appropriate enrollment tasks.
- **Event Log Checking** - Comprehensive verification of enrollment status through Windows event logs.
- **Interactive User Detection** - Identifies if a user is logged in for PRT-dependent enrollment.
- **Architecture-Agnostic Registry Operations** - Properly handles registry operations regardless of OS architecture.
- **DeviceEnroller With Retry Logic** - Implements intelligent retry mechanisms for enrollment attempts.
- **MDM Diagnostics Collection** - Captures diagnostic information when enrollment fails for troubleshooting.
- **Network Awareness** - Identifies proxy configurations that might affect enrollment.

Each of these components can be implemented independently or as part of the complete solution, allowing for customization based on specific organizational needs.

## Prerequisites

- Windows 10/11 device
- Device must be Entra ID (Azure AD) joined
- User must have appropriate Intune licenses
- MDM auto-enrollment configured in Entra ID

## Logging

The script creates detailed logs at:
- Path: `$env:ProgramData\IntuneEnrollment`
- Format: `EnrollmentLog_YYYYMMDD_HHMMSS.log`

## Troubleshooting

If enrollment fails, the script automatically:
- Captures MDM diagnostic information
- Logs detailed error information
- Provides specific exit codes for targeted remediation

For manual troubleshooting, check:
1. Event Viewer: Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin
2. Registry: HKLM\SOFTWARE\Microsoft\Enrollments
3. Scheduled Tasks: \Microsoft\Windows\EnterpriseMgmt\