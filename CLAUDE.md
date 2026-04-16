# CLAUDE.md — AI Agent Workspace Guide

> Read `PLAN.md` first for strategy, scope, and timeline.
> This file covers technical conventions and directory structure.

## Project Overview

| Field | Value |
|---|---|
| **Title** | When Does Kubernetes Become Worth It? |
| **Type** | YH thesis — empirical quantitative experiment |
| **Author** | Sirajulhaq Wahaj |
| **Programme** | DevOps24M — JENSEN Yrkeshögskola |
| **Supervisor** | Ludvig Malm |
| **Deadline** | 2026-05-24 |
| **Goal** | Measure reliability, stability, and performance when migrating Dagster from a single-VM Docker executor to a Kubernetes Run Launcher, and identify the crossover point |

## Research Questions (Do Not Change)

- **RQ:** How do reliability, system stability, and execution performance change when a Dagster workflow orchestration system is migrated from a single-VM Docker executor to a Kubernetes Run Launcher under increasing concurrent workload, and at what specific workload level does this migration become net beneficial?
- **SQ1:** At what concurrency level does a single-VM deployment start to degrade?
- **SQ2:** Does Kubernetes pod isolation contain failures better than VM process execution?
- **SQ3:** What scheduling and startup overhead does Kubernetes introduce?
- **SQ4:** At what concurrency level does K8s overhead become smaller than VM contention — the crossover point?

### Logical Chain

```
SQ1 (VM breaks at level X)
  + SQ2 (K8s isolates failures)
  + SQ3 (K8s has overhead Y)
  = SQ4 (crossover at level Z) → RQ answered
```

## Repository Structure

```
thesis/
├── PLAN.md                    ← Strategic plan — read first
├── CLAUDE.md                  ← You are here — technical reference
├── Makefile                   ← Build PDF, sync labels/issues, run experiments
├── README.md                  ← Project overview
│
├── docs/                      ← LaTeX thesis source (CANONICAL — supersedes proposal/)
│   ├── main.tex               ← Root document
│   ├── references.bib         ← All references (9 papers)
│   ├── frontmatter/           ← Title page, abstract
│   ├── chapters/
│   │   ├── 01-introduction/   ← Background (incl. internship), RQs, hypothesis
│   │   ├── 02-literature-review/  ← 3 pillars + positioning
│   │   ├── 03-method/         ← Experiment design, metrics, tools, validity
│   │   ├── 04-results/        ← exp1, exp2, exp3 (TODO: fill with data)
│   │   ├── 05-discussion/     ← SQ1–SQ4 answers, tradeoff, limitations
│   │   └── 06-conclusions/    ← Answer, recommendations, future work
│   ├── backmatter/appendices.tex
│   ├── figures/               ← Generated plots copied here for LaTeX
│   └── notes/
│
├── src/workload/              ← Dagster workload job + Dockerfile
│   ├── workload_job.py        ← CPU-bound SHA-256 hashing job (~30s)
│   ├── Dockerfile             ← Container image for K8s runs
│   └── dagster.yaml           ← Dagster instance config
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
│   └── analyze_results.py     ← Runs notebooks/analysis.ipynb headlessly
│
├── notebooks/
│   ├── analysis.ipynb         ← Single source of truth for all analysis (SQ1–SQ4)
│   └── setup-guide.ipynb      ← Step-by-step environment setup
│
├── data/
│   ├── raw/                   ← Experiment output (exp1, exp2, exp3)
│   └── processed/             ← Aggregated summaries (CSV)
│
├── results/                   ← Generated plots (PNG)
│
├── project/
│   ├── config/labels.json     ← GitHub label definitions
│   ├── scripts/labels.sh      ← Sync labels → GitHub
│   ├── scripts/issues.sh      ← Create/update GitHub issues from markdown
│   └── issues/                ← THESIS-001 … THESIS-012
│
├── proposal/                  ← STALE — original expanded proposal. Thesis docs are canonical.
├── LIA1-report/               ← Internship report (Swedish). Context for thesis background.
├── litreture-review/          ← Literature synthesis, supervisor feedback, PDFs
├── thesis-instruction-yh/     ← Jensen YH exam instructions and grading criteria
│
└── .github/
    ├── PULL_REQUEST_TEMPLATE.md
    ├── ISSUE_TEMPLATE/
    └── workflows/ci.yml       ← Lint Python, validate JSON, check shell, validate notebooks
```

## Experiment Design

### Concurrency Levels

| Level | Concurrent Jobs | Rationale |
|-------|----------------|-----------|
| L1    | 1              | Pure baseline, no contention |
| L2    | 2              | Minimal contention |
| L3    | 3              | 75% of 4 vCPUs — near saturation |
| L4    | 5              | Over-subscription begins |
| L5    | 7              | Heavy over-subscription |
| L6    | 10             | Extreme — 2.5× available cores |

### Experiments

| Experiment | What it tests | Env | Levels | Reps |
|-----------|--------------|-----|--------|------|
| Exp1 — VM degradation | VM failure threshold | VM | L1–L6 | 3 |
| Exp2A — K8s isolation | Pod isolation comparison | K8s | L1–L6 | 3 |
| Exp2B — Blast radius | Failure containment | Both | L4 | 3 |
| Exp2C — Spike | Scheduling under extreme load | K8s | L6 | 3 |
| Exp3 — Crossover | Synthesis (no new runs) | Both | L1–L6 | Uses Exp1+2A |

### Key Metrics (12)

1. Job success rate (%)
2. Mean execution time (s)
3. Std dev of execution time (s)
4. CPU utilisation (%)
5. Memory utilisation (%)
6. Pod scheduling latency (s) — K8s only
7. Container startup latency (s) — K8s only
8. Total overhead (s) — K8s only
9. Failure containment (binary) — blast radius
10. Neighbouring job impact (s) — blast radius
11. Net benefit flag (derived)
12. Crossover level (derived)

## Infrastructure

| Component | Spec |
|-----------|------|
| VM (primary) | UTM (macOS) or VirtualBox (Windows) · Ubuntu 22.04 · 4 vCPU · 8 GB RAM |
| VM (alternative) | Multipass — see `docs/multipass-alternative.md` |
| K8s | Kind (single-node, local) · same host · matched resource limits |
| Orchestrator | Dagster 1.12.7 |
| VM executor | DockerRunLauncher (Docker CE on VM) |
| K8s executor | K8sRunLauncher (via Helm) |
| Database | PostgreSQL 16 |
| Python | 3.12 |
| Workload | CPU-bound SHA-256 hashing, ~30 seconds per job |

## Conventions

- **Data files:** CSV for time-series and tabular data, JSON for metadata
- **Scripts:** Bash for orchestration, Python for data collection and analysis
- **LaTeX:** One .tex file per section, `\input{}` from chapter hub files
- **Issues:** Markdown in `project/issues/`, synced to GitHub via `make issues`
- **Labels:** Defined in `project/config/labels.json`, synced via `make labels`
- **Figures:** Generated in `results/`, copied to `docs/figures/` by `make copy-figures`
- **Analysis:** `notebooks/analysis.ipynb` is the single source of truth; `scripts/analyze_results.py` runs it headlessly

## Common Commands

```bash
# ── One-command full setup ──
make all              # Bootstrap → VM provision → K8s → experiments → analyze

# ── Bootstrap / Environment Setup ──
make bootstrap        # Detect OS, install deps (Homebrew/Chocolatey), create VM
make vm-provision     # Provision VM via Ansible (Python 3.12, Dagster, PostgreSQL)
make vm-validate      # Verify VM is ready for experiments
make k8s-create       # Create Kind cluster 'thesis'
make k8s-metrics      # Deploy Metrics Server (kubectl top support)
make k8s-deploy-dagster # Deploy Dagster + workload via Helm
make k8s-setup        # Full K8s setup (create + metrics + deploy, in sequence)
make k8s-validate     # Verify K8s setup is ready
make k8s-destroy      # Delete Kind cluster (destructive)
make validate-setup   # Validate VM + K8s + local compose are all ready

# ── Experiments ──
make exp1-vm          # Run Experiment 1 (VM degradation)
make exp2a-k8s        # Run Experiment 2A (K8s isolation)
make exp2b-blast      # Run Experiment 2B (Blast radius)
make exp2c-spike      # Run Experiment 2C (Spike)
make experiments      # Run all experiments in sequence
make dry-run          # Preview experiment runs without execution

# ── Analysis ──
make analyze          # Run analysis notebook headlessly
make copy-figures     # Copy results/*.png → docs/figures/

# ── Compose (local dev) ──
make compose-up       # Start services (postgres, workload, webserver, daemon)
make compose-down     # Stop services
make compose-clean    # Stop + remove volumes

# ── LaTeX + GitHub ──
make pdf              # Build thesis PDF
make clean            # Clean LaTeX build artifacts
make labels           # Sync GitHub labels
make issues           # Create/update GitHub issues from markdown
```

## Infrastructure (Updated April 2026)

The benchmarking environment is now **fully automated** with cross-platform support:

- **Primary VM path:** UTM (macOS) / VirtualBox (Windows) — provisioned by Ansible
- **K8s path:** Kind cluster with Metrics Server + Dagster Helm chart
- **Multipass:** Documented as lightweight alternative in `docs/multipass-alternative.md`

### New Files Added

| Path | Purpose |
|------|---------|
| `scripts/bootstrap.sh` | macOS entry point — detects OS, installs deps |
| `scripts/bootstrap.ps1` | Windows entry point |
| `scripts/setup-macos.sh` | Homebrew + podman machine + UTM |
| `scripts/setup-windows.ps1` | Chocolatey + VirtualBox |
| `scripts/create-vm-macos.sh` | UTM VM creation guide + SSH setup |
| `scripts/create-vm-windows.ps1` | VirtualBox VM creation |
| `scripts/provision-vm.sh` | Generates inventory + runs Ansible playbook |
| `scripts/kind-config.yaml` | Kind cluster configuration |
| `scripts/create-kind-cluster.sh` | Kind cluster creation + local registry |
| `scripts/deploy-metrics-server.sh` | Helm-based Metrics Server |
| `scripts/deploy-dagster-k8s.sh` | Build image + Helm deploy Dagster on K8s |
| `scripts/validate-experiment-setup.sh` | Pre-flight checks for all 3 systems |
| `ansible/playbooks/provision-vm.yml` | VM provisioning (Python, PG, Dagster) |
| `ansible/roles/*/tasks/main.yml` | Ansible roles: python312, postgresql16, dagster, workload |
| `k8s/helm/dagster-thesis/` | Helm chart: Chart.yaml, values.yaml, templates/ |
| `docs/setup.md` | macOS setup guide |
| `docs/setup-windows.md` | Windows setup guide |
| `docs/multipass-alternative.md` | Multipass lightweight alternative |
| `docs/architecture.md` | System architecture + design decisions |

## Tickets

| Ticket | Title | Points | Week |
|--------|-------|--------|------|
| THESIS-001 | VM Setup | 3 | W1 |
| THESIS-002 | Kind Setup | 3 | W1 |
| THESIS-003 | Workload Implementation | 2 | W1 |
| THESIS-004 | Data Collection Scripts | 3 | W1 |
| THESIS-005 | Master Runner | 2 | W1 |
| THESIS-006 | Run Exp1 (VM) | 5 | W2 |
| THESIS-007 | Run Exp2A (K8s) | 5 | W2 |
| THESIS-008 | Run Exp2B (Blast Radius) | 3 | W2 |
| THESIS-009 | Run Exp2C (Spike) | 2 | W2 |
| THESIS-010 | Analysis | 5 | W3 |
| THESIS-011 | Write Results | 5 | W3 |
| THESIS-012 | Write Discussion + Conclusions | 5 | W3–W4 |
| **Total** | | **43** | |

## For AI Agents

1. Read `PLAN.md` first for strategy, scope, and timeline.
2. Read this file for directory structure and conventions.
3. The thesis docs in `docs/chapters/` are **canonical**. The `proposal/main.tex` is stale.
4. Experiment protocols are in `docs/chapters/03-method/experiments.tex`.
5. Analysis logic is in `notebooks/analysis.ipynb`.
6. **Do not change the research questions.** They are locked.
7. Check `data/raw/` for experiment completion status (data files vs `.gitkeep`).
8. Check `docs/chapters/04-results/` for TODO comments to know what's still unwritten.
