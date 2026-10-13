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

# Suppress interactive apt/debconf prompts on Linux (e.g. needrestart "daemons" dialog).
# These are set only in this script's process environment — they do not persist in the user's shell.
if [ "$PLATFORM" = "linux" ]; then
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a
fi

# ─── Package manager + distro detection (Linux) ──────────────────────────────
# Sets PKG_MANAGER: apt | dnf | yum | zypper | unknown
# Sets DISTRO_ID:   value of ID from /etc/os-release (e.g. ubuntu, debian, fedora, amzn)
# Used by both Docker mode (plugin installs) and Local mode (tool installs).
PKG_MANAGER="unknown"
DISTRO_ID="unknown"
if [ "$PLATFORM" = "linux" ]; then
  if [ -f /etc/os-release ]; then
    DISTRO_ID="$(. /etc/os-release && echo "${ID:-unknown}" | tr '[:upper:]' '[:lower:]')"
  fi
  if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
  elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
  elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
  elif command -v zypper &>/dev/null; then
    PKG_MANAGER="zypper"
  fi
fi

# ─── Helper: pkg_install <pkg-apt> [pkg-dnf] [pkg-yum] [pkg-zypper] ─────────
# Installs a package using the detected package manager.
# If only one argument is given the same name is used for all managers.
# Caller is responsible for having called `sudo true` first if needed.
pkg_install() {
  local _apt="${1}"
  local _dnf="${2:-$1}"
  local _yum="${3:-$2}"
  local _zyp="${4:-$3}"
  # _yum defaults to _dnf value; _zyp defaults to _yum value — all fall back to _apt if unset
  _yum="${_yum:-$_dnf}"
  _zyp="${_zyp:-$_yum}"
  case "$PKG_MANAGER" in
    apt)    $SUDO_CMD apt-get install -y "$_apt" ;;
    dnf)    $SUDO_CMD dnf install -y "$_dnf" ;;
    yum)    $SUDO_CMD yum install -y "$_yum" ;;
    zypper) $SUDO_CMD zypper install -y "$_zyp" ;;
    *)
      echo -e "${RED}❌ Cannot install $_apt — unsupported package manager.${NC}"
      return 1
      ;;
  esac
}

# ─── Helper: pkg_update ───────────────────────────────────────────────────────
# Refreshes the package index for the detected package manager.
pkg_update() {
  case "$PKG_MANAGER" in
    apt)    $SUDO_CMD apt-get update -qq ;;
    dnf)    $SUDO_CMD dnf makecache -q ;;
    yum)    $SUDO_CMD yum makecache -q ;;
    zypper) $SUDO_CMD zypper refresh ;;
  esac
}

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
      echo "Docker can be installed via your package manager (${PKG_MANAGER})."
      echo ""
      read -rp "Would you like to install Docker now? [y/N] " _install_docker
      if [[ "$_install_docker" =~ ^[Yy]$ ]]; then
        # Package name varies by manager:
        #   apt    — docker.io  (universe repo, ships with Debian/Ubuntu; good enough to bootstrap)
        #   dnf    — docker     (Fedora/RHEL from Docker's own repo once added)
        #   yum    — docker     (CentOS/RHEL 7)
        #   zypper — docker     (openSUSE)
        case "$PKG_MANAGER" in
          apt)    _docker_engine_pkg="docker.io" ;;
          *)      _docker_engine_pkg="docker" ;;
        esac
        echo "  (installing ${_docker_engine_pkg}...)"
        SUDO_CMD="sudo"
        pkg_update
        if pkg_install "$_docker_engine_pkg" 2>/dev/null; then
          echo -e "${GREEN}✅ ${_docker_engine_pkg} installed.${NC}"
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

  # ── Helper: ensure Docker's official repo is configured (distro-aware) ──────
  # docker-compose-plugin and docker-buildx-plugin ship via download.docker.com,
  # not the default distro repos. This function is idempotent and handles:
  #   apt  — Debian, Ubuntu, Raspbian, Linux Mint, Pop!_OS, Kali, etc.
  #   dnf  — Fedora, RHEL 8+, CentOS Stream 8+, Rocky Linux, AlmaLinux, Amazon Linux 2023
  #   yum  — RHEL/CentOS 7, Amazon Linux 2
  #   zypper — openSUSE Leap / Tumbleweed
  _ensure_docker_repo() {
    _detect_pkg_manager

    case "$PKG_MANAGER" in

      apt)
        # Already present if apt-cache knows the package
        if apt-cache show docker-compose-plugin &>/dev/null 2>&1; then
          return 0
        fi
        echo "  (adding Docker's official apt repository for plugin packages...)"
        sudo apt-get install -y ca-certificates curl gnupg lsb-release

        # Resolve the correct repo path: Ubuntu uses /linux/ubuntu, everything
        # else that ships apt (Debian, Raspbian, Kali, Mint…) uses /linux/debian.
        local _apt_distro
        case "$DISTRO_ID" in
          ubuntu|linuxmint|pop)  _apt_distro="ubuntu" ;;
          *)                     _apt_distro="debian" ;;
        esac

        # Codename: prefer UBUNTU_CODENAME (set on Ubuntu/Mint) over VERSION_CODENAME
        # (set on Debian/others); fall back to lsb_release.
        local _codename
        _codename="$(. /etc/os-release 2>/dev/null && \
          echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
        if [ -z "$_codename" ] && command -v lsb_release &>/dev/null; then
          _codename="$(lsb_release -cs)"
        fi
        if [ -z "$_codename" ]; then
          echo -e "${RED}❌ Cannot determine OS codename. Add the Docker repo manually:${NC}"
          echo "   https://docs.docker.com/engine/install/"
          exit 1
        fi

        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "https://download.docker.com/linux/${_apt_distro}/gpg" \
          | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${_apt_distro} \
${_codename} stable" \
          | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update -qq
        ;;

      dnf)
        # Fedora / RHEL 8+ / CentOS Stream / Rocky / Alma / Amazon Linux 2023
        if dnf list installed docker-compose-plugin &>/dev/null 2>&1; then
          return 0
        fi
        echo "  (adding Docker's official dnf repository for plugin packages...)"
        sudo dnf -y install dnf-plugins-core
        # Amazon Linux 2023 uses its own repo; everything else uses the CE repo.
        case "$DISTRO_ID" in
          amzn)
            sudo dnf config-manager --add-repo \
              https://download.docker.com/linux/rhel/docker-ce.repo
            ;;
          *)
            sudo dnf config-manager --add-repo \
              https://download.docker.com/linux/fedora/docker-ce.repo
            ;;
        esac
        sudo dnf makecache -q
        ;;

      yum)
        # RHEL / CentOS 7, Amazon Linux 2
        if yum list installed docker-compose-plugin &>/dev/null 2>&1; then
          return 0
        fi
        echo "  (adding Docker's official yum repository for plugin packages...)"
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo \
          https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum makecache -q
        ;;

      zypper)
        # openSUSE Leap / Tumbleweed
        if zypper search -i docker-compose-plugin &>/dev/null 2>&1; then
          return 0
        fi
        echo "  (adding Docker's official zypper repository for plugin packages...)"
        sudo zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo || true
        sudo zypper refresh
        ;;

      *)
        echo -e "${YELLOW}⚠️  Unrecognised package manager — cannot add Docker repo automatically.${NC}"
        echo "   Add it manually: https://docs.docker.com/engine/install/"
        ;;
    esac
  }

  # ── Helper: install a Docker plugin package (distro-aware) ──────────────────
  # Usage: _install_docker_pkg <package-name>
  # Docker mode never goes through the Local mode sudo prompt, so SUDO_CMD is
  # not set here. Temporarily set it to "sudo" for the pkg_install helper.
  _install_docker_pkg() {
    local _pkg="$1"
    local _saved_sudo="${SUDO_CMD:-}"
    SUDO_CMD="sudo"
    pkg_install "$_pkg"
    local _rc=$?
    SUDO_CMD="$_saved_sudo"
    return $_rc
  }

  # Check docker compose (V2 plugin) is available
  if ! docker compose version &>/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Docker Compose plugin (V2) is not installed. Installing automatically...${NC}"
    if [ "$PLATFORM" = "macos" ]; then
      echo -e "${RED}❌ Update Docker Desktop to the latest version — Compose V2 is bundled.${NC}"
      echo "  https://docs.docker.com/desktop/release-notes/"
      exit 1
    else
      _ensure_docker_repo
      if _install_docker_pkg docker-compose-plugin; then
        echo -e "${GREEN}✅ docker-compose-plugin installed.${NC}"
      else
        echo -e "${RED}❌ Auto-install failed. Install manually:${NC}"
        echo "   https://docs.docker.com/compose/install/linux/"
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
    echo -e "${YELLOW}⚠️  Docker Buildx plugin is not installed. Installing automatically...${NC}"
    if [ "$PLATFORM" = "macos" ]; then
      echo -e "${RED}❌ Update Docker Desktop to the latest version — buildx is bundled from v4+.${NC}"
      echo "  https://docs.docker.com/desktop/release-notes/"
      exit 1
    else
      _ensure_docker_repo
      if _install_docker_pkg docker-buildx-plugin; then
        echo -e "${GREEN}✅ docker-buildx-plugin installed.${NC}"
      else
        echo -e "${RED}❌ Auto-install failed. Install manually:${NC}"
        echo "   https://docs.docker.com/buildx/working-with-buildx/"
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

  # ── Ensure the current user can reach the Docker socket without sudo ─────────
  # On Linux, /var/run/docker.sock is owned by the docker group. If the current
  # user isn't in that group the compose command fails with "permission denied".
  # We add them to the docker group here for future sessions, then for this
  # session use `sudo -E -g docker` to run compose with the docker group active
  # immediately — no logout/login required, works on all distros (sudo ≥ 1.7).
  _USE_SUDO_DOCKER=false
  if [ "$PLATFORM" = "linux" ]; then
    if ! docker info &>/dev/null 2>&1; then
      if getent group docker &>/dev/null; then
        echo "  (adding $USER to the docker group so the socket is accessible...)"
        sudo usermod -aG docker "$USER" 2>/dev/null || true
      fi
      _USE_SUDO_DOCKER=true
    fi
  fi

  echo "Starting Galaxium Travels with Docker Compose..."
  echo "(This may take a few minutes on the first run while images are built.)"
  echo ""
  echo "  Backend:   http://localhost:8001"
  echo "  Frontend:  http://localhost:5173"
  echo "  API Docs:  http://localhost:8001/docs"
  echo ""
  cd "$SCRIPT_DIR"
  if [ "$_USE_SUDO_DOCKER" = true ]; then
    exec sudo -E -g docker docker compose --profile hold-service up --build
  else
    exec docker compose --profile hold-service up --build
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LOCAL MODE
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${BLUE}💻 Local mode selected.${NC}"
echo ""

# ─── Linux: request sudo upfront ────────────────────────────────────────────
if [ "$PLATFORM" = "linux" ]; then
  echo -e "${YELLOW}Some tools may need to be installed via your package manager (${PKG_MANAGER}), which requires sudo.${NC}"
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
    echo -e "${YELLOW}⚠️  Skipping sudo. Any missing tools will not be installed automatically.${NC}"
    SUDO_CMD=""
  fi
fi

# ─── Helper: require_tool ────────────────────────────────────────────────────
# Usage: require_tool <binary> <brew-pkg> <linux-pkg> [description]
# <linux-pkg> is used as the package name for all Linux package managers.
# For packages with different names per manager use pkg_install directly.
require_tool() {
  local binary="$1"
  local brew_pkg="$2"
  local linux_pkg="$3"
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
      echo -e "${RED}❌ Cannot install $desc without sudo. Please install it manually.${NC}"
      return 1
    fi
    pkg_update
    pkg_install "$linux_pkg"
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
# apt  — NodeSource setup script (Node 20 LTS)
# dnf/yum — NodeSource rpm setup script
# zypper  — NodeSource rpm setup script (SLES/openSUSE)
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
    echo "   https://nodejs.org/en/download/package-manager"
    exit 1
  fi

  # Ensure curl is available first (used by every NodeSource path)
  if ! command -v curl &>/dev/null; then
    pkg_update
    pkg_install curl
  fi

  case "$PKG_MANAGER" in
    apt)
      curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO_CMD -E bash -
      $SUDO_CMD apt-get install -y nodejs
      ;;
    dnf)
      curl -fsSL https://rpm.nodesource.com/setup_20.x | $SUDO_CMD -E bash -
      $SUDO_CMD dnf install -y nodejs
      ;;
    yum)
      curl -fsSL https://rpm.nodesource.com/setup_20.x | $SUDO_CMD -E bash -
      $SUDO_CMD yum install -y nodejs
      ;;
    zypper)
      curl -fsSL https://rpm.nodesource.com/setup_20.x | $SUDO_CMD -E bash -
      $SUDO_CMD zypper install -y nodejs20
      ;;
    *)
      echo -e "${RED}❌ Cannot install Node.js automatically on this system.${NC}"
      echo "   Install manually: https://nodejs.org/en/download/package-manager"
      exit 1
      ;;
  esac

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
# On Debian/Ubuntu, python3 does not ship with ensurepip — needs python3.X-venv.
# On RPM-based distros (Fedora, RHEL, etc.) and openSUSE, venv ships with the
# standard python3 package so this block is a no-op there.
if [ "$PLATFORM" = "linux" ] && [ -n "$SUDO_CMD" ]; then
  if ! python3 -m venv --help &>/dev/null 2>&1 || ! python3 -c "import ensurepip" &>/dev/null 2>&1; then
    if [ "$PKG_MANAGER" = "apt" ]; then
      PYTHON_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
      VENV_PKG="python${PYTHON_VER}-venv"
      echo -e "${YELLOW}⚠️  python3 venv/ensurepip not available. Installing ${VENV_PKG}...${NC}"
      pkg_update
      if ! $SUDO_CMD apt-get install -y "$VENV_PKG" 2>/dev/null; then
        $SUDO_CMD apt-get install -y python3-venv
      fi
    else
      # On dnf/yum/zypper systems venv is part of python3 — nothing to install.
      echo -e "${YELLOW}⚠️  python3 venv not working. Try: $SUDO_CMD $PKG_MANAGER install -y python3${NC}"
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
  # Resolve package names per manager:
  #   apt    — openjdk-21-jdk / openjdk-17-jdk      (Debian, Ubuntu)
  #   dnf    — java-21-openjdk-devel / java-17-...   (Fedora, RHEL, Rocky, Alma, Amazon)
  #   yum    — java-21-openjdk-devel / java-17-...   (RHEL/CentOS 7, Amazon Linux 2)
  #   zypper — java-21-openjdk-devel / java-17-...   (openSUSE)
  case "$PKG_MANAGER" in
    apt)    _java21_pkg="openjdk-21-jdk";         _java17_pkg="openjdk-17-jdk" ;;
    *)      _java21_pkg="java-21-openjdk-devel";  _java17_pkg="java-17-openjdk-devel" ;;
  esac

  _install_java_linux() {
    pkg_update
    if ! pkg_install "$_java21_pkg" 2>/dev/null; then
      if ! pkg_install "$_java17_pkg" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Could not install Java automatically. Please install manually:${NC}"
        echo "   e.g. sudo $PKG_MANAGER install -y $_java17_pkg"
        echo "   or via SDKMAN: sdk install java 17.0.x-tem"
      fi
    fi
  }

  if command -v java &>/dev/null; then
    _jv="$(_java_major_version)"
    if [ "$_jv" = "17" ] || [ "$_jv" = "21" ]; then
      echo -e "${GREEN}✅ Java $_jv already installed — skipping.${NC}"
    else
      echo -e "${YELLOW}⚠️  Java $_jv found but Hold Service requires 17 or 21. Attempting install...${NC}"
      _install_java_linux
    fi
  else
    _install_java_linux
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
