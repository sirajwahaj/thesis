Audit the last 10 commits for thesis alignment.

## Step 1 — Get recent commits

```bash
git log --oneline -10
git diff HEAD~10 HEAD --name-only
```

## Step 2 — For each changed file, check alignment

For every file changed in the last 10 commits, answer:

**Does this change serve a research question?**

| File changed | Serves SQ1? | SQ2? | SQ3? | SQ4? | Verdict |
|-------------|-------------|------|------|------|---------|
| ...         |             |      |      |      | ALIGNED / FLAG |

Flag a change if it:
- Does not serve any of SQ1–SQ4
- Adds features outside the experiment design
- Changes the workload, levels, repetitions, or duration
- Introduces a new tool not in the approved stack

## Step 3 — Integrity checks

Run these exact checks:

```bash
# 1. Workload duration unchanged?
grep "WORKLOAD_DURATION_SECONDS" src/workload/workload_job.py

# 2. Concurrency levels unchanged?
grep "DEFAULT_LEVELS" scripts/run_experiment.sh

# 3. Repetition count unchanged?
grep "REPETITIONS" scripts/run_experiment.sh

# 4. Dagster version unchanged?
grep "dagster" src/pyproject.toml | head -5
```

Expected values:
- `WORKLOAD_DURATION_SECONDS`: default `30` (or env var, unchanged)
- `DEFAULT_LEVELS`: `"1 2 3 5 7 10"` exactly
- `REPETITIONS`: `3` exactly
- `dagster` version: `1.12.7` (not higher)

## Step 4 — Report

Final verdict: **ALIGNED** or **DRIFT DETECTED**

If DRIFT DETECTED, list:
1. The specific commit that introduced the drift
2. The exact change
3. Whether it can be safely reverted or requires discussion
