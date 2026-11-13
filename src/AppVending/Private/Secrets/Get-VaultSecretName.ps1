function Get-VaultSecretName {
    <#
    .SYNOPSIS
        Returns the Key Vault secret name that holds a client secret of an application.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        # An empty value returns the name prefix shared by all secrets of the application.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$SecretName
    )

    return "$AppName-client-secret-$SecretName"
}
