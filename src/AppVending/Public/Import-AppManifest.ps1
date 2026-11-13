function Import-AppManifest {
    <#
    .SYNOPSIS
        Reads an app registration manifest from disk.

    .DESCRIPTION
        Parses the YAML file and returns its content together with the file path and the
        owning team, which is derived from the parent folder name. No validation is performed.
        Use Test-AppManifest for that.

    .EXAMPLE
        Import-AppManifest -Path apps/payments/payments-api-prod.yaml
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path
    )

    process {
        $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
        $raw = Get-Content -LiteralPath $resolved -Raw

        $data = $null
        $parseError = $null
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            try {
                $data = ConvertFrom-Yaml -Yaml $raw -Ordered
            }
            catch {
                $parseError = $_.Exception.Message
            }
        }

        [pscustomobject]@{
            Path       = $resolved
            Team       = Split-Path -Path (Split-Path -Path $resolved -Parent) -Leaf
            Data       = $data
            ParseError = $parseError
        }
    }
}
