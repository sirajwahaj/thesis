#!/bin/bash
# =============================================================================
# Master Experiment Runner
#
# Orchestrates the full experiment pipeline: triggers concurrent Dagster runs,
# collects metrics, exports data, writes metadata, and respects cooldowns.
#
# Usage:
#   ./run_experiment.sh exp1 vm                    # Run Exp1 on VM
#   ./run_experiment.sh exp2a k8s                  # Run Exp2A on K8s
#   ./run_experiment.sh exp1 vm --dry-run          # Preview without executing
#   ./run_experiment.sh exp1 vm --levels "1 2 3"   # Only specific levels
# =============================================================================

set -euo pipefail

# -------- CONFIGURATION --------
EXPERIMENT="${1:-}"
ENVIRONMENT="${2:-}"
DRY_RUN=false
CUSTOM_LEVELS=""
REPETITIONS=3
COOLDOWN=60        # seconds between batches
WORKLOAD_SECS=30   # expected workload duration (locked, do not change)
DEFAULT_LEVELS="1 2 3 5 7 10"  # L1=1, L2=2, L3=3, L4=5, L5=7, L6=10 (locked)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="data/raw"
DAGSTER_HOST="${DAGSTER_HOST:-localhost}"
DAGSTER_PORT="${DAGSTER_PORT:-3001}"
HOSTNAME_VALUE="$(hostname -s 2>/dev/null || hostname)"

# -------- PARSE EXTRA ARGS --------
shift 2 || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true; shift ;;
    --levels)    CUSTOM_LEVELS="$2"; shift 2 ;;
    --reps)      REPETITIONS="$2"; shift 2 ;;
    --cooldown)  COOLDOWN="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# -------- VALIDATION --------
if [[ -z "$EXPERIMENT" || -z "$ENVIRONMENT" ]]; then
  echo "Usage: $0 <experiment> <environment> [--dry-run] [--levels \"1 2 3\"] [--reps N] [--cooldown N]"
  echo ""
  echo "Experiments: exp1, exp2a, exp2b, exp2c"
  echo "Environments: vm, k8s"
  echo ""
  echo "Examples:"
  echo "  $0 exp1 vm                       # Run Exp1 on VM (all levels)"
  echo "  $0 exp2a k8s --dry-run           # Preview Exp2A on K8s"
  echo "  $0 exp1 vm --levels \"1 2 3\"      # Only L1, L2, L3"
  exit 1
fi

# -------- SET LEVELS AND PATHS --------
case "$EXPERIMENT" in
  exp1)
    LEVELS=(${CUSTOM_LEVELS:-$DEFAULT_LEVELS})
    EXP_DIR="$BASE_DIR/exp1-vm-degradation"
    ;;
  exp2a)
    LEVELS=(${CUSTOM_LEVELS:-$DEFAULT_LEVELS})
    EXP_DIR="$BASE_DIR/exp2-kubernetes-isolation/part-a"
    ;;
  exp2b)
    LEVELS=(${CUSTOM_LEVELS:-5})  # Blast radius at L4 (5 concurrent)
    EXP_DIR="$BASE_DIR/exp2-kubernetes-isolation/part-b-blast-radius/$ENVIRONMENT"
    ;;
  exp2c)
    LEVELS=(${CUSTOM_LEVELS:-10})  # Spike at L6 (10 concurrent)
    EXP_DIR="$BASE_DIR/exp2-kubernetes-isolation/part-c-spike"
    ;;
  *)
    echo "Unknown experiment: $EXPERIMENT"
    exit 1
    ;;
esac

# -------- BANNER --------
echo "=============================================="
echo "  Experiment: $EXPERIMENT"
echo "  Environment: $ENVIRONMENT"
echo "  Levels: ${LEVELS[*]}"
echo "  Repetitions: $REPETITIONS"
echo "  Cooldown: ${COOLDOWN}s"
echo "  Dry run: $DRY_RUN"
echo "  Output: $EXP_DIR"
echo "=============================================="
echo ""

# -------- RUN LOOP --------
for level in "${LEVELS[@]}"; do
  LEVEL_DIR="${EXP_DIR}/L${level}"

  for rep in $(seq 1 "$REPETITIONS"); do
    RUN_DIR="${LEVEL_DIR}/run${rep}"

    echo "--- Level L${level}, Run ${rep}/${REPETITIONS} ---"

    if [[ "$DRY_RUN" == true ]]; then
      echo "  [DRY RUN] Would create: $RUN_DIR"
      echo "  [DRY RUN] Would launch $level concurrent jobs"
      echo "  [DRY RUN] Would collect ${ENVIRONMENT} metrics"
      echo "  [DRY RUN] Would wait ~$((level * WORKLOAD_SECS + 30))s"
      echo "  [DRY RUN] Would cooldown ${COOLDOWN}s"
      echo ""
      continue
    fi

    mkdir -p "$RUN_DIR"
    START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Start metrics collector in background
    METRICS_PID=""
    if [[ "$ENVIRONMENT" == "vm" ]]; then
      python3 "$SCRIPT_DIR/collect_vm_metrics.py" \
        --output "${RUN_DIR}/vm_metrics.csv" &
      METRICS_PID=$!
    else
      bash "$SCRIPT_DIR/collect_k8s_metrics.sh" \
        --output "${RUN_DIR}/k8s_pod_metrics.csv" &
      METRICS_PID=$!
    fi

    # Trigger concurrent runs with level and rep tags for traceability
    python3 "$SCRIPT_DIR/trigger_dagster_runs.py" "$level" \
      --host "$DAGSTER_HOST" \
      --port "$DAGSTER_PORT" \
      --level "$level" \
      --rep "$rep" \
      --env "$ENVIRONMENT" \
      --no-wait

    # Wait for all runs to complete while metrics are collected
    WAIT_TIME=$((level * WORKLOAD_SECS + 30))
    echo "  Waiting ${WAIT_TIME}s for runs to finish..."
    sleep "$WAIT_TIME"

    # Stop metrics collector
    if [[ -n "$METRICS_PID" ]]; then
      kill "$METRICS_PID" 2>/dev/null || true
      wait "$METRICS_PID" 2>/dev/null || true
    fi

    END_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Export Dagster run data
    # For K8s environment, port-forward PostgreSQL if needed
    PG_HOST="${DAGSTER_PG_HOSTNAME:-localhost}"
    PG_PORT="${DAGSTER_PG_PORT:-5432}"
    PG_FWD_PID=""
    if [[ "$ENVIRONMENT" == "k8s" && "$PG_HOST" == "localhost" ]]; then
      kubectl port-forward -n dagster svc/dagster-thesis-postgresql 15432:5432 &>/tmp/pg_pf.log &
      PG_FWD_PID=$!
      sleep 2
      PG_PORT=15432
    fi

    python3 "$SCRIPT_DIR/export_dagster_runs.py" \
      --output "${RUN_DIR}/dagster_runs.csv" \
      --host "$PG_HOST" \
      --port "$PG_PORT"

    if [[ -n "$PG_FWD_PID" ]]; then
      kill "$PG_FWD_PID" 2>/dev/null || true
      wait "$PG_FWD_PID" 2>/dev/null || true
    fi

    # Collect pod timing for K8s experiments
    if [[ "$ENVIRONMENT" == "k8s" ]]; then
      python3 "$SCRIPT_DIR/collect_pod_timing.py" \
        --output "${RUN_DIR}/pod_timing.csv"
    fi

    # Write metadata (required keys: experiment, env, level, rep, timestamp, host)
    cat > "${RUN_DIR}/metadata.json" <<EOF
{
    "experiment": "${EXPERIMENT}",
    "env": "${ENVIRONMENT}",
    "level": "L${level}",
    "rep": ${rep},
    "timestamp": "${START_TS}",
    "host": "${HOSTNAME_VALUE}",
    "concurrent_jobs": ${level},
    "workload_duration_s": ${WORKLOAD_SECS},
    "start_timestamp": "${START_TS}",
    "end_timestamp": "${END_TS}"
}
EOF

    echo "  Run ${rep} complete. Data saved to ${RUN_DIR}/"

    # Cooldown (skip after last run)
    LAST_LEVEL="${LEVELS[$((${#LEVELS[@]} - 1))]}"
    if [[ "$rep" -lt "$REPETITIONS" ]] || [[ "$level" != "$LAST_LEVEL" ]]; then
      echo "  Cooldown ${COOLDOWN}s..."
      sleep "$COOLDOWN"
    fi
    echo ""
  done
done

echo "=============================================="
echo "  ${EXPERIMENT} complete!"
echo "  Data directory: $EXP_DIR"
echo "=============================================="
