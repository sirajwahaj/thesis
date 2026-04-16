---
name: experiment-analysis
description: "Use when analyzing experiment results, interpreting CSVs from data/raw/ or data/processed/, writing results sections, calculating any of the 12 thesis metrics, running statistical tests, or identifying the crossover point."
---

# Experiment Analysis

## The 12 thesis metrics — exact formulas from CSV columns

### Group 1: From `dagster_runs.csv` (both VM and K8s)

| # | Metric | CSV columns | Formula |
|---|--------|------------|---------|
| 1 | Job success rate | `status` | `len(df[df.status == 'SUCCESS']) / len(df) * 100` |
| 2 | Mean execution time | `start_time`, `end_time` | `(df.end_time - df.start_time).mean()` in seconds |
| 3 | Execution time variance | `start_time`, `end_time` | `(df.end_time - df.start_time).std()` in seconds |
| 4 | CPU utilisation | `cpu_pct` | `df.cpu_pct.mean()` per level |
| 5 | Memory utilisation | `mem_pct` | `df.mem_pct.mean()` per level |
| 6 | MTTR | `status`, `run_id`, `end_time` | mean time from failure detection to next SUCCESS run in same batch |

### Group 2: From `pod_timing.csv` (K8s only)

| # | Metric | CSV columns | Formula |
|---|--------|------------|---------|
| 8 | Pod scheduling latency | `submitted_ts`, `running_ts` | `(df.running_ts - df.submitted_ts).mean()` in seconds |
| 9 | Container startup time | `running_ts`, `job_start_ts` | `(df.job_start_ts - df.running_ts).mean()` in seconds |
| 10 | Net execution time Δ | derived | `vm_mean_time[level] - (k8s_mean_time[level] + pod_sched_lat[level] + container_startup[level])` |

### Group 3: From `blast_radius.csv` (Exp2B only)

| # | Metric | Formula |
|---|--------|---------|
| 7 | Failure blast radius | `1` if any concurrent job shows degraded success rate when another fails; `0` otherwise |

### Group 4: Derived crossover metrics

| # | Metric | Formula |
|---|--------|---------|
| 11 | Reliability crossover | First level where `vm_success_rate[level] < 95.0` |
| 12 | Performance crossover | First level where `net_execution_time_delta[level] < 0` (K8s total faster) |

**Crossover point** (answers SQ4 and RQ):
```python
crossover_level = max(reliability_crossover_level, performance_crossover_level)
```
If reliability_crossover never triggered (VM always ≥ 95%), crossover_level = performance_crossover_level only.

---

## Loading data (Python/pandas)

```python
import pandas as pd
from pathlib import Path

# Load all VM runs for Exp1 levels
dfs = []
for level in [1, 2, 3, 5, 7, 10]:
    for rep in [1, 2, 3]:
        p = Path(f"data/raw/exp1-vm-degradation/vm/L{level}/run{rep}/dagster_runs.csv")
        if p.exists():
            df = pd.read_csv(p)
            df["level"] = level
            df["rep"] = rep
            dfs.append(df)

runs = pd.concat(dfs, ignore_index=True)
runs["exec_time"] = pd.to_datetime(runs["end_time"]) - pd.to_datetime(runs["start_time"])
runs["exec_secs"] = runs["exec_time"].dt.total_seconds()
```

## Per-level summary table (standard output)

```python
summary = runs.groupby("level").agg(
    n_runs=("run_id", "count"),
    success_rate=("status", lambda x: (x == "SUCCESS").mean() * 100),
    mean_exec=("exec_secs", "mean"),
    std_exec=("exec_secs", "std"),
    mean_cpu=("cpu_pct", "mean"),
    mean_mem=("mem_pct", "mean"),
).round(2)
```

---

## Statistical tests

### Choosing the right test

1. First check normality with Shapiro-Wilk:
   ```python
   from scipy import stats
   stat, p = stats.shapiro(group["exec_secs"])
   # If p < 0.05: non-normal → use Mann-Whitney U
   # If p ≥ 0.05: normal → can use t-test, but Mann-Whitney is still acceptable
   ```

2. For VM vs K8s comparison at each level:
   ```python
   stat, p = stats.mannwhitneyu(vm_times, k8s_times, alternative="two-sided")
   # α = 0.05 for all significance tests
   ```

3. Effect size (rank-biserial correlation for Mann-Whitney):
   ```python
   n1, n2 = len(vm_times), len(k8s_times)
   r = 1 - (2 * stat) / (n1 * n2)  # range: -1 to +1
   ```

### Reporting format

> "At L4 (5 concurrent jobs), VM execution time (mean=42.1s, SD=8.3s) was significantly
> higher than K8s (mean=35.6s + 4.2s overhead = 39.8s, SD=2.1s),
> U=12, p=0.03, r=0.61 (large effect)."

---

## Interpreting results

### SQ1 (VM degradation — Exp1)
- Look for: first level where success rate < 95% AND/OR execution time std dev increases sharply
- Threshold for "degradation": ≥ 2× increase in std dev OR success rate < 95%

### SQ2 (isolation — Exp2A + Exp2B)
- Compare success rates and std dev at same levels across VM vs K8s
- Blast radius: did any FAILURE run cause adjacent concurrent runs to also fail or slow down?

### SQ3 (overhead — Exp2A + Exp2C)
- Overhead = pod_scheduling_latency + container_startup_time
- Report: mean ± SD per level, trend (does overhead grow with concurrency?)

### SQ4 (crossover — Exp3, derived)
- Find both crossover levels, report separately if different
- If no crossover within L1–L6: this is still a valid finding (migration not yet beneficial)

---

## Visualization conventions

```python
import matplotlib.pyplot as plt

# Standard plot for a metric across levels
fig, ax = plt.subplots(figsize=(8, 4))
ax.errorbar(summary.index, summary["mean_exec"], yerr=summary["std_exec"],
            fmt="o-", capsize=4, label="VM")
ax.set_xlabel("Concurrency level (concurrent jobs)")
ax.set_ylabel("Execution time (s)")
ax.set_xticks([1, 2, 3, 5, 7, 10])
ax.set_xticklabels(["L1\n(1)", "L2\n(2)", "L3\n(3)", "L4\n(5)", "L5\n(7)", "L6\n(10)"])
ax.axhline(y=95, color="red", linestyle="--", label="95% threshold")  # for success rate plots
ax.legend()
plt.tight_layout()
plt.savefig("results/exp1_mean_execution_time.png", dpi=150, bbox_inches="tight")
```
