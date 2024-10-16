# Upgrade_Apps.ps1
$appsToUpgrade = @("Apple.Bonjour", "Apple.iTunes", "VideoLAN.VLC", "Adobe.Acrobat.Reader.64-bit")

foreach ($app in $appsToUpgrade) {
    winget upgrade --id $app --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
}
