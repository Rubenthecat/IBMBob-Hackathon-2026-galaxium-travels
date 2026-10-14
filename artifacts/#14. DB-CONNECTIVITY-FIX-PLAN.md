# Database Connectivity Fix Plan

## Top-Level Overview

Two Linux environments fail to reach the databases when running via `./setup.sh` in Docker mode:

1. **Ubuntu** — backend container crashes immediately with `psycopg.OperationalError: failed to resolve host 'postgres'`. The backend cannot see the Postgres container at all so the entire stack exits.
2. **Debian** — stack starts and both frontend and backend are reachable in a browser, but all data calls return no results. The root cause is that `db.py` silently falls back to SQLite when `DATABASE_URL` is absent _and_ the Java hold-service Dockerfile hardcodes the wrong backend hostname/port so the Java→Python link is also broken.

The fix spans three files: `docker-compose.yml`, `booking_system_inventory_hold_service/Dockerfile`, and `setup.sh`. No application logic changes are needed.

---

## Root-Cause Analysis

### Ubuntu: DNS resolution failure for `postgres`

The error trace ends at:
```
psycopg.OperationalError: failed to resolve host 'postgres': Temporary failure in name resolution
```

`docker-compose.yml` defines a `postgres` service and passes
`DATABASE_URL: postgresql://...@postgres:5432/...` to the backend.
Docker Compose normally auto-creates a bridge network and makes service names
resolvable by DNS inside that network.  The resolution failure means the backend
container is **not on that network** when it tries to connect.

The likely trigger: `setup.sh` detects that `docker info` fails (user not yet in
the docker group), sets `_USE_SUDO_DOCKER=true`, and runs the compose command via
`sg docker -c "docker compose --profile hold-service up --build"`.
`sg` opens a **new shell** with the docker group active but inherits the
**current working directory and environment** from the calling shell.
The problem is that `exec sg docker -c ...` replaces the current process; if the
sg shell's PATH or Docker context differs slightly, Compose may launch on the
**default** bridge network instead of the project-scoped network, or create
two separate network namespaces. The backend container then cannot resolve the
`postgres` hostname provided by the project network.

The definitive fix is to replace `sg ... exec` with `sudo -E -g docker docker compose ...`
which is the documented pattern for applying group membership in the current
session without spawning a subshell that can diverge in environment.

Additionally, the `depends_on: postgres: condition: service_healthy` is
correct, but the backend healthcheck itself (`import requests; requests.get(...)`)
requires the `requests` library to be importable inside the container. If
`requests` is not in `requirements.txt` the healthcheck is always `unhealthy`
and dependent services never start. This should be verified.

### Debian: No database response (silent SQLite fallback)

On Debian the stack starts because Docker's network setup works (user is already
in the docker group or Docker Desktop handles it), but all data queries return empty
or fail silently. There are two causes:

**Cause A — DATABASE_URL not reaching the backend container**

`docker-compose.yml` line 24 sets `DATABASE_URL` correctly. If Debian uses an
older Docker Compose v1 binary (`docker-compose` instead of `docker compose`)
the `environment:` block is processed differently and string values without quotes
can be misinterpreted. The fix is to quote all environment values in
`docker-compose.yml`.

**Cause B — Java Dockerfile hardcodes wrong backend address**

`booking_system_inventory_hold_service/Dockerfile` line 34:
```dockerfile
ENV PYTHON_BACKEND_URL=http://python-backend:8000
```
The service name in `docker-compose.yml` is `backend` (not `python-backend`) and
it listens on port `8080` (not `8000`). `docker-compose.yml` overrides this to
the correct value (`http://backend:8080`), but the Dockerfile default is the
fallback used when the image is run outside of Compose (e.g. `docker run`), and
on some Docker versions the Compose override does not fully replace a baked-in
`ENV` instruction. Correcting the Dockerfile removes the ambiguity entirely.

---

## Sub-Tasks

---

### Sub-Task 1 — Fix Java Dockerfile default `PYTHON_BACKEND_URL`

**Intent**  
Remove the incorrect fallback hostname from the Java service Dockerfile so it
matches the actual Docker Compose service name and port. Even though
`docker-compose.yml` overrides this env var, an incorrect Dockerfile default is
a latent bug and, on some Docker versions, can take precedence.

**Expected Outcomes**  
- `booking_system_inventory_hold_service/Dockerfile` line 34 reads  
  `ENV PYTHON_BACKEND_URL=http://backend:8080`  
- Rebuilding the image with `docker compose build java-service` succeeds.  
- `docker inspect` on the java-service container shows `PYTHON_BACKEND_URL=http://backend:8080`.

**Todo List**  
- [ ] Edit `booking_system_inventory_hold_service/Dockerfile` line 34:  
      change `http://python-backend:8000` → `http://backend:8080`

**Relevant Context**  
- File: `booking_system_inventory_hold_service/Dockerfile:34`  
- Compose override: `docker-compose.yml:44` (`PYTHON_BACKEND_URL: http://backend:8080`)

**Status** `[x] done`

---

### Sub-Task 2 — Quote environment variable values in `docker-compose.yml`

**Intent**  
Wrap all environment variable values in `docker-compose.yml` in double quotes.
Older Docker Compose versions (v1, shipped with some Debian/Ubuntu apt
packages) can misparse bare string values containing colons or slashes —
exactly the characters present in `DATABASE_URL` and the URL env vars.
Quoting eliminates this class of parsing bug.

**Expected Outcomes**  
- All `environment:` values in `docker-compose.yml` are quoted strings.  
- `docker compose config` output matches the intended values verbatim on both
  Debian and Ubuntu.

**Todo List**  
- [ ] In `docker-compose.yml`, quote all bare environment values (e.g.  
      `DATABASE_URL: "postgresql://..."`, `CORS_ORIGINS: "http://..."`,  
      `JAVA_SERVICE_URL: "http://..."`, `SEED_DEMO_DATA: "true"`,  
      `PYTHON_BACKEND_URL: "http://..."`, `SPRING_DATASOURCE_URL: "jdbc:..."`,  
      `VITE_API_URL: "http://..."`)

**Relevant Context**  
- File: `docker-compose.yml`  
- Docker Compose v1 vs v2 parsing: YAML bare strings with `:` after a non-space
  character are valid YAML but v1 had known bugs with connection-string values.

**Status** `[x] done`

---

### Sub-Task 3 — Fix `setup.sh` Docker group handling on Ubuntu

**Intent**  
Replace the `sg docker -c "..."` invocation with `sudo -E -g docker` so that
the compose command is run with the docker group in the current session without
spawning a divergent subshell. `sg` opens a new login-shell environment which
can cause Docker's networking context to differ from the one the user established,
leading to containers landing on different networks and the `postgres` hostname
becoming unresolvable.

**Expected Outcomes**  
- On Ubuntu, when the user is not yet in the docker group, `./setup.sh` runs  
  `sudo -E -g docker docker compose --profile hold-service up --build`  
  instead of `exec sg docker -c "docker compose ..."`.  
- The backend container resolves the `postgres` hostname successfully and the
  stack starts without DNS errors.

**Todo List**  
- [ ] In `setup.sh`, locate the block where `_USE_SUDO_DOCKER=true` triggers  
      `exec sg docker -c "docker compose --profile hold-service up --build"`  
      (around line 567-568).  
- [ ] Replace that branch with:  
      `exec sudo -E -g docker docker compose --profile hold-service up --build`  
- [ ] Verify the non-sudo branch (line 569-571) is unchanged.

**Relevant Context**  
- File: `setup.sh:548-571`  
- `sudo -E` preserves the current environment; `-g docker` sets the supplemental
  group without opening a new shell.

**Status** `[x] done`

---

### Sub-Task 4 — Verify `requests` library is in backend requirements

**Intent**  
The backend container's Docker healthcheck runs  
`python -c "import requests; requests.get('http://localhost:8080/', timeout=2)"`.  
If `requests` is absent from `requirements.txt`, the healthcheck always exits
non-zero, the container is never marked `healthy`, and the `frontend` service
(which `depends_on: backend: condition: service_healthy`) never starts. This is
a pre-condition check, not a code change — but it must be confirmed before the
other fixes can be tested end-to-end.

**Expected Outcomes**  
- `requests` (or `httpx` with an alias) is present in  
  `booking_system_backend/requirements.txt`.  
- If missing, add `requests` to `requirements.txt`.

**Todo List**  
- [ ] Read `booking_system_backend/requirements.txt`.  
- [ ] If `requests` is not listed, add it.

**Relevant Context**  
- File: `booking_system_backend/requirements.txt`  
- Healthcheck definition: `docker-compose.yml:32`

**Status** `[x] done`

---

## Implementation Order

```
Sub-Task 4  (verify requirements — cheapest check, unblocks healthcheck)
    ↓
Sub-Task 1  (fix Java Dockerfile — isolated single-line change)
    ↓
Sub-Task 2  (quote docker-compose.yml env vars — fixes Debian parsing)
    ↓
Sub-Task 3  (fix setup.sh sg → sudo -E -g — fixes Ubuntu DNS)
```

After all four are applied, test with:
```bash
./setup.sh   # choose Docker mode
# On Ubuntu: should start without DNS errors
# On Debian:  backend logs should show "Connected to postgresql://..." not SQLite
```
