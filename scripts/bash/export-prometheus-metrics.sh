#!/usr/bin/env bash
# =============================================================================
# Export Prometheus metrics to CSV files in data/processed/
# Queries the Prometheus HTTP API for key experiment metrics over a time range
# and dumps them in a format aligned with the analysis notebook expectations.
#
# Usage:
#   bash scripts/bash/export-prometheus-metrics.sh [--start <timestamp>] [--end <timestamp>]
#   bash scripts/bash/export-prometheus-metrics.sh --start 2026-05-01T10:00:00Z --end 2026-05-01T12:00:00Z
#   bash scripts/bash/export-prometheus-metrics.sh --last 3h
#
# Environment variables:
#   PROMETHEUS_URL    Base URL (default: http://<vm-ip>:9090)
#   GRAFANA_ADMIN_PASSWORD  (unused here, but kept consistent with .env.monitoring)
#
# Output:
#   data/processed/prometheus_cpu.csv
#   data/processed/prometheus_memory.csv
#   data/processed/prometheus_containers.csv
#   data/processed/prometheus_oom.csv
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VM_IP_FILE="$REPO_ROOT/vm-ip.txt"
OUTPUT_DIR="$REPO_ROOT/data/processed"

# ── Defaults ─────────────────────────────────────────────────────────────────
PROM_URL="${PROMETHEUS_URL:-}"
LAST_DURATION="2h"
START_TIME=""
END_TIME=""
STEP="30s"

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --start)  START_TIME="$2"; shift 2 ;;
        --end)    END_TIME="$2"; shift 2 ;;
        --last)   LAST_DURATION="$2"; shift 2 ;;
        --step)   STEP="$2"; shift 2 ;;
        --url)    PROM_URL="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ── Resolve Prometheus URL ────────────────────────────────────────────────────
if [[ -z "$PROM_URL" ]]; then
    if [[ -f "$VM_IP_FILE" ]]; then
        VM_IP="$(cat "$VM_IP_FILE" | tr -d '[:space:]')"
        PROM_URL="http://$VM_IP:9090"
    else
        PROM_URL="http://localhost:9090"
    fi
fi

echo "==> Exporting Prometheus metrics from $PROM_URL"

# ── Verify Prometheus is reachable ────────────────────────────────────────────
if ! curl -sf "$PROM_URL/-/ready" >/dev/null 2>&1; then
    echo "[ERROR] Prometheus is not reachable at $PROM_URL" >&2
    echo "        Start monitoring stack first: make monitoring-up" >&2
    exit 1
fi

# ── Resolve time range ────────────────────────────────────────────────────────
if [[ -z "$START_TIME" ]]; then
    # Default: last N hours from now
    END_TIME=$(python3 -c "import time; print(int(time.time()))")
    case "$LAST_DURATION" in
        *h) HOURS="${LAST_DURATION%h}"; START_TIME=$((END_TIME - HOURS * 3600)) ;;
        *m) MINS="${LAST_DURATION%m}";  START_TIME=$((END_TIME - MINS * 60))    ;;
        *)  START_TIME=$((END_TIME - 7200)) ;;
    esac
else
    START_TIME=$(python3 -c "from datetime import datetime, timezone; \
        dt = datetime.fromisoformat('$START_TIME'.replace('Z','+00:00')); \
        print(int(dt.timestamp()))")
    END_TIME=$(python3 -c "from datetime import datetime, timezone; \
        dt = datetime.fromisoformat('$END_TIME'.replace('Z','+00:00')); \
        print(int(dt.timestamp()))")
fi

echo "   Range: $(python3 -c "from datetime import datetime; print(datetime.fromtimestamp($START_TIME).isoformat())") → $(python3 -c "from datetime import datetime; print(datetime.fromtimestamp($END_TIME).isoformat())")"

mkdir -p "$OUTPUT_DIR"

# ── Helper: query Prometheus range API and save to CSV ───────────────────────
query_range_csv() {
    local QUERY="$1"
    local OUTPUT_FILE="$2"
    local LABEL_NAMES="${3:-}"   # comma-separated extra label names to include

    local RESPONSE
    RESPONSE=$(curl -sf --data-urlencode "query=${QUERY}" \
        --data-urlencode "start=${START_TIME}" \
        --data-urlencode "end=${END_TIME}" \
        --data-urlencode "step=${STEP}" \
        "$PROM_URL/api/v1/query_range") || {
            echo "[WARN] Query failed for: $QUERY" >&2
            return 1
        }

    # Convert JSON response to CSV using Python
    python3 - <<PYTHON
import json, sys, csv
from datetime import datetime

data = json.loads('''${RESPONSE}''')

if data.get('status') != 'success':
    print(f"[WARN] Prometheus returned status: {data.get('status')}", file=sys.stderr)
    sys.exit(0)

results = data.get('data', {}).get('result', [])
if not results:
    print("[WARN] Empty result for query: ${QUERY}", file=sys.stderr)
    # Write empty file with header
    with open("${OUTPUT_FILE}", "w") as f:
        f.write("timestamp,value,metric\n")
    sys.exit(0)

rows = []
for series in results:
    metric_labels = series.get('metric', {})
    metric_name = metric_labels.get('__name__', '${QUERY[:30]}')
    label_str = ",".join(f"{k}={v}" for k, v in metric_labels.items() if k != '__name__')
    for ts, val in series.get('values', []):
        rows.append({
            "timestamp": datetime.fromtimestamp(float(ts)).strftime("%Y-%m-%dT%H:%M:%S"),
            "unix_ts": int(float(ts)),
            "value": val,
            "metric": metric_name,
            "labels": label_str
        })

with open("${OUTPUT_FILE}", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["timestamp", "unix_ts", "value", "metric", "labels"])
    writer.writeheader()
    writer.writerows(rows)

print(f"   [{len(rows)} rows] -> ${OUTPUT_FILE}")
PYTHON
}

# ── Export key metrics ────────────────────────────────────────────────────────
echo ""
echo "==> Exporting CPU utilization..."
query_range_csv \
    "thesis:node_cpu_utilization:ratio" \
    "$OUTPUT_DIR/prometheus_cpu.csv"

echo "==> Exporting memory utilization..."
query_range_csv \
    "thesis:node_memory_utilization:ratio" \
    "$OUTPUT_DIR/prometheus_memory.csv"

echo "==> Exporting running container count..."
query_range_csv \
    "thesis:dagster_workload_containers:count" \
    "$OUTPUT_DIR/prometheus_containers.csv"

echo "==> Exporting OOM kill events..."
query_range_csv \
    "increase(container_oom_events_total[5m])" \
    "$OUTPUT_DIR/prometheus_oom.csv"

echo "==> Exporting PostgreSQL connection ratio..."
query_range_csv \
    "thesis:postgres_connections:ratio" \
    "$OUTPUT_DIR/prometheus_pg_connections.csv"

echo ""
echo "================================================================"
echo "  Metrics exported to data/processed/"
echo ""
echo "  prometheus_cpu.csv        VM CPU utilization over time"
echo "  prometheus_memory.csv     VM memory utilization over time"
echo "  prometheus_containers.csv Running workload container count"
echo "  prometheus_oom.csv        OOM kill events (5m windows)"
echo "  prometheus_pg_connections.csv  PostgreSQL connection ratio"
echo ""
echo "  Load in notebook: pd.read_csv('data/processed/prometheus_cpu.csv')"
echo "================================================================"
