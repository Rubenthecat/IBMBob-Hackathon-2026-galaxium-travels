# Ruvix Fix Hackathon team repo
## Member: Ruben Guerra
# YT Link: https://www.youtube.com/watch?v=YblZcFj6BBI

# Consensus
The point of this project is to show IBM Bob's capability to enable developers to create projects that are easily adaptable to any OS of their choosing. Additionally, it demonstrates BOB's ability to create deployment scripts for a chosen Cloud infrastructure. 
Within the project, in artifacts/issue-tracker , i have demonstrated how it can be used as a bug tracker as well. This documentation doubles as a way to train Bob on not making the same mistake twice, by creating change documentation it can reference at any time.

## Quick Start (IBM Deployment Path)
```
./scripts/ibm/deploy-to-ibm.sh
```
1. The script will exit if you do not have the dependancies installed.
2. It will list the missing dependacies and you can re-run
3. You must have an active IBM Cloud account to create resources with the IBM Cloud CLI.


## Quick Start (Local Hosting)

Clone the repo and run a single command — the script will ask whether you want to use **Docker** (recommended) or run **locally**, then install any missing dependencies automatically, including the Java Hold Service which is required for full functionality.

### macOS / Linux
```bash
./setup.sh
```

### Windows (PowerShell)
```powershell
.\setup.ps1
```
> **Windows requirement:** `winget` (used for auto-installing tools in Local mode) requires Windows 10 version 1709 or newer.

### Already have Docker? (any platform)
```bash
docker compose up --build
```
> The Java Hold Service starts automatically — no extra flags needed.

The scripts detect your platform, prompt for a mode, handle all dependency installation (Python, Node, Java 21, Maven), and launch all services. No manual setup needed.

| URL | Service |
|---|---|
| http://localhost:5173 | Frontend |
| http://localhost:8001 | Backend API |
| http://localhost:8001/docs | API Docs (Swagger) |
| http://localhost:8082 | Java Hold Service |

---

## Project Origin

**Original Project:** [https://github.com/example-developer/hotel-booking-app](https://github.com/IBM/galaxium-travels)

**Fork:** [https://github.com/RubenGuerra/hotel-booking-app](https://github.com/Rubenthecat/IBMBob-Hackathon-2026-galaxium-travels)

This project is a fork of the original Galaxium Travels repository found on Github.
IBM Bob was used to analyze the existing codebase, identify its architecture, and implement a new feature, allowing for the user to select their preferred currency
