# Shared helpers for the unit tests. Dot-source from BeforeAll.

function Get-RepoRoot {
    (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).ProviderPath
}

function Import-AppVendingModule {
    Import-Module (Join-Path (Get-RepoRoot) 'src' 'AppVending' 'AppVending.psd1') -Force
}

function New-ManifestData {
    # A manifest that passes the schema and the default policy.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param([string]$Name = 'sample-app')

    [ordered]@{
        apiVersion  = 'appvending/v1'
        name        = $Name
        displayName = 'Sample App'
        description = 'Application used by the unit tests.'
        owners      = @('alice@contoso.com', 'bob@contoso.com')
    }
}

function Save-Manifest {
    # Writes manifest data to <Root>/apps/<Team>/<FileName> and returns the path.
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Data,
        [Parameter(Mandatory)][string]$Root,
        [string]$Team = 'team-a',
        [string]$FileName
    )

    if (-not $FileName) { $FileName = "$($Data['name']).yaml" }
    $folder = Join-Path $Root 'apps' $Team
    $null = New-Item -ItemType Directory -Path $folder -Force
    $path = Join-Path $folder $FileName
    ConvertTo-Yaml -Data $Data | Set-Content -LiteralPath $path
    return $path
}
