# Detect-BatteryHealth.ps1
# Proactive Remediation - Detection
#
# Checks battery health by comparing full charge capacity against
# design capacity. Flags batteries below the health threshold.
# Desktop/VM machines with no battery are considered compliant.
#
# Threshold: < 80% health = non-compliant (replace battery)
#
# Exit 0 = compliant (battery healthy or no battery present)
# Exit 1 = non-compliant (battery degraded)

$HealthThresholdPct = 80

try {
    # Query battery static data via WMI root\wmi namespace
    $BatteryStatic = Get-WmiObject -Namespace root\wmi -Class BatteryStaticData -ErrorAction SilentlyContinue
    $BatteryFull   = Get-WmiObject -Namespace root\wmi -Class BatteryFullChargedCapacity -ErrorAction SilentlyContinue

    if (-not $BatteryStatic -or -not $BatteryFull) {
        # No battery present (desktop or VM)
        Write-Output "COMPLIANT: No battery detected (desktop or VM)"
        exit 0
    }

    $DesignCapacity    = $BatteryStatic.DesignedCapacity
    $FullChargeCapacity = $BatteryFull.FullChargedCapacity

    if ($DesignCapacity -le 0) {
        Write-Output "COMPLIANT: Battery present but design capacity unavailable — skipping check"
        exit 0
    }

    $HealthPct = [math]::Round(($FullChargeCapacity / $DesignCapacity) * 100, 1)

    if ($HealthPct -lt $HealthThresholdPct) {
        Write-Output "NON-COMPLIANT: Battery health is $HealthPct% (threshold: $HealthThresholdPct%)"
        Write-Output "  Design capacity:     $DesignCapacity mWh"
        Write-Output "  Full charge capacity: $FullChargeCapacity mWh"
        Write-Output "  Action: Schedule battery replacement"
        exit 1
    }

    Write-Output "COMPLIANT: Battery health $HealthPct% ($FullChargeCapacity / $DesignCapacity mWh)"
    exit 0
}
catch {
    Write-Output "ERROR: $_"
    exit 1
}
