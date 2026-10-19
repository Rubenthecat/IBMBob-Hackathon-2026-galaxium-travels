# Plan: Fix holds.db Path for Local Mode

## Top-Level Overview

**Goal:** Make `holds.db` accessible in local mode (via `setup.sh` → `start.sh`) the same way `booking.db` is accessible.

**Root Cause:** The Java hold service's `application.properties` hard-codes the SQLite path as `jdbc:sqlite:/app/data/holds.db` — an absolute path that only exists inside the Docker container (`/app/data/` is created in the Dockerfile and mounted via a Docker named volume). When running locally, this path does not exist on the developer's machine, so SQLite cannot open or create the database file.

The Python backend avoids this problem by using a *relative* path (`sqlite:///./booking.db` in `db.py`) and never hard-coding an absolute path in the base config. `start_locally.sh` also never injects `SPRING_DATASOURCE_URL` into the Java process, so the Java service always falls back to the Docker-only hard-coded path when run locally.

**Scope:** One-line change to `scripts/local/start_locally.sh`. No Java source changes needed.

**Non-goals:** No changes to Docker mode, `docker-compose.yml`, `application.properties` (Docker path stays as default), or any Python backend files.

---

## Sub-Tasks

### Sub-Task 1 — Pass `SPRING_DATASOURCE_URL` in local startup script

**Intent:**  
Inject `SPRING_DATASOURCE_URL` as an environment variable when launching the Java hold service in local mode, mirroring how `PYTHON_BACKEND_URL` is already injected on the same line. This overrides the Docker-specific absolute path with a local relative path, exactly the same strategy used by `docker-compose.yml` line 44 to override the path in Docker mode.

**Expected Outcomes:**
- In local mode, SQLite creates/opens `holds.db` inside `booking_system_inventory_hold_service/holds.db` (the service's working directory), which is a committed artefact that already seeds local dev.
- In Docker mode, `docker-compose.yml` continues to set `SPRING_DATASOURCE_URL=jdbc:sqlite:/app/data/holds.db`, so Docker mode is unaffected.
- The Java service starts successfully in local mode and the health check passes.

**Todo List:**
1. Open `scripts/local/start_locally.sh`.
2. Locate line 161 where the Java service is launched:
   ```
   JAVA_HOME="${JAVA_HOME_FOR_MAVEN:-$JAVA_HOME}" PYTHON_BACKEND_URL=http://localhost:8001 $HOLD_SERVICE_CMD > java.log 2>&1 &
   ```
3. Prepend `SPRING_DATASOURCE_URL=jdbc:sqlite:./holds.db` to the env variable list on that same line:
   ```
   JAVA_HOME="${JAVA_HOME_FOR_MAVEN:-$JAVA_HOME}" PYTHON_BACKEND_URL=http://localhost:8001 SPRING_DATASOURCE_URL=jdbc:sqlite:./holds.db $HOLD_SERVICE_CMD > java.log 2>&1 &
   ```
4. Save the file. No other changes needed.

**Relevant Context:**
- `scripts/local/start_locally.sh` line 161 — Java service launch command
- `booking_system_inventory_hold_service/src/main/resources/application.properties` line 6 — the Docker-only default path being overridden
- `docker-compose.yml` line 44 — proof this override strategy works (Docker already uses it)
- `booking_system_backend/db.py` line 11 — the relative-path pattern that works for `booking.db`
- `booking_system_inventory_hold_service/holds.db` — committed artefact that already exists for local dev

**Status:** [x] done

---

## Why This Is the Minimal Fix

| | booking.db (works) | holds.db (broken → fixed) |
|---|---|---|
| Base config | `sqlite:///./booking.db` (relative) | `jdbc:sqlite:/app/data/holds.db` (absolute, Docker-only) |
| Local override | None needed — relative path just works | Add `SPRING_DATASOURCE_URL=jdbc:sqlite:./holds.db` in `start_locally.sh` |
| Docker override | `DATABASE_URL` in `docker-compose.yml` | `SPRING_DATASOURCE_URL` in `docker-compose.yml` (already present, line 44) |

The change is a single env var addition on one line of one shell script. It matches the existing pattern already used for `PYTHON_BACKEND_URL` on that same line.
