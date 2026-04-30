#!/usr/bin/env bash
# =============================================================================
# Deploy Thesis App to VM
#
# Copies docker-compose.yml + config to the VM, authenticates with GHCR,
# pulls the latest images, and starts all containers.
#
# Prerequisites:
#   - VM is running (make vm-up)
#   - Image is pushed to GHCR (make build && make push)
#   - vm-ip.txt contains the VM IP
#
# Usage:
#   bash scripts/deploy-vm.sh
#
# Environment:
#   GHCR_TOKEN   GitHub token with read:packages scope (required for private)
#   GHCR_USER    GitHub username (default: sirajwahaj)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VM_IP_FILE="$REPO_ROOT/vm-ip.txt"
SSH_KEY="$HOME/.ssh/thesis_vm"
VM_DIR="/opt/thesis"

# ---- Read VM IP ----
if [[ ! -f "$VM_IP_FILE" ]]; then
    echo "[FAIL] vm-ip.txt not found."
    echo "   Run: make vm-up"
    exit 1
fi

VM_IP="$(cat "$VM_IP_FILE" | tr -d '[:space:]')"
if [[ -z "$VM_IP" ]]; then
    echo "[FAIL] vm-ip.txt is empty."
    echo "   Run: make vm-up"
    exit 1
fi

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"

echo ""
echo "================================================================"
echo "  Deploy Thesis App → VM ($VM_IP)"
echo "================================================================"
echo ""

# ---- Verify SSH is reachable ----
echo "-> Checking VM connectivity..."
if ! ssh $SSH_OPTS ubuntu@"$VM_IP" "echo ok" &>/dev/null; then
    echo "[FAIL] Cannot reach VM at $VM_IP."
    echo "   Check: multipass list"
    echo "   Or: make vm-up"
    exit 1
fi
echo "[OK] VM reachable"

# ---- Verify Docker is running on VM ----
echo ""
echo "-> Verifying Docker on VM..."
if ! ssh $SSH_OPTS ubuntu@"$VM_IP" "docker info" &>/dev/null; then
    echo "[FAIL] Docker not running on VM."
    echo "   Re-run provisioning: make vm-provision"
    exit 1
fi
echo "[OK] Docker running"

# ---- Create deployment directory on VM ----
echo ""
echo "-> Creating deployment directory $VM_DIR on VM..."
ssh $SSH_OPTS ubuntu@"$VM_IP" \
    "sudo mkdir -p '$VM_DIR' && sudo chown ubuntu:ubuntu '$VM_DIR'"
echo "[OK] Directory ready"

# ---- Copy files to VM ----
echo ""
echo "-> Copying deployment files to VM..."

# docker-compose.yml
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    "$REPO_ROOT/infrastructure/docker-compose.yml" \
    ubuntu@"$VM_IP":"$VM_DIR/docker-compose.yml"

# dagster.yaml (instance config — DockerRunLauncher + PostgreSQL settings)
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    "$REPO_ROOT/src/dagster.yaml" \
    ubuntu@"$VM_IP":"$VM_DIR/dagster.yaml"

# workspace.yaml (code location — points to gRPC workload server)
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    "$REPO_ROOT/src/workspace.yaml" \
    ubuntu@"$VM_IP":"$VM_DIR/workspace.yaml"

echo "[OK] Files copied"

# ---- Authenticate with GHCR (if token provided) ----
echo ""
GHCR_USER="${GHCR_USER:-sirajwahaj}"
if [[ -n "${GHCR_TOKEN:-}" ]]; then
    echo "-> Logging into GHCR on VM..."
    # Pass token via stdin to avoid it appearing in ps output
    ssh $SSH_OPTS ubuntu@"$VM_IP" \
        "echo '${GHCR_TOKEN}' | docker login ghcr.io -u '${GHCR_USER}' --password-stdin"
    echo "[OK] Authenticated with ghcr.io"
else
    echo "[INFO] GHCR_TOKEN not set — skipping docker login."
    echo "   If the image is private, set:"
    echo "     export GHCR_TOKEN=<your_github_token>"
    echo "     export GHCR_USER=sirajwahaj"
    echo "   Then re-run: make deploy"
fi

# ---- Pull images ----
echo ""
echo "-> Pulling images on VM..."
ssh $SSH_OPTS ubuntu@"$VM_IP" \
    "cd '$VM_DIR' && docker compose pull"
echo "[OK] Images pulled"

# ---- Stop any existing containers ----
echo ""
echo "-> Stopping existing containers (if any)..."
ssh $SSH_OPTS ubuntu@"$VM_IP" \
    "cd '$VM_DIR' && docker compose down 2>/dev/null || true"

# ---- Start containers ----
echo ""
echo "-> Starting containers..."
ssh $SSH_OPTS ubuntu@"$VM_IP" \
    "cd '$VM_DIR' && docker compose up -d"
echo "[OK] Containers started"

# ---- Wait for Dagster to be ready ----
echo ""
echo "-> Waiting for Dagster webserver to be ready (up to 60s)..."
WAITED=0
MAX_WAIT=60
READY=false
while [[ $WAITED -lt $MAX_WAIT ]]; do
    if ssh $SSH_OPTS ubuntu@"$VM_IP" \
        "curl -sf http://localhost:3001/server_info > /dev/null 2>&1"; then
        READY=true
        break
    fi
    sleep 5
    WAITED=$((WAITED + 5))
done

echo ""
echo "================================================================"
if [[ "$READY" == "true" ]]; then
    echo "[OK] Deployment complete — Dagster is ready"
else
    echo "[WARN] Deployment complete — Dagster may still be starting up"
fi
echo "================================================================"
echo ""
echo "   Dagster UI:  http://$VM_IP:3001"
echo "   PostgreSQL:  $VM_IP:5432 (user: dagster, db: dagster)"
echo "   gRPC:        $VM_IP:4000"
echo ""
echo "Useful commands:"
echo "  ssh -i $SSH_KEY ubuntu@$VM_IP"
echo "  docker compose logs -f       (run from $VM_DIR on the VM)"
echo ""
echo "  make destroy                 — delete the VM"
echo "  make truncate                — clear experiment data"
echo ""
