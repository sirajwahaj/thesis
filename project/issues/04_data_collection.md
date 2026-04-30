# [THESIS-004] Data Collection Scripts

Labels: measurement
Story Points: 3
Dependencies: THESIS-001, THESIS-002, THESIS-003

## Description
Build all data collection scripts: VM metrics collector (psutil), K8s metrics collector (kubectl top), pod timing exporter, Dagster run exporter, and the run trigger script.

## Acceptance Criteria
- [x] `collect_vm_metrics.py` writes CSV with timestamps, CPU %, memory %, process count
- [x] `collect_k8s_metrics.sh` writes CSV with pod-level CPU and memory (via kubectl top)
- [x] `collect_pod_timing.py` writes CSV with submitted, scheduled, running, job_start timestamps
- [x] `export_dagster_runs.py` exports all runs from Dagster PostgreSQL to CSV (JOINs run_tags for level/rep)
- [x] `trigger_dagster_runs.py` launches N concurrent runs via GraphQL (auto-discovers repo/location)
- [x] All scripts tested end-to-end with L1 runs (Exp2A L1 complete: 3/3 reps)
- [ ] Graceful SIGTERM shutdown verified for all collector scripts

## Notes
`trigger_dagster_runs.py` auto-discovers repository/location via `repositoryLocationsOrError` GraphQL query.
`export_dagster_runs.py` uses port-forward to PostgreSQL (port 15432 for K8s, 5432 for VM).
