#!/usr/bin/env bash
# =============================================================================
# Bootstrap: Cross-Platform Benchmarking Environment Setup
#
# Entry point for macOS. Detects OS, routes to platform-specific setup,
# provisions dependencies, and validates the environment is ready for
# thesis experiments.
#
# Usage:
#   bash scripts/bootstrap.sh                  # Full setup
#   bash scripts/bootstrap.sh --skip-vm        # Skip VM creation (if exists)
#   bash scripts/bootstrap.sh --deps-only      # Only install dependencies
#   bash scripts/bootstrap.sh --validate-only  # Only validate existing setup
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- Parse args ----
SKIP_VM=false
DEPS_ONLY=false
VALIDATE_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-vm)       SKIP_VM=true; shift ;;
    --deps-only)     DEPS_ONLY=true; shift ;;
    --validate-only) VALIDATE_ONLY=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ---- Detect OS ----
OS="$(uname -s)"
ARCH="$(uname -m)"

echo ""
echo "================================================================"
echo "  THESIS BENCHMARKING — Bootstrap"
echo "================================================================"
echo ""
echo "  Host OS:   $OS"
echo "  Arch:      $ARCH"
echo "  Repo:      $REPO_ROOT"
echo ""

case "$OS" in
  Darwin)
    echo "→ Detected macOS"
    if [[ "$ARCH" == "arm64" ]]; then
      echo "→ Apple Silicon (M-series) — UTM will be used for VM"
    else
      echo "→ Intel Mac — UTM will be used for VM"
    fi
    echo ""
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
      bash "$SCRIPT_DIR/setup-macos.sh" --validate-only
    elif [[ "$DEPS_ONLY" == "true" ]]; then
      bash "$SCRIPT_DIR/setup-macos.sh" --deps-only
    elif [[ "$SKIP_VM" == "true" ]]; then
      bash "$SCRIPT_DIR/setup-macos.sh"
    else
      bash "$SCRIPT_DIR/setup-macos.sh"
      bash "$SCRIPT_DIR/create-vm-macos.sh"
    fi
    ;;
  MINGW64_NT-*|MSYS_NT-*|CYGWIN_NT-*)
    echo "→ Detected Windows (Git Bash / MSYS2)"
    echo ""
    echo "[WARN]  Windows bootstrap requires PowerShell."
    echo "   Please run: powershell.exe -ExecutionPolicy Bypass -File scripts\\bootstrap.ps1"
    echo ""
    exit 0
    ;;
  Linux)
    echo "→ Detected Linux"
    echo ""
    echo "[WARN]  Linux host support is not implemented."
    echo "   For experiments, set up the VM using the Multipass alternative:"
    echo "   See docs/multipass-alternative.md"
    echo ""
    exit 1
    ;;
  *)
    echo "[FAIL] Unsupported OS: $OS"
    exit 1
    ;;
esac

# ---- Create required data directories ----
echo ""
echo "→ Creating experiment data directories..."
mkdir -p "$REPO_ROOT/data/raw/exp1-vm-degradation/vm"
mkdir -p "$REPO_ROOT/data/raw/exp2-kubernetes-isolation/part-a"
mkdir -p "$REPO_ROOT/data/raw/exp2-kubernetes-isolation/part-b-blast-radius/vm"
mkdir -p "$REPO_ROOT/data/raw/exp2-kubernetes-isolation/part-b-blast-radius/k8s"
mkdir -p "$REPO_ROOT/data/raw/exp2-kubernetes-isolation/part-c-spike"
mkdir -p "$REPO_ROOT/data/raw/exp3-overhead-crossover"
mkdir -p "$REPO_ROOT/data/processed"
mkdir -p "$REPO_ROOT/results"
echo "   [OK] data/ directories ready"

echo ""
echo "================================================================"
echo "  [OK] Bootstrap complete"
echo "================================================================"
echo ""
echo "  Next steps:"
echo "    make vm-provision    # Ansible: install Python, Dagster, PostgreSQL on VM"
echo "    make k8s-setup       # Kind cluster + Metrics Server + Dagster on K8s"
echo "    make experiments     # Run all 4 experiments"
echo "    make all             # Do all of the above in sequence"
echo ""
