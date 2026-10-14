# Plan: Fix `setup.sh` Docker Path (Option 1) for Frictionless First-Run

## Overview

**Goal:** Make `./setup.sh` → option 1 (Docker) a genuine single-command install that works on a fresh Linux or macOS machine with no manual follow-up steps required.

**Scope:** Three targeted changes across two files — `setup.sh` and `docker-compose.yml`. No changes to `setup.ps1`, `setup.sh` Option 2, `start_locally.sh`, or any Dockerfile.

**Non-goals:** Fixing the `nginx.conf` IBM Cloud proxy rule (that bug is dormant in Docker mode because the JS bundle uses an absolute `http://localhost:8001` URL, bypassing nginx's `/api/` proxy block). Port-conflict detection is also out of scope — it is a secondary issue that does not block a fresh instance.

---

## Sub-Tasks

---

### Sub-Task 1 — Add `docker compose` (V2 plugin) check to `setup.sh`

**Intent**
On a fresh Linux machine, only the `docker` binary is required to be present — the Compose V2 plugin (`docker compose`) is a separate package (`docker-compose-plugin`) that is not bundled with the engine. The script currently calls `docker compose up --build` without verifying the plugin exists, which produces a cryptic `"docker: 'compose' is not a docker command"` failure. This check catches that condition early and provides a clear, actionable error message (or auto-installs on Linux with sudo).

**Expected Outcomes**
- On macOS: if `docker compose version` fails, the script exits with an instruction to update Docker Desktop.
- On Linux with sudo: `docker-compose-plugin` is installed automatically via `apt-get`.
- On Linux without sudo: the script exits with a manual install instruction.
- On any machine where `docker compose` already works: no change in behaviour.

**Todo List**
1. After the `docker info` check (line 100 of `setup.sh`), add a `docker compose version` probe.
2. If it fails on Linux and `$SUDO_CMD` is set, run `apt-get install -y docker-compose-plugin`.
3. If it fails on macOS, print "Update Docker Desktop to a version that includes Compose V2" and exit.
4. Re-probe after install; exit with a clear error if still missing.

**Relevant Context**
- [`setup.sh:86–100`](setup.sh:86) — existing `docker info` check; the new check slots in immediately after line 100.
- `docker-compose-plugin` is the correct apt package name on Ubuntu 20.04+/Debian.
- On macOS, Docker Desktop already bundles Compose V2; a missing plugin means the Desktop installation is stale or broken — no auto-fix is appropriate.

**Status:** `[x] done`

---

### Sub-Task 2 — Add `docker buildx` check to `setup.sh`

**Intent**
All three Dockerfiles open with `FROM --platform=linux/amd64 ...`. Without `docker buildx`, the legacy builder is used, which either rejects the `--platform` flag outright or forces slow QEMU emulation without warning. On a fresh Linux instance, `docker-buildx-plugin` is also a separate apt package. `AGENTS.md` explicitly calls this out as non-optional.

**Expected Outcomes**
- On Linux with sudo: `docker-buildx-plugin` is installed automatically if `docker buildx version` fails.
- On Linux without sudo or macOS: a clear error with a manual install command.
- On any machine where buildx already works: no change in behaviour.

**Todo List**
1. After the Compose plugin check (Sub-Task 1), add a `docker buildx version` probe.
2. If it fails on Linux and `$SUDO_CMD` is set, run `apt-get install -y docker-buildx-plugin`.
3. If it fails on macOS, print "Update Docker Desktop (buildx is bundled from version 4.x+)" and exit.
4. Re-probe after install; exit with a clear error if still missing.

**Relevant Context**
- [`setup.sh:66–117`](setup.sh:66) — entire Docker mode block; the new check belongs after the Compose check and before the `cd "$SCRIPT_DIR"` / `exec docker compose` call.
- [`AGENTS.md:35–36`](AGENTS.md:35) — "docker-buildx is NOT optional".
- `docker-buildx-plugin` is the correct apt package name on Ubuntu 20.04+/Debian.

**Status:** `[x] done`

---

### Sub-Task 3 — Gate `java-service` behind `profiles: [hold-service]` in `docker-compose.yml`

**Intent**
`docker-compose.yml` currently starts `java-service` unconditionally. This contradicts `AGENTS.md` ("the Java service is behind a profile") and means every `docker compose up --build` on a fresh machine triggers a full Maven build of the Spring Boot service — a ~500 MB image pull plus a slow compile. For a first-run demo setup, users want backend + frontend only; the Hold Service is an optional advanced feature. Adding `profiles: [hold-service]` to `java-service` makes the default `docker compose up --build` start only `postgres`, `backend`, and `frontend`, exactly as documented.

**Expected Outcomes**
- `docker compose up --build` (no flags) starts only: `postgres`, `backend`, `frontend`.
- `docker compose --profile hold-service up --build` starts all four services (existing behaviour is preserved).
- The informational note already printed by `setup.sh` ("To also start the Java Hold Service, run: docker compose --profile hold-service up --build") becomes accurate.
- `setup.ps1`, `setup.sh` Option 2, and `start_locally.sh` are unaffected — they do not use `docker-compose.yml`.

**Todo List**
1. In `docker-compose.yml`, add `profiles: [hold-service]` under the `java-service` service definition.
2. Verify that `backend` no longer lists `java-service` in its `depends_on` (it doesn't currently — no change needed, but confirm).
3. Confirm that `frontend`'s `depends_on: [backend]` chain is unaffected.

**Relevant Context**
- [`docker-compose.yml:37–53`](docker-compose.yml:37) — `java-service` definition; `profiles:` is a top-level key under the service name, sibling to `build:`, `ports:`, etc.
- [`AGENTS.md:23`](AGENTS.md:23) — "docker-compose.yml Java service is behind a profile — it uses `profiles: [hold-service]`".
- [`setup.sh:111–112`](setup.sh:111) — the existing informational note about `--profile hold-service` already tells users how to opt in.

**Status:** `[x] done`

---

## Files Changed

| File | Sub-Tasks | Change Type |
|------|-----------|-------------|
| [`setup.sh`](setup.sh) | 1, 2 | Add two plugin checks inside the Docker mode block |
| [`docker-compose.yml`](docker-compose.yml) | 3 | Add `profiles: [hold-service]` to `java-service` |

## Files Explicitly Not Changed

| File | Reason |
|------|--------|
| [`setup.ps1`](setup.ps1) | Docker Desktop on Windows bundles Compose V2 and buildx; no equivalent checks needed |
| [`scripts/local/start_locally.sh`](scripts/local/start_locally.sh) | Local mode; never calls `docker compose` |
| `booking_system_*/Dockerfile` | Build instructions are correct; the problem is pre-build prerequisite checks |
| [`booking_system_frontend/nginx.conf`](booking_system_frontend/nginx.conf) | IBM Cloud proxy rule is dormant in Docker mode (JS bundle uses absolute URL); out of scope |
