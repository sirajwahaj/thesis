#!/usr/bin/env bash
# =============================================================================
# Deploy Metrics Server to Kind Cluster
#
# The Metrics Server provides resource usage data (CPU/memory) via:
#   kubectl top pod
#   kubectl top node
#
# Required for Exp2A, Exp2B, Exp2C data collection (collect_k8s_metrics.sh).
# Deployed with --kubelet-insecure-tls flag (required for Kind).
#
# Usage:
#   bash scripts/deploy-metrics-server.sh
# =============================================================================
set -euo pipefail

CLUSTER_NAME="thesis"

echo ""
echo "── Metrics Server Setup ----------------------------------------──"

# ---- Prerequisites ----
for tool in kubectl helm; do
  if ! command -v "$tool" &>/dev/null; then
    echo "[FAIL] $tool not found. Run: make bootstrap"
    exit 1
  fi
done

# Ensure correct cluster context
kind export kubeconfig --name "$CLUSTER_NAME" 2>/dev/null || true

# ---- Add Helm repo ----
echo "→ Adding metrics-server Helm repo..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm repo update
echo "[OK] Helm repo ready"

# ---- Check if already installed ----
if helm status metrics-server -n kube-system &>/dev/null 2>&1; then
  echo "[OK] metrics-server already installed — upgrading if needed..."
  INSTALL_CMD="upgrade"
else
  echo "→ Installing metrics-server..."
  INSTALL_CMD="install"
fi

# ---- Install / Upgrade ----
helm "$INSTALL_CMD" metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args={--kubelet-insecure-tls} \
  --wait \
  --timeout 120s

echo "[OK] metrics-server deployed"

# ---- Wait for rollout ----
echo ""
echo "→ Waiting for metrics-server rollout..."
kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s
echo "[OK] metrics-server rollout complete"

# ---- Verify it works (may take 30–60s to collect first metrics) ----
echo ""
echo "→ Verifying metrics-server API..."
MAX_WAIT=90
ELAPSED=0
until kubectl top node &>/dev/null 2>&1 || [[ $ELAPSED -ge $MAX_WAIT ]]; do
  echo "   Waiting for metrics API to become available... (${ELAPSED}s / ${MAX_WAIT}s)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

if kubectl top node &>/dev/null 2>&1; then
  echo "[OK] kubectl top node works:"
  kubectl top node
else
  echo "[WARN]  kubectl top node not yet available — it may need 1–2 minutes to collect data."
  echo "   Retry with: kubectl top node"
fi

echo ""
echo "[OK] Metrics Server ready."
echo "   Next: make k8s-deploy-dagster"
echo ""
