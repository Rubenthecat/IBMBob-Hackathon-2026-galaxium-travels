# Galaxium Travels — Architecture Analysis

## 1. Top-Level Overview

Galaxium Travels is a **multi-service, interplanetary flight-booking demo** composed of four runtime components:

| # | Component | Language / Framework | Port (local) | Port (Docker) |
|---|-----------|----------------------|--------------|---------------|
| 1 | **Backend** | Python 3.11 / FastAPI + Uvicorn | 8001 | 8080 (container) |
| 2 | **Java Hold Service** | Java 17 / Spring Boot 3 + Maven | 8080 | 8080 (container) |
| 3 | **Frontend** | React 19 + TypeScript + Vite / Nginx | 5173 | 8080 (container) |
| 4 | **Database** | PostgreSQL 14 (Docker) / SQLite (local/e2e) | 5432 | 5432 |

An **MCP server** is co-hosted inside the Backend (via `FastApiMCP`) and exposes every REST route as an AI-callable tool — no separate process needed.

---

## 2. Component Communication Map

```
                     ┌──────────────────────────────────────┐
                     │         BROWSER / AI CLIENT           │
                     │  React App (Vite dev or Nginx bundle) │
                     └────────────────┬─────────────────────┘
                                      │
                         /api/* (Vite proxy in dev)
                         /api/* (Nginx reverse-proxy in Docker)
                                      │
                     ┌────────────────▼─────────────────────────────────────────┐
                     │         PYTHON BACKEND  :8001 / :8080                    │
                     │  FastAPI + Uvicorn + FastApiMCP                           │
                     │                                                           │
                     │  Health      GET  /                                       │
                     │  Flights     GET  /flights                                │
                     │  Book        POST /book                                   │
                     │  Bookings    GET  /bookings/{user_id}                     │
                     │  Cancel      POST /cancel/{booking_id}                    │
                     │  Register    POST /register                               │
                     │  User        GET  /user                                   │
                     │  Internal    POST /internal/bookings/from-hold  ◄──────┐  │
                     │  Proxy   POST /quotes, GET /quotes/{id}          httpx  │  │
                     │  Proxy   POST /quotes/{id}/holds                  ──►──┐ │  │
                     │  Proxy   GET/POST /holds/{id}[/confirm|/release]       │ │  │
                     └──────────────────────────────┬────────────────────────┘ │  │
                                                    │                          │  │
                                 JAVA_SERVICE_URL   │                          │  │
                                 (httpx.AsyncClient)│                          │  │
                     ┌──────────────────────────────▼──────────────────────────┘  │
                     │         JAVA HOLD SERVICE  :8080 / :8082                   │
                     │  Spring Boot 3 + JPA + SQLite                              │
                     │                                                            │
                     │  Health   GET  /api/v1/health                              │
                     │  Quotes   POST /api/v1/quotes                              │
                     │           GET  /api/v1/quotes/{id}                         │
                     │  Holds    POST /api/v1/quotes/{id}/holds                   │
                     │           GET  /api/v1/holds/{id}                          │
                     │           POST /api/v1/holds/{id}/confirm   ──httpClient──►┘
                     │           POST /api/v1/holds/{id}/release                  │
                     │  Scheduler: expire stale holds every N seconds             │
                     └──────────────────────────────────────────────────────────-─┘
                                      │
                              PYTHON_BACKEND_URL
                              (Spring HttpClient)
                              POST /internal/bookings/from-hold
```

**Key data flows:**

1. **Direct booking path:** Frontend → `POST /book` (Backend) → SQLite/PostgreSQL  
2. **Hold-confirm path:** Frontend → `POST /quotes` (Backend proxy) → Java → `POST /quotes/{id}/holds` → `POST /holds/{id}/confirm` → Java calls Back `POST /internal/bookings/from-hold` → creates real Booking  
3. **MCP path:** AI agent → MCP tool (auto-generated from every FastAPI route) → same Backend handlers

---

## 3. Startup Orchestration Paths

### 3a. Local Development (`./start.sh` → `scripts/local/start_locally.sh`)

```
start.sh
  └─► scripts/local/start_locally.sh
        1. Kill existing processes on :8001, :5173, :8080
        2. Create Python venv (if missing) → pip install requirements.txt
        3. .venv/bin/python server.py                    → Backend  :8001
           └─ waits 3s → curl health check /
        4. Detect Java 17/21 (sdkman or $JAVA_HOME)
           mvn spring-boot:run  OR  java -jar target/*.jar
           env: PYTHON_BACKEND_URL=http://localhost:8001
                SPRING_DATASOURCE_URL=jdbc:sqlite:./holds.db
                                                         → Java     :8080
           └─ waits 8s → curl /api/v1/health
        5. npm install (if node_modules missing)
           npm run dev                                   → Frontend :5173
        6. SIGINT/SIGTERM → kill all three PIDs
```

### 3b. Docker Compose (`docker compose up`)

```
docker-compose.yml
  ├─ postgres       (depends_on: none)                  :5433→:5432
  │    healthcheck: pg_isready -U galaxium
  ├─ backend        (depends_on: postgres healthy)       :8001→:8080
  │    env: DATABASE_URL=postgresql://...@postgres:5432/...
  │         JAVA_SERVICE_URL=http://java-service:8080
  │         CORS_ORIGINS=http://localhost:5173,...
  │         SEED_DEMO_DATA=true
  ├─ java-service   (depends_on: backend)               :8082→:8080
  │    env: PYTHON_BACKEND_URL=http://backend:8080
  │         SPRING_DATASOURCE_URL=jdbc:sqlite:/app/data/holds.db
  └─ frontend       (depends_on: backend healthy)       :5173→:8080
       Nginx proxies /api/* → http://backend:8080/$1
       SPA routing: try_files → /index.html
```

### 3c. E2E Test Stack (`e2e/docker-compose.e2e.yml`)

```
e2e/docker-compose.e2e.yml         (no postgres → SQLite ephemeral)
  ├─ backend    :18001→:8080
  │    env: HOLD_DURATION_MINUTES=1, HOLD_EXPIRATION_CHECK_INTERVAL_SECONDS=5
  └─ java-service :18082→:8080
       env: same short timers
```

Also supports native execution via `e2e/run-native.sh`:
```
run-native.sh
  1. Create tmpdir for ephemeral SQLite DBs
  2. Backend: DATABASE_URL=sqlite:///$TMPDIR/booking.db   → :8001
  3. Java:    SPRING_DATASOURCE_URL=jdbc:sqlite:$TMPDIR/holds.db
              HOLD_DURATION_MINUTES=1
              HOLD_EXPIRATION_CHECK_INTERVAL_SECONDS=5    → :8080
  4. Create e2e venv → pip install → pytest
  5. EXIT trap: kill procs, rm tmpdir
```

### 3d. AWS Deployment (`scripts/aws/deploy-to-aws.sh`)

```
deploy-to-aws.sh
  1. Verify prerequisites: aws-cli, docker, terraform, jq
  2. terraform init → plan → apply
     └─ Creates: ECS cluster, ALB, ECR repos, RDS (optional), VPC, IAM
  3. Get Terraform outputs: ECR URLs, ALB URL, ECS cluster name
  4. docker build --platform linux/amd64 backend/frontend
  5. docker tag → ECR URL → docker push
  6. aws ecs update-service --force-new-deployment (backend, frontend)
  7. Poll: wait until runningCount ≥ 1 (60 × 5s)
  8. Smoke-test ALB: GET /api/, /health, /
```

### 3e. IBM Cloud Deployment (`scripts/ibm/deploy-to-ibm.sh`)

```
deploy-to-ibm.sh
  1. ibmcloud login --sso → target us-south
  2. ibmcloud ce project select/create
  3. Setup ICR namespace → docker login to icr.io
  4. Build + push: backend, java-service, frontend
  5. Create registry secret (once)
  6. Deploy apps to Code Engine:
       backend    CPU:0.25 Mem:0.5G  scale:0-3  public
       java-service CPU:0.5 Mem:1G   scale:0-3  project-internal
       frontend   CPU:0.25 Mem:0.5G  scale:0-3  public
  7. Update backend env: JAVA_SERVICE_URL=http://<java-app>
     Update backend env: CORS_ORIGINS=<frontend-public-url>
  8. Poll: wait for all apps Ready (30 × 5s)
```

---

## 4. Backend — Detailed Route & Handler Map

### Python Backend (`booking_system_backend/server.py`)

| Method | Path | Handler | Notes |
|--------|------|---------|-------|
| GET | `/` | `health_check()` | Returns `{"status": "OK"}` |
| GET | `/flights` | `flight.list_flights()` | 14 query filters + sort |
| POST | `/book` | `booking.book_flight()` | Validates user + name + seats |
| GET | `/bookings/{user_id}` | `booking.get_bookings()` | All bookings for a user |
| POST | `/cancel/{booking_id}` | `booking.cancel_booking()` | Restores seat count |
| POST | `/register` | `user.register_user()` | Validates email uniqueness |
| GET | `/user` | `user.get_user()` | Lookup by name + email |
| POST | `/internal/bookings/from-hold` | `booking.book_flight()` | Called only by Java service |
| POST | `/quotes` | proxy → Java `/api/v1/quotes` | httpx async pass-through |
| GET | `/quotes/{quote_id}` | proxy → Java | — |
| POST | `/quotes/{quote_id}/holds` | proxy → Java | — |
| GET | `/holds/{hold_id}` | proxy → Java | — |
| POST | `/holds/{hold_id}/confirm` | proxy → Java | — |
| POST | `/holds/{hold_id}/release` | proxy → Java | — |

All 14 routes are automatically exposed as **MCP tools** via `FastApiMCP(app).mount_http()`.

### Service Layer (`booking_system_backend/services/`)

| Module | Functions | Returns |
|--------|-----------|---------|
| `booking.py` | `book_flight`, `cancel_booking`, `get_bookings` | `BookingOut \| ErrorResponse` |
| `flight.py` | `list_flights` | `FlightOut[] \| ErrorResponse` |
| `user.py` | `register_user`, `get_user`, `update_user` | `UserOut \| ErrorResponse` |

**Pattern:** Services return `Union` types; callers check `isinstance(result, ErrorResponse)` — no exceptions raised for business-logic failures.

---

## 5. Java Hold Service — Detailed Route & Handler Map

| Method | Path | Controller | Logic |
|--------|------|-----------|-------|
| GET | `/api/v1/health` | HealthController | Returns `{"status":"UP"}` |
| POST | `/api/v1/quotes` | QuoteController | PricingService → generate Q-ID → save → audit |
| GET | `/api/v1/quotes/{id}` | QuoteController | Lookup or 404 |
| POST | `/api/v1/quotes/{id}/holds` | HoldController | Validate quote → generate H-ID → HELD → audit |
| GET | `/api/v1/holds/{id}` | HoldController | Lookup or 404 |
| POST | `/api/v1/holds/{id}/confirm` | HoldController | Validate HELD + not expired → PythonBackendClient → CONFIRMED |
| POST | `/api/v1/holds/{id}/release` | HoldController | Validate HELD → RELEASED |

**Hold lifecycle states:** `HELD → CONFIRMED | RELEASED | EXPIRED | CONFIRMATION_FAILED`

**Scheduler:** `HoldExpirationScheduler` runs every `HOLD_EXPIRATION_CHECK_INTERVAL_SECONDS` (default 60s); finds `reservedUntil < now` → sets EXPIRED → audits.

---

## 6. Frontend — Routing & API Surface

### Routes (`src/App.tsx`)

| Path | Component | Purpose |
|------|-----------|---------|
| `/` | `Home` | Welcome page, featured destinations |
| `/flights` | `Flights` | Search, filter, book flights |
| `/bookings` | `MyBookings` | User's bookings, cancel option |
| `/destinations/:slug` | `DestinationDetail` | Planet detail, related flights |
| `*` | `Home` | Fallback |

### API Calls (`src/services/api.ts`)

| Function | Method + Path | Returns |
|----------|---------------|---------|
| `getFlights(filters?)` | GET `/flights` | `Flight[]` |
| `registerUser(data)` | POST `/register` | `User \| ErrorResponse` |
| `getUserByCredentials` | GET `/user?name=&email=` | `User \| ErrorResponse` |
| `bookFlight(request)` | POST `/book` | `Booking \| ErrorResponse` |
| `getUserBookings(userId)` | GET `/bookings/{userId}` | `Booking[]` |
| `cancelBooking(bookingId)` | POST `/cancel/{bookingId}` | `Booking \| ErrorResponse` |
| `createQuote(data)` | POST `/quotes` | `Quote` |
| `getQuote(quoteId)` | GET `/quotes/{quoteId}` | `Quote` |
| `createHold(quoteId)` | POST `/quotes/{quoteId}/holds` | `Hold` |
| `getHold(holdId)` | GET `/holds/{holdId}` | `Hold` |
| `confirmHold(holdId)` | POST `/holds/{holdId}/confirm` | `Hold` |
| `releaseHold(holdId)` | POST `/holds/{holdId}/release` | `Hold` |

**API base:** `VITE_API_URL` env (defaults to `/api`)  
**Dev proxy:** Vite rewrites `/api/*` → `http://localhost:8001/*`  
**Docker proxy:** Nginx rewrites `/api/*` → `http://backend:8080/*`

---

## 7. Database Layout

### Python Backend DB (`booking.db` / PostgreSQL)

```
users          user_id PK, name, email UNIQUE
flights        flight_id PK, origin, destination, departure_time, arrival_time,
               base_price, economy_seats_available, business_seats_available,
               galaxium_seats_available
bookings       booking_id PK, user_id FK→users, flight_id FK→flights,
               status, booking_time, seat_class, price_paid
```

Seeded on startup when `SEED_DEMO_DATA=true` AND `users` table is empty:
- 10 users, 10 flights, 20 bookings

### Java Service DB (`holds.db` / SQLite)

```
quotes         quoteId PK, flightId, seatClass, quantity, travelerId,
               travelerName, pricePerSeat, totalPrice, expiresAt, status, createdAt
holds          holdId PK, quoteId, status, reservedUntil,
               externalBookingReference?, errorMessage?, createdAt, updatedAt
audit_events   auditEventId PK (auto), entityType, entityId,
               eventType, details, timestamp
```

Both databases are independent; they share data only via the `/internal/bookings/from-hold` API call.

---

## 8. Environment Variables — Master Reference

| Variable | Set In | Default | Used By |
|----------|--------|---------|---------|
| `DATABASE_URL` | docker-compose / deploy scripts | `sqlite:///./booking.db` | Backend (db.py) |
| `SEED_DEMO_DATA` | docker-compose | `"true"` | Backend (server.py lifespan) |
| `CORS_ORIGINS` | docker-compose / IBM script | `""` | Backend (CORS middleware) |
| `JAVA_SERVICE_URL` | docker-compose / IBM script | `http://localhost:8080` | Backend (proxy endpoints) |
| `PYTHON_BACKEND_URL` | docker-compose / Java Dockerfile | `http://localhost:8001` | Java (PythonBackendClient) |
| `SPRING_DATASOURCE_URL` | docker-compose / local script | `jdbc:sqlite:./holds.db` | Java (JPA) |
| `HOLD_DURATION_MINUTES` | e2e docker-compose / run-native | `15` | Java (HoldService) |
| `HOLD_EXPIRATION_CHECK_INTERVAL_SECONDS` | e2e / run-native | `60` | Java (Scheduler) |
| `VITE_API_URL` | build-time ARG in frontend Dockerfile | `/api` | Frontend (api.ts baseURL) |

---

## 9. Bob Lifecycle Hooks (`.bob/settings.json`)

| Event | Hook Script | Timeout | Purpose |
|-------|-------------|---------|---------|
| SessionStart | `preflight.sh` | 15s | Validate environment on startup |
| UserPromptSubmit | `inject-pending.sh` | 10s | Inject pending context |
| UserPromptSubmit | `record-prompt.sh` | 10s | Log prompt for audit |
| PreToolUse (execute_command) | `gate-commit.sh` | 60s | Block dangerous git commits |
| PostToolUse (any) | `record-tool.sh` | 10s | Log tool use |
| PostToolUse (write/edit) | `mypy-check.sh` | 30s | Run mypy after Python file edits |
| Stop | `session-receipt.sh` | 10s | Generate session summary |

---

## 10. Test Infrastructure

### Unit/Integration Tests (`booking_system_backend/tests/`)

| File | Scope |
|------|-------|
| `conftest.py` | In-memory SQLite fixtures, TestClient, seed bypass |
| `test_rest.py` | REST endpoint tests (HTTP request/response) |
| `test_services.py` | Service function logic tests |

**Critical detail:** `conftest.py` patches `SessionLocal` in **two places** — `db.SessionLocal` AND `server.SessionLocal` — to ensure MCP tools also use the test DB.

### E2E Tests (`e2e/`)

| File | Scope |
|------|-------|
| `test_smoke.py` | Basic backend health + booking flow |
| `test_holds.py` | Full quote→hold→confirm→booking cross-service flow |

Run via `e2e/run-native.sh` (native) or `docker compose -f e2e/docker-compose.e2e.yml up` (containerized).

---

## 11. Full Architecture Diagram (Text)

```
╔══════════════════════════════════════════════════════════════════╗
║                    GALAXIUM TRAVELS SYSTEM                        ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  ┌─────────────────────────────┐                                  ║
║  │   BROWSER / AI MCP CLIENT   │                                  ║
║  └──────────┬──────────────────┘                                  ║
║             │ HTTP / MCP protocol                                 ║
║             ▼                                                     ║
║  ┌─────────────────────────────────────────────────────────────┐  ║
║  │  FRONTEND  (React 19 + Vite / Nginx)  :5173 / :8080         │  ║
║  │  Pages: Home, Flights, MyBookings, DestinationDetail         │  ║
║  │  API Client: Axios → baseURL=/api                           │  ║
║  └──────────────────────┬──────────────────────────────────────┘  ║
║                         │                                         ║
║            /api/* Vite proxy (dev) or Nginx (docker)             ║
║                         │                                         ║
║  ┌──────────────────────▼──────────────────────────────────────┐  ║
║  │  PYTHON BACKEND  (FastAPI + Uvicorn)  :8001 / :8080         │  ║
║  │                                                             │  ║
║  │  REST API:                           MCP Tools (auto-gen):  │  ║
║  │  GET  /flights                       list_flights            │  ║
║  │  POST /book                          book_flight             │  ║
║  │  GET  /bookings/{uid}                get_bookings            │  ║
║  │  POST /cancel/{bid}                  cancel_booking          │  ║
║  │  POST /register                      register_user           │  ║
║  │  GET  /user                          get_user                │  ║
║  │  POST /quotes (proxy)                create_quote            │  ║
║  │  POST /quotes/{id}/holds (proxy)     create_hold             │  ║
║  │  POST /holds/{id}/confirm (proxy)    confirm_hold            │  ║
║  │  POST /holds/{id}/release (proxy)    release_hold            │  ║
║  │  POST /internal/bookings/from-hold   ◄── Java only           │  ║
║  │                                                             │  ║
║  │  Services: booking.py / flight.py / user.py                 │  ║
║  │  DB: SQLAlchemy → SQLite (local) / PostgreSQL (Docker/AWS)  │  ║
║  └──────────────────────┬──────────────────────────────────────┘  ║
║                         │                                         ║
║             httpx.AsyncClient  (JAVA_SERVICE_URL)                ║
║                         │                                         ║
║  ┌──────────────────────▼──────────────────────────────────────┐  ║
║  │  JAVA HOLD SERVICE  (Spring Boot 3)  :8080 / :8082          │  ║
║  │                                                             │  ║
║  │  POST /api/v1/quotes             → create quote             │  ║
║  │  POST /api/v1/quotes/{id}/holds  → create hold (HELD)       │  ║
║  │  POST /api/v1/holds/{id}/confirm → confirm hold             │  ║
║  │  POST /api/v1/holds/{id}/release → release hold             │  ║
║  │  Scheduler: expire stale holds every N seconds              │  ║
║  │                                                             │  ║
║  │  DB: JPA/Hibernate → SQLite (holds.db)                      │  ║
║  └──────────────────────┬──────────────────────────────────────┘  ║
║                         │                                         ║
║          Spring HttpClient  (PYTHON_BACKEND_URL)                 ║
║          POST /internal/bookings/from-hold                       ║
║                         │                                         ║
║            (loops back to Python Backend)                        ║
╚══════════════════════════════════════════════════════════════════╝
```

---

## 12. Deployment Environment Comparison

| Aspect | Local (native) | Docker Compose | E2E | AWS | IBM Cloud |
|--------|---------------|----------------|-----|-----|-----------|
| Database | SQLite | PostgreSQL | SQLite (tmp) | PostgreSQL (RDS) | SQLite |
| Port mapping | 8001, 8080, 5173 | 8001, 8082, 5173 | 18001, 18082 | ALB :443 | Code Engine public URLs |
| Service discovery | localhost | Docker DNS | Docker DNS | ECS service DNS | Internal CE DNS |
| Frontend proxy | Vite dev proxy | Nginx | N/A | ALB rules | Nginx |
| Hold duration | 15 min | 15 min | 1 min | 15 min | 15 min |
| Seed data | Yes (if empty) | Yes | No | Yes | Yes |
| Java service | Optional | Always | Always | Not deployed | Always |

---

## 13. Relevant File Index

| Category | File |
|----------|------|
| Backend entry | `booking_system_backend/server.py` |
| DB setup | `booking_system_backend/db.py` |
| Seeding | `booking_system_backend/seed.py` |
| ORM models | `booking_system_backend/models.py` |
| Pydantic schemas | `booking_system_backend/schemas.py` |
| Booking service | `booking_system_backend/services/booking.py` |
| Flight service | `booking_system_backend/services/flight.py` |
| User service | `booking_system_backend/services/user.py` |
| Java config | `booking_system_inventory_hold_service/src/main/resources/application.properties` |
| Java main controllers | `booking_system_inventory_hold_service/src/main/java/com/galaxium/holdservice/api/` |
| Java scheduler | `booking_system_inventory_hold_service/src/main/java/com/galaxium/holdservice/scheduler/HoldExpirationScheduler.java` |
| Java Python client | `booking_system_inventory_hold_service/src/main/java/com/galaxium/holdservice/client/PythonBackendClient.java` |
| Frontend routing | `booking_system_frontend/src/App.tsx` |
| Frontend API client | `booking_system_frontend/src/services/api.ts` |
| Vite proxy config | `booking_system_frontend/vite.config.ts` |
| Docker Compose | `docker-compose.yml` |
| E2E Docker Compose | `e2e/docker-compose.e2e.yml` |
| Local start script | `scripts/local/start_locally.sh` |
| AWS deploy script | `scripts/aws/deploy-to-aws.sh` |
| IBM deploy script | `scripts/ibm/deploy-to-ibm.sh` |
| Backend test fixtures | `booking_system_backend/tests/conftest.py` |
| Bob hooks config | `.bob/settings.json` |
