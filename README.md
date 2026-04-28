<div align="center">

# When Does Kubernetes Become Worth It?

**A YH thesis (JENSEN Yrkeshögskola, DevOps24M) on the reliability and performance crossover point of Kubernetes vs a single-VM workflow executor**

[![CI](https://github.com/sirajwahaj/thesis/actions/workflows/ci.yml/badge.svg)](https://github.com/sirajwahaj/thesis/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Contributing](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Dagster](https://img.shields.io/badge/Dagster-1.12.7-purple)](https://dagster.io)
[![Python](https://img.shields.io/badge/Python-3.12-blue)](https://python.org)

</div>

---

## Background

This thesis originates from a 3-month internship (LIA1) at Insighta Inc., where the author migrated a Dagster data platform from VMs to Kubernetes (GKE). The system works — but was the migration worth the complexity? This thesis answers that question empirically.

## The Research Question

> *How do reliability, system stability, and execution performance change when a workflow orchestration system is migrated from a single-VM process executor to a Kubernetes Run Launcher under increasing concurrent workload — and at what specific workload level does this migration become **net beneficial**?*

### Supporting Questions

| | Question | Answered by |
|---|---|---|
| **SQ1** | At what concurrency level does a single-VM deployment fail? | Experiment 1 |
| **SQ2** | Does Kubernetes pod isolation contain failures better? | Experiment 2A/B |
| **SQ3** | What scheduling overhead does Kubernetes introduce? | Experiment 2A/C |
| **SQ4** | Where is the crossover point? | Experiment 3 |

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/sirajwahaj/thesis.git && cd thesis

# 2. Bootstrap (install deps, create VM, set up K8s) — one command
make bootstrap        # Detects macOS/Windows, installs everything
make vm-provision     # Provision VM via Ansible
make k8s-setup        # Kind cluster + Metrics Server + Dagster

# 3. Validate everything is ready
make validate-setup

# 4. Run all experiments (or individually)
make experiments      # All 4 experiments in sequence
# or individually:
make exp1-vm          # Experiment 1 — VM degradation
make exp2a-k8s        # Experiment 2A — K8s isolation
make exp2b-blast      # Experiment 2B — Blast radius
make exp2c-spike      # Experiment 2C — Spike observation

# 5. Analyse results
make analyze          # → data/processed/ + results/*.png

# 6. Build the thesis PDF
make pdf
```

**Or run everything in a single command:**
```bash
make all   # bootstrap → provision → k8s-setup → experiments → analyze
```

See [docs/setup.md](docs/setup.md) for full setup instructions (macOS) and [docs/setup-windows.md](docs/setup-windows.md) for Windows.

---

## Repository Layout

```
thesis/
├── 📓 notebooks/
│   ├── setup-guide.ipynb       ← Step-by-step environment setup
│   └── analysis.ipynb          ← Interactive data analysis (SQ1–SQ4)
│
├── 📜 scripts/                 ← Experiment orchestration
│   ├── run_experiment.sh       ← Master runner (all levels × 3 reps)
│   ├── collect_vm_metrics.py   ← CPU/memory via psutil
│   ├── collect_k8s_metrics.sh  ← Pod metrics via kubectl top
│   ├── collect_pod_timing.py   ← Scheduling latency from K8s events
│   ├── export_dagster_runs.py  ← Run records from PostgreSQL
│   ├── trigger_dagster_runs.py ← Launch N concurrent runs
│   ├── blast_radius_vm.sh      ← Kill a process, measure impact
│   ├── blast_radius_k8s.sh     ← Delete a pod, measure impact
│   └── analyze_results.py      ← Runs analysis notebook headlessly
│
├── 🐍 src/workload/            ← The experiment workload
│   ├── workload_job.py         ← CPU-bound Dagster job (SHA-256)
│   ├── Dockerfile              ← Container for K8s deployment
│   └── dagster.yaml            ← Dagster instance config
│
├── 📊 data/
│   ├── raw/                    ← Experiment output (exp1, exp2, exp3)
│   └── processed/              ← Aggregated summaries (CSV)
│
├── 📄 docs/                    ← LaTeX thesis source
│   └── chapters/
│       ├── 01-introduction/
│       ├── 02-literature-review/
│       ├── 03-method/
│       ├── 04-results/         ← Filled after experiments
│       ├── 05-discussion/
│       └── 06-conclusions/
│
├── 🗂 project/
│   ├── config/labels.json      ← GitHub label definitions
│   ├── scripts/labels.sh       ← Sync labels → GitHub
│   ├── scripts/issues.sh       ← Sync issues → GitHub
│   └── issues/                 ← THESIS-001 … THESIS-012
│
└── CLAUDE.md                ← Full project context for AI agents
├── PLAN.md                  ← Thesis execution plan (read first)
├── LIA1-report/             ← Internship report (context)
```

---

## Experiments

| Experiment | Environment | Concurrency Levels | Reps | Answers |
|---|---|---|---|---|
| **Exp 1** — VM Degradation | VM only | L1 (1) → L6 (10) | 3 | SQ1 |
| **Exp 2A** — K8s Isolation | K8s only | L1 (1) → L6 (10) | 3 | SQ2 |
| **Exp 2B** — Blast Radius | VM + K8s | L4 (5) | 3 each | SQ2 |
| **Exp 2C** — Spike | K8s only | L6 (10) | 3 | SQ2, SQ3 |
| **Exp 3** — Crossover | Both | L1–L6 | — | SQ3, SQ4 |

### Concurrency levels

| Level | Concurrent Jobs | Rationale |
|---|---|---|
| L1 | 1 | Pure baseline |
| L2 | 2 | Minimal contention |
| L3 | 3 | 75 % of 4 vCPUs |
| L4 | 5 | Over-subscription begins |
| L5 | 7 | Heavy over-subscription |
| L6 | 10 | Extreme — exceeds all cores |

---

## Infrastructure

| Component | Spec |
|---|---|
| VM | Multipass · Ubuntu 22.04 · 4 vCPU · 8 GB RAM |
| Kubernetes | Kind (local) · same host · matched resource limits |
| Orchestrator | Dagster 1.12.7 |
| VM executor | `ProcessExecutor` |
| K8s executor | `K8sRunLauncher` |
| Database | PostgreSQL 16 |
| Workload | 30-second CPU-bound SHA-256 hashing job |

---

## Notebooks

| Notebook | Purpose |
|---|---|
| [`notebooks/setup-guide.ipynb`](notebooks/setup-guide.ipynb) | Interactive step-by-step environment setup — VM, Kind, Dagster, smoke tests |
| [`notebooks/analysis.ipynb`](notebooks/analysis.ipynb) | Full interactive analysis: SQ1–SQ4 tables, degradation curves, crossover plot, p-values |

---

## Makefile Targets

```bash
make pdf            # Build thesis PDF via latexmk
make labels         # Sync GitHub labels from project/config/labels.json
make issues         # Create GitHub issues from project/issues/*.md
make exp1-vm        # Run Experiment 1 on VM
make exp2a-k8s      # Run Experiment 2A on K8s
make exp2b-blast    # Run Experiment 2B (blast radius, both envs)
make exp2c-spike    # Run Experiment 2C (spike, K8s)
make experiments    # Run all experiments in sequence
make dry-run        # Preview experiment runs without executing
make analyze        # Generate summary tables and plots
make copy-figures   # Copy results/*.png → docs/figures/
make clean          # Remove LaTeX build artifacts
```

---

## Tickets

| Ticket | Title | Points | Status |
|---|---|---|---|
| [THESIS-001](project/issues/01_setup_vm.md) | VM Setup | 3 | ⬜ |
| [THESIS-002](project/issues/02_kind_cluster.md) | Kind Setup | 3 | ⬜ |
| [THESIS-003](project/issues/03_workload.md) | Workload | 2 | ⬜ |
| [THESIS-004](project/issues/04_data_collection.md) | Data Collection Scripts | 3 | ⬜ |
| [THESIS-005](project/issues/05_runner.md) | Master Runner | 2 | ⬜ |
| [THESIS-006](project/issues/06_vm_experiment.md) | Run Exp1 (VM) | 5 | ⬜ |
| [THESIS-007](project/issues/07_k8s_isolation.md) | Run Exp2A (K8s) | 5 | ⬜ |
| [THESIS-008](project/issues/08_blast_radius.md) | Run Exp2B (Blast Radius) | 3 | ⬜ |
| [THESIS-009](project/issues/09_spike.md) | Run Exp2C (Spike) | 2 | ⬜ |
| [THESIS-010](project/issues/10_analysis.md) | Analysis | 5 | ⬜ |
| [THESIS-011](project/issues/11_results.md) | Write Results | 5 | ⬜ |
| [THESIS-012](project/issues/12_discussion.md) | Write Discussion + Conclusions | 5 | ⬜ |
| **Total** | | **43** | |

---

## Contributing

Contributions are welcome! This is an open research project.

- 🐛 **Found a bug?** [Open a bug report](https://github.com/sirajwahaj/thesis/issues/new?template=bug-report.yml)
- 💡 **Have a suggestion?** [Open a suggestion](https://github.com/sirajwahaj/thesis/issues/new?template=suggestion.yml)
- 🔧 **Want to contribute code?** Read [CONTRIBUTING.md](CONTRIBUTING.md) first

---

## AI Agent Context

See [`PLAN.md`](PLAN.md) for the strategic execution plan, timeline, and scope. See [`CLAUDE.md`](CLAUDE.md) for directory structure, conventions, and technical reference.

---

<div align="center">
<sub>Released under the <a href="LICENSE">MIT License</a> · <a href="CODE_OF_CONDUCT.md">Code of Conduct</a></sub>
</div>
