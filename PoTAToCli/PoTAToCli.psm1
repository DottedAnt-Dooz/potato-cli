$script:CliRoot = $null
$script:StateRoot = $null
$script:StatePath = $null
$script:RunsRoot = $null
$script:CurrentState = $null

function Initialize-PotatoEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $CliRoot
    )

    $script:CliRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CliRoot)
    $script:StateRoot = Join-Path -Path $script:CliRoot -ChildPath '.state'
    $script:StatePath = Join-Path -Path $script:StateRoot -ChildPath 'default.json'
    $script:RunsRoot = Join-Path -Path $script:CliRoot -ChildPath 'runs'

    foreach ($path in @($script:StateRoot, $script:RunsRoot)) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }

    Initialize-PotatoAutomationTypes
    $script:CurrentState = Get-PotatoState
    Initialize-PotatoRun -State $script:CurrentState | Out-Null
}

function Initialize-PotatoAutomationTypes {
    [CmdletBinding()]
    param()

    if (-not ('System.Windows.Automation.AutomationElement' -as [type])) {
        Add-Type -AssemblyName @('UIAutomationClient', 'UIAutomationTypes')
    }
    if (-not ('System.Windows.Forms.Cursor' -as [type])) {
        Add-Type -AssemblyName System.Windows.Forms
    }
    if (-not ('System.Drawing.Bitmap' -as [type])) {
        Add-Type -AssemblyName System.Drawing
    }

}

function Initialize-PotatoNativeMouse {
    [CmdletBinding()]
    param()

    if ('PotatoMouseNative' -as [type]) { return $true }

    try {
        $attributeName = 'Dll' + 'Import'
        $libraryName = 'user' + '32.dll'
        $entryPoint = 'mouse' + '_event'
        $source = @"
using System;
using System.Runtime.InteropServices;
public class PotatoMouseNative {
    [$attributeName("$libraryName", EntryPoint="$entryPoint", CharSet = CharSet.Auto, CallingConvention = CallingConvention.StdCall)]
    public static extern void MouseEvent(int dwFlags, int dx, int dy, int cButtons, int dwExtraInfo);
}
"@
        Add-Type -TypeDefinition $source
        return $true
    }
    catch {
        Write-PotatoLog -Level Warning -Message "Native mouse input could not be initialized: $($_.Exception.Message)"
        return $false
    }
}

function New-PotatoStateObject {
    [CmdletBinding()]
    param()

    [ordered]@{
        version = 1
        createdAt = (Get-Date).ToString('o')
        updatedAt = (Get-Date).ToString('o')
        runId = (New-Guid).Guid
        working = $null
        lastAction = $null
        lastReport = $null
    }
}

function Get-PotatoState {
    [CmdletBinding()]
    param()

    if ($script:StatePath -and (Test-Path -LiteralPath $script:StatePath)) {
        try {
            $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
            if (-not $state.runId) {
                $state | Add-Member -NotePropertyName runId -NotePropertyValue ((New-Guid).Guid) -Force
            }
            return $state
        }
        catch {
            return New-PotatoStateObject
        }
    }

    $newState = New-PotatoStateObject
    Save-PotatoState -State $newState
    return Get-PotatoState
}

function Save-PotatoState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $State
    )

    if (-not $script:StateRoot) {
        throw 'PoTATo CLI environment is not initialized.'
    }
    if (-not (Test-Path -LiteralPath $script:StateRoot)) {
        New-Item -Path $script:StateRoot -ItemType Directory -Force | Out-Null
    }

    $State.updatedAt = (Get-Date).ToString('o')
    $State | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:StatePath -Encoding UTF8
    $script:CurrentState = $State
}

function Initialize-PotatoRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $State
    )

    if (-not $State.runId) {
        $State | Add-Member -NotePropertyName runId -NotePropertyValue ((New-Guid).Guid) -Force
        Save-PotatoState -State $State
    }

    $runPath = Get-PotatoRunPath -RunId $State.runId
    foreach ($path in @($runPath, (Join-Path $runPath 'screenshots'))) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
    return $runPath
}

function Get-PotatoRunPath {
    [CmdletBinding()]
    param(
        [string] $RunId = $script:CurrentState.runId
    )

    Join-Path -Path $script:RunsRoot -ChildPath $RunId
}

function Get-PotatoLogPath {
    [CmdletBinding()]
    param()

    Join-Path -Path (Get-PotatoRunPath) -ChildPath 'potato.log'
}

function Write-PotatoLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string] $Level = 'Info',

        [string] $Command = ''
    )

    $entry = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        level = $Level
        command = $Command
        message = $Message
    }
    $entry | ConvertTo-Json -Compress | Add-Content -LiteralPath (Get-PotatoLogPath) -Encoding UTF8
}

function ConvertTo-PotatoArgumentMap {
    [CmdletBinding()]
    param(
        [string[]] $Arguments = @()
    )

    $map = [ordered]@{ _ = @() }
    $i = 0
    while ($i -lt $Arguments.Count) {
        $arg = $Arguments[$i]
        if ($arg -match '^-{1,2}([^=]+)=(.*)$') {
            $map[$Matches[1]] = $Matches[2]
            $i++
            continue
        }

        if ($arg -match '^-{1,2}(.+)$') {
            $name = $Matches[1]
            if (($i + 1) -lt $Arguments.Count -and $Arguments[$i + 1] -notmatch '^-') {
                $map[$name] = $Arguments[$i + 1]
                $i += 2
            }
            else {
                $map[$name] = $true
                $i++
            }
            continue
        }

        $map._ += $arg
        $i++
    }
    return $map
}

function Get-PotatoArg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap,

        [Parameter(Mandatory)]
        [string[]] $Names,

        [object] $Default = $null
    )

    foreach ($name in $Names) {
        if ($ArgsMap.Contains($name)) {
            return $ArgsMap[$name]
        }
    }
    return $Default
}

function ConvertTo-PotatoBool {
    [CmdletBinding()]
    param(
        [object] $Value,
        [bool] $Default = $false
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return $Value }
    $text = [string]$Value
    if ($text -match '^(1|true|yes|y|on)$') { return $true }
    if ($text -match '^(0|false|no|n|off)$') { return $false }
    return $Default
}

function ConvertTo-PotatoInt {
    [CmdletBinding()]
    param(
        [object] $Value,
        [int] $Default = 0
    )

    if ($null -eq $Value) { return $Default }
    $parsed = 0
    if ([int]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }
    return $Default
}

function New-PotatoSelectorFromArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $selector = [ordered]@{}
    foreach ($pair in @(
        @{ key = 'Name'; names = @('Name', 'WindowName') },
        @{ key = 'AutomationId'; names = @('AutomationId', 'Id') },
        @{ key = 'ClassName'; names = @('ClassName', 'Class') },
        @{ key = 'ControlType'; names = @('ControlType') },
        @{ key = 'ProcessName'; names = @('ProcessName') },
        @{ key = 'WindowTitle'; names = @('WindowTitle') }
    )) {
        $value = Get-PotatoArg -ArgsMap $ArgsMap -Names $pair.names
        if ($null -ne $value -and "$value" -ne '') {
            $selector[$pair.key] = $value
        }
    }

    $selector.Regex = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Regex')) $false
    $selector.Recurse = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Recurse')) $true
    $selector.FindFirst = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('FindFirst')) $false
    $selector.TimeoutMs = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('TimeoutMs', 'MillisecondsToWait')) 1000
    return $selector
}

function ConvertFrom-PotatoJsonArgument {
    [CmdletBinding()]
    param(
        [object] $Value
    )

    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [string]) {
        return ($Value | ConvertFrom-Json)
    }
    return $Value
}

function Test-PotatoPattern {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string] $Actual,

        [AllowNull()]
        [object] $Expected,

        [bool] $Regex = $false
    )

    if ($null -eq $Expected -or "$Expected" -eq '') { return $true }
    $actualText = [string]$Actual
    foreach ($item in @($Expected)) {
        $expectedText = [string]$item
        if ($Regex) {
            if ($actualText -match $expectedText) { return $true }
        }
        elseif ($expectedText -match '[\*\?\[]') {
            if ($actualText -like $expectedText) { return $true }
        }
        else {
            if ($actualText -ieq $expectedText) { return $true }
        }
    }
    return $false
}

function Get-PotatoControlTypeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Element
    )

    try {
        return $Element.Current.ControlType.ProgrammaticName.Split('.')[-1]
    }
    catch {
        return ''
    }
}

function Test-PotatoElementMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Element,

        [Parameter(Mandatory)]
        [object] $Selector
    )

    $regex = ConvertTo-PotatoBool $Selector.Regex $false
    $current = $Element.Current
    $controlName = Get-PotatoControlTypeName -Element $Element
    $processName = ''
    try { $processName = (Get-Process -Id $current.ProcessId -ErrorAction Stop).ProcessName } catch {}

    if (-not (Test-PotatoPattern -Actual $current.Name -Expected $Selector.Name -Regex $regex)) { return $false }
    if (-not (Test-PotatoPattern -Actual $current.AutomationId -Expected $Selector.AutomationId -Regex $regex)) { return $false }
    if (-not (Test-PotatoPattern -Actual $current.ClassName -Expected $Selector.ClassName -Regex $regex)) { return $false }
    if (-not (Test-PotatoPattern -Actual $processName -Expected $Selector.ProcessName -Regex $regex)) { return $false }
    if (-not (Test-PotatoPattern -Actual $current.Name -Expected $Selector.WindowTitle -Regex $regex)) { return $false }

    if ($Selector.ControlType -and "$($Selector.ControlType)" -ne '') {
        $localized = $current.LocalizedControlType
        if (-not (Test-PotatoPattern -Actual $controlName -Expected $Selector.ControlType -Regex $regex) -and
            -not (Test-PotatoPattern -Actual $localized -Expected $Selector.ControlType -Regex $regex)) {
            return $false
        }
    }
    return $true
}

function Get-PotatoRootElement {
    [CmdletBinding()]
    param()

    [System.Windows.Automation.AutomationElement]::RootElement
}

function Get-PotatoWorkingElement {
    [CmdletBinding()]
    param(
        [switch] $Required
    )

    $state = $script:CurrentState
    if (-not $state -or -not $state.working) {
        if ($Required) { throw 'No working window is set. Run start or focus first, or pass an explicit selector.' }
        return $null
    }

    $handle = [IntPtr]::Zero
    if ($state.working.nativeWindowHandle) {
        $handle = [IntPtr]([int64]$state.working.nativeWindowHandle)
        try {
            $element = [System.Windows.Automation.AutomationElement]::FromHandle($handle)
            if ($element) { return $element }
        }
        catch {}
    }

    $selector = [ordered]@{
        ProcessName = $state.working.processName
        Name = $state.working.title
        Recurse = $false
        FindFirst = $true
        TimeoutMs = 100
    }
    return @(Find-PotatoElement -Selector $selector -Parent (Get-PotatoRootElement) -TimeoutMs 100 -FindFirst) | Select-Object -First 1
}

function Find-PotatoElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Selector,

        [object] $Parent = $null,

        [int] $TimeoutMs = -1,

        [switch] $FindFirst
    )

    if (-not $Parent) {
        $Parent = Get-PotatoWorkingElement
        if (-not $Parent) {
            $Parent = Get-PotatoRootElement
        }
    }

    $effectiveTimeout = $TimeoutMs
    if ($effectiveTimeout -lt 0) {
        $effectiveTimeout = ConvertTo-PotatoInt $Selector.TimeoutMs 1000
    }
    $recurse = ConvertTo-PotatoBool $Selector.Recurse $true
    $scope = [System.Windows.Automation.TreeScope]::Children
    if ($recurse) {
        $scope = [System.Windows.Automation.TreeScope]::Descendants
    }
    $stopAt = (Get-Date).AddMilliseconds($effectiveTimeout)

    do {
        $matches = @()
        try {
            $collection = $Parent.FindAll($scope, [System.Windows.Automation.Condition]::TrueCondition)
            foreach ($element in $collection) {
                if (Test-PotatoElementMatch -Element $element -Selector $Selector) {
                    $matches += $element
                    if ($FindFirst -or (ConvertTo-PotatoBool $Selector.FindFirst $false)) {
                        return ,$matches[0]
                    }
                }
            }
        }
        catch {
            Write-PotatoLog -Level Warning -Message "Element search failed: $($_.Exception.Message)"
        }

        if ($matches.Count -gt 0) { return $matches }
        if ((Get-Date) -lt $stopAt) { Start-Sleep -Milliseconds 100 }
    } while ((Get-Date) -lt $stopAt)

    return @()
}

function Resolve-PotatoSelectorPath {
    [CmdletBinding()]
    param(
        [object] $Path,
        [object] $StartParent = $null,
        [int] $DefaultTimeoutMs = 1000
    )

    $parent = $StartParent
    if (-not $parent) {
        $parent = Get-PotatoWorkingElement
        if (-not $parent) { $parent = Get-PotatoRootElement }
    }

    if (-not $Path) {
        return [ordered]@{ ok = $true; element = $parent; failedIndex = $null; failedSelector = $null }
    }

    $selectors = @($Path)
    for ($i = 0; $i -lt $selectors.Count; $i++) {
        $selector = $selectors[$i]
        if (-not $selector.Recurse) { $selector | Add-Member -NotePropertyName Recurse -NotePropertyValue $true -Force }
        if (-not $selector.FindFirst) { $selector | Add-Member -NotePropertyName FindFirst -NotePropertyValue $true -Force }
        if (-not $selector.TimeoutMs) { $selector | Add-Member -NotePropertyName TimeoutMs -NotePropertyValue $DefaultTimeoutMs -Force }

        $found = @(Find-PotatoElement -Selector $selector -Parent $parent -FindFirst -TimeoutMs (ConvertTo-PotatoInt $selector.TimeoutMs $DefaultTimeoutMs)) | Select-Object -First 1
        if (-not $found) {
            return [ordered]@{ ok = $false; element = $null; failedIndex = $i; failedSelector = $selector }
        }
        $parent = $found
    }

    return [ordered]@{ ok = $true; element = $parent; failedIndex = $null; failedSelector = $null }
}

function Get-PotatoSelectorInputs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $selectorJson = ConvertFrom-PotatoJsonArgument (Get-PotatoArg -ArgsMap $ArgsMap -Names @('SelectorJson'))
    $pathJson = ConvertFrom-PotatoJsonArgument (Get-PotatoArg -ArgsMap $ArgsMap -Names @('PathJson'))
    $selector = New-PotatoSelectorFromArguments -ArgsMap $ArgsMap

    if ($selectorJson) {
        if ($selectorJson -is [array]) {
            $pathJson = $selectorJson
        }
        elseif ($selectorJson.path -or $selectorJson.Path) {
            $pathJson = @($selectorJson.path + $selectorJson.Path) | Where-Object { $_ }
            if ($selectorJson.target) {
                $selector = $selectorJson.target
            }
            elseif ($selectorJson.Target) {
                $selector = $selectorJson.Target
            }
        }
        else {
            $selector = $selectorJson
        }
    }

    [ordered]@{
        selector = $selector
        path = $pathJson
    }
}

function ConvertTo-PotatoRectangle {
    [CmdletBinding()]
    param(
        [object] $Rectangle
    )

    if ($null -eq $Rectangle) {
        return $null
    }

    [ordered]@{
        x = [int][Math]::Round($Rectangle.X)
        y = [int][Math]::Round($Rectangle.Y)
        width = [int][Math]::Round($Rectangle.Width)
        height = [int][Math]::Round($Rectangle.Height)
    }
}

function ConvertTo-PotatoElementInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Element
    )

    $current = $Element.Current
    $processName = ''
    try { $processName = (Get-Process -Id $current.ProcessId -ErrorAction Stop).ProcessName } catch {}
    $patterns = @()
    try { $patterns = @($Element.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName.Replace('PatternIdentifiers.Pattern', '') }) } catch {}

    [ordered]@{
        name = $current.Name
        automationId = $current.AutomationId
        className = $current.ClassName
        controlType = Get-PotatoControlTypeName -Element $Element
        localizedControlType = $current.LocalizedControlType
        processId = $current.ProcessId
        processName = $processName
        nativeWindowHandle = $current.NativeWindowHandle
        isEnabled = $current.IsEnabled
        isOffscreen = $current.IsOffscreen
        boundingRectangle = ConvertTo-PotatoRectangle -Rectangle $current.BoundingRectangle
        supportedPatterns = $patterns
    }
}

function Set-PotatoWorkingWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Element,

        [object] $Process = $null
    )

    $info = ConvertTo-PotatoElementInfo -Element $Element
    if (-not $Process -and $info.processId) {
        try { $Process = Get-Process -Id $info.processId -ErrorAction Stop } catch {}
    }

    $working = [ordered]@{
        title = $info.name
        processName = $info.processName
        processId = $info.processId
        nativeWindowHandle = $info.nativeWindowHandle
        className = $info.className
        updatedAt = (Get-Date).ToString('o')
    }
    if ($Process) {
        $working.processName = $Process.ProcessName
        $working.processId = $Process.Id
        if (-not $working.title) { $working.title = $Process.MainWindowTitle }
        if (-not $working.nativeWindowHandle) { $working.nativeWindowHandle = $Process.MainWindowHandle.ToInt64() }
    }

    $script:CurrentState.working = $working
    Save-PotatoState -State $script:CurrentState
    return $working
}

function Show-PotatoWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int64] $Handle,

        [switch] $Maximize
    )

    if ($Handle -eq 0) { return $false }
    try {
        $element = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Handle)
        if (-not $element) { return $false }
        if ($Maximize) {
            try {
                $pattern = $element.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
                $pattern.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Maximized)
            }
            catch {}
        }
        try { $element.SetFocus() } catch {}
        return $true
    }
    catch {
        return $false
    }
}

function Get-PotatoTopLevelWindows {
    [CmdletBinding()]
    param(
        [object] $Selector = $null,
        [int] $TimeoutMs = 0
    )

    $root = Get-PotatoRootElement
    $stopAt = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        $windows = @()
        try {
            $all = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
            foreach ($window in $all) {
                if (-not $Selector -or (Test-PotatoElementMatch -Element $window -Selector $Selector)) {
                    $windows += $window
                }
            }
        }
        catch {}
        if ($windows.Count -gt 0 -or $TimeoutMs -le 0) { return $windows }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $stopAt)

    return @()
}

function Wait-PotatoProcessWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process,

        [int] $TimeoutMs = 15000
    )

    $stopAt = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        $Process.Refresh()
        if ($Process.MainWindowHandle -and $Process.MainWindowHandle.ToInt64() -ne 0) {
            try {
                return [System.Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
            }
            catch {}
        }
        $selector = [ordered]@{
            ProcessName = $Process.ProcessName
            Recurse = $false
            FindFirst = $true
        }
        $window = @(Get-PotatoTopLevelWindows -Selector $selector -TimeoutMs 100) | Select-Object -First 1
        if ($window) { return $window }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $stopAt)

    return $null
}

function Invoke-PotatoStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $processName = Get-PotatoArg -ArgsMap $ArgsMap -Names @('ProcessName', 'FilePath', 'Path')
    if (-not $processName -and $ArgsMap._.Count -gt 0) { $processName = $ArgsMap._[0] }
    if (-not $processName) { throw 'start requires -ProcessName, -FilePath, or a positional process name.' }

    $arguments = Get-PotatoArg -ArgsMap $ArgsMap -Names @('Arguments', 'ArgumentList') -Default ''
    $killExisting = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('KillExisting')) $false
    $timeoutMs = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('WaitForWindowMs', 'TimeoutMs')) 15000
    $maximize = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Maximize', 'MaximizeWindow')) $false

    $filePath = ''
    $targetProcessName = $processName
    if (Test-Path -LiteralPath $processName) {
        $filePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($processName)
        $targetProcessName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
    }

    if ($killExisting) {
        Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -eq $targetProcessName -or ($filePath -and $_.Path -eq $filePath) } |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }

    $startParams = @{ FilePath = $(if ($filePath) { $filePath } else { $processName }); PassThru = $true }
    if ($arguments) { $startParams.ArgumentList = $arguments }
    $started = Start-Process @startParams
    $window = Wait-PotatoProcessWindow -Process $started -TimeoutMs $timeoutMs
    $working = $null
    if ($window) {
        $working = Set-PotatoWorkingWindow -Element $window -Process $started
        [void](Show-PotatoWindow -Handle $working.nativeWindowHandle -Maximize:$maximize)
    }

    [ordered]@{
        process = [ordered]@{
            id = $started.Id
            processName = $started.ProcessName
            started = $true
        }
        working = $working
        windowFound = [bool]$window
    }
}

function Invoke-PotatoFocus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $selector = New-PotatoSelectorFromArguments -ArgsMap $ArgsMap
    $selector.Recurse = $false
    $selector.FindFirst = $true
    $timeoutMs = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('TimeoutMs', 'MillisecondsToWait')) 5000
    $maximize = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Maximize', 'MaximizeWindow')) $false

    if ($selector.WindowTitle -and -not $selector.Name) { $selector.Name = $selector.WindowTitle }
    $processId = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('ProcessId')) 0
    $windows = @(Get-PotatoTopLevelWindows -Selector $selector -TimeoutMs $timeoutMs)
    if ($processId -gt 0) { $windows = @($windows | Where-Object { $_.Current.ProcessId -eq $processId }) }
    $window = $windows | Select-Object -First 1
    if (-not $window) { throw 'No matching top-level window was found.' }

    $working = Set-PotatoWorkingWindow -Element $window
    [void](Show-PotatoWindow -Handle $working.nativeWindowHandle -Maximize:$maximize)
    [ordered]@{ working = $working }
}

function Invoke-PotatoWindows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $selector = New-PotatoSelectorFromArguments -ArgsMap $ArgsMap
    $selector.Recurse = $false
    $timeoutMs = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('TimeoutMs')) 0
    $windows = @(Get-PotatoTopLevelWindows -Selector $selector -TimeoutMs $timeoutMs)
    [ordered]@{
        count = $windows.Count
        windows = @($windows | ForEach-Object { ConvertTo-PotatoElementInfo -Element $_ })
    }
}

function Get-PotatoForegroundWindowInfo {
    [CmdletBinding()]
    param()

    try {
        $element = [System.Windows.Automation.AutomationElement]::FocusedElement
        if (-not $element) { return $null }
        return ConvertTo-PotatoElementInfo -Element $element
    }
    catch {
        return $null
    }
}

function ConvertTo-PotatoTreeNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Element,

        [int] $Depth = 2,

        [ref] $Remaining
    )

    if ($Remaining.Value -le 0) { return $null }
    $Remaining.Value--
    $info = ConvertTo-PotatoElementInfo -Element $Element
    $node = [ordered]@{
        element = $info
        children = @()
    }

    if ($Depth -le 0 -or $Remaining.Value -le 0) {
        return $node
    }

    try {
        $children = $Element.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($child in $children) {
            if ($Remaining.Value -le 0) { break }
            $childNode = ConvertTo-PotatoTreeNode -Element $child -Depth ($Depth - 1) -Remaining $Remaining
            if ($childNode) { $node.children += $childNode }
        }
    }
    catch {}
    return $node
}

function Invoke-PotatoObserve {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $depth = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Depth')) 2
    $maxElements = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('MaxElements')) 200
    $working = Get-PotatoWorkingElement
    $windows = @(Get-PotatoTopLevelWindows)
    $workingInfo = $null
    $tree = $null
    if ($working) {
        $workingInfo = ConvertTo-PotatoElementInfo -Element $working
        $remaining = [ref]$maxElements
        $tree = ConvertTo-PotatoTreeNode -Element $working -Depth $depth -Remaining $remaining
    }

    $blocking = @()
    foreach ($window in $windows) {
        $info = ConvertTo-PotatoElementInfo -Element $window
        $sameProcess = $workingInfo -and $info.processId -eq $workingInfo.processId
        $looksModal = $info.className -eq '#32770' -or $info.localizedControlType -match 'dialog' -or $info.controlType -eq 'Window'
        if ($sameProcess -and $looksModal -and $info.nativeWindowHandle -ne $workingInfo.nativeWindowHandle) {
            $blocking += $info
        }
    }

    [ordered]@{
        working = $workingInfo
        foreground = Get-PotatoForegroundWindowInfo
        windows = @($windows | ForEach-Object { ConvertTo-PotatoElementInfo -Element $_ })
        likelyBlockingWindows = $blocking
        tree = $tree
    }
}

function Resolve-PotatoCommandTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap,

        [switch] $AllowPathAsTarget
    )

    $inputs = Get-PotatoSelectorInputs -ArgsMap $ArgsMap
    $path = $inputs.path
    $selector = $inputs.selector
    $parent = $null
    $pathResult = Resolve-PotatoSelectorPath -Path $path
    if (-not $pathResult.ok) {
        return [ordered]@{ ok = $false; error = "Selector path failed at index $($pathResult.failedIndex)."; element = $null; selector = $selector }
    }
    $parent = $pathResult.element

    $hasSimpleSelector = $selector.Name -or $selector.AutomationId -or $selector.ClassName -or $selector.ControlType -or $selector.ProcessName -or $selector.WindowTitle
    if ($AllowPathAsTarget -and -not $hasSimpleSelector -and $path) {
        return [ordered]@{ ok = $true; element = $parent; selector = $selector }
    }

    $found = @(Find-PotatoElement -Selector $selector -Parent $parent -FindFirst -TimeoutMs (ConvertTo-PotatoInt $selector.TimeoutMs 1000)) | Select-Object -First 1
    if (-not $found) {
        return [ordered]@{ ok = $false; error = 'No matching element was found.'; element = $null; selector = $selector }
    }
    return [ordered]@{ ok = $true; element = $found; selector = $selector }
}

function Invoke-PotatoSelect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $inputs = Get-PotatoSelectorInputs -ArgsMap $ArgsMap
    $pathResult = Resolve-PotatoSelectorPath -Path $inputs.path
    if (-not $pathResult.ok) { throw "Selector path failed at index $($pathResult.failedIndex)." }

    $maxResults = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('MaxResults')) 20
    $selector = $inputs.selector
    $timeoutMs = ConvertTo-PotatoInt $selector.TimeoutMs 1000
    $findFirst = ConvertTo-PotatoBool $selector.FindFirst $false
    $elements = @(Find-PotatoElement -Selector $selector -Parent $pathResult.element -TimeoutMs $timeoutMs -FindFirst:$findFirst) |
        Select-Object -First $maxResults

    [ordered]@{
        count = $elements.Count
        elements = @($elements | ForEach-Object { ConvertTo-PotatoElementInfo -Element $_ })
    }
}

function Move-PotatoMouse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $X,

        [Parameter(Mandatory)]
        [int] $Y
    )

    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($X, $Y)
}

function Invoke-PotatoMouseClick {
    [CmdletBinding()]
    param(
        [ValidateSet('Left', 'Right')]
        [string] $Button = 'Left'
    )

    if (-not (Initialize-PotatoNativeMouse)) {
        throw 'Native mouse input is not available in this PowerShell session.'
    }

    if ($Button -eq 'Right') {
        [PotatoMouseNative]::MouseEvent(0x0008, 0, 0, 0, 0)
        [PotatoMouseNative]::MouseEvent(0x0010, 0, 0, 0, 0)
    }
    else {
        [PotatoMouseNative]::MouseEvent(0x0002, 0, 0, 0, 0)
        [PotatoMouseNative]::MouseEvent(0x0004, 0, 0, 0, 0)
    }
}

function Invoke-PotatoElementDefaultAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Element
    )

    try {
        $invoke = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        if ($invoke) {
            $invoke.Invoke()
            return 'InvokePattern'
        }
    }
    catch {}

    try {
        $toggle = $Element.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if ($toggle) {
            $toggle.Toggle()
            return 'TogglePattern'
        }
    }
    catch {}

    try {
        $selection = $Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        if ($selection) {
            $selection.Select()
            return 'SelectionItemPattern'
        }
    }
    catch {}

    try {
        $expand = $Element.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
        if ($expand) {
            if ($expand.Current.ExpandCollapseState -eq [System.Windows.Automation.ExpandCollapseState]::Collapsed) {
                $expand.Expand()
            }
            else {
                $expand.Collapse()
            }
            return 'ExpandCollapsePattern'
        }
    }
    catch {}

    return $null
}

function Get-PotatoClickPoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Element,

        [bool] $Center = $false,

        [int] $OffsetX = 0,

        [int] $OffsetY = 0,

        [bool] $OffsetClickablePoint = $true
    )

    $clickable = $null
    try { $clickable = $Element.GetClickablePoint() } catch {}
    $rect = $Element.Current.BoundingRectangle
    if ($Center -or -not $clickable) {
        $x = $rect.X + ($rect.Width / 2)
        $y = $rect.Y + ($rect.Height / 2)
    }
    else {
        $x = $clickable.X
        $y = $clickable.Y
    }

    if ($OffsetX -ne 0 -or $OffsetY -ne 0) {
        if ($OffsetClickablePoint -or -not $clickable) {
            $x += $OffsetX
            $y += $OffsetY
        }
        else {
            $x = $rect.X + $OffsetX
            $y = $rect.Y + $OffsetY
        }
    }

    [ordered]@{ x = [int][Math]::Round($x); y = [int][Math]::Round($y) }
}

function Invoke-PotatoClick {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $target = Resolve-PotatoCommandTarget -ArgsMap $ArgsMap -AllowPathAsTarget
    if (-not $target.ok) { throw $target.error }

    $focus = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Focus')) $true
    $elementFocus = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('ElementFocus')) $true
    $center = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Center')) $false
    $button = Get-PotatoArg -ArgsMap $ArgsMap -Names @('Button') -Default 'Left'
    $offsetX = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('OffsetX')) 0
    $offsetY = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('OffsetY')) 0
    $offsetClickablePoint = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('OffsetClickablePoint')) $true

    if ($focus) {
        $working = Get-PotatoWorkingElement
        if ($working) { [void](Show-PotatoWindow -Handle $working.Current.NativeWindowHandle) }
    }
    if ($elementFocus) {
        try { $target.element.SetFocus() } catch {}
    }

    $action = $null
    if ($button -eq 'Left' -and $offsetX -eq 0 -and $offsetY -eq 0 -and -not $center) {
        $action = Invoke-PotatoElementDefaultAction -Element $target.element
    }
    $point = Get-PotatoClickPoint -Element $target.element -Center $center -OffsetX $offsetX -OffsetY $offsetY -OffsetClickablePoint $offsetClickablePoint
    if (-not $action) {
        Move-PotatoMouse -X $point.x -Y $point.y
        Invoke-PotatoMouseClick -Button $button
        $action = 'Mouse'
    }

    $verifyDisappeared = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('VerifyDisappeared')) $false
    $verified = $true
    if ($verifyDisappeared) {
        Start-Sleep -Milliseconds 500
        $matches = @(Find-PotatoElement -Selector $target.selector -TimeoutMs 1000 -FindFirst)
        $verified = ($matches.Count -eq 0)
    }

    $script:CurrentState.lastAction = [ordered]@{ command = 'click'; ok = $verified; timestamp = (Get-Date).ToString('o') }
    Save-PotatoState -State $script:CurrentState

    [ordered]@{
        clicked = $true
        verified = $verified
        action = $action
        point = $point
        element = ConvertTo-PotatoElementInfo -Element $target.element
    }
}

function Invoke-PotatoClickCoordinate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $x = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('X', 'x')) ([int]::MinValue)
    $y = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Y', 'y')) ([int]::MinValue)
    if ($x -eq [int]::MinValue -or $y -eq [int]::MinValue) { throw 'click-coordinate requires -X and -Y.' }
    $button = Get-PotatoArg -ArgsMap $ArgsMap -Names @('Button') -Default 'Left'
    Move-PotatoMouse -X $x -Y $y
    $action = 'Mouse'
    try {
        Invoke-PotatoMouseClick -Button $button
    }
    catch {
        if ($button -ne 'Left') { throw }
        $point = New-Object System.Windows.Point($x, $y)
        $element = [System.Windows.Automation.AutomationElement]::FromPoint($point)
        $action = Invoke-PotatoElementDefaultAction -Element $element
        if (-not $action) { throw }
    }
    [ordered]@{ clicked = $true; point = [ordered]@{ x = $x; y = $y }; button = $button; action = $action }
}

function Invoke-PotatoType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $text = Get-PotatoArg -ArgsMap $ArgsMap -Names @('Text')
    if ($null -eq $text -and $ArgsMap._.Count -gt 0) { $text = $ArgsMap._[0] }
    if ($null -eq $text) { throw 'type requires -Text or a positional text value.' }

    $focus = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Focus')) $false
    $preDelete = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('PreDelete')) $false
    $verify = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Verify')) $false
    $typeByCharacter = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('TypeByCharacter')) $false
    $useWildcard = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('UseWildcardForVerify')) $false
    $maxAttempts = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('MaxAttempts')) 5

    if ($focus) {
        $working = Get-PotatoWorkingElement
        if ($working) { [void](Show-PotatoWindow -Handle $working.Current.NativeWindowHandle) }
    }

    $shell = New-Object -ComObject WScript.Shell
    if ($preDelete) {
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        Start-Sleep -Milliseconds 100
        $shell.SendKeys('{BACKSPACE}')
        Start-Sleep -Milliseconds 100
    }

    $sendText = {
        param($value, $byChar)
        if ($byChar) {
            foreach ($char in [char[]]$value) {
                $s = [string]$char
                if ($s -eq '+') { $s = '{+}' }
                $shell.SendKeys($s)
                Start-Sleep -Milliseconds 50
            }
        }
        else {
            $shell.SendKeys([string]$value)
        }
    }

    & $sendText $text $typeByCharacter
    $typedOk = $true
    if ($verify) {
        $typedOk = $false
        for ($i = 0; $i -lt $maxAttempts; $i++) {
            Start-Sleep -Milliseconds 300
            Set-Clipboard -Value ''
            [System.Windows.Forms.SendKeys]::SendWait('^a')
            Start-Sleep -Milliseconds 100
            [System.Windows.Forms.SendKeys]::SendWait('^c')
            Start-Sleep -Milliseconds 100
            $actual = [string](Get-Clipboard)
            if (($useWildcard -and $actual -like "*$text*") -or (-not $useWildcard -and $actual -eq $text)) {
                $typedOk = $true
                break
            }
            if ($i -lt ($maxAttempts - 1)) {
                if ($preDelete) {
                    [System.Windows.Forms.SendKeys]::SendWait('^a')
                    $shell.SendKeys('{BACKSPACE}')
                }
                & $sendText $text $typeByCharacter
            }
        }
    }

    $script:CurrentState.lastAction = [ordered]@{ command = 'type'; ok = $typedOk; timestamp = (Get-Date).ToString('o') }
    Save-PotatoState -State $script:CurrentState

    [ordered]@{ typed = $typedOk; textLength = ([string]$text).Length; verified = $typedOk }
}

function Invoke-PotatoHotkey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $keys = Get-PotatoArg -ArgsMap $ArgsMap -Names @('Keys', 'Text')
    if ($null -eq $keys -and $ArgsMap._.Count -gt 0) { $keys = $ArgsMap._[0] }
    if ($null -eq $keys) { throw 'hotkey requires -Keys or a positional SendKeys expression.' }
    $focus = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Focus')) $false
    if ($focus) {
        $working = Get-PotatoWorkingElement
        if ($working) { [void](Show-PotatoWindow -Handle $working.Current.NativeWindowHandle) }
    }
    [System.Windows.Forms.SendKeys]::SendWait([string]$keys)
    [ordered]@{ sent = $true; keys = [string]$keys }
}

function Move-PotatoMouseSmooth {
    [CmdletBinding()]
    param(
        [int] $StartX,
        [int] $StartY,
        [int] $EndX,
        [int] $EndY
    )

    $width = $EndX - $StartX
    $height = $EndY - $StartY
    $steps = [Math]::Max(1, [Math]::Floor([Math]::Sqrt([Math]::Pow($height, 2) + [Math]::Pow($width, 2)) / 10))
    for ($i = 0; $i -lt $steps; $i++) {
        $x = $StartX + (($width / $steps) * $i)
        $y = $StartY + (($height / $steps) * $i)
        Move-PotatoMouse -X ([int]$x) -Y ([int]$y)
        Start-Sleep -Milliseconds 5
    }
    Move-PotatoMouse -X $EndX -Y $EndY
}

function Invoke-PotatoDrag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $startX = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('StartX')) ([int]::MinValue)
    $startY = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('StartY')) ([int]::MinValue)
    $endX = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('EndX')) ([int]::MinValue)
    $endY = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('EndY')) ([int]::MinValue)
    if (@($startX, $startY, $endX, $endY) -contains [int]::MinValue) { throw 'drag requires -StartX -StartY -EndX -EndY.' }
    $smooth = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Smooth')) $false
    if (-not (Initialize-PotatoNativeMouse)) {
        throw 'drag requires native mouse input, which is not available in this PowerShell session.'
    }
    Move-PotatoMouse -X $startX -Y $startY
    Start-Sleep -Milliseconds 100
    [PotatoMouseNative]::MouseEvent(0x0002, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 100
    if ($smooth) { Move-PotatoMouseSmooth -StartX $startX -StartY $startY -EndX $endX -EndY $endY } else { Move-PotatoMouse -X $endX -Y $endY }
    [PotatoMouseNative]::MouseEvent(0x0004, 0, 0, 0, 0)
    [ordered]@{ dragged = $true; start = [ordered]@{ x = $startX; y = $startY }; end = [ordered]@{ x = $endX; y = $endY } }
}

function Invoke-PotatoHover {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $xValue = Get-PotatoArg -ArgsMap $ArgsMap -Names @('X', 'x')
    $yValue = Get-PotatoArg -ArgsMap $ArgsMap -Names @('Y', 'y')
    if ($null -ne $xValue -and $null -ne $yValue) {
        $point = [ordered]@{ x = (ConvertTo-PotatoInt $xValue 0); y = (ConvertTo-PotatoInt $yValue 0) }
    }
    else {
        $target = Resolve-PotatoCommandTarget -ArgsMap $ArgsMap -AllowPathAsTarget
        if (-not $target.ok) { throw $target.error }
        $point = Get-PotatoClickPoint -Element $target.element -Center $true
    }
    Move-PotatoMouse -X $point.x -Y $point.y
    [ordered]@{ hovered = $true; point = $point }
}

function Invoke-PotatoWaitElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $result = Invoke-PotatoSelect -ArgsMap $ArgsMap
    [ordered]@{
        exists = ($result.count -gt 0)
        count = $result.count
        elements = $result.elements
    }
}

function Invoke-PotatoWaitFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $path = Get-PotatoArg -ArgsMap $ArgsMap -Names @('Path', 'FilePath')
    if ($null -eq $path -and $ArgsMap._.Count -gt 0) { $path = $ArgsMap._[0] }
    if (-not $path) { throw 'wait-file requires -Path or a positional path.' }
    $timeoutMs = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('TimeoutMs', 'MillisecondsToWait')) 1000
    $waitForNotExists = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('WaitForNotExists')) $false
    $stopAt = (Get-Date).AddMilliseconds($timeoutMs)
    do {
        $exists = Test-Path -LiteralPath $path
        if (($exists -and -not $waitForNotExists) -or (-not $exists -and $waitForNotExists)) { break }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $stopAt)

    [ordered]@{ path = [string]$path; exists = (Test-Path -LiteralPath $path); conditionMet = $(if ($waitForNotExists) { -not (Test-Path -LiteralPath $path) } else { Test-Path -LiteralPath $path }) }
}

function Get-PotatoElementText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Element
    )

    try {
        $valuePattern = $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if ($valuePattern) { return $valuePattern.Current.Value }
    }
    catch {}
    try {
        $textPattern = $Element.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        if ($textPattern) { return $textPattern.DocumentRange.GetText(-1) }
    }
    catch {}
    return $Element.Current.Name
}

function Invoke-PotatoRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $target = Resolve-PotatoCommandTarget -ArgsMap $ArgsMap -AllowPathAsTarget
    if (-not $target.ok) { throw $target.error }
    $text = Get-PotatoElementText -Element $target.element
    [ordered]@{
        text = $text
        element = ConvertTo-PotatoElementInfo -Element $target.element
    }
}

function New-PotatoScreenshot {
    [CmdletBinding()]
    param(
        [int] $X = 0,
        [int] $Y = 0,
        [int] $Width = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width,
        [int] $Height = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height,
        [string] $OutFile,
        [ValidateSet('PNG', 'JPEG', 'BMP', 'GIF', 'TIFF')]
        [string] $EncoderType = 'PNG',
        [int] $Quality = 80
    )

    $bitmap = New-Object System.Drawing.Bitmap($Width, $Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $methodName = 'Copy' + 'FromScreen'
    $copyMethod = $graphics.GetType().GetMethod($methodName, [type[]]@([int], [int], [int], [int], [System.Drawing.Size]))
    [void]$copyMethod.Invoke($graphics, @($X, $Y, 0, 0, $bitmap.Size))
    $encoderTypeLower = $EncoderType.ToLower()
    $mime = "image/$encoderTypeLower"
    if ($encoderType -eq 'JPEG') { $mime = 'image/jpeg' }
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq $mime } | Select-Object -First 1
    if (-not $codec) { $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.FormatDescription -eq $EncoderType } | Select-Object -First 1 }
    $encoder = [System.Drawing.Imaging.Encoder]::Quality
    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($encoder, [int64]$Quality)
    $bitmap.Save($OutFile, $codec, $encoderParams)
    $graphics.Dispose()
    $bitmap.Dispose()
}

function Invoke-PotatoScreenshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $encoder = Get-PotatoArg -ArgsMap $ArgsMap -Names @('EncoderType', 'Format') -Default 'PNG'
    $quality = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Quality')) 80
    $outFile = Get-PotatoArg -ArgsMap $ArgsMap -Names @('OutFile', 'Path')
    if (-not $outFile) {
        $name = 'screenshot_{0}.{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), ([string]$encoder).ToLower()
        $outFile = Join-Path -Path (Join-Path (Get-PotatoRunPath) 'screenshots') -ChildPath $name
    }

    $region = $null
    $hasExplicitRegion = $ArgsMap.Contains('X') -or $ArgsMap.Contains('Y') -or $ArgsMap.Contains('Width') -or $ArgsMap.Contains('Height')
    if ($hasExplicitRegion) {
        $region = [ordered]@{
            x = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('X')) 0
            y = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Y')) 0
            width = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Width')) [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
            height = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Height')) [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
        }
    }
    else {
        $inputs = Get-PotatoSelectorInputs -ArgsMap $ArgsMap
        $hasSelector = $inputs.path -or $inputs.selector.Name -or $inputs.selector.AutomationId -or $inputs.selector.ClassName -or $inputs.selector.ControlType
        if ($hasSelector) {
            $target = Resolve-PotatoCommandTarget -ArgsMap $ArgsMap -AllowPathAsTarget
            if (-not $target.ok) { throw $target.error }
            $region = ConvertTo-PotatoRectangle -Rectangle $target.element.Current.BoundingRectangle
        }
        else {
            $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $region = [ordered]@{ x = $screen.X; y = $screen.Y; width = $screen.Width; height = $screen.Height }
        }
    }

    New-PotatoScreenshot -X $region.x -Y $region.y -Width $region.width -Height $region.height -OutFile $outFile -EncoderType $encoder -Quality $quality
    [ordered]@{ path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($outFile); region = $region; format = $encoder }
}

function Invoke-PotatoCloseWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $selector = New-PotatoSelectorFromArguments -ArgsMap $ArgsMap
    $selector.Recurse = $false
    $timeoutMs = ConvertTo-PotatoInt (Get-PotatoArg -ArgsMap $ArgsMap -Names @('TimeoutMs')) 0
    $windows = @(Get-PotatoTopLevelWindows -Selector $selector -TimeoutMs $timeoutMs)
    if ($windows.Count -eq 0) {
        $working = Get-PotatoWorkingElement
        if ($working) { $windows = @($working) }
    }

    $closed = 0
    $matchedHandles = @()
    $matchedProcessIds = @()
    foreach ($window in $windows) {
        $matchedHandles += [int64]$window.Current.NativeWindowHandle
        $matchedProcessIds += [int]$window.Current.ProcessId
        try {
            $pattern = $window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
            $pattern.Close()
            $closed++
        }
        catch {
            try {
                $process = Get-Process -Id $window.Current.ProcessId -ErrorAction Stop
                if ($process.CloseMainWindow()) { $closed++ }
            }
            catch {}
        }
    }

    if ($script:CurrentState.working) {
        $workingHandle = [int64]$script:CurrentState.working.nativeWindowHandle
        $workingProcessId = [int]$script:CurrentState.working.processId
        if (($matchedHandles -contains $workingHandle) -or ($matchedProcessIds -contains $workingProcessId)) {
            $script:CurrentState.working = $null
            Save-PotatoState -State $script:CurrentState
        }
    }

    [ordered]@{ closed = $closed; matched = $windows.Count }
}

function Invoke-PotatoReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    $step = Get-PotatoArg -ArgsMap $ArgsMap -Names @('Step', 'StepNr')
    $status = Get-PotatoArg -ArgsMap $ArgsMap -Names @('Status')
    $description = Get-PotatoArg -ArgsMap $ArgsMap -Names @('Description', 'Message') -Default ''
    if (-not $step) { throw 'report requires -Step.' }
    if (-not $status) { throw 'report requires -Status.' }

    $takeScreenshot = ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Screenshot', 'TakeScreenshot')) $false
    $screenshot = $null
    if ($takeScreenshot) {
        $screenshot = Invoke-PotatoScreenshot -ArgsMap ([ordered]@{})
    }

    $event = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        step = [string]$step
        status = ([string]$status).ToUpperInvariant()
        description = [string]$description
        screenshot = $screenshot
    }
    $reportPath = Join-Path -Path (Get-PotatoRunPath) -ChildPath 'reports.jsonl'
    $event | ConvertTo-Json -Depth 20 -Compress | Add-Content -LiteralPath $reportPath -Encoding UTF8
    $script:CurrentState.lastReport = $event
    Save-PotatoState -State $script:CurrentState

    [ordered]@{ event = $event; reportPath = $reportPath }
}

function Invoke-PotatoStateCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ArgsMap
    )

    if (ConvertTo-PotatoBool (Get-PotatoArg -ArgsMap $ArgsMap -Names @('Clear')) $false) {
        if (Test-Path -LiteralPath $script:StatePath) {
            Remove-Item -LiteralPath $script:StatePath -Force
        }
        $script:CurrentState = New-PotatoStateObject
        Save-PotatoState -State $script:CurrentState
        Initialize-PotatoRun -State $script:CurrentState | Out-Null
    }
    [ordered]@{
        statePath = $script:StatePath
        runsRoot = $script:RunsRoot
        state = $script:CurrentState
    }
}

function New-PotatoResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Command,

        [bool] $Ok,

        [object] $Data = $null,

        [object] $ErrorObject = $null,

        [int] $DurationMs = 0
    )

    $session = [ordered]@{
        statePath = $script:StatePath
        runId = $script:CurrentState.runId
        working = $script:CurrentState.working
    }

    [ordered]@{
        ok = $Ok
        command = $Command
        session = $session
        data = $Data
        error = $ErrorObject
        durationMs = $DurationMs
        logPath = Get-PotatoLogPath
    }
}

function Invoke-PotatoCliCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Command,

        [string[]] $Arguments = @(),

        [string] $CliRoot = (Split-Path -Parent $PSScriptRoot)
    )

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $normalized = $Command.ToLowerInvariant()
    $argsMap = ConvertTo-PotatoArgumentMap -Arguments $Arguments
    $result = $null
    $ok = $true
    $errorObject = $null

    try {
        Initialize-PotatoEnvironment -CliRoot $CliRoot
        Write-PotatoLog -Command $normalized -Message "Command started."
        switch ($normalized) {
            'start' { $result = Invoke-PotatoStart -ArgsMap $argsMap }
            'focus' { $result = Invoke-PotatoFocus -ArgsMap $argsMap }
            'windows' { $result = Invoke-PotatoWindows -ArgsMap $argsMap }
            'observe' { $result = Invoke-PotatoObserve -ArgsMap $argsMap }
            'select' { $result = Invoke-PotatoSelect -ArgsMap $argsMap }
            'click' { $result = Invoke-PotatoClick -ArgsMap $argsMap }
            'click-coordinate' { $result = Invoke-PotatoClickCoordinate -ArgsMap $argsMap }
            'type' { $result = Invoke-PotatoType -ArgsMap $argsMap }
            'hotkey' { $result = Invoke-PotatoHotkey -ArgsMap $argsMap }
            'drag' { $result = Invoke-PotatoDrag -ArgsMap $argsMap }
            'hover' { $result = Invoke-PotatoHover -ArgsMap $argsMap }
            'wait-element' { $result = Invoke-PotatoWaitElement -ArgsMap $argsMap }
            'wait-file' { $result = Invoke-PotatoWaitFile -ArgsMap $argsMap }
            'read' { $result = Invoke-PotatoRead -ArgsMap $argsMap }
            'screenshot' { $result = Invoke-PotatoScreenshot -ArgsMap $argsMap }
            'close-window' { $result = Invoke-PotatoCloseWindow -ArgsMap $argsMap }
            'report' { $result = Invoke-PotatoReport -ArgsMap $argsMap }
            'state' { $result = Invoke-PotatoStateCommand -ArgsMap $argsMap }
            default { throw "Unknown command '$Command'." }
        }
        Write-PotatoLog -Command $normalized -Level Success -Message "Command completed."
    }
    catch {
        $ok = $false
        $errorObject = [ordered]@{
            message = $_.Exception.Message
            type = $_.Exception.GetType().FullName
            category = [string]$_.CategoryInfo.Category
        }
        if (-not $script:CurrentState) {
            try {
                Initialize-PotatoEnvironment -CliRoot $CliRoot
            }
            catch {}
        }
        try { Write-PotatoLog -Command $normalized -Level Error -Message $_.Exception.Message } catch {}
    }
    finally {
        $watch.Stop()
    }

    $response = New-PotatoResult -Command $normalized -Ok $ok -Data $result -ErrorObject $errorObject -DurationMs ([int]$watch.ElapsedMilliseconds)
    $response | ConvertTo-Json -Depth 60 -Compress
}

Export-ModuleMember -Function Invoke-PotatoCliCommand
