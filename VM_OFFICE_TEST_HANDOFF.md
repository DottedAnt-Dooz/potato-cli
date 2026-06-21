# VM Codex Handoff: PoTATo CLI Office Smoke Testing

Use this handoff in the Codex session running inside the prepared Windows 11 VM.

## Copy-Paste Prompt for VM Codex

You are testing `C:\diplomamunka\potato_cli`, a standalone PowerShell CLI for Windows UI automation. The goal is to validate it against real installed Microsoft Office desktop apps in this VM.

Do not start by refactoring. First run real UI smoke checks against the CLI. Only patch source if you find a concrete CLI bug. Keep all test artifacts under `C:\diplomamunka\potato_cli\runs` or another temporary path inside `potato_cli`.

The CLI entrypoint is:

```powershell
C:\diplomamunka\potato_cli\potato.ps1
```

Every command should return exactly one JSON object to stdout. Capture failures with the command used, the JSON output, the relevant log path, and a screenshot when useful.

## Preflight

Run Codex in the logged-in interactive desktop session, not only through a background SSH service. UI Automation, focus, mouse, and SendKeys need access to the active user desktop.

Before testing:

```powershell
cd C:\diplomamunka\potato_cli
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 state -Clear
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 windows
```

Confirm:

- Office apps are installed and activated.
- Office first-run, privacy, sign-in, update, and template dialogs are already dismissed or handled explicitly.
- Display scaling is 100% and resolution is fixed.
- Sleep/lock screen is disabled during the run.
- The VM checkpoint is available for reset after testing.

## General CLI Usage

Start an app and persist the working window:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 start -ProcessName winword -WaitForWindowMs 30000
```

Inspect the current UI:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 observe -Depth 2 -MaxElements 250
```

Take a screenshot:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 screenshot
```

Click by selector:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 click -Name "OK" -ControlType Button -FindFirst
```

Type or send hotkeys:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 type -Text "PoTATo Office smoke" -Focus
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 hotkey -Keys "^s" -Focus
```

Record a local report event:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 report -Step 1 -Status PASS -Description "Word opened and accepted text input"
```

Close the target:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 close-window -ProcessName winword
```

## Preferred Office Smoke Scenarios

Use hotkeys where possible because ribbon labels can vary by language and Office version. Use `observe` to discover selectors when dialogs appear.

### 1. Word

Goal: open Word, create or focus a blank document, type text, save a `.docx`, verify the file exists, close Word.

Suggested flow:

```powershell
$out = "C:\diplomamunka\potato_cli\runs\WordSmoke.docx"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 start -ProcessName winword -WaitForWindowMs 30000
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 hotkey -Keys "^n" -Focus
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 type -Text "PoTATo Word smoke test" -Focus
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 hotkey -Keys "{F12}" -Focus
```

When the Save As dialog appears, use `observe` to identify the filename field and Save button. Then type `$out`, save, and verify:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 wait-file -Path $out -TimeoutMs 10000
```

### 2. Excel

Goal: open Excel, create or focus a blank workbook, enter text/numbers, save `.xlsx`, verify file exists, close Excel.

Suggested flow:

```powershell
$out = "C:\diplomamunka\potato_cli\runs\ExcelSmoke.xlsx"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 start -ProcessName excel -WaitForWindowMs 30000
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 hotkey -Keys "^n" -Focus
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 type -Text "PoTATo Excel smoke{TAB}123" -Focus
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 hotkey -Keys "{F12}" -Focus
```

Use `observe` to handle the Save As dialog, save to `$out`, then run `wait-file`.

### 3. PowerPoint

Goal: open PowerPoint, create a blank presentation, enter title text, save `.pptx`, verify file exists, close PowerPoint.

Suggested flow:

```powershell
$out = "C:\diplomamunka\potato_cli\runs\PowerPointSmoke.pptx"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 start -ProcessName powerpnt -WaitForWindowMs 30000
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 hotkey -Keys "^n" -Focus
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 type -Text "PoTATo PowerPoint smoke" -Focus
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 hotkey -Keys "{F12}" -Focus
```

Use `observe` to handle the Save As dialog, save to `$out`, then run `wait-file`.

### 4. Outlook

Only run Outlook if a profile is configured and the VM can safely send no real mail.

Goal: open Outlook, observe main window, detect and handle any profile/security dialogs, close Outlook. Do not send email unless a disposable test mailbox is configured.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 start -ProcessName outlook -WaitForWindowMs 60000
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 observe -Depth 2 -MaxElements 300
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 screenshot
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\potato.ps1 close-window -ProcessName outlook
```

## What to Validate

For each app, verify:

- `start` finds and persists the working window.
- `observe` returns relevant window and UI tree data without excessive noise.
- `click` works on Office ribbon/dialog controls when a selector is known.
- `type` and `hotkey` work in the active document/workbook/presentation.
- `wait-file` correctly reports saved files.
- `screenshot` writes an image under the active run folder.
- `report` appends local JSONL report events.
- `close-window` closes the target and clears stale working state.
- Failures return JSON with `ok:false` and a useful `error.message`.

## Expected Deliverable Back to Main Session

Report back with:

- Windows version and Office version/channel if easy to obtain.
- Office apps tested.
- For each app: pass/fail, command sequence used, saved output path, and any screenshot/log path.
- Any CLI defects found, with the exact failing JSON output.
- Any source patches made and the verification rerun after each patch.

## Important Constraints

- Keep runtime artifacts under `C:\diplomamunka\potato_cli\runs`.
- Do not copy old PoTATo testcases into `potato_cli`.
- Do not add Selenium, image recognition, browser-specific automation, Jira/report-server integration, VM tooling, or Office-specific hardcoded testcase scripts.
- Use the VM checkpoint to reset after testing if Office state becomes messy.
