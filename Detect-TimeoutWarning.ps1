$idletime = 8 * 60  # idle time before the lock in seconds (e.g., 8 minutes for a 10-minute lock)
$lastinputinfo = new-object "lastinputinfo"
$lastinputinfo.cbsize = [system.runtime.interopservices.marshal]::sizeof($lastinputinfo)
[system.runtime.interopservices.marshal]::getlastwin32error()
if ([system.runtime.interopservices.marshal]::getlastinputinfo([ref]$lastinputinfo)) {
    $idletimepassed = ((get-tickcount) - $lastinputinfo.dwtime) / 1000
    if ($idletimepassed -gt $idletime) {
        exit 1  # Issue detected
    }
}
exit 0  # No issue detected
