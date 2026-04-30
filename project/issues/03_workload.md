# [THESIS-003] Workload Implementation

Labels: experiment
Story Points: 2
Dependencies: THESIS-001, THESIS-002

## Description
Build the CPU-bound workload job (SHA-256 hashing), Dockerfile, and Dagster configuration. Test that the workload produces consistent results across both environments.

## Acceptance Criteria
- [x] `workload_job.py` with configurable duration via `WORKLOAD_DURATION_SECONDS` env var
- [x] Containerfile (`src/Containerfile`) that packages the workload for K8s deployment (Python 3.13, dagster-k8s 0.28.22)
- [x] Workload produces deterministic CPU load (SHA-256 hashing loop verified)
- [x] 30-second default duration per job
- [x] Iteration count logged for secondary throughput metric
- [ ] Single-job execution time within 5% between VM and K8s (baseline L1 comparison — needs both envs running)

## Notes
Image: `localhost:5001/thesis-workload:latest` loaded into Kind registry.
SHA-256 hash line preserved: `hashlib.sha256(b"dagster-thesis-workload").hexdigest()`.
