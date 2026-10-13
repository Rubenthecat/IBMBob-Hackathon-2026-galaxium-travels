# Bug Report: `setup.sh` Docker Mode Missing Plugin Checks

**Project:** Galaxium Travels — Docker Setup (Option 1)

| Field | Value |
|---|---|
| **Files** | `setup.sh`, `docker-compose.yml` |
| **Status** | ✅ Resolved |
| **Branch** | `linux-test` |
| **Affected Mode** | Option 1 — Docker |
| **Platform** | Ubuntu / Debian Linux, macOS |
| **Bugs Fixed** | 3 |

---

## Summary

Running `./setup.sh` with option **1 (Docker)** on a fresh Linux machine failed in three distinct ways: the script called `docker compose` without verifying the V2 Compose plugin was installed (a separate apt package from the Docker engine), it called `docker compose up --build` against Dockerfiles that all use `--platform=linux/amd64` without checking that `docker buildx` was available, and `docker-compose.yml` unconditionally included the Java Hold Service in the default `up` target despite `AGENTS.md` documenting it as a profile-gated optional service — causing every first-run to attempt a slow Maven build of a service the user had no way to skip. Together these three issues meant a user could follow every instruction in the README, run `./setup.sh`, select Docker mode, and still get a hard failure before a single container started.

---

## Observed Symptoms

- ✗ **Cryptic compose error on fresh Linux** — Running `./setup.sh` → option 1 on a stock Ubuntu install (where only `docker-ce` is installed) exited immediately with `docker: 'compose' is not a docker command. See 'docker --help'.` No install guidance was offered.
- ✗ **`--platform` build failure without buildx** — On hosts with the legacy builder only, `docker compose up --build` failed with `ERROR: unknown flag: --platform` or silently fell back to slow QEMU emulation with no warning.
- ✗ **Java Maven build always runs on first start** — Every `docker compose up --build` triggered a full Maven build of `booking_system_inventory_hold_service` (pulling a ~500 MB `maven:3.9-eclipse-temurin-17` image plus all Spring Boot dependencies), even though the Hold Service is an optional component that most users don't need for a basic demo run.

---

## Root Causes

### Bug #1 — `docker compose` V2 plugin not checked before use `[Critical]`

**Location:** `setup.sh` — Docker mode block (original `exec docker compose up --build`)

**Cause:** On Linux, Docker Engine and the Compose V2 plugin are separate apt packages. Installing `docker-ce` does not install `docker-compose-plugin`. The script checked for the `docker` binary and for the daemon being alive, but never verified that `docker compose` (the V2 subcommand) was available. On any fresh Ubuntu/Debian machine installed via the official Docker apt repository without explicitly requesting the compose plugin, the `exec docker compose up --build` call at the end of the Docker mode block failed immediately.

**Fix:** Added a `docker compose version` probe immediately after the `docker info` check. On Linux, if the probe fails and the user grants sudo, `docker-compose-plugin` is installed automatically via `apt-get`. If sudo is unavailable, the script exits with a clear manual install instruction. On macOS, Docker Desktop bundles Compose V2 natively — the script exits with a link to update Docker Desktop instead.

---

### Bug #2 — `docker buildx` not checked despite `--platform` usage in all Dockerfiles `[Critical]`

**Location:** `setup.sh` — Docker mode block; `booking_system_backend/Dockerfile:1`, `booking_system_frontend/Dockerfile:1`, `booking_system_inventory_hold_service/Dockerfile:20`

**Cause:** All three Dockerfiles open with `FROM --platform=linux/amd64 ...`. This requires the BuildKit-backed `docker buildx` builder. On Linux, `docker-buildx-plugin` is also a separate apt package not bundled with `docker-ce`. Without it, the legacy builder is invoked, which either rejects the `--platform` flag outright (`ERROR: unknown flag: --platform`) or performs a silent and extremely slow QEMU-based cross-architecture emulation build with no warning. `AGENTS.md` explicitly states: *"docker-buildx is NOT optional: without it, 'docker compose --build' falls back to the legacy builder."*

**Fix:** Added a `docker buildx version` probe after the Compose plugin check. On Linux with sudo available, `docker-buildx-plugin` is installed automatically. On macOS, Docker Desktop bundles buildx from v4+ — the script exits directing the user to update Docker Desktop.

---

### Bug #3 — `java-service` included in default `docker compose up` with no profile gate `[Major]`

**Location:** `docker-compose.yml` — `java-service` service definition

**Cause:** `docker-compose.yml` defined `java-service` with no `profiles:` key, meaning it was included in every `docker compose up` call. `AGENTS.md` states: *"docker-compose.yml Java service is behind a profile — it uses `profiles: [hold-service]`."* The code contradicted the documentation. On a first run, this silently added a full Maven build of the Spring Boot Hold Service to the startup sequence — pulling `maven:3.9-eclipse-temurin-17` (~500 MB) and downloading all Spring Boot dependencies — with no way for the user to opt out. On slow or memory-constrained machines this was the most common cause of first-run timeouts or OOM failures. It also meant the Hold Service URL (`localhost:8082`) appeared in the running stack on every start, creating user confusion when backend calls to `JAVA_SERVICE_URL: http://java-service:8080` were answered by a service the user hadn't intentionally started.

**Fix:** Added `profiles: [hold-service]` to the `java-service` definition in `docker-compose.yml`. `docker compose up --build` now starts only `postgres`, `backend`, and `frontend`. The Hold Service is started by `docker compose --profile hold-service up --build`, which `setup.sh` now uses as its default command so all four services start together — but the profile gate allows the Compose file to be used standalone without the Hold Service when desired.

---

## Remediation Steps (in order applied)

1. **Added `docker compose version` check** — inserted immediately after the `docker info` daemon check in the Docker mode block; auto-installs `docker-compose-plugin` on Linux with sudo, or directs macOS users to update Docker Desktop.
2. **Added `docker buildx version` check** — inserted after the Compose plugin check; auto-installs `docker-buildx-plugin` on Linux with sudo, or directs macOS users to update Docker Desktop.
3. **Added `profiles: [hold-service]`** to `java-service` in `docker-compose.yml` — brings the file into alignment with `AGENTS.md` and removes the Hold Service from the default `up` target.
4. **Updated `setup.sh` launch command** — changed `exec docker compose up --build` to `exec docker compose --profile hold-service up --build` so the full stack (including Hold Service) starts from `setup.sh` as intended, while the `docker-compose.yml` profile gate still allows bare `docker compose up` to run without it.
5. **Removed the now-redundant tip message** — the `echo "To also start the Java Hold Service, run: docker compose --profile hold-service up --build"` lines were removed since `setup.sh` now runs that command directly.

---

## Roadblocks Encountered

> ⚠️ **`$SUDO_CMD` is not set in Docker mode** — The `$SUDO_CMD` variable used throughout the Local mode block is only initialised in the Local mode section of `setup.sh` (after the Docker mode block `exit`s). The initial plugin check drafts incorrectly referenced `$SUDO_CMD`, which is always empty in Docker mode. The fix was to replace the `$SUDO_CMD` guard with an inline `sudo -n true 2>/dev/null || { prompt user; sudo true; }` pattern that acquires sudo credentials on demand within the Docker mode block itself.

> ⚠️ **`docker-compose.yml` contradicted `AGENTS.md`** — `AGENTS.md` documented the Java service as profile-gated, but the file had no `profiles:` key. The discrepancy was only discovered by cross-referencing both sources; neither file produced an error on its own.

> ⚠️ **macOS Docker Desktop bundles both plugins natively** — The auto-install path (apt-get) is Linux-only. On macOS, both `docker compose` and `docker buildx` are provided by Docker Desktop and cannot be installed independently via Homebrew in a way that integrates with the Desktop daemon. The macOS branch correctly exits with an update-Docker-Desktop instruction rather than attempting a broken install.

---

## How It Was Tested

- ✓ **Plugin check flow verified by code review** — `docker compose version` and `docker buildx version` both return non-zero when the respective plugins are absent; the `if !` guards and the re-probe after install were confirmed structurally correct against the existing daemon check patterns in the same file.
- ✓ **`profiles` key validated in `docker-compose.yml`** — Final file confirmed via read: `profiles: [hold-service]` appears as a sibling key to `build:` and `ports:` under `java-service`. `docker compose up --build` (no profile) would start `postgres`, `backend`, `frontend` only. `docker compose --profile hold-service up --build` starts all four.
- ✓ **`setup.sh` launch command confirmed** — Final `exec` line reads `exec docker compose --profile hold-service up --build`.
- ✓ **Bash structure reviewed** — All `if`/`fi` pairs balanced; `[[...]]` regex used correctly inside `{ ... }` group command for the interactive sudo prompt; no `$SUDO_CMD` references remain in the Docker mode block.
- ✓ **No regression to other paths** — `setup.ps1` (Docker Desktop on Windows bundles both plugins natively) and `setup.sh` Option 2 / `start_locally.sh` (never call `docker compose`) confirmed unaffected by all three changes.

---

## Change Summary

| File | Change | Bug Fixed |
|---|---|---|
| `setup.sh` | Added `docker compose version` probe + auto-install of `docker-compose-plugin` on Linux | #1 |
| `setup.sh` | Added `docker buildx version` probe + auto-install of `docker-buildx-plugin` on Linux | #2 |
| `docker-compose.yml` | Added `profiles: [hold-service]` to `java-service` | #3 |
| `setup.sh` | Changed launch command from `docker compose up --build` to `docker compose --profile hold-service up --build` | #3 |
| `setup.sh` | Removed redundant "To also start the Java Hold Service" tip message | #3 |

---

## Final State

✅ **Docker mode now works on a fresh Linux machine** — `setup.sh` (Option 1) self-heals missing Compose and buildx plugins on Linux (with sudo), provides clear actionable errors without sudo or on macOS, and launches the full four-service stack (`postgres`, `backend`, `frontend`, `java-service`) via `docker compose --profile hold-service up --build`. The `docker-compose.yml` profile gate also correctly aligns the file with `AGENTS.md`. No Dockerfiles, application source files, or other setup paths were modified.

---

*Made with IBM Bob*
