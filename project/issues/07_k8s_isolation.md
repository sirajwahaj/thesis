# [THESIS-007] Run Experiment 2A — K8s Isolation

Labels: experiment  
Story Points: 5  
Dependencies: THESIS-005  

## Description
Execute Experiment 2A on the Kind cluster. Same 6 levels, 3 repetitions. Collect pod-level metrics and pod timing data. This answers SQ2.

## Acceptance Criteria
- [ ] 18 batches completed (6 levels × 3 reps)
- [ ] `k8s_pod_metrics.csv` per batch with pod-level CPU/memory
- [ ] `pod_timing.csv` per batch with scheduling and startup timestamps
- [ ] `dagster_runs.csv` per batch with run status and duration
- [ ] All `metadata.json` files present and accurate
- [ ] Pod isolation confirmed: each run has its own pod visible in `kubectl get pods`
- [ ] No data corruption or missing files