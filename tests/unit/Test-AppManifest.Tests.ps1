BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-AppVendingModule

    $script:vaultId = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sample/providers/Microsoft.KeyVault/vaults/kv-sample-prod'

    function Get-Findings {
        param([System.Collections.IDictionary]$Data, [string]$FileName, [string]$Root = (Join-Path $TestDrive ([guid]::NewGuid())))
        $path = Save-Manifest -Data $Data -Root $Root -FileName $FileName
        @(Test-AppManifest -Path $path)
    }
}

Describe 'Test-AppManifest' {
    Context 'valid manifests' {
        It 'accepts the minimal manifest' {
            Get-Findings -Data (New-ManifestData) | Should -BeNullOrEmpty
        }

        It 'accepts the sample fixture with redirect URIs, permissions and a secret' {
            $fixture = Join-Path (Get-RepoRoot) 'tests' 'fixtures' 'apps' 'team-a' 'sample-web-app.yaml'
            Test-AppManifest -Path $fixture | Should -BeNullOrEmpty
        }

        It 'accepts http redirect URIs on localhost' {
            $data = New-ManifestData
            $data.web = @{ redirectUris = @('http://localhost:5000/signin-oidc') }
            Get-Findings -Data $data | Should -BeNullOrEmpty
        }
    }

    Context 'schema' {
        It 'rejects a file that is not valid YAML' {
            $folder = Join-Path $TestDrive 'broken' 'apps' 'team-a'
            $null = New-Item -ItemType Directory -Path $folder -Force
            $path = Join-Path $folder 'broken.yaml'
            Set-Content -LiteralPath $path -Value "name: [unclosed"
            (Test-AppManifest -Path $path).Rule | Should -Be 'yaml'
        }

        It 'rejects an empty file' {
            $folder = Join-Path $TestDrive 'empty' 'apps' 'team-a'
            $null = New-Item -ItemType Directory -Path $folder -Force
            $path = Join-Path $folder 'empty.yaml'
            Set-Content -LiteralPath $path -Value ''
            (Test-AppManifest -Path $path).Rule | Should -Be 'schema'
        }

        It 'rejects a missing required property' {
            $data = New-ManifestData
            $data.Remove('description')
            (Get-Findings -Data $data).Rule | Should -Contain 'schema'
        }

        It 'rejects an unknown property' {
            $data = New-ManifestData
            $data.federatedCredentials = @()
            (Get-Findings -Data $data).Rule | Should -Contain 'schema'
        }

        It 'rejects a name with invalid characters' {
            $data = New-ManifestData -Name 'Sample_App'
            (Get-Findings -Data $data).Rule | Should -Contain 'schema'
        }

        It 'rejects a malformed Key Vault resource ID' {
            $data = New-ManifestData
            $data.keyVault = @{ resourceId = 'kv-sample-prod' }
            (Get-Findings -Data $data).Rule | Should -Contain 'schema'
        }
    }

    Context 'policy' {
        It 'requires the file name to match the manifest name' {
            (Get-Findings -Data (New-ManifestData) -FileName 'other.yaml').Rule | Should -Be 'file-name'
        }

        It 'requires the manifest to be stored under apps/<team>' {
            $folder = Join-Path $TestDrive 'elsewhere'
            $null = New-Item -ItemType Directory -Path $folder -Force
            $path = Join-Path $folder 'sample-app.yaml'
            ConvertTo-Yaml -Data (New-ManifestData) | Set-Content -LiteralPath $path
            (Test-AppManifest -Path $path).Rule | Should -Be 'location'
        }

        It 'requires the minimum number of owners' {
            $data = New-ManifestData
            $data.owners = @('alice@contoso.com')
            (Get-Findings -Data $data).Rule | Should -Be 'owners-minimum'
        }

        It 'rejects a sign-in audience outside the policy' {
            $data = New-ManifestData
            $data.signInAudience = 'AzureADMultipleOrgs'
            (Get-Findings -Data $data).Rule | Should -Be 'sign-in-audience'
        }

        It 'rejects <Uri>' -ForEach @(
            @{ Uri = 'http://app.contoso.com/signin-oidc' }
            @{ Uri = 'https://*.contoso.com/signin-oidc' }
        ) {
            $data = New-ManifestData
            $data.web = @{ redirectUris = @($Uri) }
            (Get-Findings -Data $data).Rule | Should -Be 'redirect-uri'
        }

        It 'applies redirect URI rules to spa and logoutUrl' {
            $data = New-ManifestData
            $data.spa = @{ redirectUris = @('http://app.contoso.com') }
            $data.web = @{ logoutUrl = 'http://app.contoso.com/out' }
            (Get-Findings -Data $data).Rule | Should -Be @('redirect-uri', 'redirect-uri')
        }

        It 'rejects a resource that is not on the allowlist' {
            $data = New-ManifestData
            $data.requiredResourceAccess = @(@{ resource = 'Azure Service Management'; delegated = @('user_impersonation') })
            (Get-Findings -Data $data).Rule | Should -Be 'permission-not-allowed'
        }

        It 'rejects a permission that is not on the allowlist' {
            $data = New-ManifestData
            $data.requiredResourceAccess = @(@{ resource = 'Microsoft Graph'; delegated = @('User.Read'); application = @('Directory.ReadWrite.All') })
            $findings = Get-Findings -Data $data
            $findings.Rule | Should -Be 'permission-not-allowed'
            $findings.Message | Should -Match 'Directory.ReadWrite.All'
        }

        It 'requires a Key Vault when secrets are declared' {
            $data = New-ManifestData
            $data.secrets = @(@{ name = 'backend' })
            (Get-Findings -Data $data).Rule | Should -Be 'secret-key-vault'
        }

        It 'limits the number of secrets' {
            $data = New-ManifestData
            $data.keyVault = @{ resourceId = $vaultId }
            $data.secrets = @(@{ name = 'a' }, @{ name = 'b' }, @{ name = 'c' })
            (Get-Findings -Data $data).Rule | Should -Be 'secret-limit'
        }

        It 'rejects duplicate secret names' {
            $data = New-ManifestData
            $data.keyVault = @{ resourceId = $vaultId }
            $data.secrets = @(@{ name = 'a' }, @{ name = 'a' })
            (Get-Findings -Data $data).Rule | Should -Be 'secret-duplicate'
        }
    }

    Context 'folders' {
        It 'reports every invalid file and duplicate names across teams' {
            $root = Join-Path $TestDrive 'folder'
            $null = Save-Manifest -Data (New-ManifestData -Name 'shared-name') -Root $root -Team 'team-a'
            $null = Save-Manifest -Data (New-ManifestData -Name 'shared-name') -Root $root -Team 'team-b'
            $invalid = New-ManifestData -Name 'one-owner'
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
            $fixture = Join-Path (Get-RepoRoot) 'tests' 'fixtures' 'apps' 'team-a' 'sample-web-app.yaml'
            { Test-AppManifest -Path $fixture -PolicyPath $policyPath } | Should -Throw '*missing the required setting*'
        }
    }
}
