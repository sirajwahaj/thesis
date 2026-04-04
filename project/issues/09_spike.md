# [THESIS-009] Run Experiment 2C — Spike Observation

Labels: experiment  
Story Points: 2  
Dependencies: THESIS-007  

## Description
Run L6 (10 concurrent) on K8s and observe scheduling delays. Record how many pods are pending, how long until all start, and any failures.

## Acceptance Criteria
- [ ] 3 repetitions at L6 (10 concurrent) on K8s
- [ ] Record: number of pending pods over time, time to all-pods-running
- [ ] Record any scheduling timeouts or failures
- [ ] `spike_observation.csv` per run with timestamps
- [ ] `pod_timing.csv` per run showing scheduling latency at extreme load