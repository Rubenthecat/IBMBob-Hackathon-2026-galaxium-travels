# Galaxium Travels — IBM Cloud vs AWS Cloud Deployment Comparison

## Overview

Galaxium Travels supports deployment to both **IBM Cloud (Code Engine)** and **AWS (ECS Fargate + ALB)**. Both use containerized services but differ significantly in operational model, networking complexity, and cost structure.

---

## Architecture Diagrams

### IBM Cloud — Code Engine (Serverless)

```
┌─────────────────────────────────────────────────────┐
│                     IBM Cloud                        │
│                                                     │
│   IBM Container Registry                            │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│   │ frontend │  │ backend  │  │   java   │        │
│   │  image   │  │  image   │  │  image   │        │
│   └────┬─────┘  └────┬─────┘  └────┬─────┘        │
│        │              │              │               │
│   ┌────▼──────────────▼──────────────▼────────┐    │
│   │          Code Engine Project               │    │
│   │                                            │    │
│   │  ┌──────────┐  ┌──────────┐  ┌─────────┐ │    │
│   │  │ Frontend │  │ Backend  │  │  Java   │ │    │
│   │  │  nginx   │  │ FastAPI  │  │  Hold   │ │    │
│   │  │ 0.25 CPU │  │ 0.25 CPU │  │ 0.5 CPU │ │    │
│   │  │ 0.5 GB   │  │ 0.5 GB   │  │ 1 GB    │ │    │
│   │  │ Min 0    │  │ Min 0    │  │ Min 0   │ │    │
│   │  │ Max 3    │  │ Max 3    │  │ Max 3   │ │    │
│   │  └──────────┘  └──────────┘  └─────────┘ │    │
│   └────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘

👤 User → HTTPS (public URL) → Frontend → /api/* → Backend → Java Hold Service
                                                      ↑________________________↓
                                          /internal/bookings/from-hold (callback)
```

### AWS — ECS Fargate + ALB

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS (us-east-1)                           │
│                                                                  │
│  Amazon ECR                                                      │
│  ┌───────────────┐  ┌───────────────┐                          │
│  │ backend repo  │  │ frontend repo │                          │
│  └───────┬───────┘  └───────┬───────┘                          │
│          │                  │                                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  VPC  10.0.0.0/16                                         │  │
│  │                                                           │  │
│  │  Public Subnets (AZ-a, AZ-b)                             │  │
│  │  ┌─────────────────────────────────────────────────┐     │  │
│  │  │  Application Load Balancer (HTTP :80)            │     │  │
│  │  │  Rule: /api/* → Backend Target Group             │     │  │
│  │  │  Rule: /*     → Frontend Target Group (default)  │     │  │
│  │  └──────────────────┬──────────────────────────────┘     │  │
│  │                     │                                     │  │
│  │  ┌──────────────────┼──────────────────────┐             │  │
│  │  │  ECS Fargate Tasks                       │             │  │
│  │  │                  │                       │             │  │
│  │  │  ┌───────────────▼───┐  ┌─────────────┐ │             │  │
│  │  │  │  Backend Task      │  │ Frontend    │ │             │  │
│  │  │  │  Python/FastAPI    │  │ Task nginx  │ │             │  │
│  │  │  │  :8080             │  │ :80         │ │             │  │
│  │  │  │  256 CPU / 512 MB  │  │ 256 CPU     │ │             │  │
│  │  │  └────────────────────┘  │ 512 MB      │ │             │  │
│  │  │                          └─────────────┘ │             │  │
│  │  └──────────────────────────────────────────┘             │  │
│  │                                                           │  │
│  │  NAT Gateway  │  CloudWatch Logs  │  Auto Scaling         │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

👤 User → HTTP → ALB → /api/* → Backend Task
                     → /*     → Frontend Task
```

> ⚠️ **Note:** The Java Hold Service is deployed on IBM Cloud but is **not yet included in the AWS Terraform config**. It would require a new ECS task definition, target group, and ALB routing rule.

---

## Side-by-Side Comparison

| Dimension | IBM Cloud (Code Engine) | AWS (ECS Fargate + ALB) |
|---|---|---|
| **Platform model** | Fully managed serverless | IaaS containers (you manage VPC, ALB, SGs) |
| **Java service deployed** | ✅ Yes | ❌ Not yet in Terraform |
| **Networking setup** | Automatic — no config needed | Full VPC, subnets, security groups, NAT Gateway |
| **Load balancing** | Built-in to Code Engine | Application Load Balancer (provisioned + billed separately) |
| **Scale-to-zero** | ✅ Yes — after 30 min of inactivity (traffic-based) | ✅ Yes — via scheduled scale-down (2 AM UTC daily) |
| **Scale-up trigger** | Automatic on incoming traffic | Scheduled (8 AM UTC) + target tracking (100 req/target) |
| **Cold start risk** | After idle period | After scheduled shutdown |
| **Cost model** | Pay per request/second | Pay per Fargate vCPU-hour |
| **Container registry** | IBM Container Registry | Amazon ECR |
| **Observability** | Code Engine built-in logs | CloudWatch Logs (7d dev / 30d prod) |
| **Infrastructure-as-Code** | Shell script only (~600 lines) | Terraform HCL (10+ files) |
| **Operational complexity** | Low | High |
| **Multi-AZ support** | Built-in | Explicit (2 AZs configured) |

---

## Resource Sizing

### IBM Cloud (Code Engine)

| Service | CPU | Memory | Min Instances | Max Instances |
|---|---|---|---|---|
| Frontend (nginx) | 0.25 vCPU | 0.5 GB | 0 | 3 |
| Backend (Python/FastAPI) | 0.25 vCPU | 0.5 GB | 0 | 3 |
| Java Hold Service (Spring Boot) | 0.5 vCPU | 1 GB | 0 | 3 |

### AWS (ECS Fargate)

| Service | CPU Units | Memory | Min Tasks | Max Tasks |
|---|---|---|---|---|
| Backend (Python/FastAPI) | 256 (0.25 vCPU) | 512 MB | 0 | 4 |
| Frontend (nginx) | 256 (0.25 vCPU) | 512 MB | 0 | 4 |
| Java Hold Service | ❌ Not deployed | — | — | — |

---

## Request Flow Comparison

Both deployments follow the same logical flow, but traffic entry differs:

### IBM Cloud
```
User → Code Engine public URL (Frontend)
     → Frontend calls Backend public URL (/api/*)
     → Backend proxies to Java internal URL
     → Java callbacks to Backend internal URL (/internal/bookings/from-hold)
```

### AWS
```
User → ALB public DNS (single entry point)
     → ALB rule: /api/* → Backend ECS Task
     → ALB rule: /*     → Frontend ECS Task
     → Backend proxies to Java (not on ECS — local only currently)
```

---

## Database Situation

Both deployments currently use **SQLite embedded in the container**. This means data is **ephemeral** — lost on every container restart or scale event.

| Cloud | Current DB | Production-Ready Alternative |
|---|---|---|
| IBM Cloud | SQLite (ephemeral) | IBM Databases for PostgreSQL |
| AWS | SQLite (ephemeral) | Amazon RDS PostgreSQL (`rds.tf` exists but is empty placeholder) |

`SEED_DEMO_DATA=true` re-seeds on every startup, which masks this limitation for demo purposes.

---

## Deployment Commands

### IBM Cloud
```bash
./scripts/ibm/deploy-to-ibm.sh
```

### AWS
```bash
./scripts/aws/deploy-to-aws.sh
# Runs: terraform init → plan → apply → ECR push → ECS force deploy
```

---

## When to Choose Which

| Scenario | Recommended |
|---|---|
| Demo / hackathon / low traffic | **IBM Cloud** — simpler, scale-to-zero, lower ops overhead |
| Production with all 3 services | **IBM Cloud** — Java service is already deployed |
| Enterprise AWS ecosystem | **AWS** — but add Java to Terraform and swap SQLite for RDS |
| Cost-sensitive, bursty traffic | **IBM Cloud** — true scale-to-zero on traffic |
| Compliance / multi-AZ HA | **AWS** — explicit AZ control, CloudWatch, IAM |
| Teams already using Terraform | **AWS** — full IaC already scaffolded |

---

## Gaps to Address Before Production

Both platforms share the same unresolved issues:

1. **SQLite must be replaced** with a persistent database (RDS on AWS, IBM Databases for PostgreSQL on IBM Cloud)
2. **AWS Terraform missing Java service** — needs ECS task definition, target group, and ALB rule
3. **No HTTPS/TLS** configured in current Terraform (ALB listener is HTTP :80 only)
4. **No secrets management** — environment variables are passed in plaintext (should use AWS Secrets Manager or IBM Secrets Manager)
5. **No CI/CD pipeline** — deployments are manual shell scripts
