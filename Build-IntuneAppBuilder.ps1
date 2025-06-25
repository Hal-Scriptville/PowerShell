# Define the base path (current location or customize)
$basePath = Join-Path -Path $PSScriptRoot -ChildPath "App"

# Define folder structure
$folders = @(
    $basePath,
    "$basePath\Intune",
    "$basePath\Source",
    "$basePath\Detection",
    "$basePath\Output"
)

# Create folders if they don't exist
foreach ($folder in $folders) {
    if (-not (Test-Path -Path $folder)) {
        New-Item -Path $folder -ItemType Directory | Out-Null
        Write-Host "Created folder: $folder"
    } else {
        Write-Host "Folder already exists: $folder"
    }
}

# Updated correct binary download URL
$downloadUrl = "https://raw.githubusercontent.com/microsoft/Microsoft-Win32-Content-Prep-Tool/master/IntuneWinAppUtil.exe"
$destination = Join-Path -Path $basePath -ChildPath "IntuneWinAppUtil.exe"

try {
    Write-Host "Downloading IntuneWinAppUtil.exe..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $destination -UseBasicParsing
    Write-Host "Download complete: $destination"

    # Unblock the file
    Unblock-File -Path $destination
    Write-Host "File unblocked."
} catch {
    Write-Warning "Failed to download IntuneWinAppUtil.exe: $_"
}
