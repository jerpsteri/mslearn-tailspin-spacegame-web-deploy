BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-AppVendingModule

    function Get-SampleState {
        @{
            DisplayName             = 'Sample App'
            Description             = 'Application used by the unit tests.'
            SignInAudience          = 'AzureADMyOrg'
            WebLogoutUrl            = $null
            WebRedirectUris         = @('https://sample.contoso.com/signin-oidc')
            SpaRedirectUris         = @()
            RequiredResourceAccess  = @('00000003-0000-0000-c000-000000000000/e1fe6dd8-ba31-4d61-89e7-88639da4683d/Scope')
            OwnerIds                = @('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002')
            Tags                    = @('managed-by:app-vending')
            ServicePrincipalEnabled = $true
        }
    }
}

Describe 'Compare-AppRegistration' {
    It 'returns Create with every desired value when the application does not exist' {
        InModuleScope AppVending -Parameters @{ Desired = Get-SampleState } {
            $result = Compare-AppRegistration -Name 'sample-app' -Desired $Desired -Actual $null
            $result.Action | Should -Be 'Create'
            $result.Changes.Property | Should -Contain 'DisplayName'
            $result.Changes.Property | Should -Contain 'OwnerIds'
            $result.Changes.Property | Should -Not -Contain 'WebLogoutUrl'
            $result.Changes.Property | Should -Not -Contain 'SpaRedirectUris'
        }
    }

    It 'returns None when desired and actual state are equal' {
        InModuleScope AppVending -Parameters @{ Desired = Get-SampleState; Actual = Get-SampleState } {
            $result = Compare-AppRegistration -Name 'sample-app' -Desired $Desired -Actual $Actual
            $result.Action | Should -Be 'None'
            $result.Changes | Should -BeNullOrEmpty
        }
    }

    It 'ignores the order of set values' {
        $actual = Get-SampleState
        [array]::Reverse($actual.OwnerIds)
        InModuleScope AppVending -Parameters @{ Desired = Get-SampleState; Actual = $actual } {
            (Compare-AppRegistration -Name 'sample-app' -Desired $Desired -Actual $Actual).Action | Should -Be 'None'
        }
    }

    It 'treats a missing scalar and an empty string as equal' {
        $actual = Get-SampleState
        $actual.WebLogoutUrl = ''
        InModuleScope AppVending -Parameters @{ Desired = Get-SampleState; Actual = $actual } {
            (Compare-AppRegistration -Name 'sample-app' -Desired $Desired -Actual $Actual).Action | Should -Be 'None'
        }
    }

    It 'reports a changed scalar with before and after values' {
        $desired = Get-SampleState
        $desired.DisplayName = 'Renamed App'
        InModuleScope AppVending -Parameters @{ Desired = $desired; Actual = Get-SampleState } {
            $result = Compare-AppRegistration -Name 'sample-app' -Desired $Desired -Actual $Actual
            $result.Action | Should -Be 'Update'
            $result.Changes.Count | Should -Be 1
            $result.Changes[0].Property | Should -Be 'DisplayName'
            $result.Changes[0].Before | Should -Be 'Sample App'
            $result.Changes[0].After | Should -Be 'Renamed App'
        }
    }

    It 'reports additions and removals of set values' {
        $desired = Get-SampleState
        $desired.WebRedirectUris = @('https://sample.contoso.com/callback')
        InModuleScope AppVending -Parameters @{ Desired = $desired; Actual = Get-SampleState } {
            $change = (Compare-AppRegistration -Name 'sample-app' -Desired $Desired -Actual $Actual).Changes | Where-Object Property -EQ 'WebRedirectUris'
            $change.Add | Should -Be 'https://sample.contoso.com/callback'
            $change.Remove | Should -Be 'https://sample.contoso.com/signin-oidc'
        }
    }

    It 'compares redirect URIs case sensitively' {
        $actual = Get-SampleState
        $actual.WebRedirectUris = @('https://sample.contoso.com/Signin-Oidc')
        InModuleScope AppVending -Parameters @{ Desired = Get-SampleState; Actual = $actual } {
            (Compare-AppRegistration -Name 'sample-app' -Desired $Desired -Actual $Actual).Action | Should -Be 'Update'
        }
    }

    It 'compares identifiers case insensitively' {
        $actual = Get-SampleState
        $actual.OwnerIds = $actual.OwnerIds | ForEach-Object { $_.ToUpperInvariant() }
        InModuleScope AppVending -Parameters @{ Desired = Get-SampleState; Actual = $actual } {
            (Compare-AppRegistration -Name 'sample-app' -Desired $Desired -Actual $Actual).Action | Should -Be 'None'
        }
    }

    It 'adds missing tags and keeps tags set by other tools' {
        $actual = Get-SampleState
        $actual.Tags = @('owned-by-someone-else')
        InModuleScope AppVending -Parameters @{ Desired = Get-SampleState; Actual = $actual } {
            $change = (Compare-AppRegistration -Name 'sample-app' -Desired $Desired -Actual $Actual).Changes | Where-Object Property -EQ 'Tags'
            $change.Add | Should -Be 'managed-by:app-vending'
            $change.Remove | Should -BeNullOrEmpty
        }
    }

    It 'reports a service principal that should no longer exist' {
        $desired = Get-SampleState
        $desired.ServicePrincipalEnabled = $false
        InModuleScope AppVending -Parameters @{ Desired = $desired; Actual = Get-SampleState } {
            $result = Compare-AppRegistration -Name 'sample-app' -Desired $Desired -Actual $Actual
            $result.Changes.Property | Should -Be 'ServicePrincipalEnabled'
        }
    }
}
