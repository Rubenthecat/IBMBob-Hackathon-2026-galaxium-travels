# setup.ps1 — First-run bootstrap for Galaxium Travels (Windows)
# Prompts for Docker or Local mode, installs missing tools via winget, then launches the app.
# Requires: Windows 10 version 1709 or newer (for winget support in Local mode)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── Colours ──────────────────────────────────────────────────────────────────
function Write-Green  { param($msg) Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Yellow { param($msg) Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Write-Red    { param($msg) Write-Host "❌ $msg" -ForegroundColor Red }
function Write-Blue   { param($msg) Write-Host $msg -ForegroundColor Cyan }

Write-Host ""
Write-Host "🌌 Galaxium Travels — First-Run Setup" -ForegroundColor White
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""

# ── Mode Prompt ───────────────────────────────────────────────────────────────
Write-Host "How would you like to run the application?"
Write-Host ""
Write-Host "  1) Docker  (recommended — no local dependencies needed beyond Docker)"
Write-Host "  2) Local   (runs directly on your machine — installs missing tools via winget)"
Write-Host ""
$modeChoice = Read-Host "Enter your choice [1 or 2]"

switch ($modeChoice) {
    "1" { $mode = "docker" }
    "2" { $mode = "local"  }
    default {
        Write-Red "Invalid choice. Please re-run and enter 1 or 2."
        exit 1
    }
}

Write-Host ""

# ════════════════════════════════════════════════════════════════════════════════
# DOCKER MODE
# ════════════════════════════════════════════════════════════════════════════════
if ($mode -eq "docker") {
    Write-Blue "🐳 Docker mode selected."
    Write-Host ""

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Red "Docker is not installed."
        Write-Host ""
        Write-Host "Install Docker Desktop via winget:"
        Write-Host "  winget install Docker.DockerDesktop"
        Write-Host ""
        Write-Host "Or download from: https://docs.docker.com/desktop/install/windows-install/"
        Write-Host ""
        Write-Host "After installing, re-run: .\setup.ps1"
        exit 1
    }

    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Red "Docker daemon is not running."
        Write-Host ""
        Write-Host "Start Docker Desktop from the Start Menu or system tray,"
        Write-Host "wait for it to finish starting (whale icon stops animating),"
        Write-Host "then re-run: .\setup.ps1"
        exit 1
    }

    Write-Green "Docker is running."
    Write-Host ""
    Write-Host "Starting Galaxium Travels with Docker Compose..."
    Write-Host "(This may take a few minutes on the first run while images are built.)"
    Write-Host ""
    Write-Host "  Backend:   http://localhost:8001"
    Write-Host "  Frontend:  http://localhost:5173"
    Write-Host "  API Docs:  http://localhost:8001/docs"
    Write-Host ""
    Write-Host "To also start the Java Hold Service, run:"
    Write-Host "  docker compose --profile hold-service up --build"
    Write-Host ""

    Set-Location $ScriptDir
    docker compose up --build
    exit $LASTEXITCODE
}

# ════════════════════════════════════════════════════════════════════════════════
# LOCAL MODE
# ════════════════════════════════════════════════════════════════════════════════
Write-Blue "💻 Local mode selected."
Write-Host ""
Write-Yellow "Note: Local mode requires Windows 10 version 1709 or newer for winget support."
Write-Host ""

# ── Helper: Require-Tool ─────────────────────────────────────────────────────
function Require-Tool {
    param(
        [string]$Binary,
        [string]$WingetId,
        [string]$DisplayName
    )
    if (Get-Command $Binary -ErrorAction SilentlyContinue) {
        Write-Green "$DisplayName found: $((Get-Command $Binary).Source)"
        return
    }
    Write-Yellow "$DisplayName not found. Installing via winget..."
    winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements
    # Refresh PATH so the newly installed binary is visible
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    if (Get-Command $Binary -ErrorAction SilentlyContinue) {
        Write-Green "$DisplayName installed successfully."
    } else {
        Write-Red "Failed to install $DisplayName. Please install it manually and re-run."
        exit 1
    }
}

# ── Check / install required tools ───────────────────────────────────────────
Write-Host "Checking required tools..."
Write-Host ""

Require-Tool -Binary "python"  -WingetId "Python.Python.3.11" -DisplayName "Python 3"
Require-Tool -Binary "node"    -WingetId "OpenJS.NodeJS"       -DisplayName "Node.js"

# Java 21 required — the Java Hold Service is a required component
Require-Tool -Binary "java" -WingetId "Microsoft.OpenJDK.21" -DisplayName "Java 21"
Require-Tool -Binary "mvn"  -WingetId "Apache.Maven"         -DisplayName "Maven"

Write-Host ""

# ── Create .env from .env.example ────────────────────────────────────────────
$envExample = Join-Path $ScriptDir "booking_system_frontend\.env.example"
$envFile    = Join-Path $ScriptDir "booking_system_frontend\.env"
if ((Test-Path $envExample) -and (-not (Test-Path $envFile))) {
    Copy-Item $envExample $envFile
    Write-Green "Created booking_system_frontend\.env from .env.example"
}

Write-Host ""

# ── Port cleanup (PowerShell equivalent of lsof + kill) ──────────────────────
function Stop-PortProcess {
    param([int]$Port)
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        $pid_ = $conn.OwningProcess | Select-Object -First 1
        try {
            Stop-Process -Id $pid_ -Force -ErrorAction SilentlyContinue
            Write-Yellow "Stopped existing process on port $Port (PID $pid_)"
        } catch { }
    }
}

Write-Host "Clearing ports 8001, 5173, 8080..."
Stop-PortProcess 8001
Stop-PortProcess 5173
Stop-PortProcess 8080
Start-Sleep -Seconds 1

# ── Start Backend ─────────────────────────────────────────────────────────────
Write-Blue "`n📡 Starting Backend Server..."
Set-Location (Join-Path $ScriptDir "booking_system_backend")

if (-not (Test-Path ".venv")) {
    Write-Host "Creating Python virtual environment..."
    python -m venv .venv
}

Write-Host "Installing Python dependencies..."
.\.venv\Scripts\pip install -q -r requirements.txt

$backendLog = Join-Path $ScriptDir "booking_system_backend\backend.log"
$backendProc = Start-Process -FilePath ".\.venv\Scripts\python" -ArgumentList "server.py" `
    -RedirectStandardOutput $backendLog -RedirectStandardError $backendLog `
    -NoNewWindow -PassThru

# ── Health-check backend (5 attempts, 2 s apart) ─────────────────────────────
Write-Host "Waiting for backend to start..."
$backendReady = $false
for ($i = 1; $i -le 5; $i++) {
    Start-Sleep -Seconds 2
    try {
        $null = Invoke-WebRequest -Uri "http://localhost:8001/" -UseBasicParsing -TimeoutSec 2
        $backendReady = $true
        break
    } catch { }
}

if (-not $backendReady) {
    Write-Red "Backend failed to start. Check booking_system_backend\backend.log for errors."
    Stop-Process -Id $backendProc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Green "Backend started on http://localhost:8001"

# ── Start Frontend ────────────────────────────────────────────────────────────
Write-Blue "`n🎨 Starting Frontend Server..."
Set-Location (Join-Path $ScriptDir "booking_system_frontend")

if (-not (Test-Path "node_modules")) {
    Write-Host "Installing frontend dependencies..."
    npm install
}

$frontendProc = Start-Process -FilePath "npm" -ArgumentList "run", "dev" `
    -NoNewWindow -PassThru

Start-Sleep -Seconds 3
Write-Green "Frontend started on http://localhost:5173"

# ── Summary ───────────────────────────────────────────────────────────────────
Set-Location $ScriptDir
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "🌟 Galaxium Travels is running!" -ForegroundColor White
Write-Host ""
Write-Host "   Backend:   http://localhost:8001"
Write-Host "   Frontend:  http://localhost:5173"
Write-Host "   API Docs:  http://localhost:8001/docs"
Write-Host ""
Write-Host "Press Ctrl+C to stop. Backend log: booking_system_backend\backend.log"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Keep the script alive so Ctrl+C stops both child processes
try {
    Wait-Process -Id $backendProc.Id, $frontendProc.Id
} finally {
    Stop-Process -Id $backendProc.Id  -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $frontendProc.Id -Force -ErrorAction SilentlyContinue
    Remove-Item $backendLog -ErrorAction SilentlyContinue
}

# Made with Bob
