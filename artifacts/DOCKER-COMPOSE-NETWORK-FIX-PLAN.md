# Docker Compose Network Fix Plan

## Top-Level Overview

When `setup.sh` is run on Linux and the user is not yet in the `docker` group, the script falls back to `exec sudo -g docker docker compose … up --build`. Linux ignores the `-E` flag (`sudo: preserving the entire environment is not supported, '-E' is ignored`), so the `$HOME` and working-directory-derived project name can drift between the `sudo` invocation and prior Docker state. More critically, the backend container exits immediately with a DNS failure (`failed to resolve host 'postgres'`), which then causes a cascading failure where nginx can't resolve the `backend` upstream and the frontend exits too.

There are two root causes to fix:

1. **`sudo -E` is silently ignored on this Ubuntu host** — the compose invocation should not rely on `-E` to forward env; it should use a safer approach that does not require `-E`.
2. **nginx resolves upstreams at startup** — if the backend exits, nginx fails. The nginx config needs to use a runtime-resolved upstream (via a variable or DNS resolver directive) so it doesn't hard-fail at parse time.

Both fixes are minimal and targeted. No architecture changes.

---

## Sub-Tasks

---

### Sub-Task 1 — Fix the `sudo` invocation in `setup.sh`

**Status:** `[x] done`

**Intent**

Replace `exec sudo -E -g docker docker compose …` with an approach that does not depend on `-E` (which is ignored on many Linux distros when `env_reset` is set in `/etc/sudoers`). The simplest safe fix is to use `newgrp docker` or `sg docker` to re-exec the script under the docker group without needing sudo at all — because `usermod -aG docker $USER` has already been called above it. Alternatively, drop into `sudo -u "$USER" -g docker` without `-E`, and pass only the specific env vars that Docker Compose needs (none — they're all baked into the compose file).

**Root Cause Detail**

In `setup.sh` line 568:
```bash
exec sudo -E -g docker docker compose --profile hold-service up --build
```
`-E` is a no-op on Ubuntu when `/etc/sudoers` has `env_reset`. The working directory is preserved by the `cd "$SCRIPT_DIR"` call above it, so the project name is fine. The real danger is that if `sudo` resets `$HOME`, Docker may look for config in `/root/.docker/` instead of the user's home, potentially using a different Docker context or credentials — which could affect network creation in edge cases.

The correct fix: use `sg docker -c "docker compose --profile hold-service up --build"` instead of `sudo`. `sg` activates the new group for just that command without elevating privileges, and it does not reset the environment. This is the standard pattern for "run with a new group immediately without logout."

**Expected Outcomes**
- No `sudo: preserving the entire environment is not supported, '-E' is ignored` warning
- Docker Compose runs as the original user with the `docker` group active
- Docker uses the user's own Docker context and config (no `/root/.docker/` confusion)
- Backend can resolve `postgres` hostname via the compose default network

**Todo List**
- [ ] In `setup.sh`, in the `_USE_SUDO_DOCKER=true` branch (around line 567–568), replace `exec sudo -E -g docker docker compose --profile hold-service up --build` with `exec sg docker -c "docker compose --profile hold-service up --build"` 
- [ ] Verify the non-sudo branch (line 570) remains unchanged

**Relevant Context**
- [`setup.sh` lines 548–571](setup.sh:548) — the docker group / sudo logic
- The `sg` command is available on all Linux distros that have `shadow-utils`; it executes a command under a supplementary group without requiring `sudo`

---

### Sub-Task 2 — Make nginx resilient to backend startup order

**Status:** `[x] done`

**Intent**

Even after fixing Sub-Task 1, there is a latent fragility: nginx resolves `proxy_pass http://backend:8080/` **at config parse time**. If the backend container is slow to register its DNS name, or if backend ever crashes and restarts, nginx will fail to start or proxy requests to a dead upstream. The fix is to use nginx's `resolver` directive + a variable for the upstream, which defers DNS resolution to request time.

**Expected Outcomes**
- nginx starts successfully even if the `backend` container hasn't fully registered its DNS name yet
- nginx re-resolves `backend` dynamically on each proxied request (or on TTL expiry)
- The frontend `depends_on: backend` can remain as-is (starts when backend container exists, not just when it's healthy)

**Todo List**
- [ ] In `booking_system_frontend/nginx.conf`, add a `resolver 127.0.0.11 valid=10s;` directive inside the `server` block (Docker Compose's embedded DNS resolver is always at `127.0.0.11`)
- [ ] Change the `/api/` location to use a variable: set `$backend_url http://backend:8080` and use `proxy_pass $backend_url/;` — this makes nginx resolve at request time, not at startup
- [ ] Optionally add `resolver_timeout 5s;` to fail fast on DNS errors rather than hanging

**Relevant Context**
- [`booking_system_frontend/nginx.conf` line 21](booking_system_frontend/nginx.conf:21) — the hard-coded `proxy_pass http://backend:8080/`
- Docker Compose always runs a DNS resolver at `127.0.0.11` inside every container on the compose network
- nginx variable-based `proxy_pass` is well-documented; requires the `resolver` directive to be set first

---

### Sub-Task 3 — Add `condition: service_healthy` to frontend's depends_on

**Status:** `[x] done`

**Intent**

The `frontend` service depends on `backend` with no health condition. This means Docker Compose starts frontend immediately when backend's *container* starts — not when backend is actually ready. Combined with Sub-Task 2, this is safe, but making frontend wait for backend to be healthy is a cleaner solution and removes the race entirely.

**Expected Outcomes**
- Docker Compose only starts the frontend container after the backend passes its healthcheck
- Eliminates the startup race between nginx and the backend service

**Todo List**
- [ ] In `docker-compose.yml`, change `frontend.depends_on` from a list (`- backend`) to a map with `condition: service_healthy`

**Relevant Context**
- [`docker-compose.yml` lines 64–65](docker-compose.yml:64) — current `depends_on: - backend`
- The backend already has a `healthcheck` defined at lines 31–35
- Backend healthcheck uses `python -c "import requests; requests.get('http://localhost:8080/', timeout=2)"` — this will pass once the FastAPI/MCP server is up
