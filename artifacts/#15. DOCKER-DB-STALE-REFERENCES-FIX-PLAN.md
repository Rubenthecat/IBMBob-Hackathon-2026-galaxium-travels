# Docker DB Stale References Fix Plan

## Top-Level Overview

When running `./setup.sh` in Docker mode on Linux, three stale/hardcoded values prevent the application from working correctly:

1. **`docker-compose.yml` passes `VITE_API_URL: "http://localhost:8001"` as a build arg** — this value is baked into the production JavaScript bundle at image build time. Inside the frontend container, `localhost` resolves to the container's own loopback interface, not the host or backend container. The frontend therefore sends every API request into a void and never reaches the backend. The fix already exists in the frontend `Dockerfile` (line 14: `ARG VITE_API_URL=/api`) — the compose file simply must not override it with the broken localhost value.

2. **`application.properties` hardcodes `spring.datasource.url=jdbc:sqlite:./holds.db`** — this relative path resolves to `/app/holds.db` inside the Java container's working directory. The Docker Compose volume, however, mounts `java_data` at `/app/data`. If the container starts without the `SPRING_DATASOURCE_URL` env var (e.g. `docker run` without `-e`, or the env block being stripped in certain compose versions), the database is created at the wrong path, outside the volume, and is lost on restart. The `application.properties` value should be updated to match the intended `/app/data/holds.db` path to remove this ambiguity permanently.

3. **`java-service` is gated behind `profiles: [hold-service]` in `docker-compose.yml`** — this means a plain `docker compose up` silently omits the Java hold service. The profile must be explicitly activated via `--profile hold-service`. This is a footgun: the service appears configured in the compose file but does not start, causing all quote/hold flows to silently fail. The Java service should start implicitly alongside the other services. `setup.sh` already works around this by appending `--profile hold-service` to every compose invocation, but the correct fix is to remove the profile gate from `docker-compose.yml` itself and clean up the workaround from `setup.sh`.

These are targeted, minimal changes — no architecture changes and no application logic changes are required.

---

## Sub-Tasks

---

### Sub-Task 1 — Remove the `VITE_API_URL` build arg override from `docker-compose.yml`

**Status:** `[x] done`

**Intent**

The frontend `Dockerfile` already defaults `VITE_API_URL` to `/api` (line 14), which is correct: the nginx config proxies all `/api/` requests to the `backend` container on the Docker Compose internal network. The `docker-compose.yml` build args block (lines 57–60) overrides this correct default with `"http://localhost:8001"`, which resolves to the frontend container's own loopback at runtime — the backend is not there. Removing the override restores the Dockerfile's correct default.

**Expected Outcomes**
- The frontend container's JS bundle has `baseURL = '/api'`, not `http://localhost:8001`
- All API calls from the browser are sent as same-origin `/api/...` requests
- nginx proxies those to `http://backend:8080` via the compose network
- Data loads correctly in the browser when the stack is started with `./setup.sh` in Docker mode

**Todo List**
- [ ] In `docker-compose.yml`, remove the `args:` block under `frontend.build` (lines 59–60 — the `VITE_API_URL: "http://localhost:8001"` line and its `args:` parent key if it becomes empty), leaving `build: context: ./booking_system_frontend` as a simple context-only build directive
- [ ] Confirm the `frontend.build` section has no remaining `args:` key after the edit

**Relevant Context**
- [`docker-compose.yml` lines 56–60](docker-compose.yml:56) — current `frontend.build` block
- [`booking_system_frontend/Dockerfile` line 14](booking_system_frontend/Dockerfile:14) — `ARG VITE_API_URL=/api` (the correct default)
- [`booking_system_frontend/src/services/api.ts` line 15](booking_system_frontend/src/services/api.ts:15) — `baseURL: import.meta.env.VITE_API_URL || '/api'`
- [`booking_system_frontend/nginx.conf` lines 25–27](booking_system_frontend/nginx.conf:25) — `/api/` location proxies to `http://backend:8080`

---

### Sub-Task 2 — Fix `application.properties` SQLite path to match the volume mount

**Status:** `[x] done`

**Intent**

`booking_system_inventory_hold_service/src/main/resources/application.properties` line 6 sets `spring.datasource.url=jdbc:sqlite:./holds.db`. This relative path resolves to `/app/holds.db` at runtime (the container's `WORKDIR` is `/app`). The volume mount in `docker-compose.yml` and the `SPRING_DATASOURCE_URL` env var both point to `/app/data/holds.db`. While Spring Boot's relaxed binding should allow the env var to override the property, updating `application.properties` to use the correct absolute path `/app/data/holds.db` eliminates the mismatch permanently and ensures correct behavior regardless of how the container is launched.

**Expected Outcomes**
- `application.properties` reads `spring.datasource.url=jdbc:sqlite:/app/data/holds.db`
- The Java hold service creates and reads `holds.db` inside the `/app/data` directory in all launch scenarios (compose, `docker run`, local dev via `mvn spring-boot:run` with override)
- The `java_data` Docker volume persists the database across container restarts
- `docker inspect` on the java-service container shows the database file at `/app/data/holds.db`

**Todo List**
- [ ] In `booking_system_inventory_hold_service/src/main/resources/application.properties` line 6, change `spring.datasource.url=jdbc:sqlite:./holds.db` to `spring.datasource.url=jdbc:sqlite:/app/data/holds.db`

**Relevant Context**
- [`booking_system_inventory_hold_service/src/main/resources/application.properties` line 6](booking_system_inventory_hold_service/src/main/resources/application.properties:6) — the stale relative path
- [`booking_system_inventory_hold_service/Dockerfile` line 33](booking_system_inventory_hold_service/Dockerfile:33) — `ENV SPRING_DATASOURCE_URL=jdbc:sqlite:/app/data/holds.db` (the correct path)
- [`docker-compose.yml` line 45](docker-compose.yml:45) — `SPRING_DATASOURCE_URL: "jdbc:sqlite:/app/data/holds.db"` (the correct path)
- [`docker-compose.yml` line 54](docker-compose.yml:54) — `volumes: - java_data:/app/data` (the volume mount)
- **Note for local dev:** When running `mvn spring-boot:run` locally (without Docker), the path `/app/data/holds.db` will not exist. Local developers must pass `-Dspring.datasource.url=jdbc:sqlite:./holds.db` or set `SPRING_DATASOURCE_URL=jdbc:sqlite:./holds.db` in their shell. The README or `start_locally.sh` should note this. The `scripts/local/start_locally.sh` already passes `SPRING_DATASOURCE_URL` overrides, so local dev is unaffected.

---

### Sub-Task 3 — Remove the `profiles: [hold-service]` gate from `java-service` and clean up `setup.sh`

**Status:** `[x] done`

**Intent**

`docker-compose.yml` line 38 places `java-service` behind the `hold-service` profile. A plain `docker compose up` therefore silently omits it, breaking all quote and hold flows without any error message. The profile was originally added to make the Java service opt-in, but `setup.sh` has been manually working around this with `--profile hold-service` on every invocation. The correct fix is to remove the profile gate entirely so the service starts as part of the default stack, and then remove the now-redundant `--profile hold-service` flags from `setup.sh`. The `e2e/docker-compose.e2e.yml` already omits the profile on its `java-service` definition, establishing the correct pattern.

**Expected Outcomes**
- `docker compose up` (no flags) starts all four services: `postgres`, `backend`, `java-service`, and `frontend`
- `docker compose up --build` behaves identically
- `setup.sh` Docker mode invocation no longer passes `--profile hold-service`
- `AGENTS.md` footgun note about the profile is updated to reflect the new default-on behaviour

**Todo List**
- [ ] In `docker-compose.yml`, remove line 38 (`profiles: [hold-service]`) from the `java-service` definition
- [ ] In `setup.sh`, change both compose invocations (lines 568 and 570) from `docker compose --profile hold-service up --build` to `docker compose up --build`
- [ ] In `AGENTS.md`, update the footgun note (line 23) that says the Java service is behind a profile — it is no longer profile-gated; update to reflect that `docker compose up` now starts it by default

**Relevant Context**
- [`docker-compose.yml` line 38](docker-compose.yml:38) — `profiles: [hold-service]`
- [`setup.sh` lines 568, 570](setup.sh:568) — `--profile hold-service` flags in both the sudo and non-sudo branches
- [`e2e/docker-compose.e2e.yml` lines 29–46](e2e/docker-compose.e2e.yml:29) — `java-service` with no profile (correct pattern to follow)
- [`AGENTS.md` line 23](AGENTS.md:23) — footgun note referencing the profile

---

## Implementation Order

```
Sub-Task 3  (remove profile gate — java-service now starts by default)
    ↓
Sub-Task 1  (remove VITE_API_URL override — fixes frontend→backend communication)
    ↓
Sub-Task 2  (fix application.properties SQLite path — fixes holds DB persistence)
```

After all three are applied, test with:
```bash
./setup.sh   # choose Docker mode
# Open http://localhost:5173 in a browser
# Flights should load (backend→postgres connected)
# Quote/Hold flow should work (java-service started by default, DB at /app/data/holds.db)
```
