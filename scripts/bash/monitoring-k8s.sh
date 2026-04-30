#!/usr/bin/env bash
# =============================================================================
# Deploy Monitoring on Kind K8s Cluster (kube-prometheus-stack)
#
# Installs a lightweight Prometheus + Grafana stack into the Kind cluster
# using the kube-prometheus-stack Helm chart. Provides:
#   - Node metrics (kubelet, node-exporter)
#   - Pod-level CPU/memory (for K8s experiment run pods)
#   - Grafana dashboards accessible at localhost:30300
#
# Prerequisites:
#   - Kind cluster 'thesis' running
#   - Helm 3 installed
#   - kubectl configured for the Kind cluster
#
# Usage:
#   bash scripts/bash/monitoring-k8s.sh          # install
#   bash scripts/bash/monitoring-k8s.sh uninstall # remove
#
# Environment variables:
#   GRAFANA_ADMIN_PASSWORD   Grafana admin password (default: randomly generated)
# =============================================================================
set -euo pipefail

NAMESPACE="monitoring"
RELEASE="kube-prometheus"
ACTION="${1:-install}"

# Use provided password or generate a random one for this session
if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
    GRAFANA_ADMIN_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
    _PASSWORD_GENERATED=true
else
    _PASSWORD_GENERATED=false
fi

case "$ACTION" in
  install|up)
    echo "==> Installing kube-prometheus-stack on Kind cluster..."

    # Add Helm repo if not already present
    if ! helm repo list 2>/dev/null | grep -q "prometheus-community"; then
      helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    fi
    helm repo update

    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # Install with thesis-specific values
    helm upgrade --install "$RELEASE" prometheus-community/kube-prometheus-stack \
      --namespace "$NAMESPACE" \
      --set prometheus.prometheusSpec.retention=3d \
      --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
      --set prometheus.prometheusSpec.resources.limits.memory=512Mi \
      --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
      --set grafana.service.type=NodePort \
      --set grafana.service.nodePort=30300 \
      --set "grafana.grafana\\.ini.server.root_url=http://localhost:30300" \
      --set alertmanager.enabled=false \
      --set kubeStateMetrics.enabled=true \
      --set nodeExporter.enabled=true \
      --set prometheus.service.type=NodePort \
      --set prometheus.service.nodePort=30090 \
      --wait --timeout 5m

    # ── Deploy Loki for K8s log aggregation ────────────────────────────────
    echo ""
    echo "==> Deploying Loki on Kind cluster..."

    if ! helm repo list 2>/dev/null | grep -q "grafana"; then
      helm repo add grafana https://grafana.github.io/helm-charts
    fi
    helm repo update

    helm upgrade --install loki grafana/loki-stack \
      --namespace "$NAMESPACE" \
      --set loki.enabled=true \
      --set loki.persistence.enabled=false \
      --set loki.resources.requests.memory=128Mi \
      --set loki.resources.limits.memory=256Mi \
      --set promtail.enabled=true \
      --set grafana.enabled=false \
      --wait --timeout 3m

    # ── Add Loki datasource to the existing Grafana ────────────────────────
    # Wait for Grafana to be ready
    kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=grafana" \
        -n "$NAMESPACE" --timeout=60s 2>/dev/null || true

    GRAFANA_POD=$(kubectl get pod -n "$NAMESPACE" -l "app.kubernetes.io/name=grafana" \
        -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "")

    if [[ -n "$GRAFANA_POD" ]]; then
        echo "-> Adding Loki datasource to Grafana..."
        LOKI_SVC="http://loki.${NAMESPACE}.svc.cluster.local:3100"
        kubectl exec -n "$NAMESPACE" "$GRAFANA_POD" -- \
            curl -sf -X POST http://admin:"${GRAFANA_ADMIN_PASSWORD}"@localhost:3000/api/datasources \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"Loki\",\"type\":\"loki\",\"url\":\"${LOKI_SVC}\",\"access\":\"proxy\",\"isDefault\":false}" \
            2>/dev/null && echo "   [OK] Loki datasource added" || echo "   [SKIP] Could not add Loki datasource automatically"
    fi

    echo ""
    echo "================================================================"
    echo "  K8s Monitoring stack deployed!"
    echo ""
    echo "  Grafana:    http://localhost:30300"
    if [[ "$_PASSWORD_GENERATED" == "true" ]]; then
        echo "  Credentials: admin / ${GRAFANA_ADMIN_PASSWORD}"
        echo "  (password was auto-generated; set GRAFANA_ADMIN_PASSWORD to use your own)"
    else
        echo "  Credentials: admin / <your GRAFANA_ADMIN_PASSWORD>"
    fi
    echo "  Prometheus: http://localhost:30090"
    echo ""
    echo "  View Dagster run pods:"
    echo "    kubectl top pods -n dagster"
    echo ""
    echo "  Port-forward if NodePort isn't accessible:"
    echo "    kubectl port-forward -n monitoring svc/${RELEASE}-grafana 3000:80"
    echo "================================================================"
    ;;

  uninstall|down)
    echo "==> Uninstalling kube-prometheus-stack..."
    helm uninstall "$RELEASE" --namespace "$NAMESPACE" 2>/dev/null || true
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
    echo "[OK] K8s monitoring stack removed."
    ;;

  status)
    echo "==> Monitoring pods:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    echo "==> Monitoring services:"
    kubectl get svc -n "$NAMESPACE"
    ;;

  *)
    echo "Usage: $0 {install|uninstall|status}"
    exit 1
    ;;
esac
