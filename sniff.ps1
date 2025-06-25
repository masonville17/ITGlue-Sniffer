# Load the IT Glue module if it's not already loaded
If (Get-Module -ListAvailable -Name "ITGlueAPIv2") { 
    Import-module ITGlueAPIv2 
} Else { 
    Install-Module ITGlueAPIv2 -Force
    Import-Module ITGlueAPIv2
}

$ITGKey = $ITGKey ?? "$(read-host "enter ITGKey")"
$ITGAPIEndpoint = $ITGAPIEndpoint ?? "https://api.itglue.com"
Add-ITGlueBaseURI -base_uri $ITGAPIEndpoint
Add-ITGlueAPIKey $ITGKey

if ((get-host).version.major -ne 7) {
    Write-Host "Powershell 7 Required" -foregroundcolor Red
    exit 1
}

$secondaryRequests = @(
    "Get-ITGlueConfigurationInterfaces",
    "Get-ITGlueFlexibleAssetFields",
    "Get-ITGlueFlexibleAssets"
)

# create a directory to store output
$outputDir = "ITGlueExports"

foreach ($folder in @($outputDir)) {
    if (!(Test-Path -Path "$folder")) { New-Item "$folder" -ItemType Directory }
    Get-ChildItem -Path "$folder" -File -Recurse -Force | Remove-Item -Force
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

# Get all functions from the ITGlue module that start with 'Get-'
$itgGetFunctions = Get-Command -Module ITGlueAPIv2 | Where-Object {
    $_.Name -like 'Get-*'
}

foreach ($func in $itgGetFunctions) {
    $funcName = $func.Name
    if ($secondaryRequests -contains $funcName) {
        continue
    }

    Write-Host "Invoking $funcName..." -ForegroundColor Cyan

    try {
        # Try to invoke with no parameters — some may require parameters, skip if so
        $result = & $funcName

        if ($result) {
            $filePath = Join-Path $outputDir "$funcName.json"
            $result | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8
            Write-Host "Wrote $funcName output to $filePath"
        } else {
            Write-Host "No data returned from $funcName"
        }
    } catch {
        Write-Host "Failed to invoke $funcName : $_" -ForegroundColor Red
    }
}

$configs = Get-ITGlueConfigurations
$pageSize = 100

foreach ($config in $configs.data) {
    $conf_id = $config.id
    $page = 1
    $allData = @()

    do {
        try {
            $result = Get-ITGlueConfigurationInterfaces -conf_id $conf_id -page_number $page -page_size $pageSize
            $dataPage = $result.data
            $allData += $dataPage
            $page++
        } catch {
            Write-Warning "Failed to get interfaces for configuration $conf_id on page $page"
            break
        }
    } while ($dataPage.Count -eq $pageSize)

    if ($allData.Count -gt 0) {
        $allData | ConvertTo-Json -Depth 10 | Set-Content -Path "ITGlueExports\Interfaces_$conf_id.json"
    }
}
$faTypes = Get-ITGlueFlexibleAssetTypes
$pageSize = 100

foreach ($type in $faTypes.data) {
    $typeId = $type.id
    $page = 1
    $allData = @()

    do {
        try {
            $result = Get-ITGlueFlexibleAssetFields -flexible_asset_type_id $typeId -page_number $page -page_size $pageSize
            $dataPage = $result.data
            $allData += $dataPage
            $page++
        } catch {
            Write-Warning "Failed to get flexible asset fields for type $typeId on page $page"
            break
        }
    } while ($dataPage.Count -eq $pageSize)

    if ($allData.Count -gt 0) {
        $allData | ConvertTo-Json -Depth 10 | Set-Content -Path "ITGlueExports\FlexibleAssetFields_$typeId.json"
    }
}
$orgs = Get-ITGlueOrganizations
$faTypes = Get-ITGlueFlexibleAssetTypes
$pageSize = 100

foreach ($org in $orgs.data) {
    foreach ($type in $faTypes.data) {
        $orgId = $org.id
        $typeId = $type.id
        $page = 1
        $allData = @()

        do {
            try {
                $result = Get-ITGlueFlexibleAssets -filter_flexible_asset_type_id $typeId -filter_organization_id $orgId -page_number $page -page_size $pageSize
                $dataPage = $result.data
                $allData += $dataPage
                $page++
            } catch {
                Write-Warning "Failed to get flexible assets for org $orgId and type $typeId on page $page"
                break
            }
        } while ($dataPage.Count -eq $pageSize)

        if ($allData.Count -gt 0) {
            $filePath = "ITGlueExports\FlexibleAssets_org${orgId}_type${typeId}.json"
            $allData | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath
        }
    }
}
