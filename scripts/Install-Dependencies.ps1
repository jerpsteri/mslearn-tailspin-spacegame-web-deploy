#Requires -Version 7.4
<#
.SYNOPSIS
    Installs the pinned PowerShell modules listed in requirements.psd1.

.DESCRIPTION
    Safe to run repeatedly. A module is installed only when the pinned version is missing.
#>
[CmdletBinding()]
param(
    [string]$RequirementsPath = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'requirements.psd1')
)

$ErrorActionPreference = 'Stop'

$requirements = Import-PowerShellDataFile -LiteralPath $RequirementsPath

foreach ($name in $requirements.Keys) {
    $version = $requirements[$name]
    $installed = Get-Module -ListAvailable -Name $name | Where-Object { $_.Version -eq [version]$version }

    if ($installed) {
        Write-Verbose "$name $version is already installed."
        continue
    }

    Write-Information "Installing $name $version" -InformationAction Continue
    Install-Module -Name $name -RequiredVersion $version -Scope CurrentUser -Force -SkipPublisherCheck
}
