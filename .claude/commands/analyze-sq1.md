Analyze the SQ1 results from Experiment 1 (VM degradation).

**SQ1**: "At what concurrency level does a single-VM deployment fail, and how do success rate,
execution time variance, and resource utilisation degrade?"

## Step 1 — Check data availability

List `data/raw/exp1-vm-degradation/` and report:
- Which levels (L1–L6) have data
- Which repetitions (1–3) are present per level
- Any missing files (signal these as gaps before analysis)

If no data exists at all, report which make command to run:
```bash
make exp1-vm    # runs Experiment 1 on the VM
```

## Step 2 — Run analysis

If data exists, run:
```bash
make analyze
```

Then load `data/processed/exp1_vm_summary.csv` and compute:

| Metric | What to report |
|--------|---------------|
| Success rate | % per level — flag any level below 95% |
| Mean execution time | seconds, per level |
| Execution time std dev | seconds, per level — flag sharp increases |
| CPU utilisation | % per level |
| Memory utilisation | % per level |

## Step 3 — Answer SQ1

State the direct answer to SQ1:

> "The VM deployment begins to degrade at concurrency level **L?** (? concurrent jobs),
> where the success rate drops to **?%** (below the 95% threshold).
> Execution time variance increases by **?×** between L1 and the degradation point.
> CPU utilisation reaches **?%** at L?."

If the 95% threshold is never crossed, report that too — it is still a valid SQ1 answer.

## Step 4 — Flag anomalies

Report anything unexpected:
- Levels with 0% success (VM crash?)
- Non-monotonic variance (one level unexpectedly stable)
- Memory spikes that precede CPU saturation
