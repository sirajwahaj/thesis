#!/usr/bin/env bash
# =============================================================================
# macOS Dependency Setup
#
# Installs and configures all dependencies required for the thesis
# benchmarking environment on macOS (Intel or Apple Silicon):
#   - Homebrew packages: podman, kind, kubectl, helm, ansible, python3
#   - UTM (via Homebrew cask) for VM virtualisation
#   - podman machine with 4 vCPU / 8 GB RAM
#
# Usage (called by bootstrap.sh — can also be run standalone):
#   bash scripts/setup-macos.sh
#   bash scripts/setup-macos.sh --deps-only      # Skip podman machine init
#   bash scripts/setup-macos.sh --validate-only  # Only check, don't install
# =============================================================================
set -euo pipefail

VALIDATE_ONLY=false
DEPS_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --validate-only) VALIDATE_ONLY=true; shift ;;
    --deps-only)     DEPS_ONLY=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ---- Helpers ----
print_section() { echo ""; echo "── $1 ----------------------------------------------------──"; }
check_cmd()     { command -v "$1" &>/dev/null; }
brew_installed() { brew list --formula 2>/dev/null | grep -qx "$1"; }
cask_installed() { brew list --cask 2>/dev/null | grep -qx "$1"; }

ERRORS=()

# ---- (1) Homebrew ----
print_section "Homebrew"
if check_cmd brew; then
  echo "[OK] brew $(brew --version | head -1 | awk '{print $2}')"
else
  if [[ "$VALIDATE_ONLY" == "true" ]]; then
    ERRORS+=("brew: not installed")
  else
    echo "→ Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Apple Silicon: ensure brew is in PATH for this session
    if [[ "$(uname -m)" == "arm64" ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    echo "[OK] Homebrew installed"
  fi
fi

if [[ "$VALIDATE_ONLY" == "true" ]]; then
  # Validate-only mode: check tools, report, exit
  print_section "Validating installed tools"
  TOOLS=(podman kind kubectl helm ansible python3 git)
  for tool in "${TOOLS[@]}"; do
    if check_cmd "$tool"; then
      echo "  [OK] $tool ($(command -v "$tool"))"
    else
      ERRORS+=("$tool: not found in PATH")
      echo "  [FAIL] $tool: NOT FOUND"
    fi
  done
  # Check UTM
  if [[ -d "/Applications/UTM.app" ]]; then
    echo "  [OK] UTM.app present"
  else
    ERRORS+=("UTM: /Applications/UTM.app not found")
    echo "  [FAIL] UTM: NOT FOUND"
  fi
  # Check podman machine
  if podman machine list 2>/dev/null | grep -q "thesis"; then
    echo "  [OK] podman machine 'thesis' exists"
  else
    ERRORS+=("podman machine 'thesis': not found — run: make bootstrap")
    echo "  [FAIL] podman machine 'thesis': NOT FOUND"
  fi
  if [[ ${#ERRORS[@]} -eq 0 ]]; then
    echo ""
    echo "[OK] All dependencies are installed and ready."
    exit 0
  else
    echo ""
    echo "[FAIL] Validation failed — missing: ${ERRORS[*]}"
    echo "   Run: make bootstrap   (to install everything)"
    exit 1
  fi
fi

# ---- (2) Core CLI Tools (Homebrew) ----
print_section "Installing core CLI tools"

BREW_PACKAGES=(podman kind kubectl helm ansible python@3.12 git)
for pkg in "${BREW_PACKAGES[@]}"; do
  PKG_NAME="${pkg%@*}"
  if brew_installed "$pkg" || check_cmd "$PKG_NAME"; then
    echo "  [OK] $pkg already installed"
  else
    echo "  → Installing $pkg..."
    brew install "$pkg"
    echo "  [OK] $pkg installed"
  fi
done

# ---- (3) UTM (macOS VM hypervisor) ----
print_section "UTM hypervisor"
if [[ -d "/Applications/UTM.app" ]]; then
  echo "[OK] UTM.app already installed"
elif cask_installed "utm"; then
  echo "[OK] UTM installed via Homebrew cask"
else
  echo "→ Installing UTM via Homebrew cask..."
  brew install --cask utm
  echo "[OK] UTM installed"
fi

# ---- (4) podman machine ----
if [[ "$DEPS_ONLY" == "true" ]]; then
  echo ""
  echo "→ Skipping podman machine setup (--deps-only)"
else
  print_section "podman machine"

  # Get list of machines (names only)
  MACHINES="$(podman machine list --format '{{.Name}}' 2>/dev/null || true)"

  # Detect if 'thesis' exists
  MACHINE_EXISTS=false
  while read -r name; do
    if [[ "$name" == "thesis" ]]; then
      MACHINE_EXISTS=true
      break
    fi
  done <<< "$MACHINES"

  # Detect currently running machine (if any)
  RUNNING_MACHINE="$(podman machine list --format '{{.Name}} {{.Running}}' 2>/dev/null | awk '$2=="true" {print $1}')"

  # If another machine is running → stop it (Podman allows only one)
  if [[ -n "$RUNNING_MACHINE" && "$RUNNING_MACHINE" != "thesis" ]]; then
    echo "→ Detected running machine: $RUNNING_MACHINE"
    echo "→ Stopping it (Podman allows only one active VM)..."
    podman machine stop "$RUNNING_MACHINE"
  fi

  # Create machine if it doesn't exist
  if [[ "$MACHINE_EXISTS" == "false" ]]; then
    echo "→ Creating podman machine 'thesis' (4 vCPU, 8192 MB RAM, 60 GB disk)..."
    podman machine init \
      --cpus 4 \
      --memory 8192 \
      --disk-size 60 \
      thesis
    echo "[OK] podman machine 'thesis' created"
  else
    echo "[OK] podman machine 'thesis' already exists"
  fi

  # Start machine if not running
  if ! podman machine list --format '{{.Name}} {{.Running}}' | grep -q "^thesis true"; then
    echo "→ Starting podman machine 'thesis'..."
    podman machine start thesis
  else
    echo "[OK] podman machine 'thesis' already running"
  fi

  # ---- Podman socket setup ----
  PODMAN_SOCKET="$(podman machine inspect thesis --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null || true)"

  if [[ -n "$PODMAN_SOCKET" && -S "$PODMAN_SOCKET" ]]; then
    echo "[OK] podman socket: $PODMAN_SOCKET"

    # Persist DOCKER_HOST if not already set
    if ! grep -q "DOCKER_HOST=.*podman" "$HOME/.zshrc" 2>/dev/null; then
      {
        echo ""
        echo "# podman socket for docker-compose compatibility (thesis benchmarking)"
        echo "export DOCKER_HOST=\"unix://$PODMAN_SOCKET\""
      } >> "$HOME/.zshrc"

      echo "→ Added DOCKER_HOST to ~/.zshrc (restart shell or run: source ~/.zshrc)"
    fi

    export DOCKER_HOST="unix://$PODMAN_SOCKET"
  else
    echo "[WARN]  Could not detect podman socket"
  fi
fi

# ---- (5) Summary ----
echo ""
echo "── Summary ----------------------------------------------------─"
for tool in podman kind kubectl helm ansible python3; do
  if check_cmd "$tool"; then
    VERSION="$($tool --version 2>/dev/null | head -1 || echo 'unknown')"
    echo "  [OK] $tool → $VERSION"
  else
    echo "  [FAIL] $tool → NOT FOUND"
    ERRORS+=("$tool missing after install")
  fi
done

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "[FAIL] Setup completed with errors:"
  for e in "${ERRORS[@]}"; do echo "   - $e"; done
  exit 1
fi

echo ""
echo "[OK] macOS setup complete. All dependencies installed."
echo ""
