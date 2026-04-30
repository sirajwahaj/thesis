#!/usr/bin/env bash
# =============================================================================
# Deploy Dagster + Workload to Kind Cluster via Helm
#
# Steps:
#  1. Build and load workload image into Kind (via local registry or kind load)
#  2. Create 'dagster' namespace
#  3. Deploy PostgreSQL + Dagster (webserver, daemon, workload) via Helm
#  4. Wait for all pods to be ready
#  5. Verify gRPC health
#
# Usage:
#   bash scripts/deploy-dagster-k8s.sh
#   bash scripts/deploy-dagster-k8s.sh --reset   # Uninstall and reinstall
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLUSTER_NAME="thesis"
NAMESPACE="dagster"
HELM_RELEASE="dagster-thesis"
HELM_CHART="$REPO_ROOT/k8s/helm/dagster-thesis"
IMAGE_NAME="localhost:5001/thesis-workload"
IMAGE_TAG="latest"

RESET=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset) RESET=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo ""
echo "── Dagster K8s Deployment ----------------------------------------"

# ---- Auto-detect container runtime socket ----
if [[ -z "${DOCKER_HOST:-}" ]]; then
  # Windows (Git Bash / MINGW): use Podman Desktop named pipe
  if [[ "${MSYSTEM:-}" == MINGW* ]] || [[ "${OS:-}" == "Windows_NT" ]]; then
    export DOCKER_HOST="npipe:////./pipe/docker_engine"
    export KIND_EXPERIMENTAL_PROVIDER="podman"
    echo "→ Windows detected: using Podman (KIND_EXPERIMENTAL_PROVIDER=podman)"
  # macOS: find the podman machine socket
  elif [[ "$(uname)" == "Darwin" ]]; then
    for candidate in \
      "/var/folders"*"/T/podman/thesis-api.sock" \
      "${XDG_RUNTIME_DIR:-/tmp}/podman/podman.sock" \
      "/var/run/docker.sock"; do
      candidate_expanded="$(ls $candidate 2>/dev/null | head -1 || true)"
      if [[ -S "${candidate_expanded}" ]]; then
        export DOCKER_HOST="unix://${candidate_expanded}"
        break
      fi
    done
  elif [[ -S "/var/run/docker.sock" ]]; then
    export DOCKER_HOST="unix:///var/run/docker.sock"
  fi
fi
echo "→ Using container runtime via: ${DOCKER_HOST:-system default}"

# ---- Prerequisites ----
for tool in kubectl helm kind; do
  if ! command -v "$tool" &>/dev/null; then
    echo "[FAIL] $tool not found. Run: make bootstrap"
    exit 1
  fi
done

# ---- Ensure correct kubeconfig ----
kind export kubeconfig --name "$CLUSTER_NAME"
echo "[OK] kubeconfig -> kind-$CLUSTER_NAME"

# ---- Build image ----
echo ""
echo "→ Building workload image..."
CONTAINER_RUNTIME="docker"
if command -v podman &>/dev/null && podman info &>/dev/null 2>&1; then
  CONTAINER_RUNTIME="podman"
fi

"$CONTAINER_RUNTIME" build \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  -f "$REPO_ROOT/src/Containerfile" \
  "$REPO_ROOT/src/"
echo "[OK] Image built: ${IMAGE_NAME}:${IMAGE_TAG}"

# ---- Load image directly into Kind nodes ----
# kind load docker-image only works with Docker API.
# For Podman on Windows, /dev/stdin doesn't exist — save to a temp file first.
echo "→ Loading image into Kind cluster '$CLUSTER_NAME'..."
if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
  TMP_TAR="$(mktemp --suffix=.tar 2>/dev/null || echo "/tmp/thesis-workload-$$.tar")"
  echo "  Saving image to temp archive: $TMP_TAR"
  podman save -o "$TMP_TAR" "${IMAGE_NAME}:${IMAGE_TAG}"
  kind load image-archive "$TMP_TAR" --name "$CLUSTER_NAME"
  rm -f "$TMP_TAR"
else
  kind load docker-image "${IMAGE_NAME}:${IMAGE_TAG}" --name "$CLUSTER_NAME"
fi
echo "[OK] Image loaded into Kind"

# ---- Reset if requested ----
if [[ "$RESET" == "true" ]]; then
  echo "→ Uninstalling existing Helm release '$HELM_RELEASE'..."
  helm uninstall "$HELM_RELEASE" -n "$NAMESPACE" 2>/dev/null || true
  kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
  echo "[OK] Existing release removed"
  sleep 5
fi

# ---- Create namespace ----
echo ""
echo "→ Creating namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo "[OK] Namespace '$NAMESPACE' ready"

# ---- Add Bitnami repo (for PostgreSQL sub-chart) ----
echo "→ Adding Bitnami Helm repo..."
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
helm repo update --fail-on-repo-update-fail 2>/dev/null || helm repo update

# ---- Update Helm chart dependencies ----
echo "→ Updating Helm chart dependencies..."
helm dependency update "$HELM_CHART"
echo "[OK] Dependencies updated"

# ---- Install or Upgrade ----
if helm status "$HELM_RELEASE" -n "$NAMESPACE" &>/dev/null 2>&1; then
  echo "→ Upgrading Helm release '$HELM_RELEASE'..."
  HELM_VERB="upgrade"
else
  echo "→ Installing Helm release '$HELM_RELEASE'..."
  HELM_VERB="install"
fi

helm "$HELM_VERB" "$HELM_RELEASE" "$HELM_CHART" \
  --namespace "$NAMESPACE" \
  --values "$HELM_CHART/values.yaml" \
  --set "image.repository=${IMAGE_NAME}" \
  --set "image.tag=${IMAGE_TAG}" \
  --wait \
  --timeout 300s

echo "[OK] Helm release '$HELM_RELEASE' deployed"

# ---- Wait for all pods ----
echo ""
echo "→ Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod \
  --all \
  -n "$NAMESPACE" \
  --timeout=300s

echo ""
echo "── Pod Status ----------------------------------------------------"
kubectl get pods -n "$NAMESPACE" -o wide

# ---- Verify gRPC health ----
echo ""
echo "→ Verifying workload gRPC server..."
WORKLOAD_POD="$(kubectl get pod -n "$NAMESPACE" -l component=workload -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$WORKLOAD_POD" ]]; then
  kubectl exec "$WORKLOAD_POD" -n "$NAMESPACE" -- \
    dagster api grpc-health-check -p 4000 2>/dev/null && \
    echo "[OK] gRPC health check passed" || \
    echo "[WARN]  gRPC health check failed — check: kubectl logs $WORKLOAD_POD -n $NAMESPACE"
fi

# ---- Summary ----
echo ""
echo "================================================================"
echo "[OK] Dagster on K8s deployed"
echo "================================================================"
echo ""
echo "  Dagster UI:    http://localhost:3001"
echo "  Namespace:     $NAMESPACE"
echo "  K8s Context:   kind-$CLUSTER_NAME"
echo ""
echo "  Useful commands:"
echo "    kubectl get pods -n $NAMESPACE"
echo "    kubectl top pod -n $NAMESPACE"
echo "    kubectl logs -n $NAMESPACE -l component=daemon -f"
echo ""
echo "  Next: make k8s-validate && make exp2a-k8s"
echo ""
