#!/bin/bash
# =============================================================================
# Blast Radius Test — Kubernetes (K8sRunLauncher)
#
# Force-deletes one Dagster run pod while others are running and records
# how many sibling pods are affected.
#
# Contribution to RQ: Part of SQ2 — measures failure containment in K8s.
#
# Usage:
#   bash blast_radius_k8s.sh --output data/raw/exp2/part-b-blast-radius/k8s/run1/blast_radius.csv
#   bash blast_radius_k8s.sh --output blast.csv --namespace dagster --wait 10
# =============================================================================

set -euo pipefail

OUTPUT=""
NAMESPACE="dagster"
WAIT_BEFORE_KILL=10  # seconds to wait after launch before killing

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)    OUTPUT="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --wait)      WAIT_BEFORE_KILL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$OUTPUT" ]]; then
  echo "Usage: $0 --output <file.csv> [--namespace <ns>] [--wait <seconds>]"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

# Ensure graceful exit on interrupt
trap 'echo "[INTERRUPTED] Blast radius test interrupted."; exit 130' INT TERM

echo "Blast radius test (K8s) — waiting ${WAIT_BEFORE_KILL}s for pods to start..."
sleep "$WAIT_BEFORE_KILL"

# Find running Dagster run pods (exclude dagster-daemon, dagster-webserver, etc.)
RUNNING_PODS=$(kubectl get pods -n "$NAMESPACE" \
  --field-selector=status.phase=Running \
  --no-headers \
  -o custom-columns=":metadata.name" | grep -E "^dagster-run" || true)

if [[ -z "$RUNNING_PODS" ]]; then
  echo "ERROR: No running Dagster run pods found."
  exit 1
fi

POD_ARRAY=($RUNNING_PODS)
TOTAL_PODS=${#POD_ARRAY[@]}
TARGET_POD=${POD_ARRAY[0]}

echo "Found $TOTAL_PODS running run pods. Deleting pod $TARGET_POD..."
kubectl delete pod "$TARGET_POD" -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true

echo "Deleted pod $TARGET_POD. Waiting for remaining jobs to settle..."
sleep 35  # Wait for remaining 30s jobs + buffer

# Count surviving/successful pods
SURVIVING_PODS=$(kubectl get pods -n "$NAMESPACE" \
  --field-selector=status.phase=Running \
  --no-headers \
  -o custom-columns=":metadata.name" | grep -E "^dagster-run" || true)

SUCCEEDED_PODS=$(kubectl get pods -n "$NAMESPACE" \
  --field-selector=status.phase=Succeeded \
  --no-headers \
  -o custom-columns=":metadata.name" | grep -E "^dagster-run" || true)

SURVIVING_COUNT=0
SUCCEEDED_COUNT=0
[[ -n "$SURVIVING_PODS" ]] && SURVIVING_COUNT=$(echo "$SURVIVING_PODS" | wc -l | tr -d ' ')
[[ -n "$SUCCEEDED_PODS" ]] && SUCCEEDED_COUNT=$(echo "$SUCCEEDED_PODS" | wc -l | tr -d ' ')

# Other jobs affected = total - 1 (killed) - survived - succeeded
AFFECTED=$((TOTAL_PODS - 1 - SURVIVING_COUNT - SUCCEEDED_COUNT))
[[ $AFFECTED -lt 0 ]] && AFFECTED=0

echo "Results:"
echo "  Total pods before kill: $TOTAL_PODS"
echo "  Killed: 1 ($TARGET_POD)"
echo "  Still running: $SURVIVING_COUNT"
echo "  Succeeded: $SUCCEEDED_COUNT"
echo "  Other pods affected: $AFFECTED"

# Write CSV
echo "timestamp,environment,total_pods,killed_pod,still_running,succeeded,affected_pods" > "$OUTPUT"
echo "$(date +%s),k8s,$TOTAL_PODS,$TARGET_POD,$SURVIVING_COUNT,$SUCCEEDED_COUNT,$AFFECTED" >> "$OUTPUT"

echo "Results saved to $OUTPUT"
