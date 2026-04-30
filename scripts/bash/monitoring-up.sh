#!/usr/bin/env bash
# =============================================================================
# Deploy Monitoring Stack (Prometheus + Grafana)
#
# Starts Prometheus, Grafana, node-exporter, cAdvisor, and postgres-exporter
# alongside the running Dagster infrastructure.
#
# Prerequisites:
#   - Docker/podman running
#   - Dagster compose stack running (infrastructure/docker-compose.yml)
#
# Usage:
#   bash scripts/bash/monitoring-up.sh       # start monitoring
#   bash scripts/bash/monitoring-up.sh down   # stop monitoring
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONITORING_DIR="$REPO_ROOT/monitoring"

# Detect compose command (docker compose v2 preferred, fall back to docker-compose)
if docker compose version &>/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE="docker-compose"
else
  echo "[FAIL] Neither 'docker compose' nor 'docker-compose' found."
  exit 1
fi

ACTION="${1:-up}"

case "$ACTION" in
  up|start)
    echo "==> Starting monitoring stack (Prometheus + Grafana)..."
    echo ""

    # Ensure the Dagster network exists (created by infrastructure/docker-compose.yml)
    if ! docker network inspect thesis_dagster_network &>/dev/null 2>&1; then
      echo "[WARN] Dagster network 'thesis_dagster_network' not found."
      echo "       Creating it now. Start Dagster compose first for full observability."
      docker network create thesis_dagster_network
    fi

    $COMPOSE -f "$MONITORING_DIR/docker-compose.monitoring.yml" up -d

    echo ""
    echo "================================================================"
    echo "  Monitoring stack is running!"
    echo ""
    echo "  Grafana:    http://localhost:3000  (admin / admin)"
    echo "  Prometheus: http://localhost:9090"
    echo "  cAdvisor:   http://localhost:8080"
    echo ""
    echo "  Dashboards are auto-provisioned:"
    echo "    - Thesis Experiment Overview"
    echo "    - Dagster Container Resources"
    echo "================================================================"
    ;;

  down|stop)
    echo "==> Stopping monitoring stack..."
    $COMPOSE -f "$MONITORING_DIR/docker-compose.monitoring.yml" down
    echo "[OK] Monitoring stack stopped."
    ;;

  restart)
    echo "==> Restarting monitoring stack..."
    $COMPOSE -f "$MONITORING_DIR/docker-compose.monitoring.yml" down
    $COMPOSE -f "$MONITORING_DIR/docker-compose.monitoring.yml" up -d
    echo "[OK] Monitoring stack restarted."
    ;;

  status)
    $COMPOSE -f "$MONITORING_DIR/docker-compose.monitoring.yml" ps
    ;;

  *)
    echo "Usage: $0 {up|down|restart|status}"
    exit 1
    ;;
esac
