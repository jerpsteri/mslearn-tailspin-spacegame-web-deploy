BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-AppVendingModule

    $script:now = [datetime]::new(2026, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    $script:app = 'sample-app'

    function New-Credential {
        param([string]$KeyId, [string]$Name = 'appvending:backend', [int]$AgeDays = 10, [int]$LifetimeDays = 730)
        $start = $now.AddDays(-$AgeDays)
        [pscustomobject]@{ KeyId = $KeyId; DisplayName = $Name; StartDateTime = $start; EndDateTime = $start.AddDays($LifetimeDays) }
    }

    function New-VaultSecret {
        param([string]$KeyId, [string]$Name = 'sample-app-client-secret-backend', [bool]$Enabled = $true, [string]$App = 'sample-app')
        [pscustomobject]@{
            Name    = $Name
            Enabled = $Enabled
            Tags    = @{ 'managed-by' = 'app-vending'; app = $App; keyId = $KeyId }
        }
    }

    function Get-Plan {
        param([string[]]$Declared = @('backend'), [object[]]$Credential = @(), [object[]]$VaultSecret = @())
        InModuleScope AppVending -Parameters @{ App = $app; Declared = $Declared; Credential = $Credential; VaultSecret = $VaultSecret; Now = $now } {
            @(Get-SecretPlan -AppName $App -DeclaredSecret $Declared -Credential $Credential -VaultSecret $VaultSecret -LifetimeDays 730 -RotateBeforeDays 30 -Now $Now)
        }
    }

    function Invoke-PlanSimulation {
        # Applies a plan to in-memory state the way apply does and returns the new state.
        param([object[]]$Plan, [object[]]$Credential = @(), [object[]]$VaultSecret = @())

        $credentials = [System.Collections.Generic.List[object]]::new($Credential)
        $vault = [System.Collections.Generic.List[object]]::new($VaultSecret)

        foreach ($action in $Plan) {
            switch ($action.Action) {
                'CreateSecret' {
                    $keyId = [guid]::NewGuid().ToString()
                    $credentials.Add([pscustomobject]@{ KeyId = $keyId; DisplayName = "appvending:$($action.SecretName)"; StartDateTime = $now; EndDateTime = $now.AddDays(730) })
                    $existing = $vault | Where-Object Name -EQ $action.VaultSecretName
                    if ($existing) { $null = $vault.Remove($existing) }
                    $vault.Add((New-VaultSecret -KeyId $keyId -Name $action.VaultSecretName))
                }
                'RemoveCredential' {
                    $null = $credentials.Remove(($credentials | Where-Object KeyId -EQ $action.KeyId))
                }
                'DisableVaultSecret' {
                    ($vault | Where-Object Name -EQ $action.VaultSecretName).Enabled = $false
                }
            }
        }

        @{ Credential = $credentials.ToArray(); VaultSecret = $vault.ToArray() }
    }
}

Describe 'Get-SecretPlan' {
    Context 'steady state' {
        It 'does nothing when no secrets are declared and none exist' {
            Get-Plan -Declared @() | Should -BeNullOrEmpty
        }

        It 'does nothing when the vault points to a valid credential outside the rotation window' {
            Get-Plan -Credential (New-Credential -KeyId 'k1') -VaultSecret (New-VaultSecret -KeyId 'k1') | Should -BeNullOrEmpty
        }

        It 'keeps the previous credential until it expires after a rotation' {
            $credentials = @(
                New-Credential -KeyId 'old' -AgeDays 710
                New-Credential -KeyId 'new' -AgeDays 5
            )
            Get-Plan -Credential $credentials -VaultSecret (New-VaultSecret -KeyId 'new') | Should -BeNullOrEmpty
        }
    }

    Context 'creation' {
        It 'creates a declared secret that does not exist' {
            $plan = Get-Plan
            $plan.Count | Should -Be 1
            $plan[0].Action | Should -Be 'CreateSecret'
            $plan[0].Reason | Should -Be 'Missing'
            $plan[0].VaultSecretName | Should -Be 'sample-app-client-secret-backend'
        }

        It 'creates every declared secret independently' {
            $plan = Get-Plan -Declared 'backend', 'worker' -Credential (New-Credential -KeyId 'k1') -VaultSecret (New-VaultSecret -KeyId 'k1')
            $plan.Count | Should -Be 1
            $plan[0].SecretName | Should -Be 'worker'
        }

        It 'recreates the secret when the vault secret is disabled' {
            $plan = Get-Plan -Credential (New-Credential -KeyId 'k1') -VaultSecret (New-VaultSecret -KeyId 'k1' -Enabled $false)
            $plan.Action | Should -Be @('CreateSecret', 'RemoveCredential')
        }
    }

    Context 'rotation' {
        It 'rotates when the current credential enters the rotation window' {
            $plan = Get-Plan -Credential (New-Credential -KeyId 'k1' -AgeDays 700) -VaultSecret (New-VaultSecret -KeyId 'k1')
            $plan.Count | Should -Be 1
            $plan[0].Action | Should -Be 'CreateSecret'
            $plan[0].Reason | Should -Be 'Rotation'
        }

        It 'does not rotate one day before the rotation window' {
            Get-Plan -Credential (New-Credential -KeyId 'k1' -AgeDays 699) -VaultSecret (New-VaultSecret -KeyId 'k1') | Should -BeNullOrEmpty
        }

        It 'removes an expired credential and creates a replacement' {
            $plan = Get-Plan -Credential (New-Credential -KeyId 'k1' -AgeDays 731) -VaultSecret (New-VaultSecret -KeyId 'k1')
            $plan.Action | Should -Be @('CreateSecret', 'RemoveCredential')
            $plan[0].Reason | Should -Be 'Missing'
            $plan[1].Reason | Should -Be 'Expired'
        }
    }

    Context 'interrupted runs' {
        It 'replaces a credential that never reached the vault' {
            $plan = Get-Plan -Credential (New-Credential -KeyId 'lost')
            $plan.Action | Should -Be @('CreateSecret', 'RemoveCredential')
            $plan[0].Reason | Should -Be 'Orphaned'
            $plan[1].KeyId | Should -Be 'lost'
        }

        It 'removes a newer credential the vault does not point to and rotates again' {
            $credentials = @(
                New-Credential -KeyId 'current' -AgeDays 705
                New-Credential -KeyId 'lost' -AgeDays 1
            )
            $plan = Get-Plan -Credential $credentials -VaultSecret (New-VaultSecret -KeyId 'current')
            $plan.Action | Should -Be @('CreateSecret', 'RemoveCredential')
            $plan[0].Reason | Should -Be 'Rotation'
            $plan[1].KeyId | Should -Be 'lost'
        }
    }

    Context 'removal' {
        It 'removes the credential and disables the vault secret when a secret is no longer declared' {
            $plan = Get-Plan -Declared @() -Credential (New-Credential -KeyId 'k1') -VaultSecret (New-VaultSecret -KeyId 'k1')
            $plan.Action | Should -Be @('RemoveCredential', 'DisableVaultSecret')
            $plan[0].Reason | Should -Be 'Undeclared'
        }

        It 'leaves vault secrets of other applications alone' {
            $vault = @(
                New-VaultSecret -KeyId 'x' -Name 'sample-app-client-secret-legacy' -App 'another-app'
                New-VaultSecret -KeyId 'y' -Name 'unrelated-secret'
            )
            Get-Plan -Declared @() -VaultSecret $vault | Should -BeNullOrEmpty
        }
    }

    Context 'safety' {
        It 'reports a conflict instead of overwriting a vault secret it does not own' {
            $foreign = [pscustomobject]@{ Name = 'sample-app-client-secret-backend'; Enabled = $true; Tags = @{} }
            $plan = Get-Plan -VaultSecret $foreign
            $plan.Count | Should -Be 1
            $plan[0].Action | Should -Be 'Conflict'
        }

        It 'reports a conflict when the vault secret belongs to another application' {
            $plan = Get-Plan -VaultSecret (New-VaultSecret -KeyId 'k1' -App 'another-app')
            $plan.Action | Should -Be 'Conflict'
        }

        It 'reports credentials created outside the pipeline without touching them' {
            $credentials = @(
                New-Credential -KeyId 'k1'
                New-Credential -KeyId 'manual' -Name 'created in portal'
            )
            $plan = Get-Plan -Credential $credentials -VaultSecret (New-VaultSecret -KeyId 'k1')
            $plan.Count | Should -Be 1
            $plan[0].Action | Should -Be 'ReportUnmanaged'
            $plan[0].KeyId | Should -Be 'manual'
        }
    }

    Context 'idempotency' {
        It 'produces no further changes after the plan has been applied: <Name>' -ForEach @(
            @{ Name = 'new secret'; Declared = @('backend'); Credential = @(); Vault = @() }
            @{ Name = 'two new secrets'; Declared = @('backend', 'worker'); Credential = @(); Vault = @() }
            @{ Name = 'rotation'; Declared = @('backend'); Credential = @(@{ KeyId = 'k1'; AgeDays = 715 }); Vault = @(@{ KeyId = 'k1' }) }
            @{ Name = 'interrupted run'; Declared = @('backend'); Credential = @(@{ KeyId = 'lost'; AgeDays = 0 }); Vault = @() }
            @{ Name = 'interrupted rotation'; Declared = @('backend'); Credential = @(@{ KeyId = 'k1'; AgeDays = 715 }, @{ KeyId = 'lost'; AgeDays = 0 }); Vault = @(@{ KeyId = 'k1' }) }
            @{ Name = 'secret removed'; Declared = @(); Credential = @(@{ KeyId = 'k1'; AgeDays = 10 }); Vault = @(@{ KeyId = 'k1' }) }
            @{ Name = 'expired secret'; Declared = @('backend'); Credential = @(@{ KeyId = 'k1'; AgeDays = 800 }); Vault = @(@{ KeyId = 'k1' }) }
        ) {
            $credentials = @($Credential | ForEach-Object { New-Credential @_ })
            $vaultSecrets = @($Vault | ForEach-Object { New-VaultSecret @_ })

            $first = Get-Plan -Declared $Declared -Credential $credentials -VaultSecret $vaultSecrets
            $first | Should -Not -BeNullOrEmpty

            $state = Invoke-PlanSimulation -Plan $first -Credential $credentials -VaultSecret $vaultSecrets
            $second = Get-Plan -Declared $Declared -Credential $state.Credential -VaultSecret $state.VaultSecret

            $second | Should -BeNullOrEmpty
        }
    }
}
