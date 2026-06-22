# PoTATo Agent CLI

`potato_cli` is a standalone PowerShell command-line interface for agent-driven Windows UI automation. It is intentionally smaller than the original PoTATo project: it keeps the UI Automation, window, selector, input, screenshot, report, log, and state primitives needed to build repeatable GUI tests for Office and Nucleus-style desktop applications.

It does not import the old `Potato` module and does not include legacy testcases, browser automation, Selenium, image recognition, OCR, Jira integration, VM tooling, or application-specific cleanup helpers.

## Requirements

- Windows with an interactive desktop session.
- Windows PowerShell 5.1 or later.
- The target application must be visible in the logged-in user session.
- Run from a normal or elevated PowerShell session depending on the target application. UI Automation is most reliable when the CLI and target application run at the same integrity level.

## Entry Point

```powershell
cd C:\diplomamunka\potato_cli
.\potato.ps1 <command> [parameters]
```

Example:

```powershell
.\potato.ps1 start -ProcessName winword -Maximize
.\potato.ps1 observe -Depth 2 -MaxElements 120
```

## JSON Contract

Every command writes exactly one compact JSON object to stdout.

```json
{
  "ok": true,
  "command": "observe",
  "session": {
    "statePath": "C:\\diplomamunka\\potato_cli\\.state\\default.json",
    "runId": "...",
    "working": {}
  },
  "data": {},
  "error": null,
  "durationMs": 123,
  "logPath": "C:\\diplomamunka\\potato_cli\\runs\\...\\potato.log"
}
```

Agents and scripts should parse stdout as JSON and treat `ok: false` as a command failure. Human-readable logs are written separately.

## Runtime Files

The CLI creates runtime state and evidence below `potato_cli`:

- `.state\default.json` stores the current run ID and working window context.
- `runs\<runId>\potato.log` stores command logs as JSON lines.
- `runs\<runId>\metrics.jsonl` stores command timing metrics.
- `runs\<runId>\reports.jsonl` stores explicit `report` events.
- `runs\<runId>\screenshots\` stores screenshots.

These paths are runtime output and should not be committed.

## Commands

| Command | Purpose |
| --- | --- |
| `state` | Show current session state. Use `-Clear` to reset it. |
| `start` | Start a process and set its first window as the working window. |
| `focus` | Find and focus an existing top-level window. |
| `windows` | List top-level windows. |
| `observe` | Return working window, foreground element, top-level windows, likely blocking dialogs, and a bounded UI tree. |
| `select` | Find UI elements by selector. |
| `click` | Click or invoke a selected element. |
| `click-coordinate` | Click absolute screen coordinates. Use only as a documented fallback. |
| `type` | Type text into the currently focused control. |
| `hotkey` | Send a Windows Forms SendKeys expression. Prefer GUI actions when possible. |
| `drag` | Drag between two absolute screen coordinates. |
| `hover` | Move the mouse over an element or coordinate. |
| `wait-element` | Wait for an element selector to appear. |
| `wait-file` | Wait for a file to appear or disappear. |
| `read` | Read text/name/value from an element. |
| `screenshot` | Save a full-screen, region, or element screenshot. |
| `close-window` | Close matching top-level windows, or the current working window. |
| `report` | Append a local JSONL report event, optionally with a screenshot. |

## Selectors

Most element commands accept the same selector flags:

```powershell
-Name <text-or-pattern>
-AutomationId <id>
-ClassName <class>
-Class <class>
-ControlType <type>
-ProcessName <process>
-WindowTitle <title>
-Regex
-Recurse <true|false>
-FindFirst
-TimeoutMs <milliseconds>
```

Matching is case-insensitive by default. `-Regex` switches string matching to regular expressions. Without `-Regex`, wildcard characters such as `*` and `?` are accepted through PowerShell wildcard matching.

Examples:

```powershell
.\potato.ps1 select -Name "Blank document" -ControlType Button -FindFirst
.\potato.ps1 click -AutomationId FileTabButton -ControlType Button -TimeoutMs 5000
.\potato.ps1 wait-element -Name "Save As" -ControlType Window -TimeoutMs 10000
```

## Nested Selectors

Use `-PathJson` or `-SelectorJson` when a target is easier to describe as a path through the UI tree. Each path item is resolved under the previous item, so this replaces old in-memory chained element workflows.

```powershell
$path = @(
    @{ Name = "File"; ControlType = "TabItem"; FindFirst = $true; TimeoutMs = 3000 },
    @{ Name = "Save As"; ControlType = "ListItem"; FindFirst = $true; TimeoutMs = 3000 }
) | ConvertTo-Json -Compress

.\potato.ps1 click -PathJson $path
```

`-SelectorJson` may also be a single selector object, a selector path array, or an object containing `path` and `target`.

## Common Workflows

Start Word, inspect the UI, create a blank document, type text, save evidence, and close:

```powershell
.\potato.ps1 state -Clear
.\potato.ps1 start -ProcessName winword -Maximize
.\potato.ps1 observe -Depth 2 -MaxElements 150
.\potato.ps1 click -Name "Blank document" -ControlType Button -TimeoutMs 10000
.\potato.ps1 type -Text "PoTATo smoke test"
.\potato.ps1 screenshot
.\potato.ps1 report -Step 1 -Status PASS -Description "Created and typed into a Word document." -Screenshot
.\potato.ps1 close-window
```

Focus an existing app:

```powershell
.\potato.ps1 focus -ProcessName WINWORD -WindowTitle "*Word*" -Maximize
```

Wait for a saved file:

```powershell
.\potato.ps1 wait-file -Path "C:\Temp\PoTAToSmoke.docx" -TimeoutMs 15000
```

## Agent Guidance

- Prefer selector-based `click`, `select`, `wait-element`, and `read` over coordinates.
- Use `observe` frequently during exploration, but keep `-Depth` and `-MaxElements` bounded to avoid excessive output.
- Avoid `hotkey` unless the UI action is not practically accessible through visible controls. These tests are meant to exercise GUI behavior.
- Use `click-coordinate` only as a fallback. Record a screenshot and explain why selector-based automation was not possible.
- Reset state with `state -Clear` at the start of repeatable test scripts.
- Close applications and delete created test files at the end of generated scripts so the test can run again after a VM checkpoint reset or normal rerun.
- Treat `ok: false` as a real failure and include the command JSON in generated test evidence.

## Troubleshooting

- If `start` succeeds but `windowFound` is false, increase `-WaitForWindowMs` or focus the app later with `focus`.
- If selectors time out in Office, first run `observe -Depth 3 -MaxElements 300` and inspect `name`, `automationId`, `className`, and `controlType`.
- If a click does nothing, try `-Center true` or inspect `supportedPatterns` from `select`/`observe`.
- If UI Automation cannot see elevated windows, run PowerShell with the same elevation level as the target application.
- If output is not valid JSON, the command has been wrapped by something that writes extra stdout. Run `potato.ps1` directly and keep diagnostic output in logs, not stdout.
