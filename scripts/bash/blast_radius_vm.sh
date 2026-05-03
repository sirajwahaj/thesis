#!/bin/bash
# =============================================================================
# Blast Radius Test — VM (DockerRunLauncher)
#
# Kills one Dagster job container while others are running and records
# how many sibling containers are affected.
#
# Contribution to RQ: Part of SQ2 — measures failure containment in VM.
#
# Usage:
#   bash blast_radius_vm.sh --output data/raw/exp2/part-b-blast-radius/vm/run1/blast_radius.csv
#   bash blast_radius_vm.sh --output blast.csv --wait 10
# =============================================================================

set -euo pipefail

OUTPUT=""
WAIT_BEFORE_KILL=10  # seconds to wait after launch before killing

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --wait)   WAIT_BEFORE_KILL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$OUTPUT" ]]; then
  echo "Usage: $0 --output <file.csv> [--wait <seconds>]"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

# Ensure we record results even on early exit
trap 'echo "[INTERRUPTED] Blast radius test interrupted."; exit 130' INT TERM

echo "Blast radius test (VM — DockerRunLauncher) — waiting ${WAIT_BEFORE_KILL}s for containers to start..."
sleep "$WAIT_BEFORE_KILL"

# Find running Dagster job containers (DockerRunLauncher labels them)
DOCKER_CIDS=$(docker ps -q --filter "label=dagster/image_type=run_worker" 2>/dev/null || true)

if [[ -z "$DOCKER_CIDS" ]]; then
  echo "ERROR: No Dagster job containers found. Is DockerRunLauncher active?"
  exit 1
fi

CID_ARRAY=($DOCKER_CIDS)
TOTAL_CONTAINERS=${#CID_ARRAY[@]}
TARGET_CID=${CID_ARRAY[0]}

echo "Found $TOTAL_CONTAINERS Dagster containers. Killing container $TARGET_CID..."
docker kill "$TARGET_CID" 2>/dev/null || true

echo "Killed container $TARGET_CID. Waiting for remaining jobs to settle..."
sleep 35  # Wait for remaining 30s jobs + buffer

# Count surviving containers
SURVIVING_CIDS=$(docker ps -q --filter "label=dagster/image_type=run_worker" 2>/dev/null || true)
SURVIVING_COUNT=0
if [[ -n "$SURVIVING_CIDS" ]]; then
  SURVIVING_COUNT=$(echo "$SURVIVING_CIDS" | wc -l | tr -d ' ')
fi

AFFECTED=$((TOTAL_CONTAINERS - 1 - SURVIVING_COUNT))

echo "Results:"
echo "  Total containers before kill: $TOTAL_CONTAINERS"
echo "  Killed: 1 (CID $TARGET_CID)"
echo "  Surviving: $SURVIVING_COUNT"
echo "  Other jobs affected: $AFFECTED"

# Write CSV
echo "timestamp,environment,total_jobs,killed_cid,surviving_jobs,affected_jobs" > "$OUTPUT"
echo "$(date +%s),vm,$TOTAL_CONTAINERS,$TARGET_CID,$SURVIVING_COUNT,$AFFECTED" >> "$OUTPUT"

echo "Results saved to $OUTPUT"
