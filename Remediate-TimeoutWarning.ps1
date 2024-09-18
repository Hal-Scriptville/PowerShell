$idletime = 8 * 60  # idle time before the lock in seconds (e.g., 8 minutes for a 10-minute lock)
$warningtime = 2 * 60  # warning time in seconds (2 minutes before lock)

$lastinputinfo = new-object "lastinputinfo"
$lastinputinfo.cbsize = [system.runtime.interopservices.marshal]::sizeof($lastinputinfo)
[system.runtime.interopservices.marshal]::getlastwin32error()
if ([system.runtime.interopservices.marshal]::getlastinputinfo([ref]$lastinputinfo)) {
    $idletimepassed = ((get-tickcount) - $lastinputinfo.dwtime) / 1000
    if ($idletimepassed -gt $idletime - $warningtime -and $idletimepassed -lt $idletime) {
        [system.windows.forms.messagebox]::show("Your device will lock in 2 minutes due to inactivity.", "Inactivity Warning")
    }
}
