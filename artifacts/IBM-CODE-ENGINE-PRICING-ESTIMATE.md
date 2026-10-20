# IBM Code Engine: Pricing Estimate & Breakdown

> **Purpose:** Bottom-up cost estimate for the Hackathon Live demo running on IBM Cloud Code Engine (us-south). Covers both the $0 idle state and realistic active-use scenarios. All rates are from the [IBM Code Engine pricing page](https://cloud.ibm.com/catalog/services/codeengine) and [IBM Container Registry pricing](https://cloud.ibm.com/catalog/services/container-registry).

---

## 1. Resource Configuration (from `scripts/ibm/deploy-to-ibm.sh`)

| Service | vCPU | Memory | Min Scale | Max Scale | Scale-Down Delay |
|---|---|---|---|---|---|
| `galaxium-backend` (Python/FastAPI) | 0.25 | 0.5 GB | 0 | 3 | 1800 s (30 min) |
| `galaxium-frontend` (Nginx) | 0.25 | 0.5 GB | 0 | 3 | 1800 s (30 min) |
| `galaxium-hold-service` (Java/Spring Boot) | 0.50 | 1.0 GB | 0 | 3 | 1800 s (30 min) |

**Key decisions captured:**

- `min-scale = 0`: All three services scale completely to zero when idle. *Most important cost decision:* **$0/month when unused*.
- `scale-down-delay = 1800 (30min.)`: 30 minutes after the last request, instances scale to zero. *This avoids multiple cold starts during a continuous judge session while still scaling to $0 after the judge concludes session.*
- Java is given 2× the CPU/memory of the other services (0.5 vCPU / 1 GB) because Spring Boot JVM startup and the in-memory H2-based hold scheduler require more headroom.
- `max-scale = 3` on all services — a safety cap that prevents runaway costs if the app is left running under unexpected load.

---

## 2. IBM Code Engine Billing Rates (us-south, Standard plan)

| Dimension | Rate | Free tier |
|---|---|---|
| vCPU-second | $0.00008 / vCPU-second | 100 vCPU-seconds/month |
| GB-second | $0.00001 / GB-second | 200 GB-seconds/month |
| HTTP request | $0.0000028 / request | 100,000 requests/month |

> **Note:** The free tier is very small relative to any active use. It is consumed within the first few minutes of a warm session and is not factored into the estimates below.

---

## 3. Container Registry Costs


**Images (3)**
| Dimension | Rate | Free tier |
|---|---|---|
| Image storage | $0.023 / GB/month | 0.5 GB/month |

| Image | Estimated compressed size | Storage Cost |
|---|---|---|
| Backend | ~200 MB (0.2GB) |
| Frontend (Nginx + Vite bundle) | ~30 MB (0.03GB) | 
| Hold-service (JRE + fat JAR) | ~350 MB (0.35GB) | 
| **Total** | **~580 MB (.58GB)** *.08GB above Free tier* | **~$0.002 / month**

> **Note:** 580 MB is above the 500 MB free tier by ~80 MB.

Storage cost = ```0.08 GB × $0.023 = ```**~$0.002 / month**  (effectively free)

---
**Pull traffic** 
Occurs on every cold start Code Engine pulls the images. **Each pull is ~0.57GB**

| Dimension | Rate | Free tier |
|---|---|---|
| Pull traffic | $0.09 / GB | 5 GB/month |

| Pull traffic | Rate ($0.09 / GB) |
|---|---|
|  ~8 Pulls *First 5 GB* |  Free |
| 8< Pulls |```*0.57 GB × $0.09``` = **~$0.05 per full cold start** |

For a hackathon (single-day event, ≤ 5 cold starts), **registry pull costs are $0**.

---

## 4. Per-Instance-Second Cost per Service

Using: `vCPU cost + memory cost = cost per second (1 instance)`

| Service | vCPU × rate | Memory × rate | Total / second |
|---|---|---|---|
| Backend | 0.25 × $0.00008 | 0.5 × $0.00001 | **$0.0000250/s** |
| Frontend | 0.25 × $0.00008 | 0.5 × $0.00001 | **$0.0000250/s** |
| Java | 0.50 × $0.00008 | 1.0 × $0.00001 | **$0.0000500/s** |
| **All 3 combined** | | | **$0.0001000/s** |

At 1 instance each: **$0.10 per 1,000 seconds of uptime** across all services.

---

## 5. Pricing Scenarios 

|Scenario| Assumptions | Total
| ---| --- | ---|
|**Scenario A**: Idle (no traffic)| With `min-scale = 0`, all three services have **zero running instances** when idle.The app sits deployed and dormant at zero cost indefinitely. |The **only recurring charge is the ~$0.002/month** for image storage (80 MB over the 500 MB free tier).
|**Scenario B**: Hackathon Demo Day (single day, ~4 hours active) | <ul><li>Judges arrive at an unpredictable time.</li><li>1 cold start at T=0.2 judge sessions of 30 minutes each (separated by > 30 min gap, so second cold start occurs)</li> <li>~5 users concurrently browsing during each session. Each user makes ~30 API requests per session (search flights, view booking, hold workflow)</li></ul> |<ul><li>Compute (warm time): **\$0.72**</li><li>HTTP requests: **\$0.00**</li><li>Registry pulls: **\$0.00** </li><li>Image storage: **\~$0.002**</li> <li>**Total ≈ \$0.72**</li></ul>
|**Scenario C**: Light usage month (app left deployed, occasional visitors) |  <ul><li>1 hour of active use per day × 30 days = 30 hours</li><li>Each active hour: 1 instance per service + 30 min scale-down tail → 1.5 hours warm per day</li> <li>200 requests/day × 30 days = 6,000 requests/month</li></ul> |<ul><li>Compute (warm time): **\$16.20**</li><li>HTTP requests: **\$0.00**</li><li>Registry pulls: **\$1.09** </li><li>Image storage: **\~$0.002**</li> <li>**Total ≈ \$17.30**</li></ul>
|**Scenario D**: Medium usage month (team demo environment)|<ul><li>8 hours active / day × 20 working days = 160 hours</li><li>500 requests/day × 20 days = 10,000 requests/month</li> <li>Scales to 2 instances during peak (assume 50% of active time at 2 instances)</li></ul> | <ul><li>Compute (warm time): **\$86.40**</li><li>HTTP requests: **\$0.00**</li><li>Registry pulls: **\$7.74** </li><li>Image storage: **\~$0.002**</li> <li>**Total ≈ \$94.14**</li></ul>

```
Scenario D Breakdown
Backend:
  288,000 × 1 inst × $0.0000250 = $7.20
  288,000 × 2 inst × $0.0000250 = $14.40
  Backend subtotal: $21.60

Frontend: same profile → $21.60

Java (0.5 vCPU / 1 GB):
  288,000 × 1 inst × $0.0000500 = $14.40
  288,000 × 2 inst × $0.0000500 = $28.80
  Java subtotal: $43.20

Compute subtotal: $86.40

HTTP requests: 10,000 → within free tier  = $0.00
Registry: ~160 cold starts × 0.57 GB = 91 GB
  (91 - 5) GB × $0.09                   = $7.74
Image storage: ~$0.002                   ≈ $0.00
                                         ────────
Medium usage month total:               ~$94.14
```

---

## 9. Cost Summary Table

| Scenario | Compute | Requests | Registry | **Total** |
|---|---|---|---|---|
| Idle | $0.00 | $0.00 | ~$0.00 | **$0.00** |
| Demo day (4 h, 2 sessions) | $0.72 | $0.00 | $0.00 | **~$0.72** |
| Light month (1 h/day) | $16.20 | $0.00 | $1.09 | **~$17.29** |
| Medium month (8 h/day × 20 days) | $86.40 | $0.00 | $7.74 | **~$94.14** |

---

## 10. Key Cost Decisions and Trade-offs

| Decision | Cost impact | Alternative considered |
|---|---|---|
| `min-scale = 0` | **Saves ~$50–$130/month** vs keeping 1 instance always on | `min-scale = 1` would eliminate cold starts but bill 24/7 at ~$0.36/h for all 3 services = ~$262/month |
| `scale-down-delay = 1800` (30 min) | Adds ~$0.36 warm-tail cost per session | Delay = 0 would cold-start on every new request; delay = 3600 doubles the tail cost |
| Java at 0.5 vCPU / 1 GB | 2× cost vs backend/frontend | Minimum viable for Spring Boot JVM + Lombok + in-memory scheduler; 0.25/0.5 risks OOMKill |
| `max-scale = 3` | Hard cap; prevents runaway bill | No cap would allow unlimited scale-out if traffic spikes |
| Internal-only Java (`--visibility project`) | No impact on cost | Makes Java unreachable externally — reduces attack surface, not cost |
| Nginx frontend serving warming-up.html | $0 extra | Alternative: a separate static CDN — would add ~$1–$5/month for a demo |
| All services in the same Code Engine project | Internal traffic (backend ↔ Java) is **not billed** | Cross-project would bill every inter-service HTTP call |

> **Biggest lever:** The `min-scale = 0` + `scale-down-delay = 1800` combination makes this app cost **\$0 when the hackathon is not running** and roughly **$0.72 for a typical 4-hour demo day**. That is the primary goal stated in Plan #2.

---

## 11. Caveats

- Rates shown are IBM Cloud us-south Standard plan as of mid-2025. Actual charges may vary by geography and IBM pricing updates — use the [IBM Cloud Cost Estimator](https://cloud.ibm.com/estimator) for a live quote.
- Cold-start time (included in billed time per IBM docs) adds ~5–15 seconds of billed compute per cold start — negligible at these resource sizes (~$0.001 per cold start).
- Build runs (if using `--build-source`) are billed separately at the same vCPU/GB-second rates. The primary deploy script uses pre-built images from Container Registry, so build costs are only incurred if `deploy-to-ibm-simple.sh` is used.
- SQLite is the database (ephemeral, in-container) — no managed database cost.

---

*Made with IBM Bob*
