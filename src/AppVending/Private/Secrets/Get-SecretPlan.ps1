function Get-SecretPlan {
    <#
    .SYNOPSIS
        Decides which secret operations bring one application to its declared state.

    .DESCRIPTION
        State lives in two places and is read fresh on every run, so no state file is needed:

          * Entra holds the password credentials. Credentials created by the pipeline are
            named 'appvending:<secret name>'.
          * The Key Vault secret carries a keyId tag that points to the credential whose
            value it currently stores.

        A declared secret is healthy when its Key Vault secret is enabled and its keyId tag
        points to a credential that has not expired and is outside the rotation window.

        The write order during apply is always: create in Entra, write to Key Vault, remove
        old credentials. A run that is interrupted between the first two steps leaves a
        credential the vault does not know about. The next run detects it as orphaned,
        because it is newer than the credential the vault points to, and replaces it.

        A credential that is older than the current one is the previous secret. It is left
        in place so consumers keep working until it expires.

        The function is pure. Apply executes the returned actions in order.

    .OUTPUTS
        Objects with Action, SecretName, VaultSecretName, KeyId and Reason. Actions:

          CreateSecret        add a credential and write its value to Key Vault
          RemoveCredential    remove a credential from the application
          DisableVaultSecret  disable a Key Vault secret that is no longer declared
          ReportUnmanaged     a credential created outside the pipeline, reported only
          Conflict            the Key Vault secret name is taken by something else
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        # Secret names declared in the manifest.
        [AllowEmptyCollection()]
        [string[]]$DeclaredSecret = @(),

        # Password credential metadata of the application: KeyId, DisplayName, StartDateTime, EndDateTime.
        [AllowEmptyCollection()]
        [object[]]$EntraSecret = @(),

        # Secrets in the target vault: Name, Enabled, Tags.
        [AllowEmptyCollection()]
        [object[]]$VaultSecret = @(),

        [Parameter(Mandatory)]
        [ValidateRange(0, 3650)]
        [int]$RotateBeforeDays,

        [datetime]$Now = [datetime]::UtcNow
    )

    $prefix = $script:Constants.CredentialNamePrefix
    $creates = [System.Collections.Generic.List[object]]::new()
    $removals = [System.Collections.Generic.List[object]]::new()
    $disables = [System.Collections.Generic.List[object]]::new()
    $reports = [System.Collections.Generic.List[object]]::new()

    $newAction = {
        param($Action, $SecretName, $VaultSecretName, $KeyId, $Reason)
        [pscustomobject]@{
            Action          = $Action
            SecretName      = $SecretName
            VaultSecretName = $VaultSecretName
            KeyId           = $KeyId
            Reason          = $Reason
        }
    }

    $isOwnedVaultSecret = {
        param($Secret)
        $tags = $Secret.Tags
        $tags -is [System.Collections.IDictionary] -and
        $tags[$script:Constants.VaultTagManagedBy] -eq $script:Constants.VaultTagManagedByValue -and
        $tags[$script:Constants.VaultTagApp] -eq $AppName
    }

    $managed = @($EntraSecret | Where-Object { ([string]$_.DisplayName).StartsWith($prefix, [System.StringComparison]::Ordinal) })
    $unmanaged = @($EntraSecret | Where-Object { $_ -notin $managed })

    foreach ($item in $unmanaged) {
        $reports.Add((& $newAction 'ReportUnmanaged' $null $null $item.KeyId "Credential '$($item.DisplayName)' was not created by the pipeline."))
    }

    $declared = @($DeclaredSecret | Select-Object -Unique)

    foreach ($item in $managed) {
        $secretName = ([string]$item.DisplayName).Substring($prefix.Length)
        if ($item.EndDateTime -le $Now) {
            $removals.Add((& $newAction 'RemoveCredential' $secretName $null $item.KeyId 'Expired'))
        }
        elseif ($secretName -cnotin $declared) {
            $removals.Add((& $newAction 'RemoveCredential' $secretName $null $item.KeyId 'Undeclared'))
        }
    }

    $expectedVaultNames = [System.Collections.Generic.List[string]]::new()

    foreach ($secretName in $declared) {
        $vaultName = Get-VaultSecretName -AppName $AppName -SecretName $secretName
        $expectedVaultNames.Add($vaultName)

        $vaultEntry = $VaultSecret | Where-Object { $_.Name -eq $vaultName } | Select-Object -First 1
        if ($null -ne $vaultEntry -and -not (& $isOwnedVaultSecret $vaultEntry)) {
            $creates.Add((& $newAction 'Conflict' $secretName $vaultName $null 'The Key Vault secret exists and is not tagged as belonging to this application.'))
            continue
        }

        $valid = @($managed | Where-Object { $_.DisplayName -ceq "$prefix$secretName" -and $_.EndDateTime -gt $Now })

        $current = $null
        if ($null -ne $vaultEntry -and $vaultEntry.Enabled) {
            $currentKeyId = $vaultEntry.Tags[$script:Constants.VaultTagKeyId]
            $current = $valid | Where-Object { $_.KeyId -eq $currentKeyId } | Select-Object -First 1
        }

        if ($null -eq $current) {
            # Nothing in the vault points to a usable credential, so every existing one is unreachable.
            $reason = if ($valid.Count -eq 0) { 'Missing' } else { 'Orphaned' }
            $creates.Add((& $newAction 'CreateSecret' $secretName $vaultName $null $reason))
            foreach ($item in $valid) {
                $removals.Add((& $newAction 'RemoveCredential' $secretName $null $item.KeyId 'Orphaned'))
            }
            continue
        }

        foreach ($item in $valid) {
            if ($item.KeyId -ne $current.KeyId -and $item.StartDateTime -gt $current.StartDateTime) {
                $removals.Add((& $newAction 'RemoveCredential' $secretName $null $item.KeyId 'Orphaned'))
            }
        }

        if (($current.EndDateTime - $Now).TotalDays -le $RotateBeforeDays) {
            $creates.Add((& $newAction 'CreateSecret' $secretName $vaultName $null 'Rotation'))
        }
    }

    $vaultPrefix = Get-VaultSecretName -AppName $AppName -SecretName ''
    foreach ($entry in $VaultSecret) {
        $isStale = $entry.Enabled -and
        ([string]$entry.Name).StartsWith($vaultPrefix, [System.StringComparison]::Ordinal) -and
        $entry.Name -notin $expectedVaultNames -and
        (& $isOwnedVaultSecret $entry)

        if ($isStale) {
            $disables.Add((& $newAction 'DisableVaultSecret' $null $entry.Name $null 'Undeclared'))
        }
    }

    return @($creates) + @($removals) + @($disables) + @($reports)
}
