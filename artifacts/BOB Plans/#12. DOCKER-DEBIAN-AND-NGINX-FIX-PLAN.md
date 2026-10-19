# Plan: Fix Docker Mode on Debian — buildx Conflict + nginx API Proxy

## Overview

Two independent bugs prevent Docker mode (`setup.sh` option 1) from working correctly on a
Debian Linux host. Neither affects Local mode.

**Bug A — `docker-buildx` package conflict causes a hard exit on first run.**  
On Debian, `docker-compose-plugin` from Docker's official repo declares `docker-buildx-plugin`
as an apt dependency. The distro ships a separate, older `docker-buildx` package (v0.13.1) that
owns the same file (`/usr/libexec/docker/cli-plugins/docker-buildx`). When apt tries to unpack
both packages in a single transaction it hits a dpkg overwrite conflict and aborts — taking the
whole install with it. The script's conflict-removal logic (inside `_install_buildx_plugin`) is
only triggered *after* the compose install, so it never runs on the first pass. The script exits
at the "Auto-install failed" guard and tells the user to re-run. On the second run, compose is
partially installed (the apt cache has the `.deb` unpacked for compose even though buildx failed),
so the compose check passes and `_install_buildx_plugin` now runs and succeeds — but `docker
compose up --build` then fails immediately with `compose build requires buildx 0.17.0 or later`
because the newly installed buildx binary is not yet visible to the running shell session's
`docker` CLI lookup (the CLI plugin directory changed). The user is forced into a third run or a
manual `hash -r` before things work.

**Bug B — nginx proxies `/api/` to IBM Cloud instead of the local backend container.**  
The frontend Docker image is built on top of `nginx:alpine`. Its `nginx.conf` hard-codes the
`/api/` proxy target to an IBM Code Engine cloud URL. In Docker mode the React app is a compiled
static bundle (no Vite dev server) so every API call goes to the cloud backend, bypassing the
local `backend` container and `booking.db` entirely. In Local mode the Vite dev server's own
proxy config (`vite.config.ts`) correctly rewrites `/api` → `http://localhost:8001`, so Local
mode is unaffected.

**Goal:** One uninterrupted end-to-end run of `./setup.sh` → option 1 on Debian starts all
containers and serves API calls from the local `backend` container, with no exits or re-runs
required.

---

## Sub-Tasks

---

### Sub-Task 1 — Pre-emptively remove conflicting distro `docker-buildx` before installing compose plugin

**Status:** `[x] done`

**Intent**  
Remove the distro-packaged `docker-buildx` (if present) *before* calling `apt-get install
docker-compose-plugin`, so apt can install both `docker-compose-plugin` and its
`docker-buildx-plugin` dependency atomically without hitting a dpkg overwrite conflict. This
eliminates the first-run exit and makes the entire plugin-install sequence complete in a single
pass.

**Expected Outcomes**
- First run of `setup.sh` on a Debian host with `docker-buildx` pre-installed proceeds without
  any dpkg conflict error.
- No "Auto-install failed" exit is printed.
- No re-run is required to get past the compose/buildx install phase.
- The `_install_buildx_plugin` function and its existing conflict-removal logic are retained as
  a safety net for cases where `docker-buildx` was installed after `docker-compose-plugin`.

**Todo List**
1. In `setup.sh`, locate the `_ensure_docker_repo` function's `apt` branch (around line 277).
2. After `_ensure_docker_repo` is called and before `_install_docker_pkg docker-compose-plugin`
   is invoked (around line 437), insert a pre-flight step that checks whether the distro
   `docker-buildx` package is installed (`dpkg -l docker-buildx`) and removes it with
   `sudo -E apt-get remove -y docker-buildx` if found.
3. This pre-flight only runs on `apt`-based systems (guard with `if [ "$PKG_MANAGER" = "apt" ]`).
4. Emit a short status line so the user can see what is happening
   (e.g. `(removing conflicting distro docker-buildx package before installing plugins...)`).
5. The existing `_install_buildx_plugin` conflict-removal code (lines 392-396) must remain
   unchanged — it still handles the case where `docker-buildx` is installed separately after
   this point.

**Relevant Context**
- `setup.sh` lines 428-451: compose plugin install block
- `setup.sh` lines 390-426: `_install_buildx_plugin` (existing conflict-removal logic lives here)
- `setup.sh` lines 274-367: `_ensure_docker_repo`
- `setup.sh` line 437: `_install_docker_pkg docker-compose-plugin` — this is where apt fatally
  conflicts today
- The user's first-run output confirms: `dpkg: error processing archive
  docker-buildx-plugin ... trying to overwrite ... which is also in package docker-buildx`

---

### Sub-Task 2 — Fix nginx to proxy `/api/` to the local backend container in Docker mode

**Status:** `[x] done`

**Intent**  
Replace the hard-coded IBM Code Engine URL in `nginx.conf` with a proxy target that points to
the `backend` service on the Docker Compose internal network. This makes the frontend container
route API calls to the co-located `backend` container rather than the cloud, so `booking.db` is
reachable in Docker mode.

**Expected Outcomes**
- In Docker mode, `GET http://localhost:5173/api/flights` returns data from the local backend.
- The IBM Code Engine URL is no longer referenced in `nginx.conf`.
- Local mode is unaffected (it never uses `nginx.conf`).
- The deployed IBM Code Engine environment is unaffected: the cloud deployment overrides
  `VITE_API_URL` at build time (see `docker-compose.yml` line 60 and the IBM deploy script) and
  the nginx config for that environment is managed separately.

**Todo List**
1. Open `booking_system_frontend/nginx.conf`.
2. In the `location /api/` block (line 20), replace `proxy_pass` and the associated
   `proxy_set_header Host` directive so they target `http://backend:8080` — the Docker Compose
   service name and internal port used by the backend container (confirmed in `docker-compose.yml`
   line 19 `build: ./booking_system_backend` and line 23 `ports: "8001:8080"`).
3. Remove the `proxy_ssl_server_name on;` directive (not needed for plain HTTP on the internal
   network).
4. Update the `proxy_set_header Host` to `$host` (generic — works for both local and any future
   environment where the backend URL is injected differently).
5. Retain all timeout directives (`proxy_connect_timeout`, `proxy_read_timeout`,
   `proxy_send_timeout`) — they are still useful for slow container cold starts.
6. Update the comment above the `location /api/` block to reflect the new routing target.

**Relevant Context**
- `booking_system_frontend/nginx.conf` lines 20-31: the broken proxy block
- `docker-compose.yml` line 19: `build: ./booking_system_backend` (service name: `backend`)
- `docker-compose.yml` line 22: `ports: "8001:8080"` — internal port is `8080`
- `booking_system_frontend/src/services/api.ts` line 15: `baseURL: import.meta.env.VITE_API_URL || '/api'`
- `booking_system_frontend/Dockerfile` line 14: `ARG VITE_API_URL=/api` — bakes `/api` as the
  base URL, so all API traffic flows through nginx's `/api/` location

---

## Files Changed

| File | Sub-Task | Change |
|---|---|---|
| `setup.sh` | 1 | Pre-flight removal of distro `docker-buildx` before compose plugin install |
| `booking_system_frontend/nginx.conf` | 2 | Replace IBM Code Engine proxy URL with `http://backend:8080` |

---

*Made with IBM Bob*
