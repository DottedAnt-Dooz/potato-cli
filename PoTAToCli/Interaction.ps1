# Application-independent policy and desktop coordination. No GUI input here.
function Get-PotatoInteractionPolicy {
    param([hashtable] $ArgsMap, [string] $Command)
    $mode = [string](Get-PotatoArg $ArgsMap @('InteractionPolicy') 'VisibleControls')
    if ($mode -notin @('VisibleControls', 'AllowShortcuts')) { throw 'Unknown InteractionPolicy. Use VisibleControls or AllowShortcuts.' }
    $shortcut = $Command -eq 'hotkey' -or ($Command -eq 'type' -and
        (ConvertTo-PotatoBool (Get-PotatoArg $ArgsMap @('PreDelete')) $false) -and
        (Get-PotatoArg $ArgsMap @('ClearMethod') 'Selection') -eq 'Shortcut')
    $reason = [string](Get-PotatoArg $ArgsMap @('FallbackReason') '')
    $evidence = [string](Get-PotatoArg $ArgsMap @('FallbackEvidence') '')
    if ($Command -eq 'type') {
        $text = Get-PotatoArg $ArgsMap @('Text')
        if ($null -eq $text -and $ArgsMap._.Count) { $text = $ArgsMap._[0] }
        if ([string]$text -match '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]') { throw 'type rejects control characters that could invoke commands or clipboard operations.' }
    }
    if ($shortcut -and $mode -eq 'VisibleControls') { throw 'InteractionPolicy VisibleControls forbids hotkey and Shortcut clearing. Use visible controls; do not substitute Enter to submit a dialog.' }
    if ($shortcut -and ([string]::IsNullOrWhiteSpace($reason) -or [string]::IsNullOrWhiteSpace($evidence))) {
        throw 'Permitted shortcuts require -FallbackReason and -FallbackEvidence identifying the observed limitation. User authorization for AllowShortcuts is required.'
    }
    if ($Command -eq 'hotkey') {
        $keys = [string](Get-PotatoArg $ArgsMap @('Keys','Text'))
        if (-not $keys -and $ArgsMap._.Count) { $keys = [string]$ArgsMap._[0] }
        # One chord only: no grouped/repeated SendKeys expressions that hide clipboard input.
        if ($keys -notmatch '^([+^%]*)([a-z0-9]|\{[a-z0-9]+\})$') { throw 'hotkey accepts one chord, for example ^s, %{F4}, or {ENTER}; grouped sequences are not supported.' }
        $mods = $Matches[1]; $key = $Matches[2].Trim('{}').ToUpperInvariant()
        if (($mods.Contains('^') -and $key -in @('C','V','X','INSERT','INS')) -or
            ($mods.Contains('+') -and $key -in @('INSERT','INS','DELETE','DEL'))) { throw 'Clipboard shortcuts are not supported by this GUI testing CLI.' }
    }
    if ($Command -eq 'start') {
        $launch = [string](Get-PotatoArg $ArgsMap @('ProcessName','FilePath','Path'))
        if (-not $launch -and $ArgsMap._.Count) { $launch = [string]$ArgsMap._[0] }
        if ($launch -and ([IO.Path]::GetExtension($launch) -notin @('', '.exe'))) { throw 'start launches executables only. Open documents through the application GUI.' }
    }
    return [ordered]@{ mode=$mode; shortcutUsed=[bool]$shortcut; fallbackReason=$reason; fallbackEvidence=$evidence }
}

function Enter-PotatoDesktopLease {
    param([int] $TimeoutMs = 5000)
    if ($TimeoutMs -lt 0 -or $TimeoutMs -gt 60000) { throw 'LeaseTimeoutMs must be between 0 and 60000.' }
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $mutex = New-Object System.Threading.Mutex($false, "Local\PoTATo.Desktop.$sessionId")
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne($TimeoutMs) }
        catch [System.Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'DesktopBusy: another CLI command owns this desktop; no action was dispatched.' }
        return $mutex
    }
    catch { $mutex.Dispose(); throw }
}

function Assert-PotatoTextTarget {
    param([object] $Element, [string] $Text, [bool] $RequireFocus = $true)
    if (-not $Element -or -not $Element.Current.IsEnabled -or ($RequireFocus -and -not $Element.Current.HasKeyboardFocus)) {
        throw 'Text input requires an enabled control with confirmed keyboard focus.'
    }
    if (-not $script:CurrentState.working -or $Element.Current.ProcessId -ne $script:CurrentState.working.processId) {
        throw 'Focused text control does not belong to the working application. Resolve a scoped selector before typing.'
    }
    $role = Get-PotatoControlTypeName $Element
    $pattern = $null
    $writable = $false
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
        $writable = -not $pattern.Current.IsReadOnly
    }
    elseif ($role -in @('Document','Edit') -and $Element.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$pattern)) {
        $readOnly = $pattern.DocumentRange.GetAttributeValue([System.Windows.Automation.TextPattern]::IsReadOnlyAttribute)
        $writable = $readOnly -is [bool] -and -not $readOnly
    }
    if (-not $writable) { throw 'Target is not a confirmed writable text control. A label/name is not an input field.' }
    if ($Text -match '[\r\n\t]' -and $role -ne 'Document') {
        throw 'Newline/tab typing is limited to Document controls. Use visible controls for dialog submission and navigation.'
    }
}

function Test-PotatoModalAncestor {
    param([object] $Element)
    $node = $Element
    for ($i=0; $i -lt 32 -and $node; $i++) {
        $pattern = $null
        if ($node.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$pattern) -and $pattern.Current.IsModal) { return $true }
        $node = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($node)
    }
    return $false
}
