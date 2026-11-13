function Get-DictionaryValue {
    <#
    .SYNOPSIS
        Reads a nested value from parsed YAML and returns nothing when a key on the path is missing.

    .NOTES
        Lists are written to the pipeline item by item. Wrap the call in @() to get an array
        that is empty when the key is missing or the list has no items.
    #>
    [CmdletBinding()]
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
            return
        }
        $current = $current[$key]
    }

    return $current
}
