# PowerShell script to create 100 text files

# Define the directory where you want to create the files
$directoryPath = "C:user\documents\hal\test"

# Create the directory if it doesn't exist
if (!(Test-Path -Path $directoryPath)) {
    New-Item -ItemType Directory -Force -Path $directoryPath
}

# Loop to create 100 text files
for ($i = 1; $i -le 100; $i++) {
    $fileName = "File$i.txt"
    $filePath = Join-Path -Path $directoryPath -ChildPath $fileName

    # Create a new text file
    New-Item -ItemType File -Path $filePath -Force

    # Optional: Add content to the file
    # Add-Content -Path $filePath -Value "This is file number $i"
}

Write-Host "100 text files have been created in $directoryPath"
