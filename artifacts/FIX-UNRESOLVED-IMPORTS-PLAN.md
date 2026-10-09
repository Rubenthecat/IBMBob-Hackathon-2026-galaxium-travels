# Fix Unresolved Import Diagnostics — Plan

## Overview

Seven import errors are reported in `booking_system_backend/server.py` by Pylance/Pyright:
`httpx`, `dotenv`, `fastapi`, `fastapi.middleware.cors`, `fastapi_mcp`, `sqlalchemy.orm`, and `uvicorn`.

These are **editor-side resolution failures**, not runtime failures. All packages are already declared
in `requirements.txt`. The root causes are:

1. The Python virtual environment (`.venv`) has not been created or packages have not been installed.
2. No `pyrightconfig.json` exists to tell Pylance where to find the venv, so it falls back to the
   system Python, which does not have these packages.

The fix: create the venv, install dependencies, and add a `pyrightconfig.json` that points
Pylance at the correct interpreter.

---

## Sub-Task 1 — Create the virtual environment and install dependencies

**Intent**
Ensure the `.venv` for the backend exists and all packages from `requirements.txt` are installed.
This resolves the missing packages at runtime and gives Pylance something to resolve against.

**Expected Outcomes**
- `booking_system_backend/.venv/` exists and contains installed site-packages for all packages in
  `requirements.txt` (fastapi, httpx, sqlalchemy, uvicorn, fastapi-mcp, python-dotenv, etc.).
- The backend can be started with `.venv/bin/python server.py` without import errors.

**Todo List**
1. `cd booking_system_backend`
2. `python3 -m venv .venv`
3. `source .venv/bin/activate` (macOS/Linux) or `.\.venv\Scripts\Activate.ps1` (Windows)
4. `pip install -r requirements.txt`

**Relevant Context**
- [`booking_system_backend/requirements.txt`](booking_system_backend/requirements.txt) — full list of packages to install.
- AGENTS.md install command: `python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt`

**Status:** `[ ] pending`

---

## Sub-Task 2 — Add pyrightconfig.json to resolve imports in the editor

**Intent**
Create a `pyrightconfig.json` in the `booking_system_backend/` directory so that Pylance uses the
correct `.venv` interpreter when type-checking `server.py` and other backend files. Without this,
Pylance uses the system Python (which lacks the packages) and reports unresolved imports.

**Expected Outcomes**
- All seven import errors in `server.py` are cleared in the Problems panel.
- Pylance provides type hints and auto-complete for fastapi, sqlalchemy, httpx, etc.

**Todo List**
1. Create `booking_system_backend/pyrightconfig.json` with the following content:
   ```json
   {
     "venvPath": ".",
     "venv": ".venv",
     "pythonVersion": "3.11"
   }
   ```
   (`venvPath` is the directory containing `.venv`; `venv` is the venv folder name.)
2. Reload the VS Code Python extension (or reopen the workspace) to pick up the new config.
3. Confirm the Problems panel shows zero import errors for `server.py`.

**Relevant Context**
- No `pyrightconfig.json` exists at the repo root or in `booking_system_backend/` (confirmed by search).
- No `.vscode/settings.json` exists either, so there is no alternative interpreter pointer.
- Pyright docs: `venvPath` + `venv` together resolve to `<venvPath>/<venv>` as the interpreter root.

**Status:** `[ ] pending`
