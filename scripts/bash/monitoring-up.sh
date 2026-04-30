#!/usr/bin/env bash
# =============================================================================
# Deploy Monitoring Stack (Prometheus + Grafana) on the VM
#
# Copies monitoring configs to the VM and runs Prometheus + Grafana + exporters
# alongside the running Dagster infrastructure (on the same VM Docker daemon).
#
# Prerequisites:
#   - VM is running (make vm-up)
#   - Dagster compose is running on VM (make deploy / deploy-vm.sh)
#   - vm-ip.txt contains the VM IP
#
# Usage:
#   bash scripts/bash/monitoring-up.sh          # start monitoring on VM
#   bash scripts/bash/monitoring-up.sh down     # stop monitoring on VM
#   bash scripts/bash/monitoring-up.sh status   # show container status
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONITORING_DIR="$REPO_ROOT/monitoring"

VM_IP_FILE="$REPO_ROOT/vm-ip.txt"
SSH_KEY="$HOME/.ssh/thesis_vm"
VM_MONITORING_DIR="/opt/thesis/monitoring"

# ---- Read VM IP ----
if [[ ! -f "$VM_IP_FILE" ]]; then
    echo "[FAIL] vm-ip.txt not found. Run: make vm-up"
    exit 1
fi

VM_IP="$(cat "$VM_IP_FILE" | tr -d '[:space:]')"
if [[ -z "$VM_IP" ]]; then
    echo "[FAIL] vm-ip.txt is empty. Run: make vm-up"
    exit 1
fi

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Verify SSH
if ! ssh $SSH_OPTS ubuntu@"$VM_IP" "echo ok" &>/dev/null; then
    echo "[FAIL] Cannot reach VM at $VM_IP"
    exit 1
fi

ACTION="${1:-up}"

case "$ACTION" in
  up|start)
    echo "==> Deploying monitoring stack to VM ($VM_IP)..."
    echo ""

    # Create monitoring directory structure on VM
    ssh $SSH_OPTS ubuntu@"$VM_IP" \
        "sudo mkdir -p $VM_MONITORING_DIR/prometheus \
                       $VM_MONITORING_DIR/alertmanager \
                       $VM_MONITORING_DIR/loki \
                       $VM_MONITORING_DIR/promtail \
                       $VM_MONITORING_DIR/grafana/provisioning/datasources \
                       $VM_MONITORING_DIR/grafana/provisioning/dashboards \
                       $VM_MONITORING_DIR/grafana/dashboards && \
         sudo chown -R ubuntu:ubuntu $VM_MONITORING_DIR"

    # Copy monitoring configs to VM
    echo "-> Copying monitoring configs to VM..."
    scp $SSH_OPTS \
        "$MONITORING_DIR/docker-compose.monitoring.yml" \
        ubuntu@"$VM_IP":"$VM_MONITORING_DIR/docker-compose.yml"

    scp $SSH_OPTS \
        "$MONITORING_DIR/prometheus/prometheus.yml" \
        "$MONITORING_DIR/prometheus/alerts.yml" \
        "$MONITORING_DIR/prometheus/recording_rules.yml" \
        ubuntu@"$VM_IP":"$VM_MONITORING_DIR/prometheus/"

    scp $SSH_OPTS \
        "$MONITORING_DIR/alertmanager/alertmanager.yml" \
        ubuntu@"$VM_IP":"$VM_MONITORING_DIR/alertmanager/"

    scp $SSH_OPTS \
        "$MONITORING_DIR/loki/loki.yml" \
        ubuntu@"$VM_IP":"$VM_MONITORING_DIR/loki/"

    scp $SSH_OPTS \
        "$MONITORING_DIR/promtail/promtail.yml" \
        ubuntu@"$VM_IP":"$VM_MONITORING_DIR/promtail/"

    scp $SSH_OPTS \
        "$MONITORING_DIR/grafana/provisioning/datasources/prometheus.yml" \
        ubuntu@"$VM_IP":"$VM_MONITORING_DIR/grafana/provisioning/datasources/"

    scp $SSH_OPTS \
        "$MONITORING_DIR/grafana/provisioning/dashboards/dashboards.yml" \
        ubuntu@"$VM_IP":"$VM_MONITORING_DIR/grafana/provisioning/dashboards/"

    scp $SSH_OPTS \
        "$MONITORING_DIR/grafana/grafana.ini" \
        ubuntu@"$VM_IP":"$VM_MONITORING_DIR/grafana/"

    scp $SSH_OPTS \
        "$MONITORING_DIR/grafana/dashboards/experiment-overview.json" \
        "$MONITORING_DIR/grafana/dashboards/dagster-containers.json" \
        ubuntu@"$VM_IP":"$VM_MONITORING_DIR/grafana/dashboards/"

    echo "[OK] Configs copied"

    # Verify Docker is running on the VM before attempting compose operations
    echo "-> Checking Docker on VM..."
    if ! ssh $SSH_OPTS ubuntu@"$VM_IP" "docker info" &>/dev/null; then
        echo "[FAIL] Docker is not running on the VM."
        echo "       Run 'make vm-provision' to install Docker, then retry."
        exit 1
    fi
    if ! ssh $SSH_OPTS ubuntu@"$VM_IP" "docker compose version" &>/dev/null; then
        echo "[FAIL] 'docker compose' (plugin) not available on the VM."
        echo "       Run 'make vm-provision' to install Docker CE, then retry."
        exit 1
    fi

    # Pull images and start monitoring
    echo ""
    echo "-> Starting monitoring containers on VM..."
    ssh $SSH_OPTS ubuntu@"$VM_IP" \
        "cd $VM_MONITORING_DIR && docker compose pull && docker compose up -d"

    echo ""
    echo "================================================================"
    echo "  Monitoring stack running on VM ($VM_IP)!"
    echo ""
    echo "  Grafana:    http://$VM_IP:3000  (admin / thesis2026)"
    echo "  Prometheus: http://$VM_IP:9090"
    echo "  cAdvisor:   http://$VM_IP:8080"
    echo ""
    echo "  Dashboards are auto-provisioned:"
    echo "    - Thesis Experiment Overview"
    echo "    - Dagster Container Resources"
    echo "================================================================"
    ;;

  down|stop)
    echo "==> Stopping monitoring stack on VM ($VM_IP)..."
    ssh $SSH_OPTS ubuntu@"$VM_IP" \
        "cd $VM_MONITORING_DIR && docker compose down 2>/dev/null || true"
    echo "[OK] Monitoring stack stopped."
    ;;

  restart)
    echo "==> Restarting monitoring stack on VM..."
    ssh $SSH_OPTS ubuntu@"$VM_IP" \
        "cd $VM_MONITORING_DIR && docker compose down && docker compose up -d"
    echo "[OK] Monitoring stack restarted."
    ;;

  status)
    ssh $SSH_OPTS ubuntu@"$VM_IP" \
        "cd $VM_MONITORING_DIR && docker compose ps 2>/dev/null || echo 'Monitoring not running'"
    ;;

  logs)
    ssh $SSH_OPTS ubuntu@"$VM_IP" \
        "cd $VM_MONITORING_DIR && docker compose logs --tail=50"
    ;;

  *)
    echo "Usage: $0 {up|down|restart|status|logs}"
    exit 1
    ;;
esac
