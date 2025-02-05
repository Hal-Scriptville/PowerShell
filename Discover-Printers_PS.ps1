$computers = Get-ADComputer -Filter "OperatingSystem -like 'Windows*'" |
             Select-Object -ExpandProperty Name

foreach ($computer in $computers) {
    try {
        $printers = Get-Printer -ComputerName $computer -ErrorAction Stop
        # Process or export $printers as needed
    }
    catch {
        Write-Warning "Failed to query printers on $computer. Error: $_"
    }
}
