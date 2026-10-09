# setup.ps1 - First-run bootstrap for Galaxium Travels (Windows)
# Prompts for Docker or Local mode, installs missing tools via winget, then launches the app.
# Requires: Windows 10 version 1709 or newer (for winget support in Local mode)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── Colours ──────────────────────────────────────────────────────────────────
function Write-Green  { param($msg) Write-Host "[OK]  $msg" -ForegroundColor Green }
function Write-Yellow { param($msg) Write-Host "[!!]  $msg" -ForegroundColor Yellow }
function Write-Red    { param($msg) Write-Host "[ERR] $msg" -ForegroundColor Red }
function Write-Blue   { param($msg) Write-Host $msg -ForegroundColor Cyan }

Write-Host ""
Write-Host "Galaxium Travels - First-Run Setup" -ForegroundColor White
Write-Host "======================================="
Write-Host ""

# ── Mode Prompt ───────────────────────────────────────────────────────────────
Write-Host "How would you like to run the application?"
Write-Host ""
Write-Host "  1) Docker  (recommended - no local dependencies needed beyond Docker)"
Write-Host "  2) Local   (runs directly on your machine - installs missing tools via winget)"
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

# ==============================================================================
# DOCKER MODE
# ==============================================================================
if ($mode -eq "docker") {
    Write-Blue "Docker mode selected."
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
    Set-Location $ScriptDir
    docker compose up --build
    exit $LASTEXITCODE
}

# ==============================================================================
# LOCAL MODE
# ==============================================================================
Write-Blue "Local mode selected."
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
    # Give the installer a moment to finish writing PATH entries before we refresh
    Start-Sleep -Seconds 3
    # Refresh PATH so the newly installed binary is visible
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    # "py" (launcher) requires an elevated install; fall back to "python" for per-user installs
    $resolved = $Binary
    if (-not (Get-Command $Binary -ErrorAction SilentlyContinue)) {
        if ($Binary -eq "py" -and (Get-Command "python" -ErrorAction SilentlyContinue)) {
            $resolved = "python"
        }
    }
    if (Get-Command $resolved -ErrorAction SilentlyContinue) {
        Write-Green "$DisplayName installed successfully."
        # Keep the rest of the script working with whichever binary is available
        if ($resolved -ne $Binary) {
            Set-Alias -Name $Binary -Value $resolved -Scope Script -ErrorAction SilentlyContinue
        }
    } else {
        Write-Red "Failed to install $DisplayName. Please install it manually and re-run."
        Write-Host "  Tip: Download from https://www.python.org/downloads/ and ensure 'Add to PATH' is checked."
        exit 1
    }
}

# ── Check / install required tools ───────────────────────────────────────────
Write-Host "Checking required tools..."
Write-Host ""

Require-Tool -Binary "py"      -WingetId "Python.Python.3.11" -DisplayName "Python 3"
Require-Tool -Binary "node"    -WingetId "OpenJS.NodeJS"       -DisplayName "Node.js"

# Java 21 required - the Java Hold Service is a required component
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
Write-Blue "`nStarting Backend Server..."
Set-Location (Join-Path $ScriptDir "booking_system_backend")

if (-not (Test-Path ".venv")) {
    Write-Host "Creating Python virtual environment..."
    # Use py launcher if available, otherwise fall back to python
    $pyExe = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }
    & $pyExe -m venv .venv
}

Write-Host "Installing Python dependencies..."
.\.venv\Scripts\python -m pip install -q -r requirements.txt

# Start-Process cannot redirect stdout and stderr to the same file path.
# Use separate files; Uvicorn writes everything to stderr so backend.log.err is
# the useful one. Both are cleaned up on exit.
$backendLog    = Join-Path $ScriptDir "booking_system_backend\backend.log"
$backendErrLog = Join-Path $ScriptDir "booking_system_backend\backend.log.err"
$backendDir    = Join-Path $ScriptDir "booking_system_backend"
$pythonExe     = Join-Path $backendDir ".venv\Scripts\python.exe"
# Launch directly — no wrapper job, so we hold the real PID and Stop-Process works.
$backendProc = Start-Process -FilePath $pythonExe -ArgumentList "server.py" `
    -RedirectStandardOutput $backendLog -RedirectStandardError $backendErrLog `
    -WorkingDirectory $backendDir -NoNewWindow -PassThru

# ── Health-check backend (15 attempts, 2 s apart) ────────────────────────────
# curl.exe (ships with Windows 10+) is used instead of Invoke-WebRequest.
# IWR deadlocks when the child process has redirected stdout/stderr pipes that
# fill faster than PowerShell drains them — curl.exe has no such issue.
Write-Host "Waiting for backend to start..."
$backendReady = $false
for ($i = 1; $i -le 15; $i++) {
    Start-Sleep -Seconds 2
    $code = curl.exe -s -o NUL -w "%{http_code}" --max-time 2 "http://localhost:8001/" 2>$null
    if ($code -match '^\d+$' -and [int]$code -lt 500) {
        $backendReady = $true
        break
    }
}

if (-not $backendReady) {
    Write-Red "Backend failed to start. Check booking_system_backend\backend.log.err for errors."
    Stop-Process -Id $backendProc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Green "Backend started on http://localhost:8001"

# ── Start Java Hold Service ───────────────────────────────────────────────────
Write-Blue "`nStarting Java Hold Service..."
$javaDir    = Join-Path $ScriptDir "booking_system_inventory_hold_service"
$javaLog    = Join-Path $javaDir "java.log"
$javaErrLog = Join-Path $javaDir "java.log.err"

# mvn is a .cmd script on Windows — Start-Process requires the full name.
$mvnCmd = $null
$_mvn = Get-Command mvn.cmd -ErrorAction SilentlyContinue
if ($_mvn) { $mvnCmd = $_mvn.Source }
if (-not $mvnCmd) {
    $_mvn = Get-Command mvn -ErrorAction SilentlyContinue
    if ($_mvn) { $mvnCmd = $_mvn.Source }
}
if (-not $mvnCmd) {
    Write-Red "mvn not found on PATH. Please install Maven and re-run."
    Stop-Process -Id $backendProc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

# Inject PYTHON_BACKEND_URL so the hold service can reach the Python backend.
$env:PYTHON_BACKEND_URL = "http://localhost:8001"

$javaProc = Start-Process -FilePath $mvnCmd `
    -ArgumentList "-q", "spring-boot:run" `
    -RedirectStandardOutput $javaLog -RedirectStandardError $javaErrLog `
    -WorkingDirectory $javaDir -NoNewWindow -PassThru

# Maven startup is slow — allow up to 60 s (30 × 2 s)
Write-Host "Waiting for Java Hold Service to start..."
$javaReady = $false
for ($i = 1; $i -le 30; $i++) {
    Start-Sleep -Seconds 2
    $code = curl.exe -s -o NUL -w "%{http_code}" --max-time 2 "http://localhost:8080/api/v1/health" 2>$null
    if ($code -match '^\d+$' -and [int]$code -lt 500) {
        $javaReady = $true
        break
    }
}

if (-not $javaReady) {
    Write-Red "Java Hold Service failed to start. Check booking_system_inventory_hold_service\java.log.err for errors."
    Stop-Process -Id $backendProc.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $javaProc.Id   -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Green "Java Hold Service started on http://localhost:8080"

# ── Start Frontend ────────────────────────────────────────────────────────────
Write-Blue "`nStarting Frontend Server..."
$frontendDir    = Join-Path $ScriptDir "booking_system_frontend"
$frontendLog    = Join-Path $frontendDir "frontend.log"
$frontendErrLog = Join-Path $frontendDir "frontend.log.err"

Set-Location $frontendDir

if (-not (Test-Path "node_modules")) {
    Write-Host "Installing frontend dependencies..."
    # npm is a .cmd script on Windows; route through cmd.exe so it resolves
    & cmd.exe /c "npm install"
}

# We invoke node.exe directly (bypassing npm/cmd.exe wrappers) so that
# Start-Process holds the real long-running PID. npm.cmd and cmd.exe are
# short-lived launchers — Start-Process on them returns a PID that exits
# within seconds, making HasExited=true immediately and breaking the
# keep-alive loop. node_modules/.bin/vite.cmd itself reveals the real call:
#   node  node_modules/vite/bin/vite.js
$nodeExe    = (Get-Command node -ErrorAction SilentlyContinue).Source
$viteScript = Join-Path $frontendDir "node_modules\vite\bin\vite.js"
if (-not $nodeExe) {
    Write-Red "node.exe not found on PATH. Please install Node.js and re-run."
    Stop-Process -Id $backendProc.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $javaProc.Id   -Force -ErrorAction SilentlyContinue
    exit 1
}
if (-not (Test-Path $viteScript)) {
    Write-Red "Vite not found at $viteScript. Run 'npm install' in booking_system_frontend and re-run."
    Stop-Process -Id $backendProc.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $javaProc.Id   -Force -ErrorAction SilentlyContinue
    exit 1
}
# The vite script path may contain spaces (e.g. "IBM Bob Hackathon 2026").
# Pass it as a single quoted token so node.exe receives it as one argument.
$frontendProc = Start-Process -FilePath $nodeExe `
    -ArgumentList "`"$viteScript`"" `
    -RedirectStandardOutput $frontendLog -RedirectStandardError $frontendErrLog `
    -WorkingDirectory $frontendDir -NoNewWindow -PassThru

# ── Health-check frontend (15 attempts, 2 s apart) ───────────────────────────
Write-Host "Waiting for frontend to start..."
$frontendReady = $false
for ($i = 1; $i -le 15; $i++) {
    Start-Sleep -Seconds 2
    $code = curl.exe -s -o NUL -w "%{http_code}" --max-time 2 "http://localhost:5173/" 2>$null
    if ($code -match '^\d+$' -and [int]$code -lt 500) {
        $frontendReady = $true
        break
    }
}

if (-not $frontendReady) {
    Write-Red "Frontend failed to start. Check booking_system_frontend\frontend.log.err for errors."
    Stop-Process -Id $backendProc.Id  -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $javaProc.Id     -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $frontendProc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Green "Frontend started on http://localhost:5173"

# ── Summary ───────────────────────────────────────────────────────────────────
Set-Location $ScriptDir
Write-Host ""
Write-Host "======================================================="
Write-Host "Galaxium Travels is running!" -ForegroundColor White
Write-Host ""
Write-Host "   Backend:      http://localhost:8001"
Write-Host "   Hold Service: http://localhost:8080"
Write-Host "   Frontend:     http://localhost:5173"
Write-Host "   API Docs:     http://localhost:8001/docs"
Write-Host ""
Write-Host "Press Ctrl+C to stop. Backend log: booking_system_backend\backend.log.err"
Write-Host "======================================================="

# Keep the script alive until Ctrl+C or until a child process crashes.
# We poll HasExited instead of Wait-Process. npm/cmd.exe wrappers are
# short-lived launchers whose PID exits seconds after spawning Node —
# Wait-Process on those PIDs would unblock immediately and kill everything.
# By running node.exe directly above, $frontendProc holds the real Vite PID.
$cleanExit = $false
try {
    while ($true) {
        Start-Sleep -Seconds 2
        if ($backendProc.HasExited) {
            Write-Red "Backend process exited unexpectedly. Check booking_system_backend\backend.log.err"
            break
        }
        if ($javaProc.HasExited) {
            Write-Red "Java Hold Service exited unexpectedly. Check booking_system_inventory_hold_service\java.log.err"
            break
        }
        if ($frontendProc.HasExited) {
            Write-Red "Frontend process exited unexpectedly. Check booking_system_frontend\frontend.log.err"
            break
        }
    }
} catch [System.Management.Automation.PipelineStoppedException] {
    # Ctrl+C raises PipelineStoppedException — clean exit, safe to remove logs
    $cleanExit = $true
} finally {
    Stop-Process -Id $backendProc.Id  -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $javaProc.Id     -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $frontendProc.Id -Force -ErrorAction SilentlyContinue
    # Only delete log files on a clean Ctrl+C exit. On unexpected crashes,
    # preserve them so the user can inspect what went wrong.
    if ($cleanExit) {
        Remove-Item $backendLog     -ErrorAction SilentlyContinue
        Remove-Item $backendErrLog  -ErrorAction SilentlyContinue
        Remove-Item $javaLog        -ErrorAction SilentlyContinue
        Remove-Item $javaErrLog     -ErrorAction SilentlyContinue
        Remove-Item $frontendLog    -ErrorAction SilentlyContinue
        Remove-Item $frontendErrLog -ErrorAction SilentlyContinue
    }
}

# Made with Bob
