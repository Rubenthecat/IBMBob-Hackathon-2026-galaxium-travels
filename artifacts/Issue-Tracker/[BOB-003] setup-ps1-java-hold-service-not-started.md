# Bug Report: `setup.ps1` Java Hold Service Not Started

**Project:** Galaxium Travels — Windows Local Setup (Option 2)

| Field | Value |
|---|---|
| **File** | `setup.ps1` |
| **Status** | ✅ Resolved |
| **Branch** | `Issue-retreiving-Quotes` |
| **Affected Mode** | Option 2 — Local; Option 1 — Docker (stale hint) |
| **Platform** | Windows 10/11, PowerShell 5.1 |
| **Bugs Fixed** | 2 |

---

## Summary

Running `.\setup.ps1` with option **2 (Local)** never started the Java Hold Service, despite installing Java 21 and Maven as prerequisites. The hold service is required — it handles the quote and hold lifecycle that the frontend depends on. The omission was silent: the backend and frontend started normally, but any operation involving quotes or holds would fail at runtime. A secondary stale comment in Docker mode incorrectly instructed users to pass `--profile hold-service`, when the service is already unconditionally defined in `docker-compose.yml`.

---

## Observed Symptoms

- ✗ **Java Hold Service never started in local mode** — Port 8080 was never bound. Any frontend action that creates or confirms a hold received a proxy error from the Python backend.
- ✗ **No error or warning printed** — The script completed and printed `Galaxium Travels is running!` with no mention of the hold service, giving no indication that a required component was missing.
- ✗ **Docker mode hint was wrong** — The script printed `To also start the Java Hold Service, run: docker compose --profile hold-service up --build`, which is incorrect — the service needs no profile flag.

---

## Root Causes

### Bug #1 — Java Hold Service startup block missing from local mode `[Critical]`

**Location:** `setup.ps1` — local mode section, between backend health check and frontend startup

**Cause:** The script correctly installed Java 21 and Maven as prerequisites (lines 139–140), but contained no `Start-Process` call to actually launch `mvn spring-boot:run`. The bash equivalent [`start_locally.sh`](scripts/local/start_locally.sh:119) had the full startup block: it resolves Maven, sets `PYTHON_BACKEND_URL`, launches the service, and health-checks port 8080 before continuing. None of this existed in the PowerShell version.

**Fix:** Added a complete startup block between the backend `Write-Green` line and the frontend section:
- Resolves `mvn.cmd` (or `mvn`) from PATH using PowerShell 5.1-compatible logic (no `?.` null-conditional)
- Sets `$env:PYTHON_BACKEND_URL = "http://localhost:8001"` so the hold service can reach the Python backend
- Launches `mvn -q spring-boot:run` via `Start-Process -PassThru` to hold the real PID in `$javaProc`
- Health-checks `http://localhost:8080/api/v1/health` with up to 60 s of wait time (30 × 2 s) — Maven startup is significantly slower than Python or Node
- On failure: kills the backend and exits with code 1
- `$javaProc` is monitored in the keep-alive loop, stopped in `finally`, and its logs are deleted on clean Ctrl+C exit

---

### Bug #2 — Stale `--profile hold-service` hint in Docker mode `[Minor]`

**Location:** `setup.ps1` lines 76–77

**Cause:** A legacy comment told users to run `docker compose --profile hold-service up --build` to include the Java Hold Service. In an earlier version of the project, the service was behind a Docker Compose profile. It has since been moved to an unconditional service definition in [`docker-compose.yml`](docker-compose.yml:37) with no `profiles:` key, meaning it already runs with the default `docker compose up --build`. The stale hint caused confusion and implied the service was optional.

**Fix:** Removed the two `Write-Host` lines containing the incorrect hint. Docker mode now runs `docker compose up --build` without any additional instruction needed.

---

## Remediation Steps (in order applied)

1. **Added Java Hold Service startup block** — `Start-Process` for `mvn.cmd spring-boot:run`, with `$env:PYTHON_BACKEND_URL`, log redirection, and `$javaProc` PID capture.
2. **Added 60 s health-check loop** (30 × 2 s) against `http://localhost:8080/api/v1/health`, matching the pattern used for the backend.
3. **Added `$javaProc` to keep-alive loop** — crash detection now covers all three services.
4. **Added `$javaProc` to all `exit 1` error paths** — node-not-found and vite-not-found paths now also kill the hold service before exiting.
5. **Added `$javaProc` to `finally` block** — the hold service is stopped on both clean Ctrl+C and unexpected crash exits.
6. **Added `$javaLog` / `$javaErrLog` cleanup** — log files are deleted on clean Ctrl+C, preserved on crash.
7. **Removed stale Docker-mode hint** — deleted the two `Write-Host` lines referencing `--profile hold-service`.
8. **Used PowerShell 5.1-compatible `Get-Command` fallback** — replaced `?.Source` null-conditional (PS7+ only) with explicit `if` checks, so the script runs on the default Windows PowerShell.

---

## Roadblocks Encountered

> ⚠️ **`?.` null-conditional operator not available in PowerShell 5.1** — The initial implementation used `(Get-Command mvn.cmd -ErrorAction SilentlyContinue)?.Source`, which is PS7+ syntax. The script targets Windows PowerShell 5.1 (the default shell on Windows). A parse error was caught during syntax validation and replaced with explicit `if` guards.

---

## How It Was Tested

- ✓ **PowerShell syntax validation** — Ran `powershell -NoProfile -File setup.ps1` in a piped session to catch parse errors before live execution. Caught and fixed the `?.Source` PS7 syntax issue.
- ✓ **Full end-to-end script run** — Ran `.\setup.ps1` (Option 2). All three services started in sequence and reported healthy:
  ```
  [OK]  Backend started on http://localhost:8001
  [OK]  Java Hold Service started on http://localhost:8080
  [OK]  Frontend started on http://localhost:5173
  ```
- ✓ **Summary block verified** — Terminal output confirmed all three URLs printed in the final summary, including `Hold Service: http://localhost:8080`.

---

## Change Summary

| Location | Change | Bug Fixed |
|---|---|---|
| Lines 76–77 | Removed stale `--profile hold-service` hint | #2 |
| Lines 217–258 | Added full Java Hold Service startup block | #1 |
| Lines 283–292 | Added `$javaProc` kill to node/vite error paths | #1 |
| Lines 346–348 | Added `$javaProc.HasExited` check to keep-alive loop | #1 |
| Lines 360 | Added `Stop-Process $javaProc` to `finally` block | #1 |
| Lines 367–368 | Added `$javaLog`/`$javaErrLog` cleanup on clean exit | #1 |

---

## Final State

✅ **All three services operational** — Backend on `http://localhost:8001`, Java Hold Service on `http://localhost:8080`, frontend on `http://localhost:5173`. The hold service now starts unconditionally in local mode, matching the behaviour of `start_locally.sh` and the Docker Compose stack. No application source files were modified — both fixes are confined to `setup.ps1`.

---

*Made with IBM Bob*
