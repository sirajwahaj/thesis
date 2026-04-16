#!/usr/bin/env bash
# =============================================================================
# Create Kind Cluster for Thesis K8s Experiments
#
# Creates a single-node Kind cluster named 'thesis', loads the workload
# container image, and waits for node readiness.
#
# Usage:
#   bash scripts/create-kind-cluster.sh
#   bash scripts/create-kind-cluster.sh --reset    # Delete and recreate
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="thesis"

RESET=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset) RESET=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ---- Auto-detect Docker/podman socket for kind ----
if [[ -z "${DOCKER_HOST:-}" ]]; then
  # Find the thesis podman machine socket if running
  THESIS_SOCK="$(ls /var/folders/*/T/podman/thesis-api.sock 2>/dev/null | head -1 || true)"
  if [[ -S "${THESIS_SOCK}" ]]; then
    export DOCKER_HOST="unix://${THESIS_SOCK}"
    echo "→ Using podman machine 'thesis': ${DOCKER_HOST}"
  elif [[ -S "/var/run/docker.sock" ]]; then
    export DOCKER_HOST="unix:///var/run/docker.sock"
    echo "→ Using Docker socket: ${DOCKER_HOST}"
  fi
fi

echo ""
echo "── Kind Cluster Setup --------------------------------------------"

# ---- Check prerequisites ----
for tool in kind kubectl; do
  if ! command -v "$tool" &>/dev/null; then
    echo "[FAIL] $tool not found. Run: make bootstrap"
    exit 1
  fi
done

# ---- Reset if requested ----
if [[ "$RESET" == "true" ]]; then
  echo "→ Deleting existing cluster '$CLUSTER_NAME'..."
  kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
  echo "[OK] Cluster deleted"
fi

# ---- Check if cluster already exists ----
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "[OK] Kind cluster '$CLUSTER_NAME' already exists"
  # Ensure kubeconfig is set
  kind export kubeconfig --name "$CLUSTER_NAME"
  echo "[OK] kubeconfig exported"
else
  echo "→ Creating Kind cluster '$CLUSTER_NAME'..."
  kind create cluster \
    --name "$CLUSTER_NAME" \
    --config "$SCRIPT_DIR/kind-config.yaml" \
    --wait 60s
  echo "[OK] Kind cluster created"
fi

# ---- Export kubeconfig ----
kind export kubeconfig --name "$CLUSTER_NAME"
echo "[OK] kubeconfig active for context kind-$CLUSTER_NAME"

# ---- Create local registry for image loading ----
echo ""
echo "→ Setting up local image registry (localhost:$REGISTRY_PORT)..."
if docker inspect "$REGISTRY_NAME" &>/dev/null 2>&1 ||
   podman inspect "$REGISTRY_NAME" &>/dev/null 2>&1; then
  echo "[OK] Registry '$REGISTRY_NAME' already running"
else
  # Try podman first, fall back to docker
  if command -v podman &>/dev/null; then
    podman run -d --restart=always \
      -p "127.0.0.1:${REGISTRY_PORT}:5000" \
      --name "$REGISTRY_NAME" \
      registry:2
    # Connect registry to Kind network
    podman network connect "kind" "$REGISTRY_NAME" 2>/dev/null || true
  else
    docker run -d --restart=always \
      -p "127.0.0.1:${REGISTRY_PORT}:5000" \
      --name "$REGISTRY_NAME" \
      registry:2
    docker network connect "kind" "$REGISTRY_NAME" 2>/dev/null || true
  fi
  echo "[OK] Local registry started at localhost:$REGISTRY_PORT"
fi

# Apply the registry ConfigMap so Kind nodes can discover it
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

# ---- Wait for node ready ----
echo ""
echo "→ Waiting for node to be ready..."
kubectl wait --for=condition=ready node --all --timeout=120s
echo "[OK] All nodes ready"

# ---- Summary ----
echo ""
echo "── Cluster Info ------------------------------------------------──"
kubectl cluster-info --context "kind-$CLUSTER_NAME"
echo ""
kubectl get nodes -o wide
echo ""
echo "[OK] Kind cluster '$CLUSTER_NAME' is ready."
echo "   Image registry: localhost:$REGISTRY_PORT"
echo "   Next: make k8s-metrics && make k8s-deploy-dagster"
echo ""
