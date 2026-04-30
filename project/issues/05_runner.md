# [THESIS-005] Master Experiment Runner

Labels: experiment
Story Points: 2
Dependencies: THESIS-004

## Description
Build `run_experiment.sh` that orchestrates the full experiment pipeline: triggers runs, collects metrics, exports data, writes metadata, and respects cooldown periods.

## Acceptance Criteria
- [x] Takes `experiment` and `environment` as arguments (e.g., `exp2a k8s`)
- [x] Iterates over all 6 levels (1, 2, 3, 5, 7, 10) with 3 repetitions each
- [x] Starts and stops metrics collectors for each batch
- [x] Writes `metadata.json` per run with keys: experiment, env, level, rep, concurrent_jobs, timestamp, host
- [x] 60-second cooldown between batches (`COOLDOWN=60`)
- [x] `--dry-run` mode that prints what it would do without executing
- [x] `--levels` flag to run only specific concurrency levels
- [x] Full dry run at L1 and L2 passes without errors
- [x] K8s: PostgreSQL port-forward (port 15432) for `export_dagster_runs.py`
- [x] `--no-wait` flag passed to `trigger_dagster_runs.py`

## Notes
Fixed bash array subscript: `LAST_LEVEL="${LEVELS[$((${#LEVELS[@]} - 1))]}"`.
Uses `DAGSTER_HOST`/`DAGSTER_PORT` env vars (default: localhost:3001).
