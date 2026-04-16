# Claude Code — Project Structure Guide

**What this directory is:** Claude Code (the Anthropic CLI tool `claude`) reads this `.claude/` folder automatically. Every subdirectory controls a different aspect of how Claude behaves in this repo. This README explains each primitive with exact examples from this thesis project.

---

## Quick Reference

| File / Folder | When loaded | Purpose |
|---|---|---|
| `CLAUDE.md` (root) | Every session start | Project overview, tech stack, commands |
| `CLAUDE.local.md` (root) | Every session, gitignored | Personal overrides (your VM IP, local paths) |
| `.mcp.json` (root) | On connect | Wires Claude to external data sources (PostgreSQL, GitHub) |
| `.claude/settings.json` | Every session | Permissions: what Claude can/cannot run |
| `.claude/rules/*.md` | Always active | Standing rules by topic — enforce thesis integrity |
| `.claude/commands/*.md` | `/project:<name>` slash commands | Repeatable one-click workflows |
| `.claude/skills/<name>/SKILL.md` | Auto-triggered by context | Deep domain knowledge loaded only when needed |
| `.claude/agents/*.md` | Sub-agent invocations | Specialised agents with isolated context |
| `.claude/hooks/*.sh` | Pre/post tool-use events | Block unsafe ops, auto-validate, auto-format |

---

## 1. `CLAUDE.md` — Session Anchor

**What it does:** Loaded at the start of every Claude Code session. Defines the project, tech stack, architecture, and commands. Claude treats this as ground truth.

**Already exists** at repo root. Key sections it must include:
- Research questions (locked)
- Tech stack constraints (Python 3.12, uv, podman, Kind, Dagster 1.12.7)
- Data flow: `run_experiment.sh` → `data/raw/` → `analysis.ipynb` → `results/` → LaTeX
- Common `make` commands

**This repo's CLAUDE.md already covers all of this.** The only rule: keep it ≤ 250 lines. If a section grows, move detail to a `rules/` file and link.

---

## 2. `CLAUDE.local.md` — Personal Overrides

**What it does:** Same format as `CLAUDE.md`, but gitignored. Use for machine-specific values you don't want committed.

**For this repo, create `CLAUDE.local.md` at the root with:**
```markdown
# Local Overrides

## My VM
- IP: 192.168.64.5   (your actual UTM VM IP)
- SSH key: ~/.ssh/thesis_vm

## Paths
- DAGSTER_HOME: /opt/thesis/dagster_home
- Local registry: localhost:5001

## Experiment status
- Exp1 VM: DONE (2026-04-20)
- Exp2A K8s: IN PROGRESS
- Exp2B Blast: TODO
- Exp2C Spike: TODO
```

**Why useful:** You can ask Claude "what's my VM IP?" and it will know. You can track experiment completion status without committing it.

---

## 3. `.mcp.json` — External Data Sources

**What it does:** Wires Claude to live data sources via Model Context Protocol (MCP). Claude can then query them mid-conversation without you copy-pasting.

**For this repo — create `.mcp.json` at root:**
```json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "DATABASE_URL": "postgresql://dagster:dagster@localhost:5432/dagster"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/sirajulhaqwahaj/thesis/data"]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "your-pat-here"
      }
    }
  }
}
```

**What this unlocks for the thesis:**
- `postgres` → Claude can `SELECT * FROM runs WHERE status='FAILURE'` in real time during experiments to debug failures
- `filesystem` → Claude can read `data/raw/` CSVs without you pasting them — answers SQ1 questions directly from live data
- `github` → Claude can create GitHub issues (THESIS-006 etc.) and check PR status without leaving the editor

**Note:** Add `.mcp.json` to `.gitignore` if it contains tokens, or use env var references.

---

## 4. `.claude/settings.json` — Permissions & Tool Access

**What it does:** Controls which shell commands Claude can run, which it must ask permission for, and which are blocked entirely. Prevents accidental destructive operations.

**Create `.claude/settings.json`:**
```json
{
  "permissions": {
    "allow": [
      "Bash(make:*)",
      "Bash(bash scripts/*.sh:*)",
      "Bash(python3:*)",
      "Bash(kubectl:*)",
      "Bash(kind:*)",
      "Bash(helm:*)",
      "Bash(ansible-playbook:*)",
      "Bash(podman:*)",
      "Bash(git status)",
      "Bash(git diff:*)",
      "Bash(git log:*)"
    ],
    "deny": [
      "Bash(rm -rf data/raw/*)",
      "Bash(rm -rf src/workload/*)",
      "Bash(git push --force:*)",
      "Bash(git reset --hard:*)",
      "Bash(DROP TABLE:*)",
      "Bash(kubectl delete namespace:*)"
    ]
  },
  "model": "claude-sonnet-4-5"
}
```

**Why this matters for the thesis:**
- `data/raw/` is protected — Claude cannot wipe your experiment data even if you accidentally ask it to
- `src/workload/workload_job.py` changes require explicit approval — prevents accidental workload modification that would invalidate SQ1 results
- `kubectl delete namespace` is blocked — prevents destroying the running K8s experiment environment mid-run

**`settings.local.json`** is the gitignored version for personal model/API key overrides.

---

## 5. `.claude/rules/` — Standing Rules by Topic

**What it does:** Each `.md` file in `rules/` is always injected into Claude's context. Use one file per concern. Target specific files with frontmatter `globs:`.

### Rule files for this thesis:

---

#### `rules/experiment-integrity.md`
```markdown
---
globs: ["src/workload/*", "scripts/run_experiment.sh", "notebooks/analysis.ipynb"]
---
# Experiment Integrity Rules

These rules protect the scientific validity of the thesis experiments.

## NEVER change without supervisor approval:
- Workload duration: WORKLOAD_DURATION_SECONDS=30 is fixed
- Workload algorithm: SHA-256 hashing in cpu_burn() — do not swap
- Concurrency levels: L1=1, L2=2, L3=3, L4=5, L5=7, L6=10 — immutable
- Repetition count: 3 per level — immutable
- Research questions (RQ, SQ1–SQ4) — locked per thesis committee

## When editing workload_job.py:
- Never change the cpu_burn() loop logic
- Never change WORKLOAD_DURATION_SECONDS default
- Only allowed changes: logging, return value enrichment (non-breaking)

## When editing run_experiment.sh:
- DEFAULT_LEVELS must remain "1 2 3 5 7 10"
- REPETITIONS must remain 3
- COOLDOWN must remain >= 60s (cooldown protects measurement independence)
```

---

#### `rules/python.md`
```markdown
---
globs: ["src/**/*.py", "scripts/**/*.py"]
---
# Python Conventions

- Python 3.12 only — no f-string walrus, match/case is OK
- Package manager: uv ONLY. Never suggest `pip install`.
  - Add deps: `uv add <package>`
  - Lock file: uv.lock (commit this)
- Virtual env: src/.venv (activated by Containerfile and Ansible)
- Type hints: preferred but not required for existing scripts
- Dagster version: 1.12.7 — do not suggest upgrading mid-experiment

## Import order (ruff enforces):
1. stdlib
2. third-party (dagster, pandas, etc.)
3. local

## Data collection scripts (scripts/collect_*.py, scripts/export_*.py):
- Must output CSV with header row
- Must write to data/raw/exp{N}/{env}/L{level}/run{rep}/ path structure
- Must never write to data/processed/ (that's analysis.ipynb's job)
```

---

#### `rules/latex.md`
```markdown
---
globs: ["docs/**/*.tex"]
---
# LaTeX Thesis Conventions

## File structure:
- One .tex per section, \input{} from chapter hub files
- Hub files: docs/chapters/0N-name/main.tex
- Never edit proposal/ — it is stale. docs/chapters/ is canonical.

## Metric naming (must match metrics.tex exactly):
- "job success rate" (not "success rate" or "completion rate")
- "execution time variance" (not "std dev" or "variance")  
- "pod scheduling latency" (not "scheduling time" or "schedule latency")
- "crossover point" (not "break-even" or "inflection point")

## Figures:
- All figures come from results/*.png via make copy-figures
- Never add static images manually to docs/figures/
- Reference as: \includegraphics{figures/exp1_success_rate.png}

## Results chapter (docs/chapters/04-results/):
- Fill in TODO comments ONLY after experiments are complete
- Table values come from data/processed/*.csv — do not hardcode
```

---

#### `rules/data-pipeline.md`
```markdown
# Data Pipeline Rules

The pipeline is: run_experiment.sh → data/raw/ → analysis.ipynb → results/ → docs/figures/

## data/raw/ rules:
- Read-only after experiment runs complete (do not modify)
- Structure: data/raw/exp{N}/{env}/L{level}/run{rep}/
- Required files per run: dagster_runs.csv, metadata.json
- K8s runs also require: pod_timing.csv

## analysis.ipynb rules:
- Single source of truth for ALL analysis (SQ1–SQ4)
- No analysis logic in scripts/analyze_results.py (it only invokes the notebook)
- All metric calculations must reference exact definitions in docs/chapters/03-method/metrics.tex
- Crossover point: where BOTH reliability crossover AND performance crossover conditions are met

## Propagation rule:
- Any change to data collection scripts → also update analysis.ipynb expectations
- Any change to analysis logic → also check docs/chapters/04-results/ TODOs
- Any new metric → add to metrics.tex FIRST, then implement collection, then analysis
```

---

## 6. `.claude/commands/` — Repeatable Slash Commands

**What it does:** Each `.md` file becomes a `/project:<filename>` slash command in the Claude interface. Type `/project:validate` and Claude runs the validation workflow. Supports `$ARGUMENTS` for parameterisation.

### Commands for this thesis:

---

#### `commands/validate.md`
```markdown
Run the thesis pre-flight validation and report any issues.

Execute: `bash scripts/validate-experiment-setup.sh`

Then explain:
1. Which systems are ready (VM, K8s, local compose)
2. What specifically is failing and the exact command to fix it
3. Whether it is safe to proceed with experiments
```

---

#### `commands/run-experiment.md`
```markdown
Run a specific thesis experiment.

Experiment: $ARGUMENTS (e.g. "exp1 vm" or "exp2a k8s")

Steps:
1. Run pre-flight: `bash scripts/validate-experiment-setup.sh`
2. If validation passes, run: `bash scripts/run_experiment.sh $ARGUMENTS`
3. Monitor output and report: levels completed, any failures, data written to data/raw/
4. After completion, show the output directory structure created.

If validation fails, do not run the experiment. Fix the issue first.
```

---

#### `commands/analyze-sq1.md`
```markdown
Analyze the SQ1 results from Experiment 1 (VM degradation).

SQ1: "At what concurrency level does a single-VM deployment fail, and how do success rate, execution time variance, and resource utilisation degrade?"

Steps:
1. Check data/raw/exp1-vm-degradation/ exists and has CSV files
2. If data exists, load and summarize: success rates per level, execution time means and std devs, CPU/memory trends
3. Identify: the first level where success rate drops below 95% (reliability crossover threshold)
4. State the answer to SQ1 directly with evidence from the data
5. Flag any anomalies that need investigation before writing up results

If data does not exist: report which levels are missing and what make commands to run.
```

---

#### `commands/crossover.md`
```markdown
Calculate and explain the crossover point (SQ4).

The crossover point is where BOTH conditions are simultaneously true:
1. Reliability crossover: VM success rate drops below 95%
2. Performance crossover: K8s total execution time (including overhead) < VM execution time

Steps:
1. Load data/processed/exp1_summary.csv (VM results) and data/processed/exp2a_summary.csv (K8s results)
2. For each concurrency level, compare: VM success rate, K8s success rate, VM mean execution time, K8s mean execution time + pod scheduling latency + container startup time
3. Find the level where both crossover conditions are satisfied
4. If different levels: report them separately (reliability at L?, performance at L?)
5. State the answer to SQ4 directly

This answers the main research question: "at what workload level does migration become net beneficial?"
```

---

#### `commands/check-alignment.md`
```markdown
Check thesis alignment of recent changes.

Review the last 10 git commits and for each changed file, verify:
1. Does the change serve SQ1, SQ2, SQ3, or SQ4? If not, flag it.
2. Are metric definitions unchanged (check docs/chapters/03-method/metrics.tex)?
3. Are workload parameters unchanged (check src/workload/workload_job.py)?
4. Are concurrency levels unchanged (check scripts/run_experiment.sh DEFAULT_LEVELS)?
5. Was the data pipeline intact (no changes that break: raw → notebook → LaTeX)?

Report: ALIGNED / DRIFT DETECTED, with specific findings.
```

---

## 7. `.claude/skills/` — Auto-Triggered Domain Knowledge

**What it does:** A skill folder contains a `SKILL.md` that describes when to load it and what to do. Claude loads skills automatically based on task context — keeping the main context lean.

### Skills for this thesis:

---

#### `skills/dagster-ops/SKILL.md`
```markdown
---
name: dagster-ops
description: "Use when working with Dagster jobs, runs, assets, sensors, or the Dagster UI. Covers K8sRunLauncher configuration, DockerRunLauncher, gRPC server setup, run monitoring, and debugging failed runs."
---

# Dagster Operations

## Thesis Dagster Setup
- Version: 1.12.7 (pinned — do not upgrade)
- VM: DockerRunLauncher (Docker CE), gRPC server on 0.0.0.0:4000 (systemd service: thesis-workload)
- K8s: K8sRunLauncher via Helm chart k8s/helm/dagster-thesis/

## Trigger a run from CLI (VM environment):
```bash
curl -X POST http://localhost:3001/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { launchRun(executionParams: {selector: {repositoryName: \"__repository__\", repositoryLocationName: \"workload\", jobName: \"thesis_workload\"}, mode: \"default\"}) { run { runId } } }"}'
```

## Check run status:
```bash
python3 scripts/export_dagster_runs.py    # exports to CSV
```

## Debug K8s run failures:
```bash
kubectl get pods -n dagster                              # list all pods
kubectl logs <run-pod-name> -n dagster                   # pod logs
kubectl describe pod <run-pod-name> -n dagster           # events (scheduling issues)
```

## Common issues:
- gRPC server not responding: `systemctl restart thesis-workload` on VM
- K8s pod stuck Pending: check `kubectl describe pod` for resource pressure
- Run shows as FAILURE in Dagster but pod exited 0: check DAGSTER_HOME env var in pod
```

---

#### `skills/experiment-analysis/SKILL.md`
```markdown
---
name: experiment-analysis
description: "Use when analyzing experiment results, interpreting CSV data from data/raw/, writing results sections, calculating crossover points, or interpreting any of the 12 thesis metrics."
---

# Experiment Analysis

## The 12 metrics and how to calculate them from the CSV files:

### From dagster_runs.csv:
- success_rate = (count where status='SUCCESS') / total_runs * 100
- mean_execution_time = mean(end_time - start_time) in seconds
- execution_time_variance = std(end_time - start_time) in seconds
- MTTR = mean(time_to_next_success_after_failure) — requires sorting by run_id

### From pod_timing.csv (K8s only):
- pod_scheduling_latency = mean(pod_running_time - run_submitted_time) in seconds
- container_startup_time = mean(job_start_time - pod_running_time) in seconds
- total_overhead = pod_scheduling_latency + container_startup_time

### From blast_radius.csv:
- failure_blast_radius = 1 if any concurrent job shows degraded success_rate on same batch, else 0
- neighbouring_job_impact = mean execution time delta for surviving jobs

### Derived:
- net_execution_time_delta[level] = vm_mean_time[level] - k8s_total_time[level]
  where k8s_total_time = k8s_mean_execution_time + total_overhead
- reliability_crossover = first level where vm_success_rate < 95%
- performance_crossover = first level where net_execution_time_delta < 0 (K8s faster)
- crossover_point = max(reliability_crossover, performance_crossover)

## SciPy tests to use:
- Normality: shapiro(execution_times) — if p < 0.05, use non-parametric
- Comparison: mannwhitneyu(vm_times, k8s_times) — non-parametric, α=0.05
- Effect size: cohen_d or rank-biserial correlation
```

---

#### `skills/latex-writing/SKILL.md`
```markdown
---
name: latex-writing
description: "Use when writing or editing LaTeX thesis chapters, adding figures, creating tables, or formatting results for the thesis document."
---

# LaTeX Thesis Writing

## Chapter structure:
- docs/chapters/04-results/ — fill after ALL experiments complete
- One .tex per section: exp1.tex, exp2.tex, exp3.tex
- Hub file: docs/chapters/04-results/main.tex (uses \input{})

## Adding a result figure:
```latex
\begin{figure}[htbp]
  \centering
  \includegraphics[width=0.9\textwidth]{figures/exp1_success_rate.png}
  \caption{Job success rate across concurrency levels (VM, Experiment 1).
           Each point is the mean of 3 repetitions; error bars show ±1 std dev.}
  \label{fig:exp1-success-rate}
\end{figure}
```

## Adding a results table (from data/processed/):
```latex
\begin{table}[htbp]
  \centering
  \caption{VM execution metrics by concurrency level (Experiment 1)}
  \begin{tabular}{lrrrr}
    \toprule
    Level & Concurrent Jobs & Success Rate (\%) & Mean Time (s) & Std Dev (s) \\
    \midrule
    L1 & 1  & 100.0 & 30.2 & 0.3 \\
    % ... fill from data/processed/exp1_summary.csv
    \bottomrule
  \end{tabular}
  \label{tab:exp1-results}
\end{table}
```

## SQ answer format (use in discussion chapter):
"SQ1 is answered at concurrency level L? (? concurrent jobs), where the VM success rate
first dropped below the 95\% reliability threshold, recording ??\% success rate with
a mean execution time of ??s (±??s std dev) and CPU utilisation of ??\%."
```

---

## 8. `.claude/agents/` — Specialised Sub-Agents

**What it does:** Each `.md` file defines a specialised Claude agent with a specific role, tool set, and context. Useful for isolating concerns so one agent handles infrastructure while another handles thesis writing — without context pollution.

### Agents for this thesis:

---

#### `agents/thesis-analyzer.md`
```markdown
---
name: thesis-analyzer
description: "Specialized agent for analyzing experiment results and answering SQ1–SQ4. Has access to the data pipeline and statistical analysis tools. Use for: interpreting CSVs, calculating crossover point, drafting results sections."
tools: ["Read", "Bash", "Write"]
---

# Thesis Data Analyzer

You are a data analysis agent specializing in the thesis experiment results.

## Your purpose
Analyze data from `data/raw/` and `data/processed/` to answer the four supporting questions:
- SQ1: VM degradation threshold
- SQ2: K8s pod isolation effectiveness
- SQ3: K8s scheduling overhead
- SQ4: Crossover point

## Your constraints
- Never modify files in data/raw/ — they are raw experiment outputs
- Always cite specific CSV column names and values when making claims
- Always run `make analyze` before interpreting data (ensures notebook is current)
- Express uncertainty when data is incomplete (e.g., missing repetitions)

## Statistical standards
- Use non-parametric tests (Mann-Whitney U) unless normality confirmed (Shapiro-Wilk p > 0.05)
- Report effect size alongside p-values
- α = 0.05 for all significance tests
- Report confidence intervals for mean execution times

## Output format for SQ answers
State the answer in one sentence, then support with: table of values, statistical test result, plot reference.
```

---

#### `agents/infrastructure.md`
```markdown
---
name: infrastructure
description: "Specialized agent for VM, Kubernetes, Ansible, and Docker/podman operations. Use for: setting up the benchmarking environment, debugging K8s issues, provisioning the VM, and running make bootstrap/vm-provision/k8s-setup commands."
tools: ["Bash", "Read", "Write"]
---

# Infrastructure Agent

You are an infrastructure specialist for the thesis benchmarking environment.

## Your environment
- macOS M2 host
- UTM VM: Ubuntu 22.04, 4 vCPU, 8 GB RAM, IP in vm-ip.txt
- Kind K8s cluster: named 'thesis', single-node
- Container runtime: podman (not Docker)
- Package manager for VM config: Ansible only (never manual apt install)

## Your tools
- VM: `ssh -i ~/.ssh/thesis_vm ubuntu@$(cat vm-ip.txt)` 
- K8s: `kubectl`, `helm`, `kind`
- Validation: `bash scripts/validate-experiment-setup.sh`
- Provisioning: `make vm-provision` (Ansible) 
- K8s setup: `make k8s-setup` (Kind + Helm)

## Your constraints
- Never bypass Ansible for VM configuration (no manual `sudo apt install` on VM)
- Never apply raw `kubectl` manifests — use Helm chart `k8s/helm/dagster-thesis/`
- Never change resource limits (4 vCPU, 8 GB) — they are calibrated for experiment comparability
- Never create a second Kind cluster or add nodes — single-node thesis cluster only

## Debugging priority
1. Check `bash scripts/validate-experiment-setup.sh` first
2. Check service logs (`kubectl logs`, `journalctl -u thesis-workload`)
3. Recreate only as last resort: `make k8s-reset` or `make vm-provision`
```

---

## 9. `.claude/hooks/` — Pre/Post Tool-Use Enforcement

**What it does:** Shell scripts triggered at Claude Code lifecycle events. `PreToolUse` fires before a tool runs (can block it). `PostToolUse` fires after (can validate output). These are deterministic — unlike instructions, they actually enforce rules.

### Hooks config goes in `.claude/settings.json` under `"hooks"`:

```json
{
  "permissions": { ... },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/block-data-destruction.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [{ "type": "command", "command": "bash .claude/hooks/check-workload-unchanged.sh" }]
      }
    ]
  }
}
```

### Hook scripts:

---

#### `hooks/block-data-destruction.sh`
```bash
#!/usr/bin/env bash
# PreToolUse hook — blocks destructive commands on experiment-critical paths.
# Reads the proposed command from stdin (JSON: {"tool_input": {"command": "..."}})

INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Block rm -rf on raw experiment data
if echo "$CMD" | grep -qE "rm.*(data/raw|src/workload)"; then
  echo "BLOCKED: Cannot delete experiment data or workload source. These are protected." >&2
  exit 2
fi

# Block git reset --hard (would lose uncommitted experiment data paths)
if echo "$CMD" | grep -qE "git reset --hard"; then
  echo "BLOCKED: git reset --hard requires manual confirmation (use terminal directly)." >&2
  exit 2
fi

exit 0
```

---

#### `hooks/check-workload-unchanged.sh`
```bash
#!/usr/bin/env bash
# PostToolUse hook — warns if workload_job.py was modified.
# A changed workload invalidates experiment comparability.

INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('path',''))" 2>/dev/null || echo "")

if echo "$FILE" | grep -q "workload_job.py"; then
  echo ""
  echo "⚠️  WARNING: workload_job.py was modified." >&2
  echo "   This file defines the experiment workload (SHA-256, 30s duration)." >&2
  echo "   Changing it invalidates comparability between VM and K8s results." >&2
  echo "   Verify this change is intentional and approved by supervisor." >&2
  echo ""
fi

exit 0
```

---

## Summary: What to Create Now vs Later

| File | Priority | Effort | Benefit |
|------|----------|--------|---------|
| `CLAUDE.md` | ✅ Done | — | Session anchor |
| `.github/copilot-instructions.md` | ✅ Done | — | Auto-loaded by Copilot |
| `CLAUDE.local.md` | **HIGH** | 5 min | Personal VM IP, experiment status |
| `.mcp.json` | HIGH | 10 min | Live PostgreSQL queries mid-session |
| `.claude/settings.json` | HIGH | 10 min | Protect data/raw/ and workload |
| `rules/experiment-integrity.md` | HIGH | 5 min | Prevents science-breaking edits |
| `rules/python.md` | MEDIUM | 5 min | Consistent code style |
| `rules/data-pipeline.md` | HIGH | 5 min | Pipeline integrity |
| `commands/analyze-sq1.md` | HIGH | 5 min | One-click SQ1 analysis |
| `commands/crossover.md` | HIGH | 5 min | One-click SQ4/crossover answer |
| `commands/validate.md` | MEDIUM | 5 min | One-click pre-flight |
| `skills/experiment-analysis/` | HIGH | 10 min | Deep metric knowledge auto-loaded |
| `skills/dagster-ops/` | MEDIUM | 10 min | Dagster debugging knowledge |
| `agents/thesis-analyzer.md` | HIGH | 10 min | Isolated analysis context |
| `agents/infrastructure.md` | MEDIUM | 10 min | Isolated infra context |
| `hooks/block-data-destruction.sh` | HIGH | 5 min | Hard block on data deletion |
| `.mcp.json` postgres | MEDIUM | 15 min | Live DB queries |

**Minimum viable set** (do these today):
1. `CLAUDE.local.md` — add your VM IP and experiment status
2. `.claude/settings.json` — protect data/raw/ and workload
3. `rules/experiment-integrity.md` — SQ1–SQ4 integrity rules
4. `commands/analyze-sq1.md` + `commands/crossover.md` — one-click answers
5. `hooks/block-data-destruction.sh` — hard protection

**Use Claude Code (`claude` CLI) to create them in bulk:**
```bash
claude "Create all the .claude/ files described in .claude/README.md"
```
