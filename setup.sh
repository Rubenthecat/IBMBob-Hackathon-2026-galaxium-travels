#!/usr/bin/env bash
# setup.sh — First-run bootstrap for Galaxium Travels
# Prompts for Docker or Local mode, installs missing dependencies, then launches the app.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Colours ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ─── OS Detection ────────────────────────────────────────────────────────────
OS="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  darwin)  PLATFORM="macos" ;;
  linux)   PLATFORM="linux" ;;
  msys*|cygwin*|mingw*)
    echo ""
    echo -e "${RED}❌ Windows detected.${NC}"
    echo ""
    echo "This script requires bash (macOS/Linux). On Windows, please run:"
    echo ""
    echo -e "  ${BOLD}.\\setup.ps1${NC}   (PowerShell — recommended)"
    echo "  or use WSL2 and re-run this script inside WSL."
    echo ""
    exit 1
    ;;
  *)
    echo -e "${YELLOW}⚠️  Unknown OS '$OS'. Proceeding as Linux.${NC}"
    PLATFORM="linux"
    ;;
esac

echo ""
echo -e "${BOLD}🌌 Galaxium Travels — First-Run Setup${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── Mode Prompt ─────────────────────────────────────────────────────────────
echo "How would you like to run the application?"
echo ""
echo "  1) Docker  (recommended — no local dependencies needed beyond Docker)"
echo "  2) Local   (runs directly on your machine — installs missing tools)"
echo ""
read -rp "Enter your choice [1 or 2]: " MODE_CHOICE

case "$MODE_CHOICE" in
  1) MODE="docker" ;;
  2) MODE="local"  ;;
  *)
    echo -e "${RED}Invalid choice. Please re-run and enter 1 or 2.${NC}"
    exit 1
    ;;
esac

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# DOCKER MODE
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "docker" ]; then
  echo -e "${BLUE}🐳 Docker mode selected.${NC}"
  echo ""

  # Check docker binary
  if ! command -v docker &>/dev/null; then
    echo -e "${RED}❌ Docker is not installed.${NC}"
    echo ""
    if [ "$PLATFORM" = "macos" ]; then
      echo "Install Docker Desktop: https://docs.docker.com/desktop/install/mac-install/"
      echo "Or via Homebrew:  brew install --cask docker"
    else
      echo "Install Docker: https://docs.docker.com/engine/install/"
    fi
    echo ""
    echo "After installing Docker, re-run: ./setup.sh"
    exit 1
  fi

  # Check docker daemon is running
  if ! docker info &>/dev/null 2>&1; then
    echo -e "${RED}❌ Docker daemon is not running.${NC}"
    echo ""
    if [ "$PLATFORM" = "macos" ]; then
      echo "Start Docker Desktop from your Applications folder, wait for it to"
      echo "finish starting (whale icon in the menu bar stops animating), then re-run:"
    else
      echo "Start the Docker daemon:"
      echo "  sudo systemctl start docker"
      echo "Then re-run:"
    fi
    echo ""
    echo "  ./setup.sh"
    exit 1
  fi

  echo -e "${GREEN}✅ Docker is running.${NC}"
  echo ""
  echo "Starting Galaxium Travels with Docker Compose..."
  echo "(This may take a few minutes on the first run while images are built.)"
  echo ""
  echo "  Backend:   http://localhost:8001"
  echo "  Frontend:  http://localhost:5173"
  echo "  API Docs:  http://localhost:8001/docs"
  echo ""
  echo "To also start the Java Hold Service, run:"
  echo "  docker compose --profile hold-service up --build"
  echo ""

  cd "$SCRIPT_DIR"
  exec docker compose up --build
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LOCAL MODE
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}💻 Local mode selected.${NC}"
echo ""

# ─── Linux: request sudo upfront ────────────────────────────────────────────
if [ "$PLATFORM" = "linux" ]; then
  echo -e "${YELLOW}Some tools may need to be installed via apt-get, which requires sudo.${NC}"
  echo -n "Grant sudo access for this session? [y/N] "
  read -r SUDO_OK
  if [[ "$SUDO_OK" =~ ^[Yy]$ ]]; then
    sudo -v   # cache credentials
    # Keep sudo alive for the duration of the script
    ( while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done ) 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
    SUDO_CMD="sudo"
  else
    echo -e "${YELLOW}⚠️  Skipping sudo. Any missing apt-get tools will not be installed.${NC}"
    SUDO_CMD=""
  fi
fi

# ─── Helper: require_tool ────────────────────────────────────────────────────
# Usage: require_tool <binary> <brew-pkg> <apt-pkg> [description]
require_tool() {
  local binary="$1"
  local brew_pkg="$2"
  local apt_pkg="$3"
  local desc="${4:-$binary}"

  if command -v "$binary" &>/dev/null; then
    echo -e "${GREEN}✅ $desc found: $(command -v "$binary")${NC}"
    return 0
  fi

  echo -e "${YELLOW}⚠️  $desc not found. Installing...${NC}"

  if [ "$PLATFORM" = "macos" ]; then
    if ! command -v brew &>/dev/null; then
      echo -e "${RED}❌ Homebrew is not installed. Install it first:${NC}"
      echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      exit 1
    fi
    brew install "$brew_pkg"
  elif [ "$PLATFORM" = "linux" ]; then
    if [ -z "$SUDO_CMD" ]; then
      echo -e "${RED}❌ Cannot install $desc without sudo. Please install it manually: apt-get install $apt_pkg${NC}"
      return 1
    fi
    $SUDO_CMD apt-get update -qq
    $SUDO_CMD apt-get install -y "$apt_pkg"
  fi

  if command -v "$binary" &>/dev/null; then
    echo -e "${GREEN}✅ $desc installed successfully.${NC}"
  else
    echo -e "${RED}❌ Failed to install $desc. Please install it manually and re-run.${NC}"
    exit 1
  fi
}

# ─── Check / install required tools ─────────────────────────────────────────
echo "Checking required tools..."
echo ""

require_tool python3   python3       python3         "Python 3"
require_tool node      node          nodejs          "Node.js"
require_tool curl      curl          curl            "curl"
require_tool lsof      lsof          lsof            "lsof"

# Java 17 or 21 required — the Java Hold Service is a required component
require_tool java openjdk@21 openjdk-21-jdk "Java 21"

# After installing via brew on macOS, the JDK may not be on PATH automatically
if [ "$PLATFORM" = "macos" ] && ! command -v java &>/dev/null; then
  BREW_JAVA="$(brew --prefix openjdk@21 2>/dev/null)/bin"
  if [ -d "$BREW_JAVA" ]; then
    export PATH="$BREW_JAVA:$PATH"
    echo -e "${YELLOW}   Added $BREW_JAVA to PATH for this session.${NC}"
    echo "   To make this permanent, add to your shell profile:"
    echo "   export PATH=\"\$(brew --prefix openjdk@21)/bin:\$PATH\""
  fi
fi

require_tool mvn maven maven "Maven"

echo ""

# ─── Create .env from .env.example ──────────────────────────────────────────
ENV_EXAMPLE="$SCRIPT_DIR/booking_system_frontend/.env.example"
ENV_FILE="$SCRIPT_DIR/booking_system_frontend/.env"

if [ -f "$ENV_EXAMPLE" ] && [ ! -f "$ENV_FILE" ]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  echo -e "${GREEN}✅ Created booking_system_frontend/.env from .env.example${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BOLD}🚀 All dependencies ready. Launching Galaxium Travels...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$SCRIPT_DIR"
exec ./start.sh

# Made with Bob
