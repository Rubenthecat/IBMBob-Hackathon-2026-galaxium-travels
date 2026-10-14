# Flights Page `.map` Error Fix Plan

## Top-Level Overview

When running in Docker mode (via `./setup.sh`), navigating to `/flights` throws:

```
Uncaught TypeError: G.map is not a function
```

`G` is the `flights` React state variable. `.map` is only callable on arrays. The error means the `flights` state was set to a non-array value — i.e., `getFlights()` resolved successfully (HTTP 2xx) but returned something other than `Flight[]`.

**Root cause:** Two interacting issues introduced by the DOCKER-DB-STALE-REFERENCES fix:

1. **nginx variable-based `proxy_pass` does not reliably strip the `/api/` prefix.** When BOB-005 changed the `/api/` location to use `set $backend_upstream http://backend:8080; proxy_pass $backend_upstream/;` (to defer DNS resolution), it introduced a subtle nginx behaviour change: URI prefix stripping is guaranteed with a *literal* proxy URL, but is version-dependent and unreliable when a *variable* is used — even if the variable expands to the same string. In some nginx versions the full original URI (`/api/flights`) is forwarded to the backend instead of the stripped URI (`/flights`).

2. **`root_path="/api"` is baked into `server.py` at app level.** FastAPI/Starlette uses this to modify `scope["root_path"]` and to generate OpenAPI server URLs. Depending on FastAPI/Starlette version, this setting can cause the backend to respond to `/api/flights` as if it were `/flights` (path stripping), OR it can cause an incorrect `Location` header on redirect responses. The combination of unreliable nginx stripping + `root_path` at app level creates a version-sensitive interaction that is fragile across environments.

3. **No defensive guard in the frontend.** `Flights.tsx` calls `setFlights(data)` without verifying that `data` is actually an array. If the API returns any non-array JSON (e.g. `{"detail": "Not Found"}`, `{"status": "OK"}`) with a 2xx status, the state becomes non-array and the subsequent `.map()` call throws.

These three issues are fixed with three independent, targeted changes.

---

## Sub-Tasks

---

### Sub-Task 1 — Fix nginx path stripping with a `rewrite` rule

**Status:** `[x] done`

**Intent**

Replace the ambiguous variable-based URI substitution with an explicit `rewrite` directive that unconditionally strips the `/api/` prefix before proxying. A `rewrite` rule is version-stable and eliminates all ambiguity about whether the variable-based `proxy_pass` path component performs URI replacement or not.

**Expected Outcomes**
- nginx always forwards `GET /flights` (not `GET /api/flights`) to the backend regardless of nginx version
- The behavior is identical to what a literal `proxy_pass http://backend:8080/;` would produce, but DNS resolution is still deferred to request time via the variable
- All other nginx behaviour (resolver, timeouts, headers) is unchanged

**Todo List**
- [ ] In `booking_system_frontend/nginx.conf`, inside the `location /api/ { ... }` block, add a `rewrite ^/api/(.*) /$1 break;` directive as the **first line** of the block, before `proxy_pass`
- [ ] Change `proxy_pass $backend_upstream/;` to `proxy_pass $backend_upstream;` (remove the trailing slash — it is now redundant/conflicting with the rewrite; the rewrite already produces the final path)
- [ ] Confirm the block now reads: `rewrite ^/api/(.*) /$1 break;` then `proxy_pass $backend_upstream;` plus the existing headers and timeout directives

**Relevant Context**
- [`booking_system_frontend/nginx.conf` lines 25–36](booking_system_frontend/nginx.conf:25) — the `/api/` location block
- nginx `rewrite ... break` flag stops any further rewrites and uses the new URI for `proxy_pass`
- The `set $backend_upstream http://backend:8080;` variable remains — it is still needed for deferred DNS resolution (the resolver directive depends on it)

---

### Sub-Task 2 — Remove the hardcoded `root_path` from `server.py`

**Status:** `[x] done`

**Intent**

`root_path="/api"` was added "for ALB routing" but is not the correct way to set `root_path` in a reverse-proxied deployment. The standard approach is for the reverse proxy (ALB or nginx) to forward the `X-Forwarded-Prefix` header, and for the app to read it from the ASGI scope. Baking `root_path="/api"` into the app creates a version-sensitive path-stripping side-effect: in some Starlette versions this causes incoming requests with path `/api/flights` to be routed as if the path is `/flights`, which masks the nginx bug rather than fixing it, and in others it does nothing. In Docker mode (after Sub-Task 1 fixes nginx), the backend will always receive paths without the `/api/` prefix, so `root_path` at app level is not needed for routing.

**Expected Outcomes**
- `FastAPI(root_path="/api")` becomes `FastAPI()` (no `root_path`)
- Backend routes (`/flights`, `/book`, etc.) are matched against the raw request path only — no implicit prefix stripping
- OpenAPI Swagger UI still works correctly in Docker mode (nginx proxies `/api/docs` → backend `/docs`)
- AWS ALB behaviour: the ALB already strips `/api/` before forwarding; no `root_path` is needed in the app for routing to work

**Todo List**
- [ ] In `booking_system_backend/server.py`, remove `root_path="/api"` from the `FastAPI(...)` constructor call (line 44–50). Keep all other arguments (`title`, `description`, `version`, `lifespan`) unchanged.
- [ ] Remove the inline comment `# Add this for ALB routing` that accompanied `root_path`

**Relevant Context**
- [`booking_system_backend/server.py` lines 44–50](booking_system_backend/server.py:44) — the `FastAPI(...)` constructor
- The `root_path` parameter is documented in [Starlette docs](https://www.starlette.io/applications/) — it is intended for ASGI scope propagation from the proxy, not for app-level path matching
- AWS ALB listener rules strip the `/api` path prefix before forwarding to the target group (confirmed by existing deploy scripts); the backend therefore always receives stripped paths in production too

---

### Sub-Task 3 — Add a defensive array guard in `Flights.tsx`

**Status:** `[x] done`

**Intent**

Even after fixing nginx and `root_path`, the frontend should be resilient to unexpected API responses. If the backend ever returns a non-array value with a 2xx status (e.g. during a transient error, gateway response, or future API change), calling `.map()` on it will throw and crash the page. A one-line guard — `setFlights(Array.isArray(data) ? data : [])` — prevents this entirely.

**Expected Outcomes**
- `flights` state is always an array, even if `getFlights()` returns an unexpected value
- The page shows "No flights found" instead of a JS crash when a non-array is returned
- No other behaviour change — the existing retry logic and error handling remain intact

**Todo List**
- [ ] In `booking_system_frontend/src/pages/Flights.tsx`, change line 32 from `setFlights(data);` to `setFlights(Array.isArray(data) ? data : []);`
- [ ] Optionally add a `console.warn` inside the else branch to surface unexpected responses in dev tools

**Relevant Context**
- [`booking_system_frontend/src/pages/Flights.tsx` line 32](booking_system_frontend/src/pages/Flights.tsx:32) — `setFlights(data)` call
- This is a defensive guard only; it does not mask the root cause — Sub-Tasks 1 and 2 fix the actual routing issues

---

## Implementation Order

```
Sub-Task 1  (nginx rewrite — fixes path forwarding to backend)
    ↓
Sub-Task 2  (remove root_path — removes fragile path-stripping side-effect)
    ↓
Sub-Task 3  (array guard — defensive frontend resilience)
```

After all three are applied, rebuild and restart with:
```bash
./setup.sh   # choose Docker mode
# Open http://localhost:5173/flights — flights list should appear
```

The backend unit tests (`booking_system_backend/tests/`) are unaffected by all three changes — they call the service layer directly and do not go through nginx or test `root_path` behaviour.
