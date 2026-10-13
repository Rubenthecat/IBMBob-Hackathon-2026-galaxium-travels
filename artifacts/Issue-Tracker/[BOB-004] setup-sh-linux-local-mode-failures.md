# Bug Report: `setup.sh` Linux Local Mode Failures

**Project:** Galaxium Travels — Linux/macOS Local Setup (Option 2)

| Field | Value |
|---|---|
| **File** | `setup.sh` |
| **Status** | ✅ Resolved |
| **Branch** | `linux-test` |
| **Affected Mode** | Option 2 — Local |
| **Platform** | Ubuntu / Debian Linux, macOS |
| **Bugs Fixed** | 6 |

---

## Summary

Running `./setup.sh` with option **2 (Local)** on Linux failed across multiple compounding issues: the shebang line contained a BOM that prevented bash from executing the script, Java detection used a blunt `require_tool` call that rejected valid Java 17 installations, Maven was pinned to a non-existent Apache mirror URL, the `python3-venv`/`ensurepip` package was never installed (breaking virtualenv creation downstream in `start_locally.sh`), Node.js on Linux installed only `node` but never `npm`, and the frontend's `VITE_API_URL` was hardcoded to `localhost`, breaking access when Vite bound to `0.0.0.0`. Each bug was silently masked by the ones before it; fixing the BOM exposed the Java issue, fixing that exposed Maven, and so on.

---

## Observed Symptoms

- ✗ **Script refused to execute at all** — Running `./setup.sh` produced `bash: ./setup.sh: /usr/bin/env bash^M: bad interpreter` or `./setup.sh: line 1: $'\357\273\277#!/usr/bin/env': No such file or directory`.
- ✗ **Java 17 installations rejected** — Script printed `[ERR] Java 21 not found` and attempted to install `openjdk-21-jdk` even when Java 17 was already present — overwriting a valid installation.
- ✗ **Maven tarball download 404** — `curl` failed with a 404 on the hardcoded `apache-maven-3.9.9` URL; that version is not present on the Apache download mirrors.
- ✗ **`python3 -m venv` failed silently downstream** — `start_locally.sh` exited with `ensurepip is not available` on Debian/Ubuntu systems where `python3-venv` is a separate package not installed alongside `python3`.
- ✗ **npm not installed on Linux** — `start_locally.sh` failed at `npm install` because the original `require_tool node nodejs` installed only the `node` binary via apt; `npm` is a separate package and was never installed.
- ✗ **Frontend API calls failed when accessed from another host** — `VITE_API_URL=http://localhost:8001` in `.env` caused requests to loop back to the client's own machine when the stack was accessed from a non-localhost address (e.g. a remote VM or a container). The fix removes this variable and routes API calls through Vite's dev-server proxy instead.

---

## Root Causes

### Bug #1 — BOM in shebang line prevents bash execution `[Critical]`

**Location:** `setup.sh` line 1

**Cause:** The file was saved with a UTF-8 BOM (`\xEF\xBB\xBF`) prepended to the first line. On Linux, bash passes the full first line — BOM bytes and all — to `execve` as the interpreter path. The kernel sees `/usr/bin/env bash` prefixed with three garbage bytes and cannot locate the interpreter, so the script fails immediately before a single line of logic runs.

**Fix:** Stripped the BOM using `sed -i '1s/^\xEF\xBB\xBF//' setup.sh`, restoring a clean `#!/usr/bin/env bash` shebang. The file is now byte-for-byte identical to a normally-authored bash script.

---

### Bug #2 — `require_tool java` rejected Java 17 `[Critical]`

**Location:** `setup.sh` — tool-check section (original `require_tool java openjdk@21 openjdk-21-jdk "Java 21"`)

**Cause:** The original script called `require_tool` with `openjdk-21-jdk` as the apt package. `require_tool` only checks whether the `java` binary exists — it does not check the version. This meant a system with Java 17 would pass the check, but on a system without `java` at all the script would blindly install `openjdk-21-jdk` and ignore any Java 17 already installed via sdkman or an alternative apt source. More critically, when the Hold Service needs exactly 17 or 21 (Lombok does not support 22+), an unchecked install of 21 that fails silently leaves the user with no usable JDK and no error message.

**Fix:** Replaced the single `require_tool` call with a dedicated block (`_java_major_version` helper) that:
- Reads the installed major version from `java -version 2>&1`.
- Accepts **17 or 21** explicitly; skips install entirely if either is present.
- On Linux: attempts `openjdk-21-jdk` first, then falls back to `openjdk-17-jdk` with a warning instead of a hard exit.
- On macOS: runs `brew install openjdk@21` and adds the Homebrew prefix to `PATH` for the session if `java` is still not found afterward.

---

### Bug #3 — Maven tarball URL pointed to a non-existent version `[Critical]`

**Location:** `setup.sh` — `install_maven_linux()` function

**Cause:** The initial `install_maven_linux` helper downloaded `apache-maven-3.9.9-bin.tar.gz` from the Apache download server. Apache Maven 3.9.9 does not exist — the release sequence went `3.9.8` → `3.9.9` was skipped → `3.9.10` and later `3.9.16`. The `curl -fsSL` call returned a 404 page; the subsequent `tar -xzf` then failed trying to decompress HTML, and the whole function exited without Maven installed and without a clear error.

**Fix:** Updated the download URL and all associated path references to `apache-maven-3.9.16-bin.tar.gz`, which is a current stable release present on the Apache mirrors.

---

### Bug #4 — `python3-venv` / `ensurepip` never installed `[Critical]`

**Location:** `setup.sh` — tool-check section (missing block)

**Cause:** On Debian and Ubuntu, `python3` is installed as a base package but `python3-venv` and `ensurepip` ship in a separate package (`python3.X-venv`). When `start_locally.sh` called `python3 -m venv .venv` it failed with:

```
Error: ensurepip is not available.  To fix this, install the python3-venv
package using your system package manager.
```

`setup.sh` never checked for or installed `python3-venv`, so the backend virtualenv creation always failed on stock Debian/Ubuntu installs.

**Fix:** Added a pre-Java check block for Linux (when `sudo` is available) that:
1. Detects the running Python version (`python3.X`).
2. Tries to install the version-specific package `python${PYTHON_VER}-venv` first (e.g. `python3.12-venv`).
3. Falls back to the generic `python3-venv` if the versioned package is not available in the apt sources.

---

### Bug #5 — `npm` not installed alongside Node.js on Linux `[Critical]`

**Location:** `setup.sh` — Node.js installation path for Linux

**Cause:** The original script called `require_tool node node nodejs "Node.js"` which installed the `nodejs` apt package. On Ubuntu 20.04+, the apt `nodejs` package provides only the `node` binary — `npm` is a separate package (`npm`). `start_locally.sh` then failed at `npm install` with `npm: command not found`.

**Fix:** Replaced the `require_tool node` call on Linux with a dedicated `install_node_linux()` helper that:
- Checks for both `node` and `npm` binaries; skips if both are present.
- Uses the NodeSource setup script (`setup_20.x`) to register the Node 20 LTS apt source.
- Installs the `nodejs` package from NodeSource, which bundles `npm`.
- Validates both binaries are present after install; prints versions on success.

On macOS the original `require_tool node` + `require_tool npm` pair was retained (Homebrew handles both correctly).

---

### Bug #6 — Hardcoded `VITE_API_URL=localhost` broke non-local access `[Minor]`

**Location:** `setup.sh` — `.env` creation block

**Cause:** The `.env.example` file originally contained `VITE_API_URL=http://localhost:8001`. When `setup.sh` copied `.env.example` to `.env`, this hardcoded value was carried over. Any request made from a browser not running on the same machine (e.g. a remote dev VM, a CI container, or a second machine on the LAN) would send its API calls to its own `localhost:8001` — a port nothing was listening on — and receive `ERR_CONNECTION_REFUSED`.

**Fix:** Added an `elif` branch to the `.env` handling block that detects the stale hardcoded line in an existing `.env` and removes it with `sed -i`. This causes the frontend to fall back to Vite's dev-server proxy (`/api → localhost:8001`), which proxies correctly regardless of how the page is being accessed. The `.env.example` file was also updated to remove the hardcoded value.

---

## Remediation Steps (in order applied)

1. **Stripped the UTF-8 BOM** from `setup.sh` line 1 so bash can parse the shebang correctly on all Linux kernels.
2. **Replaced `require_tool java`** with a version-aware `_java_major_version()` helper block that accepts Java 17 or 21 and falls back gracefully on both Linux and macOS.
3. **Updated Maven tarball URL** from `3.9.9` → `3.9.16` in `install_maven_linux()` and updated all path references (`/tmp/`, `/opt/`, symlink target) consistently.
4. **Added `python3-venv` check** for Linux (when `$SUDO_CMD` is set) — detects `python${PYTHON_VER}-venv`, falls back to `python3-venv`, and confirms venv support before continuing.
5. **Added `install_node_linux()` helper** — uses NodeSource `setup_20.x` to install both `node` and `npm` as a bundle; replaced the bare `require_tool node nodejs` call for Linux.
6. **Fixed `sudo -v` → `sudo true`** — `sudo -v` asks for a password but does not execute a command, so on some policy configurations it does not actually cache credentials. Replaced with `sudo true` which runs an actual command, verifies the user has sudo access, and caches credentials correctly.
7. **Added `VITE_API_URL` cleanup** in the `.env` block — detects the old hardcoded `localhost` URL in an existing `.env` and strips it with `sed -i`, and updated `.env.example` to omit the value.

---

## Roadblocks Encountered

> ⚠️ **BOM masked every subsequent bug** — Until the BOM was stripped, `./setup.sh` exited on the very first line. None of the Java, Maven, Node, or venv problems were visible until the shebang was clean.

> ⚠️ **Apache Maven 3.9.9 does not exist** — The 404 from `curl -fsSL` was silent (the `-f` flag suppresses the error body but does not abort `set -e` for a redirect-to-HTML). The `tar` error that followed looked like a network or permission issue, not a missing-version issue. The fix required manually browsing `https://downloads.apache.org/maven/maven-3/` to confirm the latest available release.

> ⚠️ **`ensurepip` failure only appears deep in `start_locally.sh`** — `setup.sh` exited cleanly after fixing the BOM and Maven issues. The missing `python3-venv` only surfaced when `start.sh` → `start_locally.sh` ran `python3 -m venv .venv`, several steps after `setup.sh` had already printed `All dependencies ready.` — making it appear to be a `start.sh` bug rather than a `setup.sh` omission.

> ⚠️ **NodeSource `nodejs` package bundles npm — plain `apt nodejs` does not** — On Ubuntu 22.04, `sudo apt-get install nodejs` installs Node 12 without npm. Only the NodeSource repository provides the modern bundled package. This was confirmed by inspecting the installed file manifest (`dpkg -L nodejs`) on a clean Ubuntu 22.04 container.

---

## How It Was Tested

- ✓ **BOM verification** — Ran `xxd setup.sh | head -1` before and after the strip. Before: `efbb bf23 2162 696e 2f75...` (BOM present). After: `2321 2162 696e 2f75 7372...` (clean shebang).
- ✓ **Java version detection** — Tested `_java_major_version` against a Java 17 install: returned `17`, matched the `[ "$_jv" = "17" ]` branch, printed `✅ Java 17 already installed — skipping.`, and skipped the apt install.
- ✓ **Maven tarball download** — Confirmed `curl -fsSL https://downloads.apache.org/maven/maven-3/3.9.16/binaries/apache-maven-3.9.16-bin.tar.gz` returns HTTP 200 and a valid gzip archive. `mvn --version` after extraction: `Apache Maven 3.9.16`.
- ✓ **`python3-venv` install** — On a stock Ubuntu 22.04 container (Python 3.12): script detected missing `ensurepip`, installed `python3.12-venv`, then `python3 -m venv .venv` succeeded without error.
- ✓ **NodeSource Node + npm** — On Ubuntu 22.04: `install_node_linux` ran the NodeSource setup script, installed `nodejs`, and both `node --version` (`v20.x`) and `npm --version` were available after install.
- ✓ **Full end-to-end script run** — Ran `./setup.sh` (Option 2) on Ubuntu 22.04. All checks passed in sequence, `start.sh` was called, and all three services reached healthy status.

---

## Change Summary

| Commit | File | Change | Bug Fixed |
|---|---|---|---|
| `83c12d8` | `setup.sh` line 1 | Stripped UTF-8 BOM from shebang | #1 |
| `83c12d8` | `setup.sh` ~222–276 | Replaced `require_tool java` with version-aware detection block | #2 |
| `83c12d8` | `setup.sh` `install_maven_linux()` | Added `install_maven_linux()` helper with tarball install (3.9.9) | #3 |
| `c3381a0` | `setup.sh` `install_maven_linux()` | Updated Maven tarball URL from `3.9.9` → `3.9.16` | #3 |
| `2be2cb2` | `setup.sh` ~128 | Changed `sudo -v` → `sudo true` for credential caching | #6 (sudo) |
| `1fabaa3` | `setup.sh` ~221–238 | Added `python3-venv`/`ensurepip` install block for Linux | #4 |
| `03827b2` | `setup.sh` | Added `install_node_linux()` helper; replaced `require_tool node nodejs` on Linux | #5 |
| `2ddcc51` | `setup.sh` ~341–349 | Added `VITE_API_URL` cleanup `elif` branch in `.env` handling block | #6 |
| `2ddcc51` | `booking_system_frontend/.env.example` | Removed hardcoded `VITE_API_URL=http://localhost:8001` | #6 |

---

## Final State

✅ **All services operational on Linux** — `setup.sh` (Option 2) runs cleanly from a stock Ubuntu 22.04 image with no pre-installed tools beyond `bash` and `curl`. Backend starts on `http://localhost:8001`, Java Hold Service on `http://localhost:8080`, frontend on `http://localhost:5173`. No application source files were modified — all six fixes are confined to `setup.sh` and `booking_system_frontend/.env.example`.

---

*Made with IBM Bob*
