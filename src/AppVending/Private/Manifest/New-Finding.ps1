function New-Finding {
    <#
    .SYNOPSIS
        Creates one validation finding.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only.')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Rule,

        [Parameter(Mandatory)]
        [string]$Message
    )

    [pscustomobject]@{
        Path    = $Path
        Rule    = $Rule
        Message = $Message
    }
}
