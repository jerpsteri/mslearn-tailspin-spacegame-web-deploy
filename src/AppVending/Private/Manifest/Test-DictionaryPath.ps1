function Test-DictionaryPath {
    <#
    .SYNOPSIS
        Returns $true when every key on the path exists in parsed YAML, even if the value is empty.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Data,

        [Parameter(Mandatory)]
        [string[]]$Path
    )

    $current = $Data
    foreach ($key in $Path) {
        if ($current -isnot [System.Collections.IDictionary] -or -not $current.Contains($key)) {
            return $false
        }
        $current = $current[$key]
    }

    return $true
}
