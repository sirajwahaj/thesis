# [THESIS-003] Workload Implementation

Labels: experiment  
Story Points: 2  
Dependencies: THESIS-001, THESIS-002  

## Description
Build the CPU-bound workload job (SHA-256 hashing), Dockerfile, and Dagster configuration. Test that the workload produces consistent results across both environments.

## Acceptance Criteria
- [ ] `workload_job.py` with configurable duration via `WORKLOAD_DURATION_SECONDS` env var
- [ ] Dockerfile that packages the workload for K8s deployment
- [ ] Workload produces deterministic CPU load (verified via `top` / `kubectl top`)
- [ ] Single-job execution time is within 5% between VM and K8s (no contention test)
- [ ] Iteration count logged for secondary throughput metric
- [ ] 30-second default duration per job