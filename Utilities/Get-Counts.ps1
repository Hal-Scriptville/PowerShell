# List of your domains
$domains = get-content -path c:\temp\Domain_List.txt

# Base directory where domain-named folders are located
$baseDirectory = "C:\temp\Domains"


# Initialize an array to hold the result objects
$results = @()

# Loop through each domain
foreach ($domain in $domains) {
    # Count GPOs
    $gpoCount = (Get-GPO -All -Domain $domain).Count

    # Construct folder path
    $folderPath = Join-Path -Path $baseDirectory -ChildPath $domain

    # Count files in the folder
    if (Test-Path -Path $folderPath) {
        $items = Get-ChildItem -Path $folderPath -directory -Force
        $fileCount = $items.Count
        # Diagnostic output
        Write-Host "Items in $folderPath"
        $items | ForEach-Object { Write-Host "`t$($_.Name)" }
    } else {
        $fileCount = "Folder not found"
    }

    # Add results to the array
    $results += [PSCustomObject]@{
        Domain = $domain
        GPOCount = $gpoCount
        FileCount = $fileCount
    }
}

# Output results to Out-GridView
$results | Out-GridView -Title "Domain, GPO, and Folder Counts"
