# Nuclear AppX cleanup - removes EVERYTHING except core Windows Store
Get-AppxPackage -AllUsers | Where-Object {$_.Name -ne "Microsoft.WindowsStore"} | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -ne "Microsoft.WindowsStore"} | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
