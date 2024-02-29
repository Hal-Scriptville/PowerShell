# Get all GPOs and generate XML report for each

# Set the output path where the XML reports will be saved

$outputPath = "C:\GPOReports\"

if (!(Test-Path $outputPath)) {

New-Item -ItemType Directory -Path $outputPath

# Get all Group Policy Objects from the domain

$allGPOs = Get-GPO -All

# Loop through each GPO and export it to an XML report

foreach ($gpo in $allGPOs) {

$gpoReport = get-gporeport $gpo.DisplayName -ReportType xml

out-File -filepath ($outputpath + $gpo.DisplayName + ".xml") -inputobject $gpoReport

Write-Host "Exported GPO $($gpo.DisplayName)"

}

}