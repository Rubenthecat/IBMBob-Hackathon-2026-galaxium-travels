# Bug Report: `setup.ps1` Local Mode Failures

**Project:** Galaxium Travels — Windows Local Setup (Option 2)

| Field | Value |
|---|---|
| **File** | `setup.ps1` |
| **Status** | ✅ Resolved |
| **Branch** | `Windows-Setup-Fixes` |
| **Affected Mode** | Option 2 — Local |
| **Platform** | Windows 10/11, PowerShell 5.1 |
| **Bugs Fixed** | 4 |

---

## Summary

Running `.\setup.ps1` with option **2 (Local)** on Windows resulted in two user-visible symptoms: the backend server would shut down approximately 60 seconds after a successful start, and the frontend (Vite/React) never launched. The `backend.log.err` file showed no errors, making the failure appear silent. Investigation revealed four compounding bugs, all confined to `setup.ps1`. No backend or frontend application code was involved.

---

## Observed Symptoms

- ✗ **Backend shuts down ~60 seconds after a healthy start** — Terminal displays an error. `backend.log.err` shows normal startup lines only — no application error.
- ✗ **Frontend never starts** — No Vite output. `frontend.log.err` was never created.
- ✗ **Health check hangs indefinitely** — On later runs, `Waiting for backend to start...` appeared and the script never progressed — requiring a manual kill after 5+ minutes.

---

## Root Causes

### Bug #1 — `Wait-Process` race condition kills the backend `[Critical]`

**Location:** `setup.ps1` — `Wait-Process -Id $backendProc.Id, $frontendProc.Id`

**Cause:** `Wait-Process` with multiple IDs unblocks as soon as *any* of the listed processes exits. `$frontendProc` held the PID of a short-lived `npm.cmd` / `cmd.exe` launcher wrapper, which exits within seconds of handing off to Node.js. When that wrapper exited, `Wait-Process` returned, the `finally` block ran, and `Stop-Process -Force` killed the healthy backend.

**Fix:** Replaced `Wait-Process` with a `while ($true)` polling loop that checks `$proc.HasExited` every 2 seconds, with `catch [PipelineStoppedException]` to handle Ctrl+C gracefully.

---

### Bug #2 — `npm.cmd` wrapper PID — frontend process not tracked `[Critical]`

**Location:** `setup.ps1` — `Start-Process -FilePath "npm" -ArgumentList "run", "dev"`

**Cause:** On Windows, `npm` resolves to `npm.cmd`, a batch script. `Start-Process` cannot invoke `.cmd` files directly without routing through `cmd.exe`. Even when routed through `cmd.exe`, the returned PID is the short-lived launcher, not the long-running Vite/Node.js process. This made `$frontendProc.HasExited` become `true` within seconds, immediately triggering the crash-detection logic and killing the backend.

**Fix:** Replaced all launcher wrappers by invoking `node.exe` directly with the Vite entry point: `node_modules\vite\bin\vite.js`. This was discovered by reading the contents of `node_modules\.bin\vite.cmd`, which reveals the real underlying command. `Start-Process` then holds the actual long-running Node PID.

---

### Bug #3 — Spaces in workspace path break Node.js argument parsing `[Critical]`

**Location:** `setup.ps1` — `Start-Process -FilePath $nodeExe -ArgumentList $viteScript`

**Cause:** The workspace path `E:\Coding\IBM Bob Hackathon 2026\...` contains spaces. When `$viteScript` was passed to `-ArgumentList` without quoting, PowerShell word-split the path on the first space. Node.js received `E:\Coding\IBM` as the module path and immediately exited with `Error: Cannot find module 'E:\Coding\IBM'`. Because the process exited before writing anything, `frontend.log.err` was never created and the failure was invisible.

**Diagnostic output:**
```
Error: Cannot find module 'E:\Coding\IBM'
    at Module._resolveFilename (node:internal/modules/cjs/loader:1517:15)
    ...
Node.js v24.19.0
```

**Fix:** Wrapped the script path in escaped quotes: `-ArgumentList "`"$viteScript`""` so Node receives it as a single argument regardless of spaces in the path.

---

### Bug #4 — `Invoke-WebRequest` deadlocks with redirected child pipes `[Critical]`

**Location:** `setup.ps1` — both backend and frontend health-check loops using `Invoke-WebRequest`

**Cause:** In Windows PowerShell 5.1, `Invoke-WebRequest` deadlocks when run in the same process as a child whose stdout/stderr pipes are being redirected via `-RedirectStandardOutput/-Error`. The pipe buffer fills as Uvicorn writes startup logs; PowerShell's HTTP client is never scheduled because the thread is blocked trying to drain the pipe. The health-check loop hung permanently — the script never printed `[ERR]` or `[OK]`, it just stopped responding. This required a forced terminal kill after 5+ minutes.

**Fix:** Replaced both `Invoke-WebRequest` health checks with `curl.exe`, which ships with Windows 10+ and runs as a fully separate process with no shared pipe handles:

```diff
- $resp = Invoke-WebRequest -Uri "http://localhost:8001/" -UseBasicParsing -TimeoutSec 2
+ $code = curl.exe -s -o NUL -w "%{http_code}" --max-time 2 "http://localhost:8001/" 2>$null
+ if ($code -match '^\d+$' -and [int]$code -lt 500) { $backendReady = $true; break }
```

---

## Remediation Steps (in order applied)

1. **Replaced `Start-Process -FilePath "npm"` with `cmd.exe /c npm run dev`** and added stdout/stderr log redirection for the frontend, matching the backend log pattern.
2. **Replaced `Wait-Process` with a polling `while` loop** checking `$proc.HasExited` every 2 seconds. Added `catch [PipelineStoppedException]` for clean Ctrl+C handling. Log files are now only deleted on a clean exit — on crashes they are preserved for inspection.
3. **Replaced the fixed 3-second `Start-Sleep`** for the frontend with a 15×2s health-check loop (matching the backend pattern), so the script only declares success when Vite is actually serving.
4. **Replaced `cmd.exe /c npm run dev` with direct `node.exe` invocation** using `node_modules\vite\bin\vite.js`, discovered by inspecting `node_modules\.bin\vite.cmd`. This gives `Start-Process` the real long-running PID.
5. **Added escaped quotes around the Vite script path** (`` "`"$viteScript`"" ``) to handle workspace paths containing spaces.
6. **Replaced both `Invoke-WebRequest` health checks with `curl.exe`** to eliminate the pipe-deadlock hang in PowerShell 5.1.

---

## Roadblocks Encountered

> ⚠️ **Log files cleaned up before inspection** — The original `finally` block deleted all log files unconditionally — even on crash. This meant `frontend.log.err` never survived to be read. Fixed by only deleting logs when `$cleanExit = $true` (Ctrl+C path).

> ⚠️ **Each fix exposed the next hidden bug** — Fixing the `Wait-Process` race caused the npm wrapper PID issue to become visible. Fixing the npm wrapper exposed the spaces-in-path crash. Fixing that exposed the `Invoke-WebRequest` deadlock. Each bug had been masking the next.

> ⚠️ **`backend.log.err` showed a clean start — misleading diagnosis** — Because log files persisted from prior successful runs and were not overwritten, the log appeared to show a healthy backend. Multiple runs had to be compared by counting `GET /` hits before confirming the backend was healthy when it was being killed.

> ⚠️ **`Invoke-WebRequest` deadlock required forced terminal kill** — The deadlock produced no output and no timeout — the PowerShell window became completely unresponsive. The test command had to be cancelled manually after 5+ minutes. This made it the hardest bug to confirm, as the symptom (script hangs silently) was identical to a slow startup.

> ⚠️ **Spaces-in-path failure produced no log evidence** — Node.js exited before writing a single byte to `frontend.log.err`, so the log file was never created. The bug was only found by running the `Start-Process` call in isolation in a diagnostic terminal and reading the stderr output directly.

---

## How It Was Tested

- ✓ **Isolated Start-Process + node.exe diagnostic** — Ran the exact `Start-Process` invocation in a standalone PowerShell session. First run (no quotes) produced `Error: Cannot find module 'E:\Coding\IBM'` in stderr. Second run (with escaped quotes) produced `VITE v7.3.6 ready in 779 ms — Local: http://localhost:5173/` with `HasExited: False` after 6 seconds.
- ✓ **curl.exe health check against live backend** — Started backend via `Start-Process`, then ran the exact health-check loop from the updated script. Poll 1 returned `http_code=200` — `[OK] Backend health check passed` — with no hang and no deadlock. Completed in under 2 seconds.
- ✓ **Full end-to-end script run** — Ran `.\setup.ps1` (Option 2). Backend and frontend both started. `backend.log` recorded real application traffic: `GET /flights`, `POST /register`, `POST /quotes` — confirming the full stack is operational.
- ✓ **Confirmed IWR deadlock vs curl.exe isolation** — Ran `Invoke-WebRequest` against a live backend in a session with `$ErrorActionPreference = "Stop"` and redirected child pipes active — confirmed it hung indefinitely. Replaced with `curl.exe` in same conditions — returned immediately with the correct status code.
- ✓ **Dependency audit** — Verified all 12 packages in `requirements.txt` against installed `.venv` packages. All versions matched exactly. No application-level changes were needed.

---

## Change Summary

| Lines | Change | Bug Fixed |
|---|---|---|
| ~229–231 | npm install routed via `cmd.exe /c` | #2 |
| ~234–255 | Frontend launched as `node.exe vite.js` with quoted path | #2, #3 |
| ~199–217 | Backend health check replaced with `curl.exe` | #4 |
| ~259–278 | Frontend health check replaced with `curl.exe`; replaces fixed sleep | #4 |
| ~292–326 | `Wait-Process` replaced with `HasExited` polling loop | #1 |
| ~315–325 | Logs only deleted on clean Ctrl+C exit (`$cleanExit` flag) | Diagnostic |

---

## Final State

✅ **All services operational** — `backend.log` from the latest run confirms full stack activity: `GET /flights 200`, `POST /register 200`, `POST /quotes 200`. Backend running on `http://localhost:8001`, frontend on `http://localhost:5173`. No application source files were modified — all four fixes are confined to `setup.ps1`.

---

*Made with IBM Bob*
