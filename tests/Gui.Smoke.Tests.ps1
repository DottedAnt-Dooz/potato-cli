# Opt-in integration fixture: opens only a temporary test form and closes that process.
param()
$ErrorActionPreference='Stop'
$cliRoot=Split-Path -Parent $PSScriptRoot
$root=Join-Path ([IO.Path]::GetTempPath()) ('potato-gui-fixture-'+[guid]::NewGuid())
New-Item -ItemType Directory $root | Out-Null
$child=$null
try {
    $fixture=Join-Path $root 'form.ps1'
    @'
param($Title,$Output)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$form=New-Object Windows.Forms.Form
$form.Text=$Title; $form.Width=440; $form.Height=180
$field=New-Object Windows.Forms.TextBox
$field.AccessibleName='Fixture input'; $field.Top=20; $field.Left=20; $field.Width=350
$button=New-Object Windows.Forms.Button
$button.AccessibleName='Fixture save'; $button.Text='Save'; $button.Top=70; $button.Left=20
$button.Add_Click({[IO.File]::WriteAllText($Output,$field.Text)})
$form.Controls.AddRange(@($field,$button)); $form.Add_Shown({[IO.File]::WriteAllText(($Output+'.ready'),$form.Text); $field.Focus()})
# Consume the hidden process startup window state before displaying the test form.
$form.Show(); $form.Hide()
[void]$form.ShowDialog()
'@ | Set-Content $fixture
    $title='PoTATo fixture '+[guid]::NewGuid().ToString('N')
    $output=Join-Path $root 'saved.txt'
    $child=Start-Process powershell.exe -ArgumentList @('-NoProfile','-STA','-File',('"'+$fixture+'"'),'-Title',('"'+$title+'"'),'-Output',('"'+$output+'"')) -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $root 'child-error.txt') -RedirectStandardOutput (Join-Path $root 'child-output.txt')
    $module=Import-Module (Join-Path $cliRoot 'PoTAToCli\PoTAToCli.psm1') -Force -PassThru
    # State/logs are isolated under the temp root, not the user's CLI session.
    function Invoke-Fixture($command,$values) {
        $r=Invoke-PotatoCliCommand -Command $command -Arguments $values -CliRoot $root -AsObject
        if (-not $r.ok) { throw ($r | ConvertTo-Json -Depth 10 -Compress) }
        return $r
    }
    try { Invoke-Fixture focus @('-ProcessId',"$($child.Id)",'-WindowTitle',$title,'-TimeoutMs','10000') | Out-Null }
    catch {
        Get-Content (Join-Path $root 'child-error.txt'); Get-Content (Join-Path $root 'child-output.txt')
        if (Test-Path ($output+'.ready')) { 'Shown title: '+[IO.File]::ReadAllText($output+'.ready') }
        $child.Refresh(); 'Child running: '+(-not $child.HasExited)+'; window handle: '+$child.MainWindowHandle
        $own=@([Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.ProcessId -eq $child.Id })
        foreach ($window in $own) { 'Owned UIA name: '+$window.Current.Name; & $module {param($element,$title,$processId) Test-PotatoElementMatch $element @{Name=$title;ProcessId=$processId}} $window $title $child.Id }
        throw
    }
    $selected=Invoke-Fixture select @('-Name','Fixture input','-ControlType','Edit')
    if ($selected.data.count -ne 1) { throw 'Editable fixture discovery failed.' }
    $literal='Literal +^%~(){}[] text'
    try { $typed=Invoke-Fixture type @('-Name','Fixture input','-ControlType','Edit','-Text',$literal,'-Verify') }
    catch { (Invoke-Fixture read @('-Name','Fixture input')).data | ConvertTo-Json -Depth 5; throw }
    if ($typed.data.verified -ne $true) { throw 'Literal input did not verify.' }
    $literal='Replacement ^v{ENTER} '+[char]0x151+[char]0x171+[char]0x4e2d+[char]0x6587+[char]::ConvertFromUtf32(0x1f642)
    $typed=Invoke-Fixture type @('-Name','Fixture input','-ControlType','Edit','-Text',$literal,'-PreDelete','-Verify')
    if ($typed.data.verified -ne $true -or $typed.data.clearMethod -ne 'Selection') { throw 'Unicode/selection replacement failed.' }
    Invoke-Fixture click @('-Name','Fixture save','-ControlType','Button','-Method','Invoke') | Out-Null
    $wait=Invoke-Fixture wait-file @('-Path',$output,'-TimeoutMs','3000','-MinBytes','1','-StableMs','100')
    if (-not $wait.data.conditionMet -or [IO.File]::ReadAllText($output) -cne $literal) { throw 'Visible save button did not persist literal content.' }
    Invoke-Fixture close-window @('-ProcessId',"$($child.Id)") | Out-Null
    if (-not $child.WaitForExit(3000)) { throw 'Fixture window did not close.' }
    'GUI smoke: focused writable input, literal typing/readback, UIA button invocation, stable output, and scoped close passed.'
}
finally {
    if ($child -and -not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
    if ($child) {$child.Dispose()}
    $resolved=[IO.Path]::GetFullPath($root)
    $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if ($resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'potato-gui-fixture-*') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
