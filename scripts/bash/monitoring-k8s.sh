#!/usr/bin/env bash
# =============================================================================
# Deploy Monitoring on Kind K8s Cluster (kube-prometheus-stack)
#
# Installs a lightweight Prometheus + Grafana stack into the Kind cluster
# using the kube-prometheus-stack Helm chart. Provides:
#   - Node metrics (kubelet, node-exporter)
#   - Pod-level CPU/memory (for K8s experiment run pods)
#   - Grafana dashboards accessible at localhost:3000
#
# Prerequisites:
#   - Kind cluster 'thesis' running
#   - Helm 3 installed
#   - kubectl configured for the Kind cluster
#
# Usage:
#   bash scripts/bash/monitoring-k8s.sh          # install
#   bash scripts/bash/monitoring-k8s.sh uninstall # remove
# =============================================================================
set -euo pipefail

NAMESPACE="monitoring"
RELEASE="kube-prometheus"
ACTION="${1:-install}"

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
      --set grafana.adminPassword=admin \
      --set grafana.service.type=NodePort \
      --set grafana.service.nodePort=30300 \
      --set "grafana.grafana\\.ini.server.root_url=http://localhost:30300" \
      --set alertmanager.enabled=false \
      --set kubeStateMetrics.enabled=true \
      --set nodeExporter.enabled=true \
      --set prometheus.service.type=NodePort \
      --set prometheus.service.nodePort=30090 \
      --wait --timeout 5m

    echo ""
    echo "================================================================"
    echo "  K8s Monitoring stack deployed!"
    echo ""
    echo "  Grafana:    http://localhost:30300  (admin / admin)"
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
