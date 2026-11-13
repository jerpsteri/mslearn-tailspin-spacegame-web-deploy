@{
    Severity     = @('Error', 'Warning', 'Information')
    ExcludeRules = @(
        # Plan and report output is written for people reading workflow logs.
        'PSAvoidUsingWriteHost'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.4')
        }
    }
}
