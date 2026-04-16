#!/bin/bash
# =============================================================================
# Collect Kubernetes pod-level CPU and memory metrics via kubectl top.
#
# Requires: kubectl, metrics-server deployed in the cluster.
#
# Contribution to RQ: Provides SQ2 and SQ3 data — per-pod resource usage.
#
# Usage:
#   bash collect_k8s_metrics.sh --output data/raw/exp2/L1/run1/k8s_pod_metrics.csv
#   bash collect_k8s_metrics.sh --output metrics.csv --namespace dagster --interval 2
# =============================================================================

set -euo pipefail

# Defaults
OUTPUT=""
NAMESPACE="dagster"
INTERVAL=2

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)    OUTPUT="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --interval)  INTERVAL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$OUTPUT" ]]; then
  echo "Usage: $0 --output <file.csv> [--namespace <ns>] [--interval <sec>]"
  exit 1
fi

# Create output directory
mkdir -p "$(dirname "$OUTPUT")"

# Write CSV header
echo "timestamp,pod,cpu_millicores,memory_mib" > "$OUTPUT"

echo "Collecting K8s pod metrics to $OUTPUT every ${INTERVAL}s (namespace: $NAMESPACE)..."

# Trap for graceful shutdown
trap 'echo "Stopped. Metrics saved to $OUTPUT"; exit 0' SIGTERM SIGINT

while true; do
  kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null | while read -r pod cpu mem; do
    cpu_mc=$(echo "$cpu" | sed 's/m//')
    mem_mi=$(echo "$mem" | sed 's/Mi//')
    echo "$(date +%s),$pod,$cpu_mc,$mem_mi" >> "$OUTPUT"
  done
  sleep "$INTERVAL"
done
