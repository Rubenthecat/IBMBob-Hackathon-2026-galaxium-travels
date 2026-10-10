# Fix: Java Hold Service Missing from setup.ps1

## Overview

`setup.ps1` installs Java 21 and Maven as prerequisites in local mode, but never actually starts the Java Hold Service. The service is required — it handles the quote/hold lifecycle that the frontend depends on. The bash equivalent (`start_locally.sh`) correctly launches the service, health-checks it on port 8080, and monitors its PID in the keep-alive loop.

A secondary stale comment in Docker mode incorrectly tells the user to use `--profile hold-service`; the `java-service` is already defined unconditionally in `docker-compose.yml` and runs with the default `docker compose up --build`.

**Scope:** `setup.ps1` only. No changes to `start_locally.sh`, `docker-compose.yml`, or any backend/frontend code.

---

## Sub-Tasks

### 1. Start the Java Hold Service in local mode

**Intent:** Add a startup block for `mvn spring-boot:run` in the `booking_system_inventory_hold_service` directory, mirroring what `start_locally.sh` does, so the hold service always runs in local mode.

**Expected Outcomes:**
- After the backend health check passes and before the frontend starts, `mvn spring-boot:run` is launched as a background `Start-Process`.
- The script health-checks `http://localhost:8080/api/v1/health` (up to 30 attempts, 2 s apart — Maven startup is slow).
- If the hold service fails to start, the script prints an error, kills the backend, and exits with code 1.
- `$javaProc` is held for the keep-alive poll loop.
- The keep-alive loop monitors `$javaProc.HasExited` alongside backend and frontend.
- The `finally` block stops `$javaProc` on exit.
- On clean Ctrl+C exit, `java.log` and `java.log.err` are deleted alongside the other log files.
- The summary block prints `Hold Service: http://localhost:8080`.

**Todo List:**
1. After the `Write-Green "Backend started"` line, add a `# ── Start Java Hold Service ──` section.
2. Set `$javaDir`, `$javaLog`, `$javaErrLog` paths.
3. Use `Start-Process` to run `mvn.cmd spring-boot:run` with `PYTHON_BACKEND_URL=http://localhost:8001` in the environment, redirecting stdout/stderr to the log files, `-PassThru` to capture `$javaProc`.
4. Add a 30-attempt / 2 s health-check loop against `http://localhost:8080/api/v1/health`; on failure, stop backend and exit 1.
5. Add `Write-Green "Hold Service started on http://localhost:8080"`.
6. Update the keep-alive `while` loop to also check `$javaProc.HasExited`.
7. Update the `finally` block to `Stop-Process $javaProc`.
8. Update the `if ($cleanExit)` block to delete `$javaLog` and `$javaErrLog`.
9. Update the summary `Write-Host` block to include the Hold Service URL.

**Relevant Context:**
- [`setup.ps1` lines 195–219](setup.ps1:195) — existing backend Start-Process + health-check pattern to follow exactly.
- [`setup.ps1` lines 299–325](setup.ps1:299) — keep-alive loop and finally block that need updating.
- [`start_locally.sh` lines 119–177](scripts/local/start_locally.sh:119) — bash equivalent, including PYTHON_BACKEND_URL env var and 8 s startup wait.
- `mvn` on Windows resolves as `mvn.cmd`; `Start-Process` needs the `.cmd` extension or a `cmd.exe /c mvn` wrapper.

**Status:** `[ ] pending`

---

### 2. Remove stale Docker-mode hint about `--profile hold-service`

**Intent:** The comment on lines 76–77 of `setup.ps1` tells users to run `docker compose --profile hold-service up --build` to get the Java Hold Service. This is wrong — `java-service` has no `profiles:` constraint in `docker-compose.yml` and already runs with the default `docker compose up --build`. Remove the misleading hint.

**Expected Outcomes:**
- Lines 76–77 (`Write-Host "To also start the Java Hold Service..."`) are deleted.
- The Docker mode summary still shows the hold service is included implicitly.
- No other Docker mode logic changes.

**Relevant Context:**
- [`setup.ps1` lines 76–77](setup.ps1:76) — the stale hint to remove.
- [`docker-compose.yml` lines 37–53](docker-compose.yml:37) — confirms `java-service` has no `profiles:` key.

**Status:** `[ ] pending`
