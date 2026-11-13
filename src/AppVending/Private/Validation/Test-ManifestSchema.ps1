function Test-ManifestSchema {
    <#
    .SYNOPSIS
        Validates manifest data against the JSON schema and returns one message per violation.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Data,

        [Parameter(Mandatory)]
        [string]$SchemaPath
    )

    if ($Data -isnot [System.Collections.IDictionary]) {
        return , @('The file must contain a YAML mapping at the top level.')
    }

    $json = ConvertTo-Json -InputObject $Data -Depth 20
    $schemaErrors = @()
    $null = Test-Json -Json $json -SchemaFile $SchemaPath -ErrorVariable schemaErrors -ErrorAction SilentlyContinue

    $messages = foreach ($schemaError in $schemaErrors) {
        $schemaError.Exception.Message -replace '^The JSON is not valid with the schema:\s*', ''
    }

    return , @($messages | Select-Object -Unique)
}
