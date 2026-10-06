# Setup Scripts Plan — First-Run Bootstrap for Galaxium Travels

## Top-Level Overview

**Goal:** Make the repository runnable immediately after a `git clone` on any platform (macOS, Linux, Windows) with a single script invocation.

**Scope:** Two new scripts at the repo root — `setup.sh` (Unix/macOS/Linux) and `setup.ps1` (Windows PowerShell) — that always ask the user to choose between Docker mode and local mode, install any missing system dependencies automatically, configure environment files, and then launch the application.

**Out of scope:** Changes to existing `start.sh`, `docker-compose.yml`, or any service source code. The new scripts are additive only.

**Approach:**
- Both scripts present the same user-facing experience: a clear mode choice prompt (Docker or Local).
- Docker mode: verify Docker is installed and the daemon is running, then delegate to `docker compose up --build`.
- Local mode: detect and auto-install missing system tools (platform-specific), create `.env` files from `.env.example`, then delegate to `./start.sh`.
- Windows: auto-install via `winget`. macOS: auto-install via `brew`. Linux: auto-install via `apt-get`.

---

## Sub-Task 1 — Create `setup.sh` (Unix/macOS/Linux)

**Intent:** Provide a single entry-point script for macOS and Linux users that eliminates all manual first-run setup steps.

**Expected Outcomes:**
- A file `setup.sh` exists at the repo root, executable (`chmod +x`).
- Running `./setup.sh` after a fresh clone always asks the user: "Run with Docker (recommended) or Local?"
- Docker path: checks Docker is installed and daemon is running; if daemon is not running, prints a clear error with instructions; if all good, runs `docker compose up --build`.
- Local path: checks for each required tool (`python3`, `node`, `java 17/21`, `mvn`, `curl`, `lsof`); for any missing tool, auto-installs via `brew` on macOS or `apt-get` on Linux; creates `booking_system_frontend/.env` from `.env.example` if not already present; then runs `./start.sh`.
- Script prints a clear summary of what it did and what is starting.

**Todo List:**
1. Create `setup.sh` at the repo root with a shebang `#!/usr/bin/env bash`.
2. Add OS detection block: distinguish `darwin` (macOS), `linux`, and `msys`/`cygwin` (Windows — print a message telling the user to run `setup.ps1` instead and exit).
3. Add mode prompt: display "1) Docker (recommended)  2) Local" and read the user's choice.
4. Implement Docker mode block:
   - Check `docker` binary is on `PATH`; if not, print install link and exit.
   - Check `docker info` succeeds (daemon running); if not, print a clear "Start Docker and re-run" message and exit.
   - Run `docker compose up --build`.
5. Implement Local mode block:
   - Define a `require_tool` helper that checks if a tool exists and installs it if missing (brew on macOS, apt-get on Linux).
   - Call `require_tool python3 python3` (brew name / apt package name).
   - Call `require_tool node nodejs`.
   - Call `require_tool java` with a note that Java 17 or 21 is needed (Lombok incompatibility with 22+).
   - Call `require_tool mvn maven`.
   - Call `require_tool curl curl`.
   - Call `require_tool lsof lsof`.
   - Copy `booking_system_frontend/.env.example` → `booking_system_frontend/.env` if `.env` does not already exist.
   - Exec `./start.sh`.

**Relevant Context:**
- [`scripts/local/start_locally.sh`](scripts/local/start_locally.sh) — the existing local launcher that this script delegates to; must remain unchanged.
- [`docker-compose.yml`](docker-compose.yml) — the Docker Compose file that this script delegates to for Docker mode.
- [`booking_system_frontend/.env.example`](booking_system_frontend/.env.example) — single-line file containing `VITE_API_URL=http://localhost:8001`.
- [`AGENTS.md`](AGENTS.md) — documents that Java 17/21 is required; Lombok does not support Java 22+.
- [`start.sh`](start.sh) — thin wrapper at root that delegates to `scripts/local/start_locally.sh`.

**Status:** [x] done

---

## Sub-Task 2 — Create `setup.ps1` (Windows PowerShell)

**Intent:** Provide an equivalent first-run script for Windows users who cannot run bash, using PowerShell-native equivalents for all Unix tools.

**Expected Outcomes:**
- A file `setup.ps1` exists at the repo root.
- Running `.\setup.ps1` after a fresh clone on Windows always asks the user: "Run with Docker (recommended) or Local?"
- Docker path: checks `docker` command exists and Docker daemon responds; if daemon not running, prints a clear error with Docker Desktop install/start instructions; if good, runs `docker compose up --build`.
- Local path: checks for `python`, `node`, `java`, `mvn`; auto-installs any missing tool via `winget`; creates `booking_system_frontend\.env` from `.env.example` if not present; runs a PowerShell-native local start that uses `Get-NetTCPConnection` instead of `lsof` and `Invoke-WebRequest` instead of `curl`.
- Script prints a clear summary at the end.

**Todo List:**
1. Create `setup.ps1` at the repo root.
2. Add mode prompt: display "1) Docker (recommended)  2) Local" and read the user's choice.
3. Implement Docker mode block:
   - Check `Get-Command docker` succeeds; if not, print winget install command (`winget install Docker.DockerDesktop`) and exit.
   - Check `docker info` succeeds; if not, print "Start Docker Desktop and re-run" and exit.
   - Run `docker compose up --build`.
4. Implement Local mode block:
   - Define a `Require-Tool` helper that checks with `Get-Command` and installs via `winget` if missing.
   - Call `Require-Tool python3 Python.Python.3.11`.
   - Call `Require-Tool node OpenJS.NodeJS`.
   - Call `Require-Tool java Microsoft.OpenJDK.21` (Java 21 — compatible with Lombok).
   - Call `Require-Tool mvn Apache.Maven`.
   - Copy `booking_system_frontend\.env.example` → `booking_system_frontend\.env` if `.env` does not already exist.
   - Implement PowerShell port-cleanup equivalent: use `Get-NetTCPConnection` to find PIDs on ports 8001, 5173, 8080 and `Stop-Process` to kill them.
   - Start backend: `Set-Location booking_system_backend`; create `.venv` if absent via `python -m venv .venv`; run `pip install -r requirements.txt`; start `python server.py` as a background `Start-Process`.
   - Start frontend: `Set-Location booking_system_frontend`; run `npm install` if `node_modules` absent; start `npm run dev` as a background `Start-Process`.
   - Health-check backend: poll `Invoke-WebRequest http://localhost:8001/` in a retry loop (5 attempts, 2s apart) before declaring success.
   - Print URLs for backend, frontend, and API docs.

**Relevant Context:**
- [`scripts/local/start_locally.sh`](scripts/local/start_locally.sh) — the bash script that `setup.ps1` mirrors in PowerShell; logic should match but use PS-native tools.
- [`booking_system_backend/requirements.txt`](booking_system_backend/requirements.txt) — Python dependencies.
- [`booking_system_frontend/package.json`](booking_system_frontend/package.json) — Node dependencies.
- [`AGENTS.md`](AGENTS.md) — confirms Java 17 or 21 required; Java 22+ breaks Lombok.

**Status:** [x] done

---

## Sub-Task 3 — Update README with one-command start instructions

**Intent:** Ensure that any developer who clones the repo immediately knows what single command to run, without reading the full AGENTS.md or scripts directory.

**Expected Outcomes:**
- `README.md` has a "Quick Start" section at the top (above "Project Origin") with the single commands for each platform.
- Section clearly notes Docker as the recommended path.
- Section links to `setup.sh` and `setup.ps1`.

**Todo List:**
1. Open `README.md` and prepend a "## Quick Start" section.
2. Include three commands:
   - macOS/Linux: `./setup.sh`
   - Windows: `.\setup.ps1`
   - Docker (either platform if Docker is already installed): `docker compose up --build` (with note to add `--profile hold-service` for the Java hold service).
3. Add a note that the scripts auto-install missing dependencies and prompt for mode selection.

**Relevant Context:**
- [`README.md`](README.md) — currently starts with "Project Origin" with no quick-start guidance.

**Status:** [x] done

---

## Design Decisions Recorded

| Decision | Choice | Reason |
|---|---|---|
| Mode selection | Always prompt Docker vs Local | User preference; no auto-detection |
| Windows missing tools | Auto-install via `winget` | User preference; built into Windows 10/11 (requires Windows 10 1709 or newer) |
| macOS missing tools | Auto-install via `brew` | User preference; standard macOS package manager; never requires sudo |
| Linux missing tools | Auto-install via `apt-get` with explicit `sudo` prompt | User preference; script must ask for sudo and not assume elevated privileges |
| Scope of changes | Additive only (new files) | Avoids breaking existing `start.sh` or `docker-compose.yml` |
| Java version for winget | Java 21 (Microsoft OpenJDK) | Java 17 and 21 are both valid; 21 is the newer LTS and winget-friendly |
| README Windows note | Add minimum OS version note | `winget` requires Windows 10 version 1709 or newer |
| Linux sudo handling | Script prompts user for sudo before `apt-get` | Avoids overstepping permissions; user must explicitly grant sudo access |
