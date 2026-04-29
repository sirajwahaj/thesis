# Thesis Repository — AI Agent Instructions

**This file is auto-loaded by GitHub Copilot for every conversation in this repo.**
For full detail read [CLAUDE.md](../CLAUDE.md) and [docs/architecture.md](../docs/architecture.md).

---

## What This Repo Is

YH thesis: *"When Does Kubernetes Become Worth It?"* — an empirical benchmarking experiment comparing Dagster workflow execution on a single VM (DockerRunLauncher) vs Kubernetes (K8sRunLauncher) under increasing concurrent load. The goal is to find the **crossover point** where K8s becomes net beneficial.

**Author:** Sirajulhaq Wahaj | **Deadline:** 2026-05-24 | **Supervisor:** Ludvig Malm

---

## Research Questions (LOCKED — Do Not Change)

**RQ:** How do reliability, system stability, and execution performance change when a Dagster workflow orchestration system is migrated from a single-VM Docker executor to a Kubernetes Run Launcher under increasing concurrent workload, and at what specific workload level does this migration become net beneficial?

| | Question | Answered by |
|-|----------|-------------|
| **SQ1** | At what concurrency level do Docker containers on a single VM degrade in reliability and performance, and how do success rate, execution time variance, and resource utilisation degrade? | Exp 1 |
| **SQ2** | To what degree does Kubernetes pod isolation contain failures and reduce variance compared to VM under equivalent load? | Exp 2A/B |
| **SQ3** | What measurable scheduling latency and execution overhead does Kubernetes introduce per concurrency level? | Exp 2A/C |
| **SQ4** | At what concurrency level does K8s overhead become smaller than VM contention-induced degradation — the crossover point? | Exp 3 (derived) |

### Logical chain

SQ1 (VM degrades at level X) + SQ2 (K8s isolates failures) + SQ3 (K8s overhead Y) → SQ4 (crossover at level Z) → RQ answered

---

## Metric Definitions (12 Metrics — Do Not Redefine)

| # | Metric | Definition | Answers |
|---|--------|-----------|---------|
| 1 | Job success rate | % of runs completing without error | SQ1, SQ2 |
| 2 | Mean execution time | End-to-end time per run (seconds) | SQ1–SQ3 |
| 3 | Execution time variance | Std deviation of execution time | SQ1, SQ2 |
| 4 | CPU utilisation | Per-job CPU % | SQ1, SQ2 |
| 5 | Memory utilisation | Per-job memory % | SQ1, SQ2 |
| 6 | Failure blast radius | Does one failure affect other concurrent jobs? (binary) | SQ2 |
| 7 | Pod scheduling latency | Submission → pod Running state (s, K8s only) | SQ3 |
| 8 | Container startup time | Pod Running → job executing (s, K8s only) | SQ3 |
| 9 | Net execution time Δ | VM vs K8s time difference per job per level | SQ3, SQ4 |
| 10 | Reliability crossover | Level where VM success rate drops below 95% | SQ4 |
| 11 | Performance crossover | Level where K8s total time < VM total time | SQ4 |

**Crossover point** = both conditions met simultaneously (reliability + performance).

---

## Experiment Design (Do Not Change Workload or Levels)

**Concurrency levels:** L1=1, L2=2, L3=3, L4=5, L5=7, L6=10 concurrent jobs  
**Repetitions:** 3 per level  
**Workload:** CPU-bound SHA-256 hashing, `WORKLOAD_DURATION_SECONDS=30` — do not change  

| Experiment | What it tests | Env | Levels |
|-----------|--------------|-----|--------|
| Exp1 | VM degradation (SQ1) | VM | L1–L6 |
| Exp2A | K8s isolation comparison (SQ2) | K8s | L1–L6 |
| Exp2B | Blast radius — failure containment (SQ2) | Both | L4 |
| Exp2C | Scheduling under extreme load (SQ3) | K8s | L6 |
| Exp3 | Crossover synthesis (SQ4) — **no new runs, derived from Exp1+2A** | Both | — |

---

## Technology Stack (No Substitutions)

| Concern | Tool | Notes |
|---------|------|-------|
| Python | 3.13+ | `requires-python = ">=3.13"` |
| Package manager | `uv` only | No pip install directly — use `uv add` or pyproject.toml |
| Orchestration | Dagster 1.12.22 | Do not upgrade mid-experiment |
| VM hypervisor | UTM (macOS) / VirtualBox (Windows) | See docs/setup.md |
| VM provisioner | Ansible | `ansible/playbooks/provision-vm.yml` |
| Container runtime | podman (macOS local) / Docker Desktop (Windows) | Compose via podman-compose |
| Kubernetes | Kind single-node cluster named `thesis` | No autoscaling, no multi-node |
| K8s executor | K8sRunLauncher (Helm chart `k8s/helm/dagster-thesis`) | |
| VM executor | DockerRunLauncher (Docker CE on VM) | |
| Database | PostgreSQL 16 | Bitnami chart on K8s; PGDG on VM |
| Load test (optional) | k6 | Complement only — not primary |
| Analysis | Pandas, Matplotlib, SciPy | In `notebooks/analysis.ipynb` |

---

## Data Flow Pipeline (Must Stay Intact)

```
scripts/run_experiment.sh
  └─ data/raw/exp{N}/{env}/L{level}/run{rep}/
       ├── dagster_runs.csv
       ├── pod_timing.csv (K8s only)
       └── metadata.json
  ↓
make analyze  (scripts/analyze_results.py → notebooks/analysis.ipynb)
  └─ data/processed/*.csv
  └─ results/*.png
  ↓
make copy-figures  (results/*.png → docs/figures/)
  ↓
make pdf  (docs/main.tex → docs/thesis.pdf)
```

Changes to any stage must propagate to all stages downstream.

---

## Infrastructure

| Component | Spec |
|-----------|------|
| VM (primary) | UTM (macOS) or VirtualBox (Windows) · Ubuntu 22.04 · 4 vCPU · 8 GB RAM |
| VM (alternative) | Multipass — see docs/multipass-alternative.md |
| K8s | Kind single-node · same host · matched resource limits |
| Orchestrator | Dagster 1.12.22 |
| VM executor | DockerRunLauncher (Docker CE on VM) |
| K8s executor | K8sRunLauncher (via Helm) |
| Database | PostgreSQL 16 |
| Python | 3.13+ |
| Workload | CPU-bound SHA-256 hashing, ~30 seconds per job |

---

## Rules for AI Agents

### Always do
- Read `CLAUDE.md` before making structural changes — it is the authoritative reference
- Propagate changes across all affected layers: code → data → notebooks → LaTeX
- Keep `analysis.ipynb` as the **single source of truth** for all analysis
- Align every change with SQ1–SQ4 — if a change does not serve a question, don't make it
- Use existing files; prefer editing over creating new files

### Never do
- Change the research questions (RQ, SQ1–SQ4) or metric definitions
- Change the workload (duration, algorithm, job structure)
- Change concurrency levels (L1–L6: 1, 2, 3, 5, 7, 10) or repetition count (3)
- Introduce tools not in the stack without updating CLAUDE.md and getting approval
- Create duplicate implementations of existing scripts
- Commit raw experiment data (`data/raw/`) or personal paths/credentials
- Add Terraform, minikube, Helm repos outside of `k8s/helm/dagster-thesis/`
- Make isolated file edits — always consider system-wide impact

### Before changing infrastructure
- Check `scripts/validate-experiment-setup.sh` — it's the canonical pre-flight check
- Check `ansible/playbooks/provision-vm.yml` for VM provisioning — don't bypass Ansible
- Check `k8s/helm/dagster-thesis/values.yaml` for K8s config — don't apply raw manifests

---

## Key File Locations

| What | Where |
|------|-------|
| Thesis source | `docs/chapters/` — **canonical** |
| Metric definitions | `docs/chapters/03-method/metrics.tex` |
| Experiment protocols | `docs/chapters/03-method/experiments.tex` |
| Analysis (single source) | `notebooks/analysis.ipynb` |
| Workload job | `src/workload/workload_job.py` |
| Infrastructure config | `infrastructure/docker-compose.yml` |
| VM provisioning | `ansible/playbooks/provision-vm.yml` |
| K8s chart | `k8s/helm/dagster-thesis/` |
| Bootstrap (macOS) | `scripts/bootstrap.sh` |
| Bootstrap (Windows) | `scripts/bootstrap.ps1` |
| Experiment runner | `scripts/run_experiment.sh` |
| Pre-flight validation | `scripts/validate-experiment-setup.sh` |

---

## One-Command Workflows

```bash
make all              # Full pipeline: bootstrap → provision → k8s-setup → experiments → analyze
make bootstrap        # Install deps, create VM (macOS/Windows auto-detected)
make vm-provision     # Ansible: Python 3.13, Dagster, PostgreSQL on VM
make k8s-setup        # Kind cluster + Metrics Server + Dagster Helm
make validate-setup   # Pre-flight: check VM + K8s + local compose
make experiments      # Run all 4 experiments
make analyze          # notebooks/analysis.ipynb → results/*.png
make pdf              # Build thesis PDF
```
