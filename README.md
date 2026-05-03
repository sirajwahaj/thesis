<div align="center">

# When Does Kubernetes Become Worth It?

**Empirical benchmarking of Dagster workflow reliability and performance: single-VM DockerRunLauncher vs Kubernetes K8sRunLauncher under increasing concurrent load**

[![CI](https://github.com/sirajwahaj/thesis/actions/workflows/ci.yml/badge.svg)](https://github.com/sirajwahaj/thesis/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Dagster](https://img.shields.io/badge/Dagster-1.12.22-purple)](https://dagster.io)
[![Python](https://img.shields.io/badge/Python-3.13-blue)](https://python.org)
[![YH Thesis](https://img.shields.io/badge/YH%20Thesis-JENSEN%20DevOps24M-darkblue)](docs/main.tex)

**Author:** Sirajulhaq Wahaj | **Programme:** DevOps24M, JENSEN Yrkeshögskola | **Supervisor:** Ludvig Malm | **Deadline:** 2026-05-24

</div>

---

## Overview

This thesis answers a question that arises after every Kubernetes migration: **was the added complexity actually worth it?**

The experiment runs the same CPU-bound Dagster workload at six increasing concurrency levels (1, 2, 3, 5, 7, 10 concurrent jobs) on two environments — a single-VM DockerRunLauncher and a Kind-based K8sRunLauncher — and identifies the exact workload level where K8s becomes net beneficial.

This work originates from a 2-year internship (LIA 1 + LIA 2) at Insighta Inc., where the author planned and executed a Dagster migration from VM Docker to Google Kubernetes Engine. See [LIA1-report/](LIA1-report/) for the internship report.

### Key findings

| Finding | Result |
|---------|--------|
| VM reliability degrades at | **L3 — 3 concurrent jobs** (66.7% → below 95% threshold) |
| K8s success rate across all levels | **100%** |
| K8s scheduling overhead (L1 → L6) | **4.3 s → 14.9 s** |
| Crossover point (K8s net beneficial) | **L3 — 3 concurrent jobs** |
| K8s effective time advantage at L6 | **169.8 s per job** |

> The migration becomes net beneficial at **L3 (3 concurrent jobs)**. Above this level, VM contention-induced failures outweigh K8s scheduling overhead.

## Research Question

> *How do reliability, system stability, and execution performance change when a Dagster workflow orchestration system is migrated from a single-VM Docker executor to a Kubernetes Run Launcher under increasing concurrent workload — and at what specific workload level does this migration become **net beneficial**?*

### Supporting Questions

| | Question | Answer |
|---|---|---|
| **SQ1** | At what concurrency level does the VM degrade? | **L3 — 3 concurrent jobs** (66.7% success rate) |
| **SQ2** | Does K8s pod isolation contain failures better? | **Yes — 100% success at all levels** |
| **SQ3** | What scheduling overhead does K8s introduce? | **4.3 s (L1) to 14.9 s (L6)** |
| **SQ4** | Where is the crossover point? | **L3 — both reliability and performance conditions met** |

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
│
├── 📜 docs/                    ← LaTeX thesis source (CANONICAL)
│   ├── main.tex                ← Root LaTeX document
│   ├── references.bib          ← BibTeX bibliography
│   ├── chapters/
│   │   ├── 01-introduction/    ← Background, RQs, hypothesis
│   │   ├── 02-literature-review/
│   │   ├── 03-method/          ← Experiment design, 12 metrics, validity
│   │   ├── 04-results/         ← Real experiment data — Exp 1, 2A/B/C, 3
│   │   ├── 05-discussion/      ← SQ1–SQ4 answers, tradeoffs, limitations
│   │   └── 06-conclusions/     ← Answer to RQ, recommendations
│   └── figures/                ← Plots copied here by make copy-figures
│
├── 📓 notebooks/
│   └── analysis.ipynb          ← Single source of truth — all 12 metrics, SQ1–SQ4
│
├── 🐍 src/workload/            ← Dagster workload job
│   ├── workload_job.py         ← CPU-bound SHA-256 hashing (~30 s/job)
│   ├── Containerfile           ← OCI image for K8s deployment
│   └── dagster.yaml            ← Dagster instance config
│
├── 📋 scripts/                 ← Experiment orchestration
│   ├── bash/run_experiment.sh  ← Master runner (all levels × 3 reps)
│   ├── trigger_dagster_runs.py ← Launch N concurrent runs
│   ├── collect_pod_timing.py   ← Scheduling latency from K8s events
│   ├── export_dagster_runs.py  ← Run records from PostgreSQL
│   └── analyze_results.py      ← Runs analysis.ipynb headlessly
│
├── 📊 data/
│   ├── raw/                    ← Experiment output (read-only after runs)
│   └── processed/              ← Aggregated summaries (from analysis.ipynb)
│
├── 📈 results/                 ← Generated plots (.png)
├── 🏗 infrastructure/          ← Docker Compose (local dev)
├── ⚙️  ansible/                ← VM provisioning playbooks
├── ☸️  k8s/helm/dagster-thesis/ ← Helm chart for K8s deployment
├── 📋 LIA1-report/             ← LIA 1 internship report
├── 📋 LIA1-report/             ← LIA 1 internship report (Swedish)
│
├── 🗂 project/issues/          ← THESIS-001 … THESIS-013 (all resolved)
└── CLAUDE.md                   ← Full project context for AI agents
```

---

## Experiments

| Experiment | Environment | Concurrency Levels | Reps | Answers |
|---|---|---|---|---|
| **Exp 1** — VM Degradation | VM only | L1 (1) → L6 (10) | 3 | SQ1 → VM fails at L3 |
| **Exp 2A** — K8s Isolation | K8s only | L1 (1) → L6 (10) | 3 | SQ2 → 100% success |
| **Exp 2B** — Blast Radius | VM + K8s | L4 (5) | 3 each | SQ2 → K8s isolates failures |
| **Exp 2C** — Spike | K8s only | L6 (10) | 3 | SQ3 → 14.9 s overhead |
| **Exp 3** — Crossover | Both | L1–L6 | — (derived) | SQ4 → crossover at L3 |

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
| VM | Multipass · Ubuntu 22.04 · 4 vCPU · 4 GB RAM |
| Kubernetes | Kind (single-node, local) · 8 GB node RAM |
| Orchestrator | Dagster 1.12.22 |
| VM executor | DockerRunLauncher (Docker CE) · 2 GB per-container limit |
| K8s executor | K8sRunLauncher (Helm) · 2 GiB per-pod limit |
| Database | PostgreSQL 16 |
| Python | 3.13+ |
| Workload | CPU-bound SHA-256 hashing · `WORKLOAD_DURATION_SECONDS=30` |

---

## Notebooks

| Notebook | Purpose |
|---|---|
| [`notebooks/analysis.ipynb`](notebooks/analysis.ipynb) | **Single source of truth** — all 12 metrics, SQ1–SQ4, degradation curves, crossover point, p-values |

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

## Results Summary

### VM (Exp 1) — job success rate degrades from L3

| Level | Jobs | Success Rate | Mean Time (s) |
|-------|------|-------------|---------------|
| L1 | 1 | 100% | 65.3 |
| L2 | 2 | 100% | 70.6 |
| **L3** | **3** | **66.7%** | **70.6** |
| L4 | 5 | 46.7% | 76.6 |
| L5 | 7 | 42.9% | 77.7 |
| L6 | 10 | 30.0% | 79.9 |

### K8s (Exp 2A) — 100% success rate at all levels

| Level | Jobs | Success Rate | Exec Time (s) | Scheduling Overhead (s) |
|-------|------|-------------|--------------|-------------------------|
| L1 | 1 | 100% | 63.4 | 4.3 |
| L2 | 2 | 100% | 63.9 | 4.6 |
| L3 | 3 | 100% | 64.7 | 5.1 |
| L4 | 5 | 100% | 68.7 | 6.8 |
| L5 | 7 | 100% | 80.6 | 11.6 |
| L6 | 10 | 100% | 81.6 | 14.9 |

### Crossover (Exp 3)

| Level | VM Success | K8s Success | Net Beneficial |
|-------|-----------|------------|----------------|
| L1 | 100% | 100% | No |
| L2 | 100% | 100% | No |
| **L3** | **66.7%** | **100%** | **Yes ← crossover** |
| L4 | 46.7% | 100% | Yes |
| L5 | 42.9% | 100% | Yes |
| L6 | 30.0% | 100% | Yes |

---

## Tickets (all resolved)

| Ticket | Title | Points | Status |
|--------|-------|--------|--------|
| [THESIS-001](project/issues/01_setup_vm.md) | VM Setup | 3 | ✅ |
| [THESIS-002](project/issues/02_kind_cluster.md) | Kind Setup | 3 | ✅ |
| [THESIS-003](project/issues/03_workload.md) | Workload Implementation | 2 | ✅ |
| [THESIS-004](project/issues/04_data_collection.md) | Data Collection Scripts | 3 | ✅ |
| [THESIS-005](project/issues/05_runner.md) | Master Runner | 2 | ✅ |
| [THESIS-006](project/issues/06_vm_experiment.md) | Run Exp 1 (VM) | 5 | ✅ |
| [THESIS-007](project/issues/07_k8s_isolation.md) | Run Exp 2A (K8s) | 5 | ✅ |
| [THESIS-008](project/issues/08_blast_radius.md) | Run Exp 2B (Blast Radius) | 3 | ✅ |
| [THESIS-009](project/issues/09_spike.md) | Run Exp 2C (Spike) | 2 | ✅ |
| [THESIS-010](project/issues/10_analysis.md) | Analysis | 5 | ✅ |
| [THESIS-011](project/issues/11_results.md) | Write Results | 5 | ✅ |
| [THESIS-012](project/issues/12_discussion.md) | Write Discussion + Conclusions | 5 | ✅ |
| [THESIS-013](project/issues/) | Final Polish & Submission | 3 | ✅ |
| **Total** | | **46** | **All done** |

---

## Contributing

Contributions are welcome! This is an open research project.

- 🐛 **Found a bug?** [Open a bug report](https://github.com/sirajwahaj/thesis/issues/new?template=bug-report.yml)
- 💡 **Have a suggestion?** [Open a suggestion](https://github.com/sirajwahaj/thesis/issues/new?template=suggestion.yml)
- 🔧 **Want to contribute code?** Read [CONTRIBUTING.md](CONTRIBUTING.md) first

---

## Internship Reports

| Report | Period | Description |
|--------|--------|-------------|
| [LIA1-report/](LIA1-report/) | 2025 | LIA 1 at Insighta Inc. — initial K8s migration planning |
| [LIA1-report/](LIA1-report/) | 2025 | LIA 1 internship report — production DevOps context for this thesis |

---

## AI Agent Context

- [`CLAUDE.md`](CLAUDE.md) — directory structure, conventions, agent rules
- [`PLAN.md`](PLAN.md) — strategic execution plan and timeline
- [`.github/copilot-instructions.md`](.github/copilot-instructions.md) — Copilot-specific context

---

<div align="center">
<sub>
Released under the <a href="LICENSE">MIT License</a> ·
<a href="CODE_OF_CONDUCT.md">Code of Conduct</a> ·
JENSEN Yrkeshögskola DevOps24M · 2026
</sub>
</div>
