# [THESIS-008] Run Experiment 2B — Blast Radius

Labels: experiment  
Story Points: 3  
Dependencies: THESIS-006, THESIS-007  

## Description
Execute the blast radius test at L4 (5 concurrent) on both VM and K8s. Kill one process/pod mid-execution and measure the impact on other running jobs. Part of SQ2.

## Acceptance Criteria
- [ ] 3 repetitions on VM: `kill -9` one Dagster process at L4, record how many other jobs fail
- [ ] 3 repetitions on K8s: `kubectl delete pod --force` one run pod at L4, record same
- [ ] `blast_radius.csv` per run with: killed job, other jobs affected/succeeded/failed
- [ ] Clear documentation of exact kill timing (after all 5 jobs are running)
- [ ] Results clearly show K8s isolates failures better than VM (or not)