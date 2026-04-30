#!/usr/bin/env bash
# =============================================================================
# Validate the monitoring stack — config lint + live service health checks
#
# Runs in two modes:
#   local  — validate configs on this machine (no VM needed)
#   live   — check that running services on the VM are healthy
#
# Usage:
#   bash scripts/bash/monitoring-validate.sh             # local config check
#   bash scripts/bash/monitoring-validate.sh live        # live VM health check
#   bash scripts/bash/monitoring-validate.sh all         # both
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONITORING_DIR="$REPO_ROOT/monitoring"

VM_IP_FILE="$REPO_ROOT/vm-ip.txt"
SSH_KEY="$HOME/.ssh/thesis_vm"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

MODE="${1:-local}"
PASS=0
FAIL=0

ok()   { echo "  [OK]   $*"; ((PASS++)); }
fail() { echo "  [FAIL] $*"; ((FAIL++)); }
skip() { echo "  [SKIP] $*"; }
hdr()  { echo ""; echo "── $* ──────────────────────────────────────────────"; }

# ─── Local config validation ───────────────────────────────────────────────
local_checks() {
    hdr "Prometheus config"
    if command -v promtool &>/dev/null; then
        if promtool check config "$MONITORING_DIR/prometheus/prometheus.yml" &>/dev/null; then
            ok "prometheus.yml passes promtool check"
        else
            fail "prometheus.yml FAILED promtool check"
            promtool check config "$MONITORING_DIR/prometheus/prometheus.yml" || true
        fi

        if promtool check rules "$MONITORING_DIR/prometheus/alerts.yml" &>/dev/null; then
            ok "alerts.yml passes promtool check"
        else
            fail "alerts.yml FAILED promtool check"
        fi

        if promtool check rules "$MONITORING_DIR/prometheus/recording_rules.yml" &>/dev/null; then
            ok "recording_rules.yml passes promtool check"
        else
            fail "recording_rules.yml FAILED promtool check"
        fi
    else
        skip "promtool not found — install: brew install prometheus"
    fi

    hdr "Alertmanager config"
    if command -v amtool &>/dev/null; then
        if amtool check-config "$MONITORING_DIR/alertmanager/alertmanager.yml" &>/dev/null; then
            ok "alertmanager.yml passes amtool check"
        else
            fail "alertmanager.yml FAILED amtool check"
            amtool check-config "$MONITORING_DIR/alertmanager/alertmanager.yml" || true
        fi
    else
        skip "amtool not found — install: brew install alertmanager"
    fi

    hdr "YAML syntax (yamllint)"
    if command -v yamllint &>/dev/null; then
        local _failed=0
        for f in \
            "$MONITORING_DIR/prometheus/prometheus.yml" \
            "$MONITORING_DIR/prometheus/alerts.yml" \
            "$MONITORING_DIR/prometheus/recording_rules.yml" \
            "$MONITORING_DIR/alertmanager/alertmanager.yml" \
            "$MONITORING_DIR/loki/loki.yml" \
            "$MONITORING_DIR/promtail/promtail.yml" \
            "$MONITORING_DIR/grafana/provisioning/datasources/prometheus.yml" \
            "$MONITORING_DIR/grafana/provisioning/dashboards/dashboards.yml" \
            "$MONITORING_DIR/grafana/provisioning/alerting/contact-points.yml" \
            "$MONITORING_DIR/grafana/provisioning/alerting/rules.yml"; do
            if yamllint -d relaxed "$f" &>/dev/null; then
                ok "$(basename "$f") YAML valid"
            else
                fail "$(basename "$f") has YAML errors"
                _failed=1
            fi
        done
    else
        skip "yamllint not found — install: pip install yamllint"
    fi

    hdr "Dashboard JSON syntax"
    for dash in "$MONITORING_DIR"/grafana/dashboards/*.json; do
        if python3 -c "import json,sys; json.load(open('$dash'))" &>/dev/null; then
            ok "$(basename "$dash") is valid JSON"
        else
            fail "$(basename "$dash") has JSON syntax errors"
        fi
    done

    hdr "Required files"
    local _required=(
        "docker-compose.monitoring.yml"
        "prometheus/prometheus.yml"
        "prometheus/alerts.yml"
        "prometheus/recording_rules.yml"
        "alertmanager/alertmanager.yml"
        "loki/loki.yml"
        "promtail/promtail.yml"
        "grafana/grafana.ini"
        "grafana/provisioning/datasources/prometheus.yml"
        "grafana/provisioning/dashboards/dashboards.yml"
        "grafana/provisioning/alerting/contact-points.yml"
        "grafana/provisioning/alerting/rules.yml"
        "grafana/dashboards/experiment-overview.json"
        "grafana/dashboards/dagster-containers.json"
        ".env.monitoring.example"
    )
    for f in "${_required[@]}"; do
        if [[ -f "$MONITORING_DIR/$f" ]]; then
            ok "$f exists"
        else
            fail "$f MISSING"
        fi
    done
}

# ─── Live VM health checks ─────────────────────────────────────────────────
live_checks() {
    if [[ ! -f "$VM_IP_FILE" ]]; then
        skip "vm-ip.txt not found — skipping live checks"
        return
    fi
    local VM_IP
    VM_IP="$(cat "$VM_IP_FILE" | tr -d '[:space:]')"

    if ! ssh $SSH_OPTS ubuntu@"$VM_IP" "echo ok" &>/dev/null; then
        skip "Cannot reach VM at $VM_IP — skipping live checks"
        return
    fi

    hdr "Live service health (VM: $VM_IP)"

    _check() {
        local name="$1" url="$2"
        local status
        status=$(ssh $SSH_OPTS ubuntu@"$VM_IP" "curl -sf -o /dev/null -w '%{http_code}' '$url'" 2>/dev/null || echo "000")
        if [[ "$status" == "200" ]]; then
            ok "$name is healthy (HTTP 200)"
        else
            fail "$name not healthy (HTTP $status) — check: make monitoring-logs"
        fi
    }

    _check "Prometheus"   "http://localhost:9090/-/healthy"
    _check "Grafana"      "http://localhost:3000/api/health"
    _check "Loki"         "http://localhost:3100/ready"
    _check "Alertmanager" "http://localhost:9093/-/healthy"

    hdr "Container status"
    ssh $SSH_OPTS ubuntu@"$VM_IP" \
        "cd /opt/thesis/monitoring && docker compose ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null || echo 'Monitoring compose not found'"
}

# ─── Run requested modes ───────────────────────────────────────────────────
echo "================================================"
echo "  Monitoring Stack Validation"
echo "  Mode: $MODE"
echo "================================================"

case "$MODE" in
  local)       local_checks ;;
  live)        live_checks ;;
  all)         local_checks; live_checks ;;
  *)
    echo "Usage: $0 {local|live|all}"
    exit 1
    ;;
esac

echo ""
echo "================================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "================================================"

[[ $FAIL -eq 0 ]]
