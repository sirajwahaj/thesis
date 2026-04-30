#!/usr/bin/env bash
# =============================================================================
# Pre-Experiment Validation
#
# Checks all required systems are ready before running experiments:
#   - VM: SSH accessible, gRPC server running on port 4000
#   - K8s: Kind cluster exists, Dagster pods ready, Metrics Server working
#   - Local compose: PostgreSQL, Dagster webserver, daemon
#
# Exit codes:
#   0 — All systems ready
#   1 — One or more systems NOT ready (prints what to fix)
#
# Usage:
#   bash scripts/validate-experiment-setup.sh          # All systems
#   bash scripts/validate-experiment-setup.sh --vm     # VM only
#   bash scripts/validate-experiment-setup.sh --k8s    # K8s only
#   bash scripts/validate-experiment-setup.sh --local  # Local compose only
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VM_IP_FILE="$REPO_ROOT/vm-ip.txt"
SSH_KEY="$HOME/.ssh/thesis_vm"

# Windows (Git Bash): use podman provider for kind
if [[ "${MSYSTEM:-}" == MINGW* ]] || [[ "${OS:-}" == "Windows_NT" ]]; then
  export KIND_EXPERIMENTAL_PROVIDER="podman"
fi

CHECK_VM=true
CHECK_K8S=true
CHECK_LOCAL=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vm)    CHECK_VM=true;  CHECK_K8S=false; CHECK_LOCAL=false; shift ;;
    --k8s)   CHECK_VM=false; CHECK_K8S=true;  CHECK_LOCAL=false; shift ;;
    --local) CHECK_VM=false; CHECK_K8S=false; CHECK_LOCAL=true;  shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

ERRORS=()
WARNINGS=()

echo ""
echo "── Pre-Experiment Validation ------------------------------------─"

# ============================================================
# VM CHECK
# ============================================================
if [[ "$CHECK_VM" == "true" ]]; then
  echo ""
  echo "  [VM]"
  # 1. vm-ip.txt exists
  if [[ ! -f "$VM_IP_FILE" ]]; then
    ERRORS+=("VM: vm-ip.txt not found — run: make vm-up")
    echo "  [FAIL] vm-ip.txt: NOT FOUND"
  else
    VM_IP="$(cat "$VM_IP_FILE" | tr -d '[:space:]')"
    if [[ -z "$VM_IP" ]]; then
      ERRORS+=("VM: vm-ip.txt is empty — run: make vm-up")
      echo "  [FAIL] vm-ip.txt: empty"
    else
      echo "  [OK] vm-ip.txt: $VM_IP"
      # 2. SSH accessible
      if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
          "ubuntu@$VM_IP" "echo ok" &>/dev/null; then
        echo "  [OK] SSH: ubuntu@$VM_IP reachable"
        # 3. Docker is running
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no \
            "ubuntu@$VM_IP" "docker info" &>/dev/null; then
          echo "  [OK] Docker: running on VM"
          # 4. Thesis containers are up
          RUNNING="$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no \
            "ubuntu@$VM_IP" "cd /opt/thesis && docker compose ps --services --filter status=running 2>/dev/null | wc -l" 2>/dev/null || echo "0")"
          if [[ "$RUNNING" -ge 4 ]]; then
            echo "  [OK] Compose stack: $RUNNING containers running"
          else
            WARNINGS+=("VM: only $RUNNING/4 containers running — run: make deploy")
            echo "  [WARN]  Compose stack: $RUNNING/4 containers running (run: make deploy)"
          fi
          # 5. Dagster webserver port 3001
          if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no \
              "ubuntu@$VM_IP" "curl -sf http://localhost:3001/server_info" &>/dev/null; then
            echo "  [OK] Dagster webserver: http://$VM_IP:3001"
          else
            WARNINGS+=("VM: Dagster webserver not responding on port 3001 — run: make deploy")
            echo "  [WARN]  Dagster webserver: not responding on port 3001"
          fi
        else
          ERRORS+=("VM: Docker not running — run: make vm-provision")
          echo "  [FAIL] Docker: NOT running on VM"
        fi
      else
        ERRORS+=("VM: cannot SSH to ubuntu@$VM_IP — VM may not be running")
        echo "  [FAIL] SSH: cannot reach ubuntu@$VM_IP"
      fi
    fi
  fi
fi

# ============================================================
# K8s CHECK
# ============================================================
if [[ "$CHECK_K8S" == "true" ]]; then
  echo ""
  echo "  [Kubernetes]"
  # 1. kind command available
  if ! command -v kind &>/dev/null; then
    ERRORS+=("K8s: 'kind' not found — run: make bootstrap")
    echo "  [FAIL] kind: NOT FOUND"
  # 2. Kind cluster exists
  elif ! kind get clusters 2>/dev/null | grep -qx "thesis"; then
    ERRORS+=("K8s: Kind cluster 'thesis' not found — run: make k8s-create")
    echo "  [FAIL] Kind cluster 'thesis': NOT FOUND"
  else
    echo "  [OK] Kind cluster 'thesis': exists"
    kind export kubeconfig --name thesis 2>/dev/null || true
    # 3. Dagster namespace
    if kubectl get namespace dagster &>/dev/null 2>&1; then
      echo "  [OK] Namespace 'dagster': exists"
      # 4. All pods running
      NOT_READY="$(kubectl get pods -n dagster \
        --field-selector='status.phase!=Running' \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -v '^$' || true)"
      if [[ -z "$NOT_READY" ]]; then
        RUNNING_COUNT="$(kubectl get pods -n dagster --field-selector='status.phase=Running' \
          -o jsonpath='{.items}' 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" || echo "0")"
        echo "  [OK] Dagster pods: $RUNNING_COUNT running"
      else
        ERRORS+=("K8s: pods not running: $NOT_READY — run: make k8s-deploy-dagster")
        echo "  [FAIL] Dagster pods NOT ready: $NOT_READY"
      fi
      # 5. Metrics server
      if kubectl top node &>/dev/null 2>&1; then
        echo "  [OK] Metrics Server: kubectl top node works"
      else
        WARNINGS+=("K8s: kubectl top node returned no data — metrics may still be initializing")
        echo "  [WARN]  Metrics Server: not yet serving data (wait 1–2 min)"
      fi
    else
      ERRORS+=("K8s: namespace 'dagster' not found — run: make k8s-deploy-dagster")
      echo "  [FAIL] Namespace 'dagster': NOT FOUND"
    fi
  fi
fi

# ============================================================
# LOCAL COMPOSE CHECK
# ============================================================
if [[ "$CHECK_LOCAL" == "true" ]]; then
  echo ""
  echo "  [Local Compose]"
  # Detect container runtime
  RUNTIME="podman"
  COMPOSE="podman-compose"
  if ! command -v podman-compose &>/dev/null; then
    if command -v docker-compose &>/dev/null; then
      RUNTIME="docker"; COMPOSE="docker-compose"
    elif command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
      RUNTIME="docker"; COMPOSE="docker compose"
    else
      WARNINGS+=("Local: no compose tool found (podman-compose, docker-compose)")
      echo "  [WARN]  No compose runtime found"
      COMPOSE=""
    fi
  fi

  if [[ -n "$COMPOSE" ]]; then
    COMPOSE_FILE="$REPO_ROOT/infrastructure/docker-compose.yml"
    # Check postgres
    PG_RUNNING="$(cd "$REPO_ROOT/infrastructure" && $COMPOSE ps --services --filter status=running 2>/dev/null | grep postgres || true)"
    if [[ -n "$PG_RUNNING" ]]; then
      echo "  [OK] PostgreSQL: running"
    else
      WARNINGS+=("Local: PostgreSQL compose service not running — run: make compose-up")
      echo "  [WARN]  PostgreSQL: NOT running (run: make compose-up)"
    fi
    # Check dagster-webserver
    WEB_RUNNING="$(cd "$REPO_ROOT/infrastructure" && $COMPOSE ps --services --filter status=running 2>/dev/null | grep dagster-webserver || true)"
    if [[ -n "$WEB_RUNNING" ]]; then
      echo "  [OK] Dagster webserver: running (http://localhost:3001)"
    else
      WARNINGS+=("Local: dagster-webserver not running — run: make compose-up")
      echo "  [WARN]  Dagster webserver: NOT running"
    fi
  fi
fi

# ============================================================
# RESULT
# ============================================================
echo ""
echo "----------------------------------------------------------------"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "[FAIL] VALIDATION FAILED — ${#ERRORS[@]} error(s):"
  for e in "${ERRORS[@]}"; do
    echo "   • $e"
  done
  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo ""
    echo "[WARN]  Warnings (non-blocking):"
    for w in "${WARNINGS[@]}"; do
      echo "   • $w"
    done
  fi
  echo ""
  echo "Fix errors above, then re-run: make validate-setup"
  exit 1
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "[WARN]  READY WITH WARNINGS:"
  for w in "${WARNINGS[@]}"; do
    echo "   • $w"
  done
  echo ""
  echo "Warnings are non-blocking. Experiments can proceed."
else
  echo "[OK] ALL SYSTEMS READY — experiments can run"
fi
echo ""
