BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-AppVendingModule

    $script:vaultId = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sample/providers/Microsoft.KeyVault/vaults/kv-sample-prod'

    function Get-Finding {
        param([System.Collections.IDictionary]$Data, [string]$FileName, [string]$Root = (Join-Path $TestDrive ([guid]::NewGuid())))
        $path = Save-Manifest -Data $Data -Root $Root -FileName $FileName
        @(Test-AppManifest -Path $path)
    }
}

Describe 'Test-AppManifest' {
    Context 'valid manifests' {
        It 'accepts the minimal manifest' {
            Get-Finding -Data (Get-SampleManifest) | Should -BeNullOrEmpty
        }

        It 'accepts the sample fixture with redirect URIs, permissions and a secret' {
            $fixture = Join-Path -Path (Get-RepoRoot) -ChildPath 'tests' -AdditionalChildPath 'fixtures', 'apps', 'team-a', 'sample-web-app.yaml'
            Test-AppManifest -Path $fixture | Should -BeNullOrEmpty
        }

        It 'accepts http redirect URIs on localhost' {
            $data = Get-SampleManifest
            $data.web = @{ redirectUris = @('http://localhost:5000/signin-oidc') }
            Get-Finding -Data $data | Should -BeNullOrEmpty
        }
    }

    Context 'schema' {
        It 'rejects a file that is not valid YAML' {
            $folder = Join-Path -Path $TestDrive -ChildPath 'broken' -AdditionalChildPath 'apps', 'team-a'
            $null = New-Item -ItemType Directory -Path $folder -Force
            $path = Join-Path $folder 'broken.yaml'
            Set-Content -LiteralPath $path -Value "name: [unclosed"
            (Test-AppManifest -Path $path).Rule | Should -Be 'yaml'
        }

        It 'rejects an empty file' {
            $folder = Join-Path -Path $TestDrive -ChildPath 'empty' -AdditionalChildPath 'apps', 'team-a'
            $null = New-Item -ItemType Directory -Path $folder -Force
            $path = Join-Path $folder 'empty.yaml'
            Set-Content -LiteralPath $path -Value ''
            (Test-AppManifest -Path $path).Rule | Should -Be 'schema'
        }

        It 'rejects a missing required property' {
            $data = Get-SampleManifest
            $data.Remove('description')
            (Get-Finding -Data $data).Rule | Should -Contain 'schema'
        }

        It 'rejects an unknown property' {
            $data = Get-SampleManifest
            $data.federatedCredentials = @()
            (Get-Finding -Data $data).Rule | Should -Contain 'schema'
        }

        It 'rejects a name with invalid characters' {
            $data = Get-SampleManifest -Name 'Sample_App'
            (Get-Finding -Data $data).Rule | Should -Contain 'schema'
        }

        It 'rejects a malformed Key Vault resource ID' {
            $data = Get-SampleManifest
            $data.keyVault = @{ resourceId = 'kv-sample-prod' }
            (Get-Finding -Data $data).Rule | Should -Contain 'schema'
        }
    }

    Context 'policy' {
        It 'requires the file name to match the manifest name' {
            (Get-Finding -Data (Get-SampleManifest) -FileName 'other.yaml').Rule | Should -Be 'file-name'
        }

        It 'requires the manifest to be stored under apps/<team>' {
            $folder = Join-Path $TestDrive 'elsewhere'
            $null = New-Item -ItemType Directory -Path $folder -Force
            $path = Join-Path $folder 'sample-app.yaml'
            ConvertTo-Yaml -Data (Get-SampleManifest) | Set-Content -LiteralPath $path
            (Test-AppManifest -Path $path).Rule | Should -Be 'location'
        }

        It 'requires the minimum number of owners' {
            $data = Get-SampleManifest
            $data.owners = @('alice@contoso.com')
            (Get-Finding -Data $data).Rule | Should -Be 'owners-minimum'
        }

        It 'rejects a sign-in audience outside the policy' {
            $data = Get-SampleManifest
            $data.signInAudience = 'AzureADMultipleOrgs'
            (Get-Finding -Data $data).Rule | Should -Be 'sign-in-audience'
        }

        It 'rejects <Uri>' -ForEach @(
            @{ Uri = 'http://app.contoso.com/signin-oidc' }
            @{ Uri = 'https://*.contoso.com/signin-oidc' }
        ) {
            $data = Get-SampleManifest
            $data.web = @{ redirectUris = @($Uri) }
            (Get-Finding -Data $data).Rule | Should -Be 'redirect-uri'
        }

        It 'applies redirect URI rules to spa and logoutUrl' {
            $data = Get-SampleManifest
            $data.spa = @{ redirectUris = @('http://app.contoso.com') }
            $data.web = @{ logoutUrl = 'http://app.contoso.com/out' }
            (Get-Finding -Data $data).Rule | Should -Be @('redirect-uri', 'redirect-uri')
        }

        It 'rejects a resource that is not on the allowlist' {
            $data = Get-SampleManifest
            $data.requiredResourceAccess = @(@{ resource = 'Azure Service Management'; delegated = @('user_impersonation') })
            (Get-Finding -Data $data).Rule | Should -Be 'permission-not-allowed'
        }

        It 'rejects a permission that is not on the allowlist' {
            $data = Get-SampleManifest
            $data.requiredResourceAccess = @(@{ resource = 'Microsoft Graph'; delegated = @('User.Read'); application = @('Directory.ReadWrite.All') })
            $findings = Get-Finding -Data $data
            $findings.Rule | Should -Be 'permission-not-allowed'
            $findings.Message | Should -Match 'Directory.ReadWrite.All'
        }

        It 'requires a Key Vault when secrets are declared' {
            $data = Get-SampleManifest
            $data.secrets = @(@{ name = 'backend' })
            (Get-Finding -Data $data).Rule | Should -Be 'secret-key-vault'
        }

        It 'limits the number of secrets' {
            $data = Get-SampleManifest
            $data.keyVault = @{ resourceId = $vaultId }
            $data.secrets = @(@{ name = 'a' }, @{ name = 'b' }, @{ name = 'c' })
            (Get-Finding -Data $data).Rule | Should -Be 'secret-limit'
        }

        It 'rejects duplicate secret names' {
            $data = Get-SampleManifest
            $data.keyVault = @{ resourceId = $vaultId }
            $data.secrets = @(@{ name = 'a' }, @{ name = 'a' })
            (Get-Finding -Data $data).Rule | Should -Be 'secret-duplicate'
        }
    }

    Context 'folders' {
        It 'reports every invalid file and duplicate names across teams' {
            $root = Join-Path $TestDrive 'folder'
            $null = Save-Manifest -Data (Get-SampleManifest -Name 'shared-name') -Root $root -Team 'team-a'
            $null = Save-Manifest -Data (Get-SampleManifest -Name 'shared-name') -Root $root -Team 'team-b'
            $invalid = Get-SampleManifest -Name 'one-owner'
            $invalid.owners = @('alice@contoso.com')
            $null = Save-Manifest -Data $invalid -Root $root -Team 'team-a'

            $findings = Test-AppManifest -Path (Join-Path $root 'apps')

            ($findings | Where-Object Rule -EQ 'duplicate-name').Count | Should -Be 2
            ($findings | Where-Object Rule -EQ 'owners-minimum').Count | Should -Be 1
        }

        It 'returns nothing for a folder without manifests' {
            $root = Join-Path $TestDrive 'none'
            $null = New-Item -ItemType Directory -Path $root -Force
            Test-AppManifest -Path $root | Should -BeNullOrEmpty
        }
    }

    Context 'policy file' {
        It 'fails when a required setting is missing' {
            $policyPath = Join-Path $TestDrive 'policy.yaml'
            Set-Content -LiteralPath $policyPath -Value "owners:`n  minimum: 2"
            $fixture = Join-Path -Path (Get-RepoRoot) -ChildPath 'tests' -AdditionalChildPath 'fixtures', 'apps', 'team-a', 'sample-web-app.yaml'
            { Test-AppManifest -Path $fixture -PolicyPath $policyPath } | Should -Throw '*missing the required setting*'
        }
    }
}
