# Galaxium Travels — Tech Stack

## Stack Classification

This is a **polyglot multi-service stack** — it does not map to a standard acronym (like MERN or MEAN) because it combines three languages across three distinct services:

| Tier | Technology |
|---|---|
| Frontend | React (TypeScript) |
| Backend API + MCP | Python / FastAPI |
| Hold/Inventory Service | Java / Spring Boot |
| Database | SQLite (backend) + PostgreSQL (hold service) |

The closest shorthand would be **RPJS** (React · Python · Java · SQLite), but it is not an industry-standard term. It is best described as a **React + FastAPI + Spring Boot** microservices stack.

---

## Frontend — `booking_system_frontend/`

| Layer | Technology |
|---|---|
| Framework | React 19 |
| Language | TypeScript |
| Build Tool | Vite |
| Styling | Tailwind CSS (custom space-themed palette) |
| Dev Port | `:5173` |

---

## Backend — `booking_system_backend/`

| Layer | Technology |
|---|---|
| Language | Python 3 |
| Web Framework | FastAPI |
| MCP Server | FastMCP (co-hosted with FastAPI) |
| ORM | SQLAlchemy |
| Schemas / Validation | Pydantic |
| Database | SQLite (ephemeral per container) |
| HTTP Client | httpx (proxies to Java hold service) |
| Test Framework | pytest (in-memory SQLite, StaticPool) |
| Dev Port | `:8001` |

---

## Inventory Hold Service — `booking_system_inventory_hold_service/`

| Layer | Technology |
|---|---|
| Language | Java 17 / 21 |
| Framework | Spring Boot 3 |
| Build Tool | Maven |
| ORM | Spring Data JPA |
| Database | PostgreSQL (via Docker) |
| Utilities | Lombok (`@Data`, `@Builder`, `@RequiredArgsConstructor`) |
| Scheduler | `HoldExpirationScheduler` (runs every 60 s) |
| HTTP Client | RestTemplate |
| Dev Port | `:8080` |

---

## End-to-End Tests — `e2e/`

| Layer | Technology |
|---|---|
| Framework | pytest |
| Orchestration | Docker Compose (`e2e/docker-compose.e2e.yml`) |

---

## Infrastructure & Deployment

| Target | Technology |
|---|---|
| Containerization | Docker / Docker Compose |
| AWS | ECS + ALB + ECR + IAM + CloudWatch |
| IBM Cloud | IBM Code Engine |
| IaC | Terraform (`scripts/terraform/`) |

---

## Request Flow (Hold Path)

```
Frontend
  → POST /quotes           (Python proxy)
  → Java /api/v1/quotes
  → Java POST /api/v1/quotes/{id}/holds
  → Python POST /quotes/{id}/holds  (proxy)
  → on confirm: Java → Python /internal/bookings/from-hold
```

---

## Summary

Galaxium Travels is a **three-service polyglot microservices application**:

1. **React 19 + TypeScript + Vite** — user-facing SPA
2. **Python 3 + FastAPI + SQLAlchemy + SQLite** — core booking API and MCP server
3. **Java 17 + Spring Boot 3 + JPA + PostgreSQL** — inventory hold lifecycle service

All services are containerized with Docker and deployable to both **AWS (ECS/Terraform)** and **IBM Cloud (Code Engine)**.
