Run a specific thesis experiment.

Arguments: $ARGUMENTS
(Examples: "exp1 vm" | "exp2a k8s" | "exp2b blast" | "exp2c spike")

## Step 1 — Pre-flight validation

First run:
```bash
bash scripts/validate-experiment-setup.sh
```

If validation fails, **do not proceed**. Report what is broken and how to fix it.

## Step 2 — Run the experiment

If validation passes, run:
```bash
bash scripts/run_experiment.sh $ARGUMENTS
```

## Step 3 — Monitor and report

While the experiment runs, report:
- Which concurrency level is currently running (L1–L6)
- Which repetition (1/3, 2/3, 3/3)
- Any FAILURE runs detected in real time

## Step 4 — Completion report

After the run finishes, report:
- How many run files were written to `data/raw/`
- The directory structure created (list it with `ls -la data/raw/`)
- Any levels with < 3 successful runs (needs investigation)
- Whether it is safe to proceed to the next experiment

## Experiment reference

| Argument | Concurrency levels | Environment | Answers |
|----------|--------------------|-------------|---------|
| exp1 vm  | L1–L6 (all 6)     | VM          | SQ1: VM degradation threshold |
| exp2a k8s | L1–L6 (all 6)   | K8s         | SQ2: Pod isolation comparison |
| exp2b blast | L4 only        | Both        | SQ2: Blast radius / failure containment |
| exp2c spike | L6 only        | K8s         | SQ3: Scheduling under extreme load |
