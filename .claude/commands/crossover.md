Calculate and explain the crossover point, which directly answers SQ4 and the main RQ.

**SQ4**: "At what concurrency level does K8s overhead become smaller than VM contention-induced
degradation — the crossover point?"

**RQ**: "...at what specific workload level does this migration become net beneficial?"

## Crossover definitions (exact, from metrics.tex)

- **Reliability crossover**: first level where VM success rate drops below 95%
- **Performance crossover**: first level where K8s total time < VM execution time
  - K8s total time = mean execution time + pod scheduling latency + container startup time
- **Crossover point**: the level where BOTH conditions are simultaneously true

## Step 1 — Check data availability

Verify these processed files exist:
- `data/processed/exp1_vm_summary.csv` — columns: level, success_rate, mean_exec_time, std_exec_time, cpu_pct, mem_pct
- `data/processed/exp2a_k8s_summary.csv` — same columns plus: pod_scheduling_latency, container_startup_time
- `data/processed/exp3_crossover.csv` — if it exists, use it directly

If `exp3_crossover.csv` does not exist, run `make analyze` to generate it.

## Step 2 — Build the crossover table

For each level L1–L6, report:

| Level | Jobs | VM Success% | K8s Success% | VM Mean (s) | K8s Total (s) | Net Δ (s) | Reliability? | Performance? |
|-------|------|-------------|--------------|-------------|---------------|-----------|-------------|-------------|
| L1    | 1    | ?           | ?            | ?           | ?             | ?         | No          | No          |
| ...   |      |             |              |             |               |           |             |             |

Net Δ = VM mean time − K8s total time. Positive = VM still faster. Negative = K8s faster.

## Step 3 — State the crossover point

Report:
- Reliability crossover: "VM success rate drops below 95% at **L?** (? jobs)"
- Performance crossover: "K8s becomes faster than VM at **L?** (? jobs)"
- Crossover point: "Both conditions met at **L?** (? concurrent jobs)"

If the two crossovers are at different levels, explain the gap.

## Step 4 — Answer the RQ

> "Migration from VM DockerRunLauncher to K8s K8sRunLauncher becomes net beneficial at
> concurrency level **L?** (? concurrent jobs), where K8s reliability advantage
> (+?% success rate) outweighs its scheduling overhead (?s average per job)."

If the crossover point is never reached within L1–L6, state that explicitly — it is still
a valid thesis finding (migration may not be net beneficial under the tested workload range).
