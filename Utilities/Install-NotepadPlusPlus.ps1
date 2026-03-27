
# Define the download URL and the destination
$notepadppUrl = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.4/npp.8.6.4.Installer.x64.exe"
$destination = "$env:TEMP\notepadpp_installer.exe"

# Download Notepad++ installer
Invoke-WebRequest -Uri $notepadppUrl -OutFile $destination

# Install Notepad++ silently
Start-Process -FilePath "$env:TEMP\notepadpp_installer.exe" -ArgumentList "/S"
