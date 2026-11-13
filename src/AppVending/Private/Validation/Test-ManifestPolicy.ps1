function Test-ManifestPolicy {
    <#
    .SYNOPSIS
        Evaluates a schema valid manifest against the policy and returns findings.

    .NOTES
        The function has no side effects and performs no network calls, so intake, CI and
        apply can all run exactly the same checks.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Manifest,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Policy
    )

    $data = $Manifest.Data
    $path = $Manifest.Path
    $name = [string]$data['name']
    $findings = [System.Collections.Generic.List[object]]::new()

    $add = {
        param($Rule, $Message)
        $findings.Add((New-Finding -Path $path -Rule $Rule -Message $Message))
    }

    # File placement: apps/<team>/<name>.yaml
    $file = [System.IO.FileInfo]$path
    if ($file.Extension -cne '.yaml' -or $file.BaseName -cne $name) {
        & $add 'file-name' "The file must be named '$name.yaml' to match the manifest name."
    }
    if ($null -eq $file.Directory.Parent -or $file.Directory.Parent.Name -cne 'apps') {
        & $add 'location' 'The manifest must be stored as apps/<team>/<name>.yaml.'
    }

    # Owners
    $owners = @(Get-DictionaryValue -Data $data -Path 'owners')
    if ($owners.Count -lt $Policy.owners.minimum) {
        & $add 'owners-minimum' "At least $($Policy.owners.minimum) owners are required, found $($owners.Count)."
    }
    $allowedDomains = @($Policy.owners.allowedDomains)
    if ($allowedDomains.Count -gt 0) {
        foreach ($owner in $owners) {
            $domain = ([string]$owner -split '@')[-1]
            if ($domain -notin $allowedDomains) {
                & $add 'owners-domain' "Owner '$owner' is not in an allowed domain ($($allowedDomains -join ', '))."
            }
        }
    }

    # Sign-in audience
    $audience = Get-DictionaryValue -Data $data -Path 'signInAudience'
    if ($null -eq $audience) { $audience = 'AzureADMyOrg' }
    if ($audience -notin @($Policy.signInAudience.allowed)) {
        & $add 'sign-in-audience' "Sign-in audience '$audience' is not allowed by policy."
    }

    # Redirect URIs
    $uriEntries = @(
        foreach ($platform in 'web', 'spa') {
            foreach ($uri in @(Get-DictionaryValue -Data $data -Path $platform, 'redirectUris')) {
                if ($null -ne $uri) { [pscustomobject]@{ Field = "$platform.redirectUris"; Uri = [string]$uri } }
            }
        }
        $logoutUrl = Get-DictionaryValue -Data $data -Path 'web', 'logoutUrl'
        if ($null -ne $logoutUrl) { [pscustomobject]@{ Field = 'web.logoutUrl'; Uri = [string]$logoutUrl } }
    )
    foreach ($entry in $uriEntries) {
        if ($entry.Uri.Contains('*')) {
            & $add 'redirect-uri' "$($entry.Field): '$($entry.Uri)' contains a wildcard."
            continue
        }

        $parsed = $null
        if (-not [uri]::TryCreate($entry.Uri, [System.UriKind]::Absolute, [ref]$parsed)) {
            & $add 'redirect-uri' "$($entry.Field): '$($entry.Uri)' is not a valid absolute URI."
            continue
        }

        $isLocalhost = $parsed.Host -in 'localhost', '127.0.0.1'
        $httpAllowed = -not $Policy.redirectUris.requireHttps -or ($Policy.redirectUris.allowLocalhost -and $isLocalhost)
        if ($parsed.Scheme -ne 'https' -and -not $httpAllowed) {
            & $add 'redirect-uri' "$($entry.Field): '$($entry.Uri)' must use https."
        }
    }

    # API permissions
    foreach ($request in @(Get-DictionaryValue -Data $data -Path 'requiredResourceAccess')) {
        if ($null -eq $request) { continue }

        $resource = [string]$request['resource']
        $allowed = @($Policy.permissions.allowed) | Where-Object { $_['resource'] -eq $resource } | Select-Object -First 1
        if ($null -eq $allowed) {
            & $add 'permission-not-allowed' "Resource '$resource' is not on the permission allowlist."
            continue
        }

        foreach ($type in 'delegated', 'application') {
            $allowedNames = @(Get-DictionaryValue -Data $allowed -Path $type)
            foreach ($permission in @(Get-DictionaryValue -Data $request -Path $type)) {
                if ($null -ne $permission -and $permission -cnotin $allowedNames) {
                    & $add 'permission-not-allowed' "The $type permission '$permission' on '$resource' is not on the permission allowlist."
                }
            }
        }
    }

    # Secrets
    $secretNames = @(
        foreach ($secret in @(Get-DictionaryValue -Data $data -Path 'secrets')) {
            if ($null -ne $secret) { [string]$secret['name'] }
        }
    )
    if ($secretNames.Count -gt 0) {
        if ($null -eq (Get-DictionaryValue -Data $data -Path 'keyVault', 'resourceId')) {
            & $add 'secret-key-vault' 'A manifest that declares secrets must also set keyVault.resourceId.'
        }
        if ($secretNames.Count -gt $Policy.secrets.maxPerApp) {
            & $add 'secret-limit' "At most $($Policy.secrets.maxPerApp) secrets are allowed per application, found $($secretNames.Count)."
        }
        foreach ($duplicate in ($secretNames | Group-Object | Where-Object Count -GT 1)) {
            & $add 'secret-duplicate' "Secret name '$($duplicate.Name)' is declared more than once."
        }
        foreach ($secretName in ($secretNames | Select-Object -Unique)) {
            $vaultSecretName = Get-VaultSecretName -AppName $name -SecretName $secretName
            if ($vaultSecretName.Length -gt 127) {
                & $add 'secret-name-length' "Key Vault secret name '$vaultSecretName' exceeds 127 characters."
            }
        }
    }

    return , $findings.ToArray()
}
