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
  _docker_just_installed=false
  if ! command -v docker &>/dev/null; then
    echo -e "${RED}❌ Docker is not installed.${NC}"
    echo ""
    if [ "$PLATFORM" = "macos" ]; then
      echo "Docker can be installed via Homebrew:"
      echo "  brew install --cask docker"
      echo ""
      read -rp "Would you like to install Docker Desktop via Homebrew now? [y/N] " _install_docker
      if [[ "$_install_docker" =~ ^[Yy]$ ]]; then
        if ! command -v brew &>/dev/null; then
          echo -e "${RED}❌ Homebrew is not installed. Install it first:${NC}"
          echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
          echo "Then re-run: ./setup.sh"
          exit 1
        fi
        brew install --cask docker
        _docker_just_installed=true
        echo ""
        echo -e "${YELLOW}⚠️  Docker Desktop was installed. You must start it before we can continue.${NC}"
        echo "Open Docker Desktop from your Applications folder and wait for it to finish"
        echo "starting (the whale icon in the menu bar will stop animating)."
        echo ""
        read -rp "Press Enter once Docker Desktop is running to continue... "
      else
        echo ""
        echo "No problem. Install Docker Desktop manually when you're ready:"
        echo "  https://docs.docker.com/desktop/install/mac-install/"
        echo "Then re-run: ./setup.sh"
        exit 0
      fi
    else
      echo "Docker can be installed via apt-get."
      echo ""
      read -rp "Would you like to install Docker now? [y/N] " _install_docker
      if [[ "$_install_docker" =~ ^[Yy]$ ]]; then
        echo "  (installing docker.io...)"
        sudo apt-get update -qq
        if sudo apt-get install -y docker.io 2>/dev/null; then
          echo -e "${GREEN}✅ docker.io installed.${NC}"
          sudo systemctl enable --now docker || true
          echo "  (waiting for Docker daemon to start...)"
          sleep 4
          _docker_just_installed=true
        else
          echo -e "${RED}❌ Auto-install failed. Install manually:${NC}"
          echo "   https://docs.docker.com/engine/install/"
          echo "Then re-run: ./setup.sh"
          exit 1
        fi
        # Re-probe after install
        if ! command -v docker &>/dev/null; then
          echo -e "${RED}❌ Docker still not available after install. Please install manually and re-run.${NC}"
          exit 1
        fi
      else
        echo ""
        echo "No problem. Install Docker manually when you're ready:"
        echo "  https://docs.docker.com/engine/install/"
        echo "Then re-run: ./setup.sh"
        exit 0
      fi
    fi
  fi

  # Check docker daemon is running
  if ! docker info &>/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Docker daemon is not running.${NC}"
    echo ""
    if [ "$PLATFORM" = "macos" ]; then
      if [ "$_docker_just_installed" = true ]; then
        echo "Docker Desktop was just installed but does not appear to be running yet."
        echo ""
      fi
      echo "Start Docker Desktop from your Applications folder, wait for it to"
      echo "finish starting (whale icon in the menu bar stops animating), then re-run:"
      echo ""
      echo "  ./setup.sh"
      exit 1
    else
      echo "Starting the Docker daemon automatically..."
      # Try systemctl first (systemd), fall back to service (SysV/upstart),
      # then fall back to launching dockerd directly (containers / WSL without systemd).
      # Note: stderr is NOT redirected so sudo can prompt for a password if needed.
      if sudo systemctl start docker; then
        echo "  (systemctl start docker — waiting 4s...)"
      elif sudo service docker start; then
        echo "  (service docker start — waiting 4s...)"
      else
        echo "  (systemctl/service unavailable — starting dockerd directly...)"
        sudo dockerd > /tmp/dockerd.log 2>&1 &
        echo "  (waiting for dockerd to initialize...)"
      fi
      sleep 4
      # Use sudo docker info so socket permission doesn't cause a false failure
      # if the current user isn't yet in the docker group.
      if ! sudo docker info &>/dev/null 2>&1; then
        echo -e "${RED}❌ Docker daemon still not responding after start attempt.${NC}"
        echo ""
        echo "Try starting it manually in another terminal:"
        echo "  sudo systemctl start docker    # systemd systems"
        echo "  sudo service docker start      # SysV/upstart systems"
        echo "  sudo dockerd &                 # minimal/container environments"
        echo ""
        echo "Then re-run: ./setup.sh"
        exit 1
      fi
      echo -e "${GREEN}✅ Docker daemon started.${NC}"
      echo ""
    fi
  fi

  # Check docker compose (V2 plugin) is available
  if ! docker compose version &>/dev/null 2>&1; then
    echo -e "${RED}❌ Docker Compose plugin (V2) is not installed.${NC}"
    echo ""
    if [ "$PLATFORM" = "macos" ]; then
      echo "Update Docker Desktop to the latest version — Compose V2 is bundled."
      echo "  https://docs.docker.com/desktop/release-notes/"
      exit 1
    else
      if sudo -n true 2>/dev/null || { echo -n "Grant sudo to install docker-compose-plugin? [y/N] " && read -r _ans && [[ "$_ans" =~ ^[Yy]$ ]] && sudo true; }; then
        echo "  (installing automatically...)"
        sudo apt-get update -qq
        if sudo apt-get install -y docker-compose-plugin 2>/dev/null; then
          echo -e "${GREEN}✅ docker-compose-plugin installed.${NC}"
        else
          echo -e "${RED}❌ Auto-install failed. Install manually:${NC}"
          echo "   sudo apt-get install -y docker-compose-plugin"
          echo "Then re-run: ./setup.sh"
          exit 1
        fi
      else
        echo "  sudo apt-get install -y docker-compose-plugin"
        echo "Then re-run: ./setup.sh"
        exit 1
      fi
    fi
    # Re-probe after install attempt
    if ! docker compose version &>/dev/null 2>&1; then
      echo -e "${RED}❌ docker compose still not available. Please install manually and re-run.${NC}"
      exit 1
    fi
  fi

  # Check docker buildx is available (required: all Dockerfiles use --platform=linux/amd64)
  if ! docker buildx version &>/dev/null 2>&1; then
    echo -e "${RED}❌ Docker Buildx plugin is not installed.${NC}"
    echo ""
    if [ "$PLATFORM" = "macos" ]; then
      echo "Update Docker Desktop to the latest version — buildx is bundled from v4+."
      echo "  https://docs.docker.com/desktop/release-notes/"
      exit 1
    else
      if sudo -n true 2>/dev/null || { echo -n "Grant sudo to install docker-buildx-plugin? [y/N] " && read -r _ans && [[ "$_ans" =~ ^[Yy]$ ]] && sudo true; }; then
        echo "  (installing automatically...)"
        sudo apt-get update -qq
        if sudo apt-get install -y docker-buildx-plugin 2>/dev/null; then
          echo -e "${GREEN}✅ docker-buildx-plugin installed.${NC}"
        else
          echo -e "${RED}❌ Auto-install failed. Install manually:${NC}"
          echo "   sudo apt-get install -y docker-buildx-plugin"
          echo "Then re-run: ./setup.sh"
          exit 1
        fi
      else
        echo "  sudo apt-get install -y docker-buildx-plugin"
        echo "Then re-run: ./setup.sh"
        exit 1
      fi
    fi
    # Re-probe after install attempt
    if ! docker buildx version &>/dev/null 2>&1; then
      echo -e "${RED}❌ docker buildx still not available. Please install manually and re-run.${NC}"
      exit 1
    fi
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
  cd "$SCRIPT_DIR"
  exec docker compose --profile hold-service up --build
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
    sudo true   # verify sudo access and cache credentials
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

# ─── Helper: install_node_linux ──────────────────────────────────────────────
# Ensures a modern Node.js (with npm) is on PATH.
# Uses the NodeSource setup script for Node 20 LTS when node/npm is missing.
install_node_linux() {
  # If both binaries are already present, nothing to do
  if command -v node &>/dev/null && command -v npm &>/dev/null; then
    echo -e "${GREEN}✅ Node.js found: $(node --version)${NC}"
    echo -e "${GREEN}✅ npm found: $(npm --version)${NC}"
    return 0
  fi

  echo -e "${YELLOW}⚠️  Node.js / npm not found. Installing via NodeSource (Node 20 LTS)...${NC}"

  if [ -z "$SUDO_CMD" ]; then
    echo -e "${RED}❌ Cannot install Node.js without sudo. Please install it manually:${NC}"
    echo "   curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
    echo "   sudo apt-get install -y nodejs"
    exit 1
  fi

  if ! command -v curl &>/dev/null; then
    $SUDO_CMD apt-get update -qq
    $SUDO_CMD apt-get install -y curl
  fi

  curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO_CMD -E bash -
  $SUDO_CMD apt-get install -y nodejs

  if command -v node &>/dev/null && command -v npm &>/dev/null; then
    echo -e "${GREEN}✅ Node.js $(node --version) and npm $(npm --version) installed successfully.${NC}"
  else
    echo -e "${RED}❌ Node.js/npm installation failed. Please install manually and re-run.${NC}"
    exit 1
  fi
}

# ─── Helper: install_maven_linux ─────────────────────────────────────────────
# Ensures Maven >= 3.8.x is on PATH. If not, installs 3.9.16 from upstream binary.
install_maven_linux() {
  if command -v mvn &>/dev/null; then
    local mvn_ver
    mvn_ver=$(mvn --version 2>/dev/null | awk '/Apache Maven/ {print $3}')
    # Accept 3.8.x or any higher minor/major (e.g. 3.9.x, 4.x)
    if [[ "$mvn_ver" =~ ^([0-9]+)\.([0-9]+) ]]; then
      local major="${BASH_REMATCH[1]}"
      local minor="${BASH_REMATCH[2]}"
      if [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 8 ]; }; then
        echo -e "${GREEN}✅ Maven found: $mvn_ver${NC}"
        return 0
      fi
    fi
  fi

  echo -e "${YELLOW}⚠️  Maven not found or too old. Installing Maven 3.9.16...${NC}"

  curl -fsSL https://downloads.apache.org/maven/maven-3/3.9.16/binaries/apache-maven-3.9.16-bin.tar.gz \
    -o /tmp/apache-maven-3.9.16-bin.tar.gz
  $SUDO_CMD tar -xzf /tmp/apache-maven-3.9.16-bin.tar.gz -C /opt/
  $SUDO_CMD ln -sf /opt/apache-maven-3.9.16/bin/mvn /usr/local/bin/mvn
  rm -f /tmp/apache-maven-3.9.16-bin.tar.gz

  if mvn --version &>/dev/null; then
    echo -e "${GREEN}✅ Maven 3.9.16 installed successfully.${NC}"
  else
    echo -e "${RED}❌ Maven installation failed. Please install manually and re-run.${NC}"
    exit 1
  fi
}

# ─── Check / install required tools ─────────────────────────────────────────
echo "Checking required tools..."
echo ""

require_tool python3   python3       python3         "Python 3"
require_tool curl      curl          curl            "curl"
require_tool lsof      lsof          lsof            "lsof"

if [ "$PLATFORM" = "macos" ]; then
  require_tool node  node  node  "Node.js"
  require_tool npm   node  npm   "npm"
elif [ "$PLATFORM" = "linux" ]; then
  install_node_linux
fi

# ─── Linux: ensure python3-venv is available ────────────────────────────────
# On Debian/Ubuntu, python3 does not ship with ensurepip; the venv module
# needs the matching python3.X-venv package or the generic python3-venv.
if [ "$PLATFORM" = "linux" ] && [ -n "$SUDO_CMD" ]; then
  PYTHON_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  VENV_PKG="python${PYTHON_VER}-venv"
  if ! python3 -m venv --help &>/dev/null 2>&1 || ! python3 -c "import ensurepip" &>/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  python3 venv/ensurepip not available. Installing ${VENV_PKG}...${NC}"
    $SUDO_CMD apt-get update -qq
    if ! $SUDO_CMD apt-get install -y "$VENV_PKG" 2>/dev/null; then
      # Fallback to the generic package name
      $SUDO_CMD apt-get install -y python3-venv
    fi
  else
    echo -e "${GREEN}✅ python3 venv support confirmed.${NC}"
  fi
fi

# Java 17 or 21 required — the Java Hold Service is a required component
_java_major_version() {
  java -version 2>&1 | head -1 | sed 's/.*version "\([0-9]*\).*/\1/'
}

if [ "$PLATFORM" = "linux" ]; then
  if command -v java &>/dev/null; then
    _jv="$(_java_major_version)"
    if [ "$_jv" = "17" ] || [ "$_jv" = "21" ]; then
      echo -e "${GREEN}✅ Java $_jv already installed — skipping.${NC}"
    else
      echo -e "${YELLOW}⚠️  Java $_jv found but Hold Service requires 17 or 21. Attempting install...${NC}"
      $SUDO_CMD apt-get update -qq
      if ! $SUDO_CMD apt-get install -y openjdk-21-jdk 2>/dev/null; then
        if ! $SUDO_CMD apt-get install -y openjdk-17-jdk 2>/dev/null; then
          echo -e "${YELLOW}⚠️  Could not install Java automatically. Please install manually:${NC}"
          echo "   sudo apt-get install -y openjdk-17-jdk"
          echo "   or via SDKMAN: sdk install java 17.0.x-tem"
        fi
      fi
    fi
  else
    $SUDO_CMD apt-get update -qq
    if ! $SUDO_CMD apt-get install -y openjdk-21-jdk 2>/dev/null; then
      if ! $SUDO_CMD apt-get install -y openjdk-17-jdk 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Could not install Java automatically. Please install manually:${NC}"
        echo "   sudo apt-get install -y openjdk-17-jdk"
        echo "   or via SDKMAN: sdk install java 17.0.x-tem"
      fi
    fi
  fi
elif [ "$PLATFORM" = "macos" ]; then
  brew install openjdk@21
  # After installing via brew on macOS, the JDK may not be on PATH automatically
  if ! command -v java &>/dev/null; then
    BREW_JAVA="$(brew --prefix openjdk@21 2>/dev/null)/bin"
    if [ -d "$BREW_JAVA" ]; then
      export PATH="$BREW_JAVA:$PATH"
      echo -e "${YELLOW}   Added $BREW_JAVA to PATH for this session.${NC}"
      echo "   To make this permanent, add to your shell profile:"
      echo "   export PATH=\"\$(brew --prefix openjdk@21)/bin:\$PATH\""
    fi
  fi
fi

if [ "$PLATFORM" = "macos" ]; then
  require_tool mvn maven maven "Maven"
elif [ "$PLATFORM" = "linux" ]; then
  install_maven_linux
fi

echo ""

# ─── Create .env from .env.example ──────────────────────────────────────────
ENV_EXAMPLE="$SCRIPT_DIR/booking_system_frontend/.env.example"
ENV_FILE="$SCRIPT_DIR/booking_system_frontend/.env"

if [ -f "$ENV_EXAMPLE" ] && [ ! -f "$ENV_FILE" ]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  echo -e "${GREEN}✅ Created booking_system_frontend/.env from .env.example${NC}"
elif [ -f "$ENV_FILE" ] && grep -q '^VITE_API_URL=http://localhost:8001' "$ENV_FILE"; then
  # Old hardcoded localhost URL breaks access when Vite is bound to 0.0.0.0 (host: true).
  # Remove it so the frontend falls back to the Vite dev-server proxy (/api → localhost:8001).
  sed -i 's|^VITE_API_URL=http://localhost:8001||' "$ENV_FILE"
  echo -e "${YELLOW}⚠️  Removed hardcoded VITE_API_URL from .env — using Vite proxy instead.${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BOLD}🚀 All dependencies ready. Launching Galaxium Travels...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$SCRIPT_DIR"
exec ./start.sh

# Made with Bob
