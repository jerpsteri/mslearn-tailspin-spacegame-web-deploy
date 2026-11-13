@{
    RootModule        = 'AppVending.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '5b0f6d0e-6f0a-4a57-9c1f-2f4f0e7f8a11'
    Author            = 'Platform team'
    Description       = 'Reconciles Microsoft Entra app registrations with YAML manifests stored in Git.'
    PowerShellVersion = '7.4'
    RequiredModules   = @('powershell-yaml')
    FunctionsToExport = @(
        'Import-AppManifest'
        'Test-AppManifest'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
