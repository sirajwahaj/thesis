# [THESIS-005] Master Experiment Runner

Labels: experiment  
Story Points: 2  
Dependencies: THESIS-004  

## Description
Build `run_experiment.sh` that orchestrates the full experiment pipeline: triggers runs, collects metrics, exports data, writes metadata, and respects cooldown periods.

## Acceptance Criteria
- [ ] Takes `experiment` and `environment` as arguments (e.g., `exp1 vm`)
- [ ] Iterates over all 6 levels (1, 2, 3, 5, 7, 10) with 3 repetitions each
- [ ] Starts and stops metrics collectors for each batch
- [ ] Writes `metadata.json` per run with all parameters
- [ ] 60-second cooldown between batches
- [ ] `--dry-run` mode that prints what it would do without executing
- [ ] `--levels` flag to run only specific concurrency levels
- [ ] Full dry run at L1 and L2 passes without errors