# Requires the ActiveDirectory module for Get-ADComputer (part of RSAT or installed on a domain-joined server).
# Adjust the -Filter and -SearchBase parameters as needed.

# 1. Gather a list of computers (example: all Windows computers in a specific OU).
$computers = Get-ADComputer -Filter "OperatingSystem -like 'Windows*'" -SearchBase "OU=Computers,DC=Contoso,DC=com" |
             Select-Object -ExpandProperty Name

# 2. Prepare a collection to store results.
$printerInventory = New-Object System.Collections.Generic.List[Object]

foreach ($computer in $computers) {
    Write-Host "Querying printers on $computer..."
    
    try {
        # Using WMI (DCOM) approach
        # Alternatively, you can use Get-CimInstance with -Authentication and -ComputerName if you prefer:
        # $printers = Get-CimInstance -ClassName Win32_Printer -ComputerName $computer

        $printers = Get-WmiObject -Class Win32_Printer -ComputerName $computer -ErrorAction Stop

        foreach ($printer in $printers) {
            $printerInfo = [PSCustomObject]@{
                ComputerName = $computer
                PrinterName  = $printer.Name
                DriverName   = $printer.DriverName
                PortName     = $printer.PortName
                ShareName    = $printer.ShareName
                SystemName   = $printer.SystemName
                Default      = $printer.Default
                Network      = $printer.Network
            }
            $printerInventory.Add($printerInfo)
        }
    }
    catch {
        Write-Warning "Failed to connect or query $computer. Error: $_"
    }
}

# 3. Export results to CSV
$exportPath = "C:\Temp\AllPrintersInventory.csv"
$printerInventory | Export-Csv -Path $exportPath -NoTypeInformation
Write-Host "Printer inventory exported to $exportPath"
