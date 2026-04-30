---
globs: ["src/workload/*", "scripts/run_experiment.sh", "notebooks/analysis.ipynb"]
---

# Experiment Integrity Rules

These rules protect the scientific validity of the thesis experiments.
Violating them invalidates comparability between VM and K8s results.

## Parameters that are LOCKED — never change without supervisor approval

| Parameter | Value | Location |
|-----------|-------|----------|
| Workload duration | `WORKLOAD_DURATION_SECONDS=30` | `src/workload/workload_job.py` |
| Workload algorithm | SHA-256 `hashlib.sha256(b"dagster-thesis-workload").hexdigest()` | `cpu_burn()` loop |
| Dagster version | 1.12.22 | `src/pyproject.toml` |
| Python version | >=3.13 | `src/pyproject.toml`, `src/Containerfile` |
| Concurrency levels | L1=1, L2=2, L3=3, L5=5, L7=7, L10=10 | `scripts/run_experiment.sh` `DEFAULT_LEVELS` |
| Repetitions per level | 3 | `scripts/run_experiment.sh` `REPETITIONS` |
| Cooldown between reps | ≥ 60 seconds | `scripts/run_experiment.sh` `COOLDOWN` |
| Research questions | RQ, SQ1, SQ2, SQ3, SQ4 | `docs/chapters/01-introduction/` |

## Rules for `src/workload/workload_job.py`

- **Never change** the `cpu_burn()` loop body (the SHA-256 hash line must remain)
- **Never change** `WORKLOAD_DURATION_SECONDS` default value from `30`
- Allowed changes (non-breaking): logging statements, adding timing fields to the return dict
- **Before any edit**, verify the change does not alter CPU load profile or duration

## Rules for `scripts/run_experiment.sh`

- `DEFAULT_LEVELS` must remain `"1 2 3 5 7 10"` (in that order)
- `REPETITIONS` must remain `3`
- `COOLDOWN` must remain `>= 60` (independent measurement requirement)
- Do not skip levels — all 6 must run to produce the SQ4 crossover analysis

## Rules for `notebooks/analysis.ipynb`

- This is the **single source of truth** for all analysis (SQ1–SQ4)
- Do not move analysis logic to `scripts/analyze_results.py` (it only invokes the notebook)
- Every crossover calculation must follow the exact definition:
  - Reliability crossover: first level where VM success rate < 95%
  - Performance crossover: first level where K8s total time < VM execution time
  - Crossover point: the level where BOTH conditions are simultaneously true

## Research Questions (Do Not Change)

- **RQ**: How do reliability, system stability, and execution performance change when a Dagster
  workflow system migrates from VM DockerRunLauncher to K8s K8sRunLauncher under increasing load,
  and at what workload level does migration become net beneficial?
- **SQ1**: VM Docker executor failure threshold (concurrency level where VM Docker containers degrade)
- **SQ2**: K8s pod isolation vs VM Docker container isolation (blast radius, containment)
- **SQ3**: K8s scheduling and startup overhead per level (on top of Docker container startup)
- **SQ4**: Crossover point where K8s overhead < VM contention degradation
