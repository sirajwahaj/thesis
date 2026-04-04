# [THESIS-006] Run Experiment 1 — VM Degradation

Labels: experiment  
Story Points: 5  
Dependencies: THESIS-005  

## Description
Execute Experiment 1 on the VM. Run all 6 concurrency levels (L1–L6), 3 repetitions each. Collect all metrics. Verify data integrity. This answers SQ1.

## Acceptance Criteria
- [ ] 18 batches completed (6 levels × 3 reps)
- [ ] `dagster_runs.csv` for each batch contains correct number of run records
- [ ] `vm_metrics.csv` for each batch has continuous timestamps during execution
- [ ] All `metadata.json` files present and accurate
- [ ] No data corruption or missing files
- [ ] Success rate drops observed at higher concurrency levels (confirms thesis premise)
- [ ] Wait 60 seconds between batches for system to settle