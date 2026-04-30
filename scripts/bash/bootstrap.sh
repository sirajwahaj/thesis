#!/usr/bin/env bash
# =============================================================================
# Bootstrap: Install Local Dependencies (macOS)
#
# Installs the tools needed to build and deploy the thesis infrastructure.
# Everything runs on your LOCAL machine (macOS), not inside the VM.
#
# Tools installed via Homebrew:
#   - Multipass  — creates the Ubuntu VM
#   - Ansible    — provisions Docker CE on the VM
#   - kubectl    — for K8s experiments
#   - kind       — creates the K8s cluster
#   - helm       — deploys Dagster on K8s
#
# Usage:
#   bash scripts/bash/bootstrap.sh               # Install all deps + create data dirs
#   bash scripts/bash/bootstrap.sh --deps-only   # Install deps only (no dirs)
#   bash scripts/bash/bootstrap.sh --validate-only  # Check deps, do NOT install
#   make bootstrap                               # Same as no-flag version
#
# Windows: run  scripts/powershell/bootstrap.ps1  instead.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEPS_ONLY=false
VALIDATE_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deps-only)     DEPS_ONLY=true;     shift ;;
    --validate-only) VALIDATE_ONLY=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

OS="$(uname -s)"
ARCH="$(uname -m)"

echo ""
echo "================================================================"
echo "  THESIS BENCHMARKING — Bootstrap"
echo "================================================================"
echo "  Host OS:   $OS"
echo "  Arch:      $ARCH"
echo "  Repo:      $REPO_ROOT"
echo ""

# ---- Windows: delegate to PowerShell ----
if [[ "$OS" == *"NT"* ]] || [[ "${OS_WIN:-}" == "Windows_NT" ]]; then
    echo "[WARN] Windows detected — run PowerShell bootstrap instead:"
    echo "  powershell.exe -ExecutionPolicy Bypass -File scripts\\powershell\\bootstrap.ps1"
    exit 0
fi

# ---- Linux hint ----
if [[ "$OS" == "Linux" ]]; then
    echo "[INFO] Linux host: install multipass, ansible, docker, kind, helm manually."
    echo "  Then run: make vm-up"
    exit 0
fi

# ---- macOS: check Homebrew ----
echo "-> Checking Homebrew..."
if ! command -v brew &>/dev/null; then
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        echo "[FAIL] Homebrew: not installed"
        exit 1
    fi
    echo "   Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
echo "[OK] Homebrew: $(brew --version | head -1)"

# ---- Helper: install or validate a tool ----
check_or_install() {
    local cmd="$1"
    local pkg="${2:-$1}"
    local cask_arg="${3:-}"

    if command -v "$cmd" &>/dev/null; then
        echo "[OK] $cmd: $($cmd --version 2>&1 | head -1)"
        return 0
    fi

    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        echo "[FAIL] $cmd: not installed (run: brew install${cask_arg:+ --cask} $pkg)"
        return 1
    fi

    echo "-> Installing $pkg..."
    if [[ -n "$cask_arg" ]]; then
        brew install --cask "$pkg"
    else
        brew install "$pkg"
    fi
    echo "[OK] $cmd installed"
}

MISSING=0
check_or_install ansible   ansible       ""        || MISSING=$((MISSING+1))
check_or_install multipass multipass     "--cask"  || MISSING=$((MISSING+1))
check_or_install kubectl   kubernetes-cli ""       || MISSING=$((MISSING+1))
check_or_install kind      kind           ""       || MISSING=$((MISSING+1))
check_or_install helm      helm           ""       || MISSING=$((MISSING+1))

# ---- Docker: check or remind ----
echo ""
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    echo "[OK] Docker: $(docker --version)"
else
    echo "[WARN] Docker Desktop not running or not installed."
    echo "   Install: https://docs.docker.com/desktop/install/mac/"
    echo "   (Required for: make build, make push, local testing)"
fi

if [[ "$VALIDATE_ONLY" == "true" ]]; then
    echo ""
    if [[ $MISSING -gt 0 ]]; then
        echo "[FAIL] $MISSING tool(s) missing — run: make bootstrap"
        exit 1
    fi
    echo "[OK] All required tools found"
    exit 0
fi

if [[ "$DEPS_ONLY" == "true" ]]; then
    echo ""
    echo "[OK] Dependencies installed. Run: make vm-up"
    exit 0
fi

# ---- Create required data directories ----
echo ""
echo "-> Creating experiment data directories..."
mkdir -p "$REPO_ROOT/data/raw"
mkdir -p "$REPO_ROOT/data/processed"
mkdir -p "$REPO_ROOT/results"
echo "[OK] data/ directories ready"

echo ""
echo "================================================================"
echo "[OK] Bootstrap complete"
echo "================================================================"
echo ""
echo "Next steps:"
echo "  make vm-up            — Create VM + install Docker CE on it"
echo "  make build            — Build Docker workload image locally"
echo "  make push             — Push image to ghcr.io"
echo "  make deploy           — Deploy containers on VM"
echo "  make k8s-setup        — Set up Kind cluster for K8s experiments"
echo ""
