function Get-AppVendingPolicy {
    <#
    .SYNOPSIS
        Loads the policy file and fails fast when a required setting is missing.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $policy = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Yaml -Ordered

    $required = @(
        , @('owners', 'minimum')
        , @('owners', 'allowedDomains')
        , @('signInAudience', 'allowed')
        , @('redirectUris', 'requireHttps')
        , @('redirectUris', 'allowLocalhost')
        , @('permissions', 'allowed')
        , @('secrets', 'lifetimeDays')
        , @('secrets', 'rotateBeforeDays')
        , @('secrets', 'maxPerApp')
        , @('secrets', 'unmanaged')
    )

    foreach ($keyPath in $required) {
        if (-not (Test-DictionaryPath -Data $policy -Path $keyPath)) {
            throw "Policy file '$Path' is missing the required setting '$($keyPath -join '.')'."
        }
    }

    if ($policy.secrets.rotateBeforeDays -ge $policy.secrets.lifetimeDays) {
        throw "Policy file '$Path' is invalid: secrets.rotateBeforeDays must be smaller than secrets.lifetimeDays."
    }

    return $policy
}
