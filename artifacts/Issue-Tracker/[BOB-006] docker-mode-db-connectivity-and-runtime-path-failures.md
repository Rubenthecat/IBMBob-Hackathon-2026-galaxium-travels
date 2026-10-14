# [BOB-006]: Docker Mode — DB Connectivity, Stale References, Flights `.map` Crash & Local holds.db Path Failure

**Project:** Galaxium Travels — Docker & Local Setup

| Field            | Value                                                                                               |
|------------------|-----------------------------------------------------------------------------------------------------|
| **Files**        | `docker-compose.yml`, `booking_system_inventory_hold_service/Dockerfile`, `setup.sh`, `booking_system_inventory_hold_service/src/main/resources/application.properties`, `booking_system_frontend/nginx.conf`, `booking_system_backend/server.py`, `booking_system_frontend/src/pages/Flights.tsx`, `scripts/local/start_locally.sh` |
| **Affected Mode**| Option 1 — Docker (all Linux platforms); Option 2 — Local (all platforms)                          |
| **Platform**     | Ubuntu, Debian Linux; macOS local mode                                                              |
| **Status**       | Resolved                                                                                            |
| **Plans**        | #14 DB-CONNECTIVITY-FIX-PLAN, #15 DOCKER-DB-STALE-REFERENCES-FIX-PLAN, #16 FLIGHTS-PAGE-MAP-ERROR-FIX-PLAN, #17 HOLDS-DB-LOCAL-PATH-FIX |
| **Bugs Fixed**   | 11                                                                                                  |

---

## Summary

Four interrelated bug clusters prevented `./setup.sh` Docker mode from functioning end-to-end on Linux and caused the `holds.db` database to be inaccessible in local mode.

1. **DB Connectivity (Plan #14)** — Ubuntu failed to start at all (`psycopg.OperationalError: failed to resolve host 'postgres'`) due to `sg docker` spawning a divergent subshell that landed the backend on a different Docker network. Debian started but returned no data, because `DATABASE_URL` was misinterpreted by Compose v1 (unquoted values) and the Java Dockerfile hardcoded the wrong backend address.

2. **Stale Docker References (Plan #15)** — `docker-compose.yml` baked `VITE_API_URL: "http://localhost:8001"` into the frontend image build args (overriding the correct `/api` default), routing all API traffic to `localhost` inside the frontend container. `application.properties` hardcoded a Docker-only absolute SQLite path (`/app/data/holds.db`), and `java-service` was hidden behind a `profiles: [hold-service]` gate, silently omitting it from `docker compose up`.

3. **Flights Page `.map` Crash (Plan #16)** — After fixing the stale references, navigating to `/flights` threw `Uncaught TypeError: G.map is not a function`. nginx's variable-based `proxy_pass` did not reliably strip the `/api/` prefix, so the backend sometimes received `/api/flights` instead of `/flights`. `root_path="/api"` baked into `FastAPI(...)` added a version-sensitive path-stripping side-effect. The frontend had no defensive guard against non-array API responses.

4. **holds.db Local Path Failure (Plan #17)** — In local mode (`start_locally.sh`), the Java hold service fell back to the Docker-only `jdbc:sqlite:/app/data/holds.db` path (which does not exist on a developer's machine), silently failing to open or create the database.

---

## Observed Symptoms

- ✗ **Ubuntu: backend crashes immediately on Docker mode start** — `psycopg.OperationalError: failed to resolve host 'postgres': Temporary failure in name resolution`. Stack exits; no services reachable.
- ✗ **Debian: stack starts but all data calls return empty** — Frontend loads but flights, bookings, and all API data are absent. Backend was silently using SQLite instead of Postgres.
- ✗ **Debian: Java→Python link broken** — Java hold service sent requests to `http://python-backend:8000` (wrong service name and port) because the Dockerfile baked in an incorrect default.
- ✗ **Frontend API calls go nowhere in Docker mode** — Every `fetch('/api/...')` resolved to `http://localhost:8001` inside the frontend container, which is the container's own loopback, not the backend.
- ✗ **Java Hold Service not started by default** — A plain `docker compose up` silently omitted `java-service` due to the `profiles: [hold-service]` gate, causing all quote/hold flows to fail with no error.
- ✗ **`holds.db` path mismatch in Docker** — The `application.properties` SQLite path (`./holds.db`) resolved to `/app/holds.db` but the volume mounted `java_data` at `/app/data` — the DB was created outside the volume and lost on restart.
- ✗ **Flights page JS crash** — `Uncaught TypeError: G.map is not a function` thrown in the browser when navigating to `/flights`.
- ✗ **nginx forwarded `/api/flights` instead of `/flights`** — Variable-based `proxy_pass $backend_upstream/;` did not reliably strip the `/api/` prefix, causing 404s from the backend.
- ✗ **`root_path="/api"` caused version-sensitive path stripping** — `FastAPI(root_path="/api")` created a fragile interaction with nginx: in some Starlette versions it silently corrected the wrong path; in others it did nothing, masking rather than fixing the bug.
- ✗ **`holds.db` inaccessible in local mode** — `start_locally.sh` passed no `SPRING_DATASOURCE_URL` override to the Java process, so it used the Docker-only absolute path (`/app/data/holds.db`), which does not exist locally.

---

## Root Causes & Fixes

### Bug #1 — `sg docker` subshell diverges Docker network context on Ubuntu `[Critical]`

**Location:** `setup.sh` — Docker group handling (around line 567)

**Cause:** When the user was not yet in the docker group, `setup.sh` ran `exec sg docker -c "docker compose --profile hold-service up --build"`. `sg` opens a new login shell which can inherit a different Docker context or network namespace, causing the backend container to land on the default bridge network instead of the Compose project network. The `postgres` hostname is only resolvable within the project-scoped network.

**Fix:** Replaced `exec sg docker -c "..."` with `exec sudo -E -g docker docker compose up --build`. `sudo -E` preserves the current environment; `-g docker` applies the group membership in-process without spawning a divergent subshell.

**Code location:** [`setup.sh` lines 567–568](setup.sh:567)

---

### Bug #2 — `DATABASE_URL` not reaching backend on Debian due to unquoted Compose values `[Major]`

**Location:** `docker-compose.yml` — all `environment:` blocks

**Cause:** Docker Compose v1 (shipped in some Debian apt packages) can misparse bare string values containing colons or slashes — exactly the characters in `DATABASE_URL`, `CORS_ORIGINS`, `JAVA_SERVICE_URL`, and other URL env vars. On Debian, the backend received an empty or truncated `DATABASE_URL` and silently fell back to SQLite.

**Fix:** Quoted all environment variable values in `docker-compose.yml` (e.g. `DATABASE_URL: "postgresql://..."`, `VITE_API_URL: "..."`, `SPRING_DATASOURCE_URL: "..."`).

**Code location:** [`docker-compose.yml`](docker-compose.yml) — all `environment:` blocks

---

### Bug #3 — Java Dockerfile hardcodes wrong backend address `[Major]`

**Location:** `booking_system_inventory_hold_service/Dockerfile` line 34

**Cause:** `ENV PYTHON_BACKEND_URL=http://python-backend:8000` — the Compose service name is `backend` (not `python-backend`) and the port is `8080` (not `8000`). While `docker-compose.yml` overrides this env var, on some Docker versions the baked-in `ENV` instruction can take precedence, leaving the Java service unable to reach the Python backend.

**Fix:** Changed the Dockerfile default to `ENV PYTHON_BACKEND_URL=http://backend:8080`.

**Code location:** [`booking_system_inventory_hold_service/Dockerfile:34`](booking_system_inventory_hold_service/Dockerfile:34)

---

### Bug #4 — `VITE_API_URL` build arg override routed all frontend API traffic to localhost `[Critical]`

**Location:** `docker-compose.yml` — `frontend.build.args` block (lines 57–60)

**Cause:** `VITE_API_URL: "http://localhost:8001"` was passed as a build arg, overriding the frontend Dockerfile's correct default (`ARG VITE_API_URL=/api`). The value was baked into the JS bundle at image build time. Inside the running frontend container, `localhost` resolves to the container's own loopback — the backend is not there. All API calls went into a void.

**Fix:** Removed the `args:` block from `frontend.build` in `docker-compose.yml`, restoring the Dockerfile's `/api` default. nginx's existing `/api/` location proxies all such requests to `http://backend:8080`.

**Code location:** [`docker-compose.yml` lines 57–60](docker-compose.yml:57)

---

### Bug #5 — `application.properties` SQLite path resolves outside the Docker volume `[Major]`

**Location:** `booking_system_inventory_hold_service/src/main/resources/application.properties` line 6

**Cause:** `spring.datasource.url=jdbc:sqlite:./holds.db` resolves to `/app/holds.db` (the container's `WORKDIR`). The Docker volume mounts `java_data` at `/app/data`. In scenarios where the `SPRING_DATASOURCE_URL` env var override was not applied (direct `docker run`, or certain Compose versions), the DB was created at the wrong path, outside the volume, and lost on restart.

**Fix:** Changed the `application.properties` default to `spring.datasource.url=jdbc:sqlite:/app/data/holds.db` to match the volume mount, eliminating the mismatch in all launch scenarios.

**Code location:** [`booking_system_inventory_hold_service/src/main/resources/application.properties:6`](booking_system_inventory_hold_service/src/main/resources/application.properties:6)

---

### Bug #6 — `profiles: [hold-service]` silently omitted `java-service` from `docker compose up` `[Major]`

**Location:** `docker-compose.yml` — `java-service` definition line 38

**Cause:** `java-service` was gated behind the `hold-service` profile. A plain `docker compose up` silently omitted it, causing all quote and hold flows to fail with no error message. `setup.sh` worked around this by always passing `--profile hold-service`, but the profile gate itself was the wrong default.

**Fix:** Removed `profiles: [hold-service]` from the `java-service` definition in `docker-compose.yml`. Removed the now-redundant `--profile hold-service` flags from `setup.sh`'s Docker mode launch invocations. `AGENTS.md`'s footgun note updated to reflect the new default-on behaviour.

**Code location:** [`docker-compose.yml:38`](docker-compose.yml:38), [`setup.sh` lines 568, 570](setup.sh:568)

---

### Bug #7 — nginx variable-based `proxy_pass` did not reliably strip `/api/` prefix `[Critical]`

**Location:** `booking_system_frontend/nginx.conf` — `/api/` location block

**Cause:** After BOB-005 changed the proxy to use a variable (`set $backend_upstream http://backend:8080; proxy_pass $backend_upstream/;`) for deferred DNS resolution, nginx's URI prefix stripping became version-dependent. With a literal proxy URL the trailing slash guarantees stripping; with a variable it is unreliable. In some nginx versions the full original URI (`/api/flights`) was forwarded to the backend instead of the stripped path (`/flights`), causing 404s.

**Fix:** Added `rewrite ^/api/(.*) /$1 break;` as the first directive in the `/api/` location block, unconditionally stripping the prefix before proxy. Changed `proxy_pass $backend_upstream/;` to `proxy_pass $backend_upstream;` (trailing slash removed; the rewrite now produces the final path).

**Code location:** [`booking_system_frontend/nginx.conf` lines 25–36](booking_system_frontend/nginx.conf:25)

---

### Bug #8 — `root_path="/api"` in `FastAPI(...)` created a fragile version-sensitive side-effect `[Major]`

**Location:** `booking_system_backend/server.py` lines 44–50

**Cause:** `FastAPI(root_path="/api")` was added "for ALB routing" but is not the correct pattern. In some Starlette versions this caused incoming requests with path `/api/flights` to be routed as `/flights` (implicit stripping), masking the nginx bug. In others it did nothing. This made the system's behaviour version-sensitive and fragile across environments. After Bug #7's nginx fix, the backend always receives stripped paths and `root_path` at app level is not needed.

**Fix:** Removed `root_path="/api"` from the `FastAPI(...)` constructor. The ALB already strips `/api/` before forwarding to the target group; no app-level prefix is needed.

**Code location:** [`booking_system_backend/server.py:44`](booking_system_backend/server.py:44)

---

### Bug #9 — Frontend `Flights.tsx` crashed on non-array API response `[Minor]`

**Location:** `booking_system_frontend/src/pages/Flights.tsx` line 32

**Cause:** `setFlights(data)` was called unconditionally. If the API returned any non-array JSON (e.g. `{"detail": "Not Found"}`) with a 2xx status, `flights` became non-array and the subsequent `.map()` call threw `TypeError: G.map is not a function`, crashing the page.

**Fix:** Changed to `setFlights(Array.isArray(data) ? data : [])`. The page now shows "No flights found" gracefully instead of crashing when an unexpected response is received.

**Code location:** [`booking_system_frontend/src/pages/Flights.tsx:32`](booking_system_frontend/src/pages/Flights.tsx:32)

---

### Bug #10 — `requests` library not verified in backend container healthcheck `[Minor]`

**Location:** `booking_system_backend/requirements.txt`; `docker-compose.yml` healthcheck

**Cause:** The backend container healthcheck runs `python -c "import requests; requests.get('http://localhost:8080/', timeout=2)"`. If `requests` was absent from `requirements.txt`, the healthcheck would always exit non-zero, the container would never be marked `healthy`, and the frontend (which `depends_on: backend: condition: service_healthy`) would never start.

**Fix:** Verified `requests` is present in `requirements.txt`. No code change required.

**Code location:** [`booking_system_backend/requirements.txt`](booking_system_backend/requirements.txt)

---

### Bug #11 — `holds.db` inaccessible in local mode due to missing `SPRING_DATASOURCE_URL` override `[Major]`

**Location:** `scripts/local/start_locally.sh` line 161

**Cause:** `application.properties` defaults to `jdbc:sqlite:/app/data/holds.db` — an absolute path that only exists inside the Docker container. `start_locally.sh` launched the Java service without injecting `SPRING_DATASOURCE_URL`, so the Java process used the Docker-only default, could not create or open the database file on the developer's machine, and silently failed. The committed `holds.db` artefact in the service directory was never reached.

**Fix:** Prepended `SPRING_DATASOURCE_URL=jdbc:sqlite:./holds.db` to the Java service launch line in `start_locally.sh`, mirroring the existing `PYTHON_BACKEND_URL` pattern on the same line. This overrides the Docker-only absolute path with a relative path that resolves to `booking_system_inventory_hold_service/holds.db`.

**Code location:** [`scripts/local/start_locally.sh:161`](scripts/local/start_locally.sh:161)

---

## Remediation Steps (in order applied)

| # | Step | Bug Fixed |
|---|------|-----------|
| 1 | Fixed `booking_system_inventory_hold_service/Dockerfile` line 34: `http://python-backend:8000` → `http://backend:8080` | #3 |
| 2 | Quoted all environment variable values in `docker-compose.yml` | #2 |
| 3 | Replaced `exec sg docker -c "..."` with `exec sudo -E -g docker docker compose up --build` in `setup.sh` | #1 |
| 4 | Verified `requests` is in `booking_system_backend/requirements.txt` | #10 |
| 5 | Removed `VITE_API_URL: "http://localhost:8001"` `args:` block from `frontend.build` in `docker-compose.yml` | #4 |
| 6 | Changed `application.properties` line 6 to `spring.datasource.url=jdbc:sqlite:/app/data/holds.db` | #5 |
| 7 | Removed `profiles: [hold-service]` from `java-service` in `docker-compose.yml`; removed `--profile hold-service` flags from `setup.sh`; updated `AGENTS.md` | #6 |
| 8 | Added `rewrite ^/api/(.*) /$1 break;` and removed trailing slash from `proxy_pass` in `nginx.conf` | #7 |
| 9 | Removed `root_path="/api"` from `FastAPI(...)` in `server.py` | #8 |
| 10 | Changed `setFlights(data)` to `setFlights(Array.isArray(data) ? data : [])` in `Flights.tsx` | #9 |
| 11 | Added `SPRING_DATASOURCE_URL=jdbc:sqlite:./holds.db` to Java launch line in `start_locally.sh` | #11 |

---

## Change Summary

| File | Change | Bug Fixed |
|------|--------|-----------|
| `setup.sh` | `exec sg docker -c "..."` → `exec sudo -E -g docker docker compose up --build` | #1 |
| `docker-compose.yml` | Quoted all environment variable values | #2 |
| `booking_system_inventory_hold_service/Dockerfile` | `ENV PYTHON_BACKEND_URL=http://python-backend:8000` → `http://backend:8080` | #3 |
| `docker-compose.yml` | Removed `args: VITE_API_URL: "http://localhost:8001"` from `frontend.build` | #4 |
| `application.properties` | `jdbc:sqlite:./holds.db` → `jdbc:sqlite:/app/data/holds.db` | #5 |
| `docker-compose.yml` | Removed `profiles: [hold-service]` from `java-service` | #6 |
| `setup.sh` | Removed `--profile hold-service` from Docker mode launch commands | #6 |
| `AGENTS.md` | Updated footgun note — `java-service` now starts by default | #6 |
| `booking_system_frontend/nginx.conf` | Added `rewrite ^/api/(.*) /$1 break;`; removed trailing slash from `proxy_pass` | #7 |
| `booking_system_backend/server.py` | Removed `root_path="/api"` from `FastAPI(...)` constructor | #8 |
| `booking_system_frontend/src/pages/Flights.tsx` | `setFlights(data)` → `setFlights(Array.isArray(data) ? data : [])` | #9 |
| `scripts/local/start_locally.sh` | Added `SPRING_DATASOURCE_URL=jdbc:sqlite:./holds.db` to Java launch line | #11 |

---

## Final State

All 11 bugs are resolved. Docker mode (`./setup.sh` Option 1) runs cleanly on fresh Ubuntu and Debian machines:

- Backend connects to Postgres (no more DNS resolution failure on Ubuntu).
- Frontend API calls route correctly through nginx to the local `backend` container (no more `localhost` void).
- All four services (`postgres`, `backend`, `java-service`, `frontend`) start by default on `docker compose up`.
- The Java hold service persists `holds.db` inside the mounted volume at `/app/data/holds.db`.
- The Flights page renders without a `.map` crash.
- nginx path stripping is explicit and version-stable via `rewrite`.
- `root_path` is no longer baked into the FastAPI app.

Local mode (`./setup.sh` Option 2) is also fixed: the Java hold service now opens `holds.db` from its working directory instead of failing silently with the Docker-only absolute path.

---

*Made with IBM Bob*
