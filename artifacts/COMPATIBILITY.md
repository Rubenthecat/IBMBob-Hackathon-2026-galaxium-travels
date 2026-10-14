# Galaxium Travels — Compatibility Reference

All information below is derived directly from the scripts, Dockerfiles, CI workflows, and
documentation in this repository.

---

## 1. Local Development (Native Toolchain)

| Operating System | Supported | Entry Point | Notes |
|-----------------|-----------|-------------|-------|
| macOS 10.15+ (Intel) | ✅ | `setup.sh` / `start.sh` | Uses `lsof`, `brew`, `/usr/libexec/java_home` |
| macOS 12+ (Apple Silicon / arm64) | ✅ | `setup.sh` / `start.sh` | Same scripts; Colima is the recommended Docker runtime |
| Ubuntu / Debian (and derivatives) | ✅ | `setup.sh` / `start.sh` | Package manager: `apt-get`; distro detected via `/etc/os-release` |
| Fedora / RHEL 8+ / CentOS Stream / Rocky / AlmaLinux / Amazon Linux 2023 | ✅ | `setup.sh` / `start.sh` | Package manager: `dnf` |
| RHEL 7 / CentOS 7 / Amazon Linux 2 | ✅ | `setup.sh` / `start.sh` | Package manager: `yum` |
| openSUSE Leap / Tumbleweed | ✅ | `setup.sh` / `start.sh` | Package manager: `zypper` |
| Windows 10 1709+ / Windows 11 | ✅ | `setup.ps1` | Uses `winget` (primary) or `Scoop` (fallback); requires PowerShell 5.1 |
| Windows — bash path (`start.sh`) | ❌ | — | `setup.sh` line 23 explicitly rejects non-bash environments and redirects to `setup.ps1` |

> **macOS Docker note:** `docker-buildx` is required. Without it the legacy builder triggers a
> Keychain prompt and fails. See `AGENTS.md` for the one-time `~/.docker/config.json` plugin path
> fix.

---

## 2. Containerised (Docker / Docker Compose)

| Environment | Architecture | Notes |
|-------------|-------------|-------|
| Docker on Linux (amd64) | `linux/amd64` | Production `docker-compose.yml` pins all services to `linux/amd64` |
| Docker Desktop on macOS (Intel) | `linux/amd64` | Native match; no emulation overhead |
| Docker Desktop on macOS (Apple Silicon) | `linux/amd64` via QEMU | Works, but incurs emulation overhead; Colima recommended |
| Docker Desktop on Windows (WSL2 / Hyper-V) | `linux/amd64` | Works via the WSL2 Linux layer |
| E2E stack (`e2e/docker-compose.e2e.yml`) | arm64 and amd64 | All `platform:` pins removed; builds natively on Apple Silicon |

---

## 3. Cloud Deployment Targets

| Platform | Architecture | Deploy Script | Infrastructure |
|----------|-------------|---------------|---------------|
| AWS ECS Fargate | `linux/amd64` only | `scripts/aws/deploy-to-aws.sh` | Terraform → ECS + ALB + ECR + RDS |
| IBM Code Engine | `linux/amd64` only | `scripts/ibm/deploy-to-ibm.sh` | ibmcloud CLI → Code Engine project (`us-south`) |

Both deploy scripts pass `--platform linux/amd64` explicitly to `docker build`.

---

## 4. CI/CD Tested Matrix

Source: `.github/workflows/`

| GitHub Actions Runner | OS Version | What Is Tested |
|-----------------------|------------|---------------|
| `ubuntu-latest` | Ubuntu 22.04+ | Docker Compose stack + local native mode |
| `macos-latest` | macOS 12+ (arm64) | Local native mode (manual trigger) |
| `windows-latest` | Windows Server 2022 | PowerShell (`setup.ps1`) local native mode |

---

## 5. Runtime Version Requirements

| Runtime | Required Version | Hard Constraint? | Source |
|---------|-----------------|-----------------|--------|
| Java | **17 or 21 only** | ✅ Hard | Lombok does not compile on Java 22+; enforced in `start_locally.sh` and `pom.xml` |
| Python | **3.11** | ✅ Hard | `FROM python:3.11-slim` in `booking_system_backend/Dockerfile`; CI setup installs 3.11 exactly |
| Node.js | **18+** (tested: 20, 22) | ⚠️ Soft | Vite 7 minimum; no `engines` field in `package.json` |
| Maven | **3.8+** | ✅ Hard | Build image is `maven:3.9`; Spring Boot 3.4 + Lombok require ≥ 3.8 |

---

## 6. Cloud CLI Prerequisites

Required only when running the relevant deploy script.

| Tool | Required For | Min Version |
|------|-------------|-------------|
| `aws` (AWS CLI) | AWS deploy | v2 (implied) |
| `terraform` | AWS deploy | ≥ 1.0 |
| `jq` | AWS + IBM deploy | any |
| `ibmcloud` (IBM Cloud CLI) | IBM deploy | any |
| IBM Cloud Code Engine plugin | IBM deploy | any |
| IBM Cloud Container Registry plugin | IBM deploy | any |

---

## 7. Docker Base Image Architecture Support

| Image | Prod Pin | E2E | Multi-arch Available |
|-------|----------|-----|----------------------|
| `python:3.11-slim` | `linux/amd64` | `linux/amd64` | amd64, arm64v8, arm32v7 |
| `node:18-alpine` | `linux/amd64` | `linux/amd64` | amd64, arm64v8, arm32v7 |
| `nginx:alpine` | `linux/amd64` | `linux/amd64` | amd64, arm64v8, arm32v7, ppc64le, s390x |
| `postgres:14-alpine` | — (host) | — | amd64, arm64v8, ppc64le, s390x |
| `maven:3.9-eclipse-temurin-17` | `linux/amd64` | `linux/amd64` | amd64, arm64v8 |
| `eclipse-temurin:17-jre-alpine` | `linux/amd64` | — | amd64 only |
| `eclipse-temurin:17-jre` (glibc) | — | native | amd64, arm64v8, arm32v7, ppc64le |

---

## 8. Known Incompatibilities and Footguns

| Issue | Affected Platform | Detail |
|-------|------------------|--------|
| Java 22+ breaks Lombok | All | `pom.xml` uses Lombok; Java 22+ changed annotation processing. Use Java 17 or 21. |
| amd64 emulation on Apple Silicon | macOS arm64 | Production `docker-compose.yml` pins to `linux/amd64`; triggers QEMU and a Keychain prompt without `docker-buildx`. Install Colima + docker-buildx. |
| `docker-buildx` missing on macOS | macOS | Without it, `docker compose --build` falls back to the legacy builder, triggering a Keychain prompt and amd64 emulation. See `AGENTS.md`. |
| `lsof` vs `fuser` | Linux | macOS ships `lsof`; some minimal Linux installs lack it. `setup.sh` falls back to `fuser` (requires `psmisc`). |
| Homebrew Java not on PATH | macOS | `brew install openjdk@21` does not auto-add to `PATH`. `setup.sh` exports the brew prefix manually. |
| `python3-venv` missing on Debian/Ubuntu | Linux | Python 3 on Debian/Ubuntu does not ship `venv` by default. `setup.sh` installs `python3.11-venv` via `apt-get`. |
| PowerShell 5.1 required on Windows | Windows | `setup.ps1` forces PS 5.1 (not pwsh 7) due to a null-conditional operator regression (BOB-003). |
| Windows PATH not auto-refreshed | Windows | After `winget`/`Scoop` installs, `setup.ps1` must manually merge Machine + User `PATH` env vars to make new tools visible in the same session. |
| Docker group permissions on Linux | Linux | User must be in the `docker` group or use `sudo`. `setup.sh` handles this but requires a logout/login to take effect. |
| `sdkman` path hardcoded | macOS, Linux | Java detection assumes sdkman lives at `$HOME/.sdkman/candidates/java`. Non-standard installs require setting `JAVA_HOME` manually. |
