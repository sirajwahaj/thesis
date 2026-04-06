# CLAUDE.md — AI Agent Workspace Guide

## Project Overview

**Title:** *When Does Kubernetes Become Worth It?*
**Type:** Master's thesis — empirical quantitative experiment
**Goal:** Measure reliability, stability, and performance when migrating a Dagster workflow orchestration system from a single-VM process executor to a Kubernetes Run Launcher, and identify the exact crossover point.

## Research Questions

- **Main RQ:** How do reliability, system stability, and execution performance change when a workflow orchestration system is migrated from a single-VM process executor to a Kubernetes Run Launcher under increasing concurrent workload, and at what specific workload level does this migration become net beneficial?
- **SQ1:** At what concurrency level does a single-VM deployment fail, and how do metrics degrade?
- **SQ2:** To what degree does Kubernetes pod isolation contain failures compared to the VM?
- **SQ3:** What scheduling latency and overhead does Kubernetes introduce?
- **SQ4:** At what concurrency level does Kubernetes overhead become smaller than VM contention — the crossover point?

## Logical Chain

```
SQ1 (What breaks on the VM?)
  → SQ2 (Does Kubernetes fix it?)
    → SQ3 (What does Kubernetes cost?)
      → SQ4 (Where do the lines cross?)
```

## Repository Structure

```
thesis/
├── CLAUDE.md                  ← You are here
├── Makefile                   ← Build PDF, sync labels/issues, run experiments
├── README.md                  ← Project overview
│
├── docs/                      ← LaTeX thesis source
│   ├── main.tex               ← Root document
│   ├── references.bib
│   ├── frontmatter/           ← Title page, abstract
│   ├── chapters/
│   │   ├── 01-introduction/   ← Background, RQs, hypothesis
│   │   ├── 02-literature-review/
│   │   ├── 03-method/         ← Experiment design, metrics, tools
│   │   ├── 04-results/        ← exp1, exp2, exp3 results (TODO: fill with data)
│   │   ├── 05-discussion/     ← SQ1–SQ4 answers, limitations
│   │   └── 06-conclusions/    ← Answer, recommendations, future work
│   ├── backmatter/
│   ├── figures/               ← Generated plots copied here for LaTeX
│   └── notes/
│
├── src/                       ← Source code
│   └── workload/              ← Dagster workload job + Dockerfile
│       ├── workload_job.py    ← CPU-bound SHA-256 hashing job
│       ├── Dockerfile         ← Container image for K8s runs
│       └── dagster.yaml       ← Dagster instance config
│
├── scripts/                   ← Experiment orchestration and data collection
│   ├── run_experiment.sh      ← Master experiment runner
│   ├── trigger_dagster_runs.py
│   ├── collect_vm_metrics.py
│   ├── collect_k8s_metrics.sh
│   ├── collect_pod_timing.py
│   ├── export_dagster_runs.py
│   ├── blast_radius_vm.sh
│   ├── blast_radius_k8s.sh
│   └── analyze_results.py     ← Generates summary tables + plots
│
├── data/                      ← Experiment output data
│   ├── raw/                   ← Raw CSVs from experiments
│   │   ├── exp1-vm-degradation/
│   │   │   └── L1/ ... L6/   ← Each has run1/, run2/, run3/
│   │   ├── exp2-kubernetes-isolation/
│   │   │   ├── part-a/
│   │   │   ├── part-b-blast-radius/
│   │   │   └── part-c-spike/
│   │   └── exp3-overhead-crossover/
│   │       └── analysis/
│   └── processed/             ← Aggregated summaries, final CSVs
│
├── results/                   ← Generated plots and figures
│
├── project/                   ← Project management
│   ├── config/
│   │   └── labels.json        ← GitHub label definitions (single source of truth)
│   ├── scripts/
│   │   ├── labels.sh          ← Syncs labels from labels.json to GitHub
│   │   └── issues.sh          ← Creates GitHub issues from markdown
│   └── issues/                ← Issue markdown files (THESIS-001 to THESIS-012)
│
├── tests/                     ← Unit tests
│
└── .github/
    ├── ISSUE_TEMPLATE/
    │   └── thesis-ticket.yml
    └── workflows/             ← CI workflows (if any)
```

## Experiment Design

### Concurrency Levels

| Level | Concurrent Jobs | Rationale |
|-------|----------------|-----------|
| L1    | 1              | Pure baseline, no contention |
| L2    | 2              | Minimal contention |
| L3    | 3              | Moderate (75% of 4 vCPUs) |
| L4    | 5              | Over-subscription begins |
| L5    | 7              | Heavy over-subscription |
| L6    | 10             | Extreme — exceeds all cores |

### Experiments

| Experiment | What it tests | Env | Levels | Reps |
|-----------|--------------|-----|--------|------|
| Exp1 — VM degradation | VM failure threshold | VM | L1–L6 | 3 |
| Exp2A — K8s isolation | Pod isolation | K8s | L1–L6 | 3 |
| Exp2B — Blast radius | Failure containment | Both | L4 | 3 |
| Exp2C — Spike | Scheduling under spike | K8s | L6 | 3 |
| Exp3 — Crossover | Net comparison | Both | L1–L6 | Uses Exp1+Exp2A |

### Key Metrics (12 total)

1. Job success rate (%)
2. Mean execution time (s)
3. Execution time variance / std dev (s)
4. CPU utilisation (%)
5. Memory utilisation (MB)
6. MTTR — mean time to recovery (s)
7. Blast radius — jobs affected by one failure
8. Pod scheduling latency (s) — K8s only
9. Container startup time (s) — K8s only
10. Process count
11. Throughput (hash iterations)
12. Net execution time delta (VM − K8s)

## Infrastructure

- **VM:** Multipass Ubuntu 22.04 — 4 vCPU, 8 GB RAM
- **K8s:** Kind cluster on same host — matched resource limits
- **Orchestrator:** Dagster 1.12.7
  - VM: `ProcessExecutor`
  - K8s: `K8sRunLauncher`
- **Database:** PostgreSQL 16
- **Python:** 3.12
- **Workload:** CPU-bound SHA-256 hashing, 30 seconds per job

## Conventions

- **Data files:** CSV for time-series and tabular data, JSON for metadata
- **Scripts:** Bash for orchestration, Python for data collection and analysis
- **LaTeX:** One .tex file per section, `\input{}` from chapter hub files
- **Issues:** Markdown in `project/issues/`, synced to GitHub via `make issues`
- **Labels:** Defined in `project/config/labels.json`, synced via `make labels`
- **Figures:** Generated in `results/`, copied to `docs/figures/` by `make copy-figures`

## Common Commands

```bash
make pdf              # Build thesis PDF
make labels           # Sync GitHub labels from labels.json
make issues           # Create GitHub issues from markdown files
make experiments      # Run all experiments
make clean            # Clean LaTeX build artifacts
```

## Tickets (THESIS-001 to THESIS-012)

| Ticket | Title | Points | Status |
|--------|-------|--------|--------|
| THESIS-001 | VM Setup | 3 | Not started |
| THESIS-002 | Kind Setup | 3 | Not started |
| THESIS-003 | Workload | 2 | Not started |
| THESIS-004 | Data Collection Scripts | 3 | Not started |
| THESIS-005 | Master Runner | 2 | Not started |
| THESIS-006 | Run Exp1 (VM) | 5 | Not started |
| THESIS-007 | Run Exp2A (K8s) | 5 | Not started |
| THESIS-008 | Run Exp2B (Blast Radius) | 3 | Not started |
| THESIS-009 | Run Exp2C (Spike) | 2 | Not started |
| THESIS-010 | Analysis | 5 | Not started |
| THESIS-011 | Write Results | 5 | Not started |
| THESIS-012 | Write Discussion + Conclusions | 5 | Not started |
| **Total** | | **43** | |

## For AI Agents

- Read this file first to understand the project.
- The thesis documents are in `docs/chapters/`. Each chapter has a hub `chapter.tex` that `\input{}`s section files.
- Experiment scripts live in `scripts/`. Project management scripts live in `project/scripts/`.
- Data goes into `data/raw/` organized by experiment → level → run.
- Processed summaries go into `data/processed/`.
- Generated figures go into `results/` and are copied to `docs/figures/` for LaTeX.
- The workload source code is in `src/workload/`.
- Issue definitions are in `project/issues/` — one file per ticket.
- Label definitions are in `project/config/labels.json` — single source of truth.
