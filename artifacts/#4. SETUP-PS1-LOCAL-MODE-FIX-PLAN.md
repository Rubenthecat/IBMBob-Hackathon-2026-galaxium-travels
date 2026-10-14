# Plan: Fix setup.ps1 Local Mode — Backend Shutdown & Frontend Startup

## Top-Level Overview

**Goal:** Fix two compounding bugs in `setup.ps1` Option 2 (Local mode) that cause the backend to be force-killed ~60 seconds after startup, and prevent the frontend from ever starting properly.

**Scope:** Changes are confined to `setup.ps1`. No backend or frontend source code changes are needed — all dependencies are correctly installed and compatible.

**Approach:** Fix the `Wait-Process` race condition that kills the backend, and fix the Windows-specific `npm` process invocation so the frontend Vite dev server starts correctly and its real PID is tracked.

---

## Root Cause Analysis

### Bug 1 — Backend Force-Killed After ~60 Seconds

**File:** [`setup.ps1` lines 229–255](setup.ps1)

`Start-Process -FilePath "npm" -ArgumentList "run", "dev"` on Windows spawns a **wrapper process** (`npm.cmd` via `cmd.exe`). The returned `$frontendProc` object holds the PID of that short-lived wrapper, which exits within seconds after handing off to the Node/Vite child. On line 250:

```powershell
Wait-Process -Id $backendProc.Id, $frontendProc.Id
```

`Wait-Process` unblocks as soon as **either** process exits. The npm wrapper exits almost immediately, so `Wait-Process` returns, the `finally` block runs, and `Stop-Process -Id $backendProc.Id -Force` kills the healthy backend. The `backend.log.err` shows no errors because the backend was functioning correctly — it was murdered by the cleanup logic.

### Bug 2 — Frontend Never Starts

**File:** [`setup.ps1` lines 229–233](setup.ps1)

Two separate sub-issues:

1. **`-FilePath "npm"` fails on Windows.** Windows `npm` is a `.cmd` script, not an executable. `Start-Process` cannot resolve `npm` to `npm.cmd` without routing through `cmd.exe`. The correct invocation is either `-FilePath "cmd.exe" -ArgumentList "/c npm run dev"` or using the full path to `npm.cmd`.

2. **No output redirection.** With `-NoNewWindow` and no `-RedirectStandard*`, Vite's stdout/stderr is inherited by the parent PowerShell process but the process object is unreliable for tracking. Redirecting to log files is cleaner and prevents silent failures.

### Bug 3 — Wait Strategy Is Fragile

Using `Wait-Process` with multiple IDs is not suitable here because the intent is to keep the script alive until **Ctrl+C** is pressed, not until any child exits. The correct Windows pattern for this scenario is a polling loop that checks `HasExited` on both processes and responds to Ctrl+C via a `try/finally` around a `while` loop.

---

## Sub-Tasks

---

### Sub-Task 1 — Fix the npm invocation to properly start Vite on Windows

**Status:** `[x] done`

**Intent:**  
On Windows, `Start-Process -FilePath "npm"` cannot resolve the `.cmd` extension automatically. We need to route through `cmd.exe` (which handles `.cmd` files natively) or resolve the full path to `npm.cmd`. This ensures the Vite dev server actually launches.

**Expected Outcomes:**
- `npm run dev` reliably launches when run from `Start-Process` on Windows.
- The Vite dev server binds to port 5173.
- stdout/stderr from Vite are redirected to log files (same pattern as the backend) so output is captured and not lost.

**Todo List:**
1. Replace the `Start-Process -FilePath "npm"` call with `Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "npm", "run", "dev"` (or resolve via `(Get-Command npm).Source` which returns the `.cmd` path).
2. Add `-RedirectStandardOutput` and `-RedirectStandardError` pointing to `$ScriptDir\booking_system_frontend\frontend.log` and `frontend.log.err` respectively, matching the backend log pattern.
3. Add a working directory argument `-WorkingDirectory (Join-Path $ScriptDir "booking_system_frontend")` to ensure Vite finds `vite.config.ts`.
4. Update the `finally` cleanup block to also remove the frontend log files.

**Relevant Context:**
- [`setup.ps1` lines 229–233](setup.ps1:229) — current broken frontend start
- [`setup.ps1` lines 190–197](setup.ps1:190) — backend start pattern to mirror
- [`setup.ps1` lines 251–256](setup.ps1:251) — cleanup block that needs updating

---

### Sub-Task 2 — Fix the Wait-Process race condition that kills the backend

**Status:** `[x] done`

**Intent:**  
Replace `Wait-Process -Id $backendProc.Id, $frontendProc.Id` with a polling loop that keeps the script alive until both processes have genuinely exited **or** until the user presses Ctrl+C. This prevents the npm wrapper process exit from accidentally unblocking the wait and triggering the cleanup that kills the backend.

**Expected Outcomes:**
- Script stays alive and responsive while both backend and frontend are running.
- If either process crashes on its own, the script detects it, reports which one died, and shuts down the other cleanly.
- Ctrl+C still triggers cleanup of both child processes.

**Todo List:**
1. Remove the `Wait-Process -Id $backendProc.Id, $frontendProc.Id` line.
2. Replace with a `while` loop that polls `$backendProc.HasExited` and `$frontendProc.HasExited` with `Start-Sleep -Seconds 2` between iterations.
3. Inside the loop, if `$backendProc.HasExited` is true, print an error message and break (the `finally` will clean up the frontend).
4. If `$frontendProc.HasExited` is true, print an error message and break (the `finally` will clean up the backend).
5. Wrap the loop in `try { } catch [System.Management.Automation.PipelineStoppedException] { }` so that Ctrl+C is handled gracefully — it raises `PipelineStoppedException` in PowerShell, which the `finally` block will then execute.

**Relevant Context:**
- [`setup.ps1` lines 249–256](setup.ps1:249) — the current `Wait-Process` + `finally` block
- The `finally` block itself is correct and should remain; only the `Wait-Process` line needs replacing.

---

### Sub-Task 3 — Add a health check for the frontend before declaring success

**Status:** `[x] done`

**Intent:**  
The current script assumes the frontend is ready after a fixed 3-second sleep (`Start-Sleep -Seconds 3`), which is unreliable. Vite can take longer on first cold-start (TypeScript compilation, plugin init). Add a short health-check polling loop similar to the one used for the backend, so the script only reports "Frontend started" when Vite is actually serving on port 5173.

**Expected Outcomes:**
- Script waits up to 30 seconds for Vite to bind port 5173.
- If Vite fails to start in time, the script reports the error, stops the backend cleanly, and exits with a non-zero code.
- If Vite starts successfully, the script reports the URL as it already does.

**Todo List:**
1. Remove the `Start-Sleep -Seconds 3` line after starting the frontend.
2. Add a polling loop (modelled on the existing backend health check, lines 201–211) that tries `http://localhost:5173` up to 15 times with 2-second intervals.
3. If `$frontendReady` is false after the loop, print an error referencing the frontend log file, stop both processes, and `exit 1`.
4. Update the success message to only print after the loop confirms readiness.

**Relevant Context:**
- [`setup.ps1` lines 201–218](setup.ps1:201) — backend health check pattern to replicate
- [`setup.ps1` lines 232–233](setup.ps1:232) — the `Start-Sleep` line to replace

---

## Summary of Changes

All three sub-tasks touch only `setup.ps1`. The changes are surgical:

| Location | Change |
|----------|--------|
| Lines 229–230 | Fix `npm` invocation via `cmd.exe`; add log redirection |
| Line 232 | Replace fixed sleep with Vite health-check loop |
| Line 250 | Replace `Wait-Process` with polling `while` loop |
| Lines 254–255 | Add frontend log file cleanup |

No backend or frontend source files require any modification.
