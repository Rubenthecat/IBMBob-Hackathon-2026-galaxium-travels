# Plan: Fix Maven Installation in setup.ps1

## Overview

On a fresh Windows clone, running `setup.ps1` in local mode fails at the Maven installation step with:
> "No package found matching input criteria."

There are two root-cause bugs in [`setup.ps1`](../setup.ps1):

1. **`Apache.Maven` is not a valid winget package ID.** Maven is not published to the winget community repository. `winget install --id Apache.Maven` always fails with "No package found."
2. **The `Require-Tool` fallback error message always points to `python.org`** regardless of which tool failed (copy-paste bug in the generic helper at line 128). A Maven failure tells the user to go to the Python download page.

The fix adds a **Scoop fallback** inside `Require-Tool`: if `winget install` exits non-zero, the function tries `scoop install <scoop-package>` before giving up. Scoop reliably carries Maven. A new `ScoopPkg` parameter and a `TipUrl` parameter are added to the function signature so the error message links to the right manual download page per tool.

---

## Sub-Tasks

---

### Sub-Task 1 — Add `ScoopPkg` and `TipUrl` parameters to `Require-Tool`

**Intent**  
Extend the `Require-Tool` helper so it can attempt a Scoop installation when winget fails, and so the error tip URL is tool-specific rather than always pointing to `python.org`.

**Expected Outcomes**
- `Require-Tool` accepts two new optional parameters: `-ScoopPkg` (the Scoop bucket package name) and `-TipUrl` (manual download URL shown on failure).
- If `winget install` exits with a non-zero code AND `-ScoopPkg` is supplied, the function runs `scoop install <ScoopPkg>` automatically.
- If Scoop also fails (or is not installed), the function falls through to the existing error path, printing `TipUrl` instead of the hardcoded `python.org` URL.
- All existing callers (Python, Node.js, Java) continue to work as before — the new parameters are optional.

**Todo List**
1. Read the current `Require-Tool` function body in `setup.ps1` (lines 96–131).
2. Add `-ScoopPkg [string]` and `-TipUrl [string]` optional parameters to the function signature.
3. After the `winget install` call, capture `$LASTEXITCODE`. If it is non-zero and `$ScoopPkg` is set, run `scoop install $ScoopPkg --no-cache` (or plain `scoop install $ScoopPkg`) and then re-run the PATH refresh + binary check.
4. Replace the hardcoded `python.org` URL on the error tip line with `$TipUrl` (defaulting to `https://www.python.org/downloads/` to preserve existing behaviour for Python).

**Relevant Context**
- [`setup.ps1` lines 96–131](../setup.ps1) — `Require-Tool` function definition.
- The winget exit code for "no package found" is non-zero; checking `$LASTEXITCODE` after the call is sufficient.
- Scoop is invoked as `scoop install <pkg>` — it writes binaries to `%USERPROFILE%\scoop\shims` which is typically already on PATH after Scoop is set up.

**Status:** `[ ] pending`

---

### Sub-Task 2 — Update the Maven `Require-Tool` call to use `ScoopPkg` and `TipUrl`

**Intent**  
Pass the new parameters when calling `Require-Tool` for Maven so that (a) a Scoop fallback is attempted automatically and (b) the failure tip links to the Apache Maven download page.

**Expected Outcomes**
- `Require-Tool` for Maven passes `-ScoopPkg "maven"` and `-TipUrl "https://maven.apache.org/download.cgi"`.
- On a machine without Maven: winget is tried first (and fails silently); Scoop is then tried.
- If Scoop is not installed, the user sees: `"Please install it manually and re-run. Tip: Download from https://maven.apache.org/download.cgi"` — not the Python URL.

**Todo List**
1. Locate the Maven `Require-Tool` call at line 142 of `setup.ps1`.
2. Add `-ScoopPkg "maven"` and `-TipUrl "https://maven.apache.org/download.cgi"` to that call.
3. Optionally update the Python and Node.js calls with their correct `TipUrl` values for consistency (Python: `https://www.python.org/downloads/`, Node.js: `https://nodejs.org/en/download/`, Java: `https://learn.microsoft.com/en-us/java/openjdk/download`).

**Relevant Context**
- [`setup.ps1` line 142](../setup.ps1) — the Maven `Require-Tool` call.
- Scoop package name for Maven is `maven` (available in the `main` bucket by default).

**Status:** `[ ] pending`

---

### Sub-Task 3 — Auto-install Scoop if absent, then use it to install Maven

**Intent**
Scoop is not present on a fresh Windows machine. Rather than printing a hint and stopping, the script should install Scoop automatically using its official one-liner — no elevation required — and then proceed with `scoop install maven`. The result is a fully hands-free experience.

**Expected Outcomes**
- Before calling `scoop install`, the function checks whether `scoop` is on PATH.
- If Scoop is absent, the function prints a yellow status line (`"Scoop not found. Installing Scoop..."`) and runs the official Scoop bootstrap:
  ```powershell
  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
  Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
  ```
- After bootstrapping, the PATH is refreshed and `scoop install <ScoopPkg>` is run.
- If the Scoop bootstrap itself fails, the function falls through to the normal error path (print `[ERR]` + `TipUrl` + exit).
- On success, `Write-Green "Scoop installed successfully."` is printed before proceeding.

**Todo List**
1. Inside the Scoop fallback block added in Sub-Task 1, add a `Get-Command scoop` guard.
2. If Scoop is missing, emit `Write-Yellow "Scoop not found. Installing Scoop automatically..."`.
3. Run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force` then `Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression`.
4. Refresh PATH after the Scoop bootstrap (same pattern as after winget).
5. If `scoop` is still not on PATH after bootstrap, emit `[ERR]` with the `TipUrl` and exit.
6. Otherwise emit `Write-Green "Scoop installed successfully."` and proceed with `scoop install <ScoopPkg>`.

**Relevant Context**
- [`setup.ps1` lines 106–130](../setup.ps1) — the install + PATH-refresh + check flow inside `Require-Tool`.
- Scoop's official install one-liner: `Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression` (documented at https://scoop.sh).
- Scoop installs to `%USERPROFILE%\scoop\shims` and adds that to the User PATH during its own bootstrap — the existing PATH refresh block will pick it up.
- No administrator rights are needed; Scoop is designed for per-user installation.
- Pattern for colour messages: `Write-Yellow`, `Write-Green`, `Write-Red` (defined at lines 15–17 of `setup.ps1`).

**Status:** `[ ] pending`

---

## Notes

- Scoop installs to `%USERPROFILE%\scoop\shims` — the existing PATH refresh block (`[System.Environment]::GetEnvironmentVariable`) picks this up because it re-reads both Machine and User PATH. Scoop adds its shims to the User PATH during its own bootstrap.
- The Scoop bootstrap requires `RemoteSigned` execution policy for the current user only — this is the standard, non-invasive requirement documented by Scoop and does not affect system-wide policy.
- The fix is purely additive: no existing success path is changed. Python, Node.js, and Java installs are unaffected.
- No new files are needed — all changes are confined to `setup.ps1`.
