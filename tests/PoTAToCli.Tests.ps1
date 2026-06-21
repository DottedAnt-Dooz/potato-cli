$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path -Path $projectRoot -ChildPath 'PoTAToCli\PoTAToCli.psm1'
Import-Module $modulePath -Force

Describe 'PoTAToCli argument parsing' {
    It 'parses named values, equals syntax, switches, and positionals' {
        InModuleScope PoTAToCli {
            $map = ConvertTo-PotatoArgumentMap -Arguments @('-Name', 'Save', '-Regex', '-TimeoutMs=500', 'notepad')
            $map.Name | Should -Be 'Save'
            $map.Regex | Should -Be $true
            $map.TimeoutMs | Should -Be '500'
            $map._[0] | Should -Be 'notepad'
        }
    }

    It 'builds selectors from common aliases' {
        InModuleScope PoTAToCli {
            $map = ConvertTo-PotatoArgumentMap -Arguments @('-Name', 'OK', '-Class', 'Button', '-ControlType', 'Button', '-FindFirst')
            $selector = New-PotatoSelectorFromArguments -ArgsMap $map
            $selector.Name | Should -Be 'OK'
            $selector.ClassName | Should -Be 'Button'
            $selector.ControlType | Should -Be 'Button'
            $selector.FindFirst | Should -Be $true
        }
    }
}

Describe 'PoTAToCli result schema and state' {
    It 'returns one JSON result object for state' {
        $root = Join-Path -Path $TestDrive -ChildPath 'cli'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        $json = Invoke-PotatoCliCommand -Command 'state' -Arguments @() -CliRoot $root
        $result = $json | ConvertFrom-Json
        $result.ok | Should -Be $true
        $result.command | Should -Be 'state'
        $result.session.runId | Should -Not -BeNullOrEmpty
        $result.logPath | Should -Match 'potato\.log$'
    }

    It 'persists and reloads session state' {
        $root = Join-Path -Path $TestDrive -ChildPath 'stateful'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        $first = Invoke-PotatoCliCommand -Command 'state' -Arguments @() -CliRoot $root | ConvertFrom-Json
        Test-Path -LiteralPath $first.data.statePath | Should -Be $true
        $second = Invoke-PotatoCliCommand -Command 'state' -Arguments @() -CliRoot $root | ConvertFrom-Json
        $second.session.runId | Should -Be $first.session.runId

        $third = Invoke-PotatoCliCommand -Command 'state' -Arguments @('-Clear') -CliRoot $root | ConvertFrom-Json
        $third.session.runId | Should -Not -Be $first.session.runId
    }

    It 'reports unknown commands as JSON errors' {
        $root = Join-Path -Path $TestDrive -ChildPath 'errors'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        $json = Invoke-PotatoCliCommand -Command 'missing-command' -Arguments @() -CliRoot $root
        $result = $json | ConvertFrom-Json
        $result.ok | Should -Be $false
        $result.error.message | Should -Match 'Unknown command'
    }
}

Describe 'PoTAToCli report and logging' {
    It 'writes local JSONL report events' {
        $root = Join-Path -Path $TestDrive -ChildPath 'reports'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        $json = Invoke-PotatoCliCommand -Command 'report' -Arguments @('-Step', '1', '-Status', 'PASS', '-Description', 'Created document') -CliRoot $root
        $result = $json | ConvertFrom-Json
        $result.ok | Should -Be $true
        Test-Path -LiteralPath $result.data.reportPath | Should -Be $true
        $line = Get-Content -LiteralPath $result.data.reportPath -Raw
        $line | Should -Match '"status":"PASS"'
    }
}

Describe 'PoTAToCli static exclusions' {
    It 'does not reference excluded legacy subsystems in source files' {
        $excluded = @(
            ('Import-Module ' + 'Potato'),
            ('Get-Potato' + 'CoreFile'),
            ('Selen' + 'ium'),
            ('Image' + 'Recognition'),
            ('Use-' + 'NavigateBrowser'),
            ('Ji' + 'ra'),
            ('Hyper' + 'V'),
            ('VS' + 'phere'),
            ('ME' + 'MCM')
        )
        $sourceFiles = Get-ChildItem -Path $projectRoot -Recurse -File |
            Where-Object { $_.FullName -notmatch '\\tests\\' -and $_.FullName -notmatch '\\\.state\\' -and $_.FullName -notmatch '\\runs\\' }

        foreach ($file in $sourceFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($term in $excluded) {
                $content | Should -Not -Match ([regex]::Escape($term))
            }
        }
    }
}
