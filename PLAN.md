# PLAN.md — Thesis Execution Plan (AI-Readable)

> **Purpose**: Single source of truth for any human or AI agent working on this
> thesis. Read this file first, then `CLAUDE.md` for technical conventions.

---

## 0 · Context

| Field | Value |
|---|---|
| **Author** | Sirajulhaq Wahaj |
| **Programme** | DevOps24M — JENSEN Yrkeshögskola |
| **Thesis title** | When Does Kubernetes Become Worth It? |
| **Subtitle** | Measuring the Reliability–Performance Crossover of Dagster on a Single VM vs Kubernetes |
| **Supervisor** | Ludvig Malm (ludvig.malm@zocom.se) |
| **Course start** | 2026-05-11 |
| **Submission deadline** | 2026-05-24 |
| **Presentation** | Week 23 (early June 2026) |
| **Today** | 2026-04-07 — ~7 weeks before deadline, ~5 weeks before course start |
| **Background** | Author completed a 3-month internship (LIA1, Sep–Dec 2025) at Insighta Inc. building a Dagster data platform on Kubernetes (GKE). This thesis measures the system the author helped build. The internship report is in `LIA1-report/`. |

### What this thesis IS

An **empirical measurement study** of an existing solution under controlled
conditions. The system already exists — the author built it during the
internship. Now the goal is to measure it scientifically and answer: *was the
Kubernetes migration actually worth it, and at what workload level?*

### What this thesis is NOT
- Not building a new system
- Not a Kubernetes benchmark or tool comparison
- Not a cloud provider comparison
- Not a proof that Kubernetes is universally better

---

## 1 · Research Questions (Final — Do Not Change)

### Main Research Question (RQ)

> How do reliability, system stability, and execution performance change when
> a Dagster workflow orchestration system is migrated from a single-VM process
> executor to a Kubernetes Run Launcher under increasing concurrent workload —
> and at what specific workload level does this migration become
> **net beneficial**?

### Supporting Questions

| ID | Question | Method | Experiment |
|----|----------|--------|------------|
| **SQ1** | At what concurrency level does a single-VM Dagster deployment start to degrade in reliability and performance? | Quantitative measurement | Exp 1 |
| **SQ2** | Does Kubernetes pod-level isolation contain individual job failures and prevent cascading degradation better than VM-level process execution? | Quantitative comparison | Exp 2A + 2B |
| **SQ3** | What scheduling and startup overhead does Kubernetes introduce compared to direct process execution, and how does this overhead change with concurrency? | Quantitative measurement | Exp 2A + 2C |
| **SQ4** | At what concurrency level does the isolation and reliability benefit of Kubernetes outweigh its scheduling overhead, making migration net beneficial? | Derived analysis | Exp 3 (synthesis) |

### Logical Chain

```
SQ1 (VM breaks at level X)
  + SQ2 (K8s isolates failures)
  + SQ3 (K8s has overhead Y)
  ─────────────────────────────
  = SQ4 (crossover at level Z)
  = RQ  answered
```

---

## 2 · Scope — What Is In vs Out (4-Week Feasibility)

### IN SCOPE (must deliver)

| # | Deliverable | Effort | Week |
|---|-------------|--------|------|
| 1 | Proposal (ch 1–3 draft) finalized and sent to supervisor | Medium | W1 |
| 2 | VM environment set up (UTM, Ansible, Dagster, Docker CE, PostgreSQL) | Small | W1 |
| 3 | Kind cluster set up (matched resources) | Small | W1 |
| 4 | Workload job implemented + smoke-tested on both envs | Small | W1 |
| 5 | Experiment 1 executed — VM degradation (6 levels × 3 reps) | Medium | W2 |
| 6 | Experiment 2A executed — K8s isolation (6 levels × 3 reps) | Medium | W2 |
| 7 | Experiment 2B executed — Blast radius (VM + K8s at L4 × 3) | Small | W2 |
| 8 | Experiment 2C executed — Spike observation (K8s at L6 × 3) | Small | W2 |
| 9 | Experiment 3 — Crossover analysis (derived from Exp 1 + 2A) | Medium | W3 |
| 10 | Results chapter written (ch 4) | Medium | W3 |
| 11 | Discussion chapter written (ch 5) | Medium | W3–W4 |
| 12 | Conclusions chapter written (ch 6) | Small | W4 |
| 13 | Abstract, final proofreading, PDF submitted | Small | W4 |

### OUT OF SCOPE (→ §6.3 "Future Research")

- Multi-node Kubernetes cluster (this study uses single-node Kind)
- Cloud-managed Kubernetes (GKE, EKS, AKS) comparison
- Horizontal Pod Autoscaler (HPA) dedicated experiments
- Infrastructure reproducibility experiments (CDKTF rebuild testing)
- Non-CPU-bound workloads (I/O, network, memory-intensive)
- Long-running production workloads (days/weeks of observation)
- Cost analysis (dollar cost per job on cloud infrastructure)
- Dagster+ (managed Dagster) comparison
- Other orchestrators (Airflow, Prefect, Argo Workflows)
- NLP/transformer workloads (potential future master's thesis)

---

## 3 · Week-by-Week Plan

### Week 1 (Apr 7 – Apr 13): Proposal + Infrastructure

| Day | Task | Output |
|-----|------|--------|
| Mon | Finalize ch 1 (Introduction): add internship context to background, clean RQs, update delimitations | `docs/chapters/01-introduction/*.tex` |
| Tue | Finalize ch 2 (Literature Review): verify all 3 pillars use real citations, check positioning | `docs/chapters/02-literature-review/*.tex` |
| Wed | Finalize ch 3 (Method): fix tools list, verify experiment protocols, update infrastructure specs | `docs/chapters/03-method/*.tex` |
| Thu | Set up VM (THESIS-001): UTM + Ansible provision, Python 3.13, Dagster 1.12.22, Docker CE, PostgreSQL 16. Verify single job runs as Docker container. | VM ready |
| Fri | Set up Kind (THESIS-002): Kind cluster, metrics-server, Helm Dagster. Match 4 vCPU / 8 GB. | K8s ready |
| Sat | Implement workload job (THESIS-003): CPU-bound SHA-256 hashing, 30s target. Build Docker image. | `src/workload/` |
| Sun | Smoke test both environments. Dry run data collection scripts. Buffer day. | Both envs verified |

**Gate**: Proposal (ch 1–3) sent to supervisor. Both environments passing `make dry-run`.

### Week 2 (Apr 14 – Apr 20): Experiments

| Day | Task | Ticket | Output |
|-----|------|--------|--------|
| Mon | Run Exp 1 — VM degradation: L1→L6, 3 reps each (18 runs) | THESIS-006 | `data/raw/exp1-vm-degradation/` |
| Tue | Run Exp 2A — K8s isolation: L1→L6, 3 reps each (18 runs) | THESIS-007 | `data/raw/exp2-kubernetes-isolation/part-a/` |
| Wed | Run Exp 2B — Blast radius: L4, 3 reps each env (6 runs) | THESIS-008 | `data/raw/exp2-kubernetes-isolation/part-b/` |
| Thu | Run Exp 2C — Spike: K8s at L6, 3 reps (3 runs) | THESIS-009 | `data/raw/exp2-kubernetes-isolation/part-c/` |
| Fri | Re-run any failed experiments. Verify all metadata.json files. Commit raw data. | — | All data populated |
| Sat–Sun | Buffer / early analysis start | — | — |

**Gate**: All `data/raw/` directories populated with real data.

### Week 3 (Apr 21 – Apr 27): Analysis + Results + Discussion Start

| Day | Task | Ticket | Output |
|-----|------|--------|--------|
| Mon | Run `make analyze` → crossover analysis. Review all plots and tables. | THESIS-010 | `data/processed/`, `results/` |
| Tue | Write ch 4 Results — Exp 1 (SQ1: VM degradation tables + curves) | THESIS-011 | `exp1-vm-degradation.tex` |
| Wed | Write ch 4 Results — Exp 2 (SQ2: K8s isolation + blast radius) | THESIS-011 | `exp2-kubernetes-isolation.tex` |
| Thu | Write ch 4 Results — Exp 3 (SQ3 + SQ4: overhead + crossover) | THESIS-011 | `exp3-crossover.tex` |
| Fri | Write ch 5 Discussion — SQ1 + SQ2 sections | THESIS-012 | `sq1-vm-threshold.tex`, `sq2-isolation.tex` |
| Sat–Sun | Write ch 5 Discussion — SQ3 + SQ4 + tradeoff + limitations | THESIS-012 | Remaining `05-discussion/*.tex` |

**Gate**: `make pdf` produces a complete document with filled results and discussion.

### Week 4 (Apr 28 – May 4): Conclusions + Polish + Submit

| Day | Task | Output |
|-----|------|--------|
| Mon | Write ch 6 Conclusions — answer RQ, summary, recommendations, future research | `06-conclusions/*.tex` |
| Tue | Write/revise Abstract. Ensure it reflects actual findings. | `frontmatter/abstract.tex` |
| Wed | Full proofread pass. Cross-check all numbers (tables ↔ plots ↔ text). Fix references. | All `.tex` files |
| Thu | Supervisor feedback round. Address comments. | — |
| Fri | Final `make pdf`. Submit. | **Thesis PDF submitted** |

---

## 4 · Experiment Design (Detailed)

### 4.1 Constants (controlled variables)

| Variable | Value | Why |
|----------|-------|-----|
| VM resources | 4 vCPU, 8 GB RAM (UTM) | Match K8s node |
| K8s node resources | 4 vCPU, 8 GB RAM (Kind) | Match VM |
| Host OS | macOS (shared physical host) | Both envs on same hardware |
| Guest OS | Ubuntu 22.04 | Same on both |
| Dagster version | 1.12.22 | Pinned |
| PostgreSQL version | 16 | Pinned |
| Python version | 3.12 | Pinned |
| Workload | CPU-bound SHA-256, ~30 seconds | Deterministic, CPU-only |
| Repetitions | 3 per level | Statistical minimum |
| Cool-down | 60 seconds between runs | Let system stabilize |

### 4.2 Independent variable

**Concurrency level** — the number of Dagster jobs launched simultaneously:

| Level | Jobs | Rationale |
|-------|------|-----------|
| L1 | 1 | Baseline — no contention |
| L2 | 2 | Minimal contention |
| L3 | 3 | 75% of 4 vCPUs — near saturation |
| L4 | 5 | Over-subscription begins |
| L5 | 7 | Heavy over-subscription |
| L6 | 10 | Extreme — 2.5× available cores |

### 4.3 Dependent variables (metrics)

| # | Metric | Source | Answers |
|---|--------|--------|---------|
| 1 | Success rate (%) | Dagster run status | SQ1, SQ2 |
| 2 | Mean execution time (s) | Dagster run records | SQ1, SQ2, SQ4 |
| 3 | Std dev of execution time | Dagster run records | SQ1, SQ2 |
| 4 | CPU utilization (%) | psutil / kubectl top | SQ1, SQ2 |
| 5 | Memory utilization (%) | psutil / kubectl top | SQ1, SQ2 |
| 6 | Scheduling latency (s) | K8s pod events | SQ3 |
| 7 | Startup latency (s) | K8s pod events | SQ3 |
| 8 | Total overhead (s) | scheduling + startup | SQ3, SQ4 |
| 9 | Failure containment (binary) | Blast radius test | SQ2 |
| 10 | Neighbouring job impact (s) | Blast radius timing | SQ2 |
| 11 | Net benefit flag | derived: isolation gain − overhead cost | SQ4 |
| 12 | Crossover level | first L where net benefit > 0 | SQ4 |

### 4.4 Experiment → SQ mapping

```
Exp 1 (VM only, L1–L6, ×3)
  └─ Measures: success rate, exec time, CPU, memory
  └─ Answers: SQ1

Exp 2A (K8s only, L1–L6, ×3)
  └─ Measures: success rate, exec time, CPU, memory, scheduling overhead
  └─ Answers: SQ2, SQ3

Exp 2B (Blast radius, both envs, L4, ×3)
  └─ Measures: failure containment, neighbouring job impact
  └─ Answers: SQ2

Exp 2C (Spike, K8s only, L6, ×3)
  └─ Measures: scheduling latency under extreme load
  └─ Answers: SQ2, SQ3

Exp 3 (Synthesis — no new runs)
  └─ Compares Exp 1 vs Exp 2A side-by-side
  └─ Derives: net benefit, crossover level
  └─ Answers: SQ3, SQ4 → RQ
```

---

## 5 · How Each Research Question Gets Answered

### SQ1: At what concurrency level does the VM start to degrade?

**Data needed**: Exp 1 results — success rate and mean exec time at each level.

**Analysis**:
1. Build a summary table: level → success rate, mean time, std time.
2. Plot a degradation curve (2-panel: success rate + exec time vs concurrency).
3. Identify the threshold: the first level where success rate drops below 95%
   OR mean exec time increases by >50% from baseline.

**Expected answer format**: "The VM deployment begins to degrade at concurrency
level L_X (Y simultaneous jobs), where the success rate drops to Z% and mean
execution time increases by W%."

### SQ2: Does K8s pod isolation contain failures better?

**Data needed**: Exp 2A results (same metrics as Exp 1, but on K8s) + Exp 2B
blast radius results.

**Analysis**:
1. Compare VM vs K8s summary tables side by side.
2. At the VM's degradation threshold (from SQ1), compare success rates.
3. Analyze blast radius: on VM, does killing one process affect others? On K8s,
   does deleting one pod affect others?
4. Quantify: isolation improvement = K8s success rate − VM success rate at each level.

**Expected answer format**: "Kubernetes pod isolation contains failures
significantly better. At L_X, VM success rate is A% while K8s maintains B%.
Blast radius testing shows that on VM, a killed process causes C neighbouring
failures, while on K8s, a deleted pod causes D neighbouring failures."

### SQ3: What scheduling overhead does K8s introduce?

**Data needed**: Exp 2A pod timing data + Exp 2C spike data.

**Analysis**:
1. Build overhead table: level → mean scheduling latency, startup latency, total overhead.
2. Plot overhead vs concurrency.
3. Compare: at low concurrency (L1–L2), how much slower is K8s? At high
   concurrency (L5–L6)?

**Expected answer format**: "Kubernetes introduces a mean scheduling overhead of
X seconds at L1, growing to Y seconds at L6. This overhead is constant /
logarithmic / linear with concurrency."

### SQ4: Where is the crossover point?

**Data needed**: SQ1 + SQ2 + SQ3 results combined.

**Analysis**:
1. At each level, compute: `net_benefit = (VM_failure_cost − K8s_failure_cost) − K8s_overhead`
2. The crossover is the first level where `net_benefit > 0`.
3. Plot both curves (VM total time vs K8s total time) and mark the intersection.
4. Run Mann-Whitney U test at each level for statistical significance.

**Expected answer format**: "The crossover occurs at concurrency level L_X (Y
simultaneous jobs). Below this level, the VM is faster due to lower overhead.
Above this level, Kubernetes is net beneficial due to its isolation preventing
the cascading failures observed on the VM."

---

## 6 · Proposal = Chapters 1–3

The proposal is chapters 1–3 of the thesis. It must be self-contained and
convince the supervisor that the study is feasible and well-designed.

### Chapter 1 — Introduction

| Section | File | Key Content |
|---------|------|-------------|
| 1.1 Background | `background.tex` | Data platforms growing. Dagster as modern orchestrator. VM vs K8s is a real decision. **Author built this system during a 3-month internship at Insighta** — now wants to measure it empirically. |
| 1.2 Research Problem | `research-problem.tex` | No empirical data for the VM→K8s migration decision for workflow orchestrators. Teams decide based on intuition. |
| 1.3 Purpose | `purpose.tex` | Provide empirical evidence for when Kubernetes becomes worth the complexity for Dagster workloads. |
| 1.4 Core Idea | `core-idea.tex` | Run identical workloads on both environments under increasing load. Measure. Compare. Find the crossover. |
| 1.5 Crossover Point | `crossover-point.tex` | Formal definition: reliability crossover + performance crossover + combined crossover. |
| 1.6 Hypothesis | `hypothesis.tex` | There exists a concurrency level above which K8s isolation benefits outweigh its scheduling overhead. |
| 1.7 Research Questions | `research-questions.tex` | RQ + SQ1–SQ4. Logical chain. |
| 1.8 Practical Value | `practical-value.tex` | Helps teams make evidence-based migration decisions. Connects to author's internship experience. |
| 1.9 Delimitations | `delimitations.tex` | Single node, CPU-bound only, Dagster only, local Kind not cloud. → Future research. |
| 1.10 Thesis Structure | `thesis-structure.tex` | Roadmap of chapters. |

### Chapter 2 — Literature Review

| Section | File | Key Content |
|---------|------|-------------|
| 2.1 Resource Contention | `pillar1-contention.tex` | Nanda et al. (1991), Arora (2023), Casalicchio (2019). Non-linear degradation under shared resources. → SQ1 |
| 2.2 Overhead & Isolation | `pillar2-overhead-isolation.tex` | Choi et al. (2021), Liu et al. (2024), Cilic et al. (2023). Pod overhead + fault isolation. → SQ2, SQ3 |
| 2.3 Autoscaling | `pillar3-autoscaling.tex` | Nguyen et al. (2020), Tran et al. (2022), Yuan & Liao (2024), Li et al. (2025). Context for spike observations. |
| 2.4 Positioning | `positioning.tex` | Gap: no empirical crossover study for workflow orchestrators. This thesis fills it. |

### Chapter 3 — Method

| Section | File | Key Content |
|---------|------|-------------|
| 3.1 Research Design | `research-design.tex` | Quantitative, experimental, controlled comparison. |
| 3.2 Infrastructure | `infrastructure.tex` | VM (UTM + DockerRunLauncher) + K8s (Kind) specs. Why matched resources. Why local-first. |
| 3.3 Tools | `tools.tex` | Dagster, UTM/Ansible, Kind, podman (macOS) / Docker CE (VM), Helm, kubectl, psutil, pandas, matplotlib, scipy. |
| 3.4 Definitions | `definitions.tex` | Formal definitions: concurrency level, reliability, stability, overhead, crossover point. |
| 3.5 Workloads | `workloads.tex` | SHA-256 CPU-bound job. 6 levels (1,2,3,5,7,10). Why deterministic. |
| 3.6 Test Harness | `test-harness.tex` | Python + Dagster GraphQL API. Concurrent submission. Automated CSV export. |
| 3.7 Experiments | `experiments.tex` | Exp 1, 2A, 2B, 2C, 3 — full protocol for each. |
| 3.8 Metrics | `metrics.tex` | 12 metrics mapped to SQs. |
| 3.9 Validity | `validity.tex` | Internal: controlled variables, repetitions. External: single-node limitation. 3 reps acknowledged as directional. |

---

## 7 · File → Ticket → Experiment Mapping

| File | Ticket | Week | Depends on |
|------|--------|------|------------|
| `src/workload/workload_job.py` | THESIS-003 | W1 | — |
| `scripts/collect_vm_metrics.py` | THESIS-004 | W1 | THESIS-003 |
| `scripts/collect_k8s_metrics.sh` | THESIS-004 | W1 | THESIS-003 |
| `scripts/collect_pod_timing.py` | THESIS-004 | W1 | THESIS-002 |
| `scripts/export_dagster_runs.py` | THESIS-004 | W1 | THESIS-001 |
| `scripts/trigger_dagster_runs.py` | THESIS-004 | W1 | THESIS-003 |
| `scripts/blast_radius_vm.sh` | THESIS-004 | W1 | THESIS-001 |
| `scripts/blast_radius_k8s.sh` | THESIS-004 | W1 | THESIS-002 |
| `scripts/run_experiment.sh` | THESIS-005 | W1 | THESIS-004 |
| `data/raw/exp1-vm-degradation/` | THESIS-006 | W2 | THESIS-005 |
| `data/raw/exp2-*/` | THESIS-007–009 | W2 | THESIS-005 |
| `notebooks/analysis.ipynb` | THESIS-010 | W3 | THESIS-006–009 |
| `docs/chapters/04-results/` | THESIS-011 | W3 | THESIS-010 |
| `docs/chapters/05-discussion/` | THESIS-012 | W3–W4 | THESIS-011 |
| `docs/chapters/06-conclusions/` | THESIS-012 | W4 | THESIS-012 |

---

## 8 · Conventions for AI Agents

1. **One `.tex` file per section** — never dump everything into one file.
2. **Hub files** (`chapter.tex`) use `\input{}` to include sections.
3. **Data files never committed** — only `.gitkeep` placeholders in `data/raw/`.
4. **Processed outputs** go to `data/processed/` (CSVs) and `results/` (PNGs).
5. **`make analyze`** runs the notebook headlessly via `scripts/analyze_results.py`.
6. **`make pdf`** builds the thesis via `latexmk`.
7. **All experiments run from repo root**: `make exp1-vm`, `make exp2a-k8s`, etc.
8. **Tickets map 1:1 to GitHub issues**: `project/issues/*.md` → `./project/scripts/issues.sh`.
9. **Labels are in `project/config/labels.json`** — synced with `./project/scripts/labels.sh`.
10. **This file (`PLAN.md`) is the strategic plan. `CLAUDE.md` is the technical reference.**

---

## 9 · Internship Connection

The author completed a **3-month internship** (LIA1) at **Insighta Inc.** (Knoxville, USA) where he:

- Evaluated whether **K8sRunLauncher** could deploy Dagster without interrupting running jobs
- Migrated **Dagster and PostgreSQL from Docker on VMs to Kubernetes (GKE)**
- Implemented **branch-based deployments** on cloud-based GKE clusters using Helm and CDKTF
- Experienced first-hand the operational complexity and trade-offs of K8s for workflow orchestration
- Observed that small teams questioned whether Kubernetes was worth the overhead for their workload scale

**This thesis directly extends the internship work** by asking: "Was the
Kubernetes migration actually worth it?" — and answering it with empirical
measurements rather than intuition.

This must be clearly stated in:
- `docs/chapters/01-introduction/background.tex` (§1.1) — "During a 3-month internship..."
- `docs/chapters/01-introduction/practical-value.tex` (§1.8) — "The author's direct experience..."
- `docs/frontmatter/abstract.tex` — brief mention in context sentence

---

## 10 · Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Experiments take longer than planned | High | Buffer days built into W2. Can reduce to 2 reps if needed. |
| VM or Kind environment unstable | Medium | Snapshot VM after setup. Kind cluster is disposable and quick to recreate. |
| Results don't show a clear crossover | Medium | That IS a valid finding. "No crossover within tested range" is publishable. |
| Supervisor requests major proposal changes | High | Submit proposal early (end of W1). Iterate fast. |
| Laptop hardware limits experiment fidelity | Low | Acknowledged in delimitations + validity section. |
| Kind single-node can't schedule L6 (10 pods) | Medium | Document scheduling delays as SQ3 data. Reduce pod resource requests if needed. |

---

## 11 · Definition of Done (Thesis)

- [ ] Chapters 1–6 complete with no TODO/placeholder text
- [ ] All tables filled with real experimental data
- [ ] All figures generated from actual measurements
- [ ] Statistical tests (Mann-Whitney U) run and reported
- [ ] Abstract reflects actual findings
- [ ] References complete and matching (`references.bib`)
- [ ] `make pdf` produces clean PDF with no warnings
- [ ] Submitted to supervisor by 2026-05-24

---

## 12 · For Follow-Up AI Agents

If you are an AI agent picking up this project:

1. **Read this file first** for strategy, scope, and timeline.
2. **Read `CLAUDE.md`** for technical conventions and directory structure.
3. **Read `docs/chapters/03-method/experiments.tex`** for the exact experiment protocol.
4. **Read `notebooks/analysis.ipynb`** for the analysis logic.
5. **Check `data/raw/`** — if directories contain data files (not just `.gitkeep`), experiments are done.
6. **Check `data/processed/`** — if CSVs exist, analysis is done.
7. **Check `docs/chapters/04-results/`** — if tables are filled (no TODO comments), results are written.

The research questions are answered by following the chain:
```
Exp 1 data  → SQ1 answer  (VM degradation threshold)
Exp 2 data  → SQ2 answer  (K8s isolation works? yes/no + how much)
Exp 2 data  → SQ3 answer  (K8s overhead = X seconds, grows how?)
SQ1+SQ2+SQ3 → SQ4 answer  (crossover at level Z)
SQ4         → RQ answered  (migration worth it above level Z)
```

### Key references
- `litreture-review/Literature_Synthesis.md` — full paper-by-paper analysis
- `litreture-review/Supervisor_Feedback.md` — supervisor's feedback on the original proposal
- `LIA1-report/` — internship report (context for the thesis background)
- `proposal/main.tex` — original expanded proposal (STALE — thesis docs are canonical)
- `thesis-instruction-yh/` — Jensen YH exam instructions and grading criteria

**Do not change the research questions.** They are locked. Everything flows from them.
