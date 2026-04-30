# [THESIS-010] Data Analysis and Crossover Calculation

Labels: analysis
Story Points: 5
Dependencies: THESIS-006, THESIS-007, THESIS-008, THESIS-009

## Description
Aggregate all experimental data. Compute summary statistics. Generate comparison tables and plots. Identify the crossover point. This answers SQ3 and SQ4.

## Acceptance Criteria
- [ ] VM summary table: success rate, mean time, std dev per level
- [ ] K8s summary table: same metrics per level
- [ ] Scheduling overhead table: mean scheduling latency, startup time per level
- [ ] Net execution time delta table: VM time minus K8s time per level
- [ ] Crossover plot: VM and K8s curves with intersection marked
- [ ] Reliability crossover identified: level where VM drops below 95%
- [ ] Performance crossover identified: level where K8s total time < VM total time
- [ ] Statistical significance tested (Mann-Whitney U, p-values per level)
- [ ] All outputs saved as CSV and PNG for Overleaf upload

## Notes
Single source of truth: `notebooks/analysis.ipynb`.
Run via: `make analyze` (invokes `scripts/analyze_results.py` headlessly).
Outputs: `data/processed/exp{N}_*_summary.csv`, `results/*.png`.
