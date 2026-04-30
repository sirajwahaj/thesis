#!/bin/bash
# =============================================================================
# Collect Kubernetes pod-level CPU and memory metrics via kubectl top.
#
# Requires: kubectl, metrics-server deployed in the cluster.
#
# Also captures OOMKill events from pod status: when a pod is OOMKilled
# (container exceeds 600Mi memory limit), it appears as a Terminated/OOMKilled
# reason in 'kubectl get pods'. This is written to a separate oom_events.csv.
#
# Contribution to RQ: Provides SQ2 and SQ3 data.
#   - k8s_pod_metrics.csv: per-pod CPU/memory usage over time
#   - oom_events.csv: records which pods were OOMKilled and when
#     (proves K8s contains blast radius — OOM in one pod does not cascade)
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

# Derive OOM events file from output path (sibling file)
OOM_OUTPUT="$(dirname "$OUTPUT")/oom_events.csv"

# Create output directory
mkdir -p "$(dirname "$OUTPUT")"

# Write CSV headers
echo "timestamp,pod,cpu_millicores,memory_mib" > "$OUTPUT"
echo "timestamp,pod,namespace,reason,exit_code" > "$OOM_OUTPUT"

echo "Collecting K8s pod metrics to $OUTPUT every ${INTERVAL}s (namespace: $NAMESPACE)..."
echo "OOMKill events will be recorded to $OOM_OUTPUT"

# Trap for graceful shutdown
trap 'echo "Stopped. Metrics saved to $OUTPUT"; exit 0' SIGTERM SIGINT

while true; do
  TS=$(date +%s)

  # Collect CPU and memory via kubectl top
  kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null | while read -r pod cpu mem; do
    cpu_mc=$(echo "$cpu" | sed 's/m//')
    mem_mi=$(echo "$mem" | sed 's/Mi//')
    echo "${TS},$pod,$cpu_mc,$mem_mi" >> "$OUTPUT"
  done

  # Detect OOMKilled containers: look for pods with OOMKilled termination reason
  kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    pod_name = item['metadata']['name']
    ns = item['metadata']['namespace']
    for cs in item.get('status', {}).get('containerStatuses', []):
        last = cs.get('lastState', {}).get('terminated', {})
        if last.get('reason') == 'OOMKilled':
            print(f\"$TS,{pod_name},{ns},OOMKilled,{last.get('exitCode', '')}\")" 2>/dev/null >> "$OOM_OUTPUT" || true

  sleep "$INTERVAL"
done
