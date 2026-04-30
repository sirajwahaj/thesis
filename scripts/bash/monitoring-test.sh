#!/usr/bin/env bash
# =============================================================================
# Run promtool unit tests for Prometheus recording rules and alert rules.
# Requires promtool to be installed (brew install prometheus).
#
# Usage:
#   bash scripts/bash/monitoring-test.sh
#   make monitoring-test
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMETHEUS_DIR="$REPO_ROOT/monitoring/prometheus"

if ! command -v promtool &>/dev/null; then
    echo "[FAIL] promtool not found."
    echo "       Install with: brew install prometheus"
    exit 1
fi

echo "==> Running promtool unit tests..."
echo ""

# First validate config and rules syntax
echo "-- Config check --"
promtool check config "$PROMETHEUS_DIR/prometheus.yml"

echo ""
echo "-- Alerts check --"
promtool check rules "$PROMETHEUS_DIR/alerts.yml"

echo ""
echo "-- Recording rules check --"
promtool check rules "$PROMETHEUS_DIR/recording_rules.yml"

echo ""
echo "-- Unit tests --"
cd "$PROMETHEUS_DIR"
promtool test rules test_rules.yml

echo ""
echo "[OK] All promtool checks passed."
