Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).ProviderPath

# Names shared by the reconcile logic. Changing any of them orphans existing resources.
$script:Constants = @{
    ApiVersion             = 'appvending/v1'
    CredentialNamePrefix   = 'appvending:'
    VaultTagManagedBy      = 'managed-by'
    VaultTagManagedByValue = 'app-vending'
    VaultTagApp            = 'app'
    VaultTagKeyId          = 'keyId'
}

$files = @(
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -Recurse
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1'
)

foreach ($file in $files) {
    . $file.FullName
}
