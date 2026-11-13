function Compare-AppRegistration {
    <#
    .SYNOPSIS
        Compares the desired and the actual state of one application and returns the difference.

    .DESCRIPTION
        Both states use the same flat shape:

            DisplayName, Description, SignInAudience, WebLogoutUrl   scalar values
            WebRedirectUris, SpaRedirectUris                         case sensitive sets
            RequiredResourceAccess, OwnerIds                         case insensitive sets
            Tags                                                     tags that must be present
            ServicePrincipalEnabled                                  boolean

        RequiredResourceAccess items are strings in the form
        '<resourceAppId>/<permissionId>/<Scope|Role>'.

        The function is pure. It is the single source of truth for plan output and for the
        writes performed by apply, which is what makes a second run produce no changes.

    .OUTPUTS
        An object with Name, Action (Create, Update or None) and Changes. Each change has
        Property, Before, After, Add and Remove.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Desired,

        # $null when the application does not exist yet.
        [AllowNull()]
        [System.Collections.IDictionary]$Actual
    )

    $scalarProperties = 'DisplayName', 'Description', 'SignInAudience', 'WebLogoutUrl', 'ServicePrincipalEnabled'
    $setProperties = @(
        @{ Name = 'WebRedirectUris'; CaseSensitive = $true; AdditiveOnly = $false }
        @{ Name = 'SpaRedirectUris'; CaseSensitive = $true; AdditiveOnly = $false }
        @{ Name = 'RequiredResourceAccess'; CaseSensitive = $false; AdditiveOnly = $false }
        @{ Name = 'OwnerIds'; CaseSensitive = $false; AdditiveOnly = $false }
        # Tags set by other tools are left untouched.
        @{ Name = 'Tags'; CaseSensitive = $false; AdditiveOnly = $true }
    )

    $exists = $null -ne $Actual
    if (-not $exists) { $Actual = @{} }

    $changes = [System.Collections.Generic.List[object]]::new()

    foreach ($property in $scalarProperties) {
        $before = if ($Actual.Contains($property)) { $Actual[$property] } else { $null }
        $after = if ($Desired.Contains($property)) { $Desired[$property] } else { $null }

        # A missing value and an empty string are the same thing to Graph.
        $beforeKey = if ($null -eq $before) { '' } else { [string]$before }
        $afterKey = if ($null -eq $after) { '' } else { [string]$after }

        if ($beforeKey -cne $afterKey) {
            $changes.Add([pscustomobject]@{
                    Property = $property
                    Before   = $before
                    After    = $after
                    Add      = @()
                    Remove   = @()
                })
        }
    }

    foreach ($spec in $setProperties) {
        $property = $spec.Name
        $before = if ($Actual.Contains($property)) { @($Actual[$property]) } else { @() }
        $after = if ($Desired.Contains($property)) { @($Desired[$property]) } else { @() }

        $comparer = if ($spec.CaseSensitive) { [System.StringComparer]::Ordinal } else { [System.StringComparer]::OrdinalIgnoreCase }
        $beforeSet = [System.Collections.Generic.HashSet[string]]::new($comparer)
        foreach ($value in $before) { $null = $beforeSet.Add([string]$value) }
        $afterSet = [System.Collections.Generic.HashSet[string]]::new($comparer)
        foreach ($value in $after) { $null = $afterSet.Add([string]$value) }

        $toAdd = @($afterSet | Where-Object { -not $beforeSet.Contains($_) } | Sort-Object)
        $toRemove = @(
            if (-not $spec.AdditiveOnly) {
                $beforeSet | Where-Object { -not $afterSet.Contains($_) } | Sort-Object
            }
        )

        if ($toAdd.Count -gt 0 -or $toRemove.Count -gt 0) {
            $changes.Add([pscustomobject]@{
                    Property = $property
                    Before   = $null
                    After    = $null
                    Add      = $toAdd
                    Remove   = $toRemove
                })
        }
    }

    $action = if (-not $exists) { 'Create' } elseif ($changes.Count -gt 0) { 'Update' } else { 'None' }

    [pscustomobject]@{
        Name    = $Name
        Action  = $action
        Changes = $changes.ToArray()
    }
}
