[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $Command = 'state',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments = @()
)

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'PoTAToCli\PoTAToCli.psm1'
Import-Module $modulePath -Force

Invoke-PotatoCliCommand -Command $Command -Arguments $Arguments -CliRoot $PSScriptRoot
