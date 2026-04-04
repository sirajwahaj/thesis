# [THESIS-004] Data Collection Scripts

Labels: measurement  
Story Points: 3  
Dependencies: THESIS-001, THESIS-002, THESIS-003  

## Description
Build all data collection scripts: VM metrics collector (psutil), K8s metrics collector (kubectl top), pod timing exporter, Dagster run exporter, and the run trigger script.

## Acceptance Criteria
- [ ] `collect_vm_metrics.py` writes CSV with timestamps, CPU %, memory %, process count
- [ ] `collect_k8s_metrics.sh` writes CSV with pod-level CPU and memory (via kubectl top)
- [ ] `collect_pod_timing.py` writes CSV with created, scheduled, ready timestamps
- [ ] `export_dagster_runs.py` exports all runs from Dagster PostgreSQL to CSV
- [ ] `trigger_dagster_runs.py` launches N concurrent runs and exits
- [ ] All scripts tested end-to-end with a single L1 test run
- [ ] Graceful shutdown on SIGTERM/SIGINT for all collector scripts