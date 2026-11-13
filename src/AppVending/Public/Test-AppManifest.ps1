function Test-AppManifest {
    <#
    .SYNOPSIS
        Validates app registration manifests against the schema and the policy.

    .DESCRIPTION
        Accepts a manifest file or a folder. A folder is searched recursively for YAML files and
        additionally checked for duplicate application names, because the name must be unique
        in the tenant.

        Returns one finding per violation. No output means every manifest is valid.

    .EXAMPLE
        Test-AppManifest -Path apps

    .EXAMPLE
        $findings = Test-AppManifest -Path apps/payments/payments-api-prod.yaml
        if ($findings) { $findings | Format-Table -AutoSize; exit 1 }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$PolicyPath = (Join-Path $script:RepoRoot 'config' 'policy.yaml'),

        [string]$SchemaPath = (Join-Path $script:RepoRoot 'schemas' 'app.schema.json')
    )

    $policy = Get-AppVendingPolicy -Path $PolicyPath

    $item = Get-Item -LiteralPath $Path
    $files = if ($item.PSIsContainer) {
        @(Get-ChildItem -LiteralPath $item.FullName -File -Recurse | Where-Object Extension -In '.yaml', '.yml' | Sort-Object FullName)
    }
    else {
        @($item)
    }

    $findings = [System.Collections.Generic.List[object]]::new()
    $validManifests = [System.Collections.Generic.List[object]]::new()

    foreach ($file in $files) {
        $manifest = Import-AppManifest -Path $file.FullName

        if ($manifest.ParseError) {
            $findings.Add((New-Finding -Path $manifest.Path -Rule 'yaml' -Message "The file is not valid YAML: $($manifest.ParseError)"))
            continue
        }

        $schemaMessages = Test-ManifestSchema -Data $manifest.Data -SchemaPath $SchemaPath
        if ($schemaMessages.Count -gt 0) {
            foreach ($message in $schemaMessages) {
                $findings.Add((New-Finding -Path $manifest.Path -Rule 'schema' -Message $message))
            }
            continue
        }

        $validManifests.Add($manifest)
        foreach ($finding in (Test-ManifestPolicy -Manifest $manifest -Policy $policy)) {
            $findings.Add($finding)
        }
    }

    $duplicates = $validManifests | Group-Object -Property { $_.Data['name'] } | Where-Object Count -GT 1
    foreach ($group in $duplicates) {
        foreach ($manifest in $group.Group) {
            $others = ($group.Group | Where-Object { $_.Path -ne $manifest.Path }).Path -join ', '
            $findings.Add((New-Finding -Path $manifest.Path -Rule 'duplicate-name' -Message "Application name '$($group.Name)' is also used by: $others"))
        }
    }

    return $findings.ToArray()
}
