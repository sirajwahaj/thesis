# When Does Kubernetes Become Worth It?

## Measuring Reliability, Stability, and Execution Overhead in Workflow Orchestration Systems Moving from Shared VM to Isolated Kubernetes Execution

**Revised Thesis Proposal — v2.0**

Jensen Yrkeshögskola — DevOps Examensarbete  
Academic Year: 2024–2025  
Revision Date: 2026-03-20

---

## Abstract

This thesis investigates how reliability, system stability, and execution performance change when a workflow orchestration system migrates from a single virtual machine using a shared process executor to a Kubernetes cluster using isolated pod execution. Dagster is used as a representative modern pipeline orchestration framework. Through three controlled experiments across six concurrency levels, the study identifies a *crossover point* — the specific concurrent workload level at which the Kubernetes deployment becomes net beneficial despite its inherent scheduling overhead. Experiments are executed on local infrastructure (a Linux VM and a Kind cluster) to ensure full control, reproducibility, and zero budget dependency, with an optional cloud validation phase on Google Kubernetes Engine if resources permit. Results are intended to provide engineering teams with data-backed guidance for VM-to-Kubernetes migration decisions in pipeline orchestration contexts.

**Keywords:** Kubernetes, Dagster, workflow orchestration, resource contention, pod isolation, crossover point, Kind, reliability measurement, DevOps

---

## 1. Introduction

### 1.1 Background and Motivation

Modern data engineering relies on pipeline orchestration frameworks to automate, schedule, and monitor workflows across variable and unpredictable workloads. A common initial deployment strategy is to host such a framework on a single virtual machine (VM) using a shared process executor. While simple to configure, this architecture contains a fundamental flaw: all pipeline jobs execute within the same process on the same host, sharing a single pool of CPU and memory.

As concurrent job execution increases, resource contention arises. Jobs compete for the same resources, performance degrades non-linearly, and under sufficient load the system fails entirely. Research on shared-memory multiprocessor systems demonstrates that this degradation compounds multiplicatively rather than additively as utilisation approaches capacity limits, producing a collapse effect rather than a smooth performance curve (Nanda et al., 1991). Arora (2023) further establishes that shared resource contention influences task timing in non-deterministic ways, making worst-case execution behaviour extremely difficult to predict.

Dagster is used in this thesis as a representative modern workflow orchestration system. It provides a Kubernetes Run Launcher that dispatches each pipeline run as an isolated pod on a Kubernetes cluster, where each pod receives defined CPU and memory resources. Failures are theoretically contained within individual pods rather than propagating across the system.

While this architectural migration is well-documented at the tool level, there is limited empirical evaluation of its actual effectiveness under controlled workload conditions. Existing research evaluates Kubernetes performance at the infrastructure level — measuring container overhead, pod scheduling latency, and autoscaler response times (Casalicchio, 2019; Nguyen et al., 2020; Choi et al., 2021). Separately, resource contention theory predicts non-linear collapse in shared execution environments (Nanda et al., 1991; Arora, 2023). But no study connects these two bodies of evidence at the application-level workflow execution layer to answer the practical question: *at what workload level does migrating from a shared VM to Kubernetes become worth it?*

### 1.2 The Research Problem

#### 1.2.1 The Surface Problem

A VM-hosted workflow orchestration system becomes unreliable under concurrent workload because all jobs share the same compute resources. This is an observable and known failure mode.

#### 1.2.2 The Deeper Problem — The Research Gap

The surface problem is not the research gap. The gap exists at the intersection of two bodies of literature that have not yet been connected.

Existing research evaluates Kubernetes performance and autoscaling behaviour at the infrastructure level — measuring container overhead, pod scheduling latency, and cluster autoscaler response under generic workloads (Casalicchio, 2019; Nguyen et al., 2020; Tran et al., 2022). Separately, research on resource contention analyses performance degradation in shared execution environments (Nanda et al., 1991; Arora, 2023). What is missing is empirical measurement of how infrastructure-level Kubernetes mechanisms — pod isolation, resource limits, and horizontal autoscaling — actually affect application-level workflow execution behaviour under controlled concurrent workload conditions.

Casalicchio (2019) demonstrates that under concurrent workloads with CPU utilisation above 75%, response times under the default Kubernetes Horizontal Pod Autoscaler are 2 to 3 orders of magnitude higher than under a contention-aware algorithm, highlighting that resource contention remains severe even in containerised environments. Choi et al. (2021) report that the median container startup latency in production orchestration systems is 25 seconds, representing a substantial fixed overhead for every pipeline job. But the specific workload threshold at which migrating from VM-based to Kubernetes-based workflow execution changes the balance between contention cost and scheduling overhead has not been empirically identified.

This thesis bridges that gap by measuring system behaviour at the pipeline execution level rather than at the infrastructure level alone.

#### 1.2.3 The Literature Gap Statement

Existing studies focus on Kubernetes performance and autoscaling at the infrastructure level, but there is no empirical evidence on how these mechanisms affect application-level workflow orchestration systems under controlled concurrent workload conditions. No study identifies the specific concurrency threshold at which a Kubernetes migration becomes net beneficial for pipeline orchestration. This thesis addresses that specific gap.

### 1.3 Purpose

The purpose of this thesis is to design, implement, and evaluate a controlled experimental comparison of single-VM and Kubernetes-based Dagster pipeline execution, measuring how reliability, system stability, and execution performance change under increasing concurrent workload, and identifying the specific workload threshold at which the Kubernetes migration becomes net beneficial.

### 1.4 The Core Idea

This thesis measures how reliability, failure behaviour, execution performance, and system stability change under increasing concurrent workload when a workflow orchestration system moves from a shared execution model on a single VM to an isolated distributed model on Kubernetes. It identifies the specific workload level at which that migration becomes net beneficial.

This thesis is **not** a proof that Kubernetes is better than a VM. It is not a Kubernetes benchmark, a tool comparison, or a cloud provider comparison. It focuses specifically on behavioural differences between two architectural execution models — shared process execution versus isolated pod execution — measured at the workflow job execution level under controlled conditions. If results show the VM performs better across all tested concurrency levels, that is an equally valid and valuable finding.

### 1.5 Primary Contribution — The Crossover Point

The primary contribution is the identification and measurement of a crossover point, defined through two complementary thresholds:

- **Reliability crossover:** The concurrent workload level at which the VM deployment's job success rate drops below 95% due to resource contention.
- **Performance crossover:** The concurrent workload level at which the Kubernetes deployment's total execution time (including pod scheduling overhead and container startup latency) becomes lower than the VM's execution time under active contention.

These two thresholds may occur at different concurrency levels. If so, both are reported, along with a **combined crossover point** — the level at which both conditions are simultaneously met. This dual definition prevents the analysis from missing scenarios where the VM is already severely degraded in performance but has not yet crossed the success rate threshold.

### 1.6 Research Hypothesis

Migrating workflow orchestration execution from a single-VM process executor to a Kubernetes Run Launcher will produce measurable reliability improvements through pod isolation, but will also introduce measurable scheduling latency and execution overhead that does not exist in the VM deployment.

These advantages are conditional on workload level. At low concurrency, the VM is expected to outperform Kubernetes on execution speed because resource contention has not yet reached critical levels and there is no pod scheduling overhead to pay. At high concurrency, Kubernetes is expected to outperform the VM as pod isolation prevents the contention collapse that a shared execution model cannot avoid.

### 1.7 Research Questions

**Main Research Question**

> How do reliability, system stability, and execution performance change when a workflow orchestration system is migrated from a single-VM process executor to a Kubernetes Run Launcher under increasing concurrent workload, and at what specific workload level does this migration become net beneficial?

**Supporting Questions (4)**

**SQ1 — VM Failure Threshold and Degradation Profile**  
At what concurrency level does a single-VM workflow deployment fail, and how do job success rate, execution time variance, and resource utilisation degrade as concurrent load increases toward that threshold?

**SQ2 — Pod Isolation Effectiveness and Blast Radius Containment**  
To what degree does Kubernetes pod isolation contain failures and reduce execution time variance compared to the single-VM deployment under equivalent concurrent workload levels?

**SQ3 — Kubernetes Scheduling Overhead**  
What measurable scheduling latency and execution overhead does Kubernetes introduce compared to the VM process executor at each concurrency level?

**SQ4 — The Crossover Point**  
At what concurrency level does the Kubernetes overhead become smaller than the VM's contention-induced degradation — the formally defined crossover point?

### 1.8 How the Questions Form One Argument

The four supporting questions form a single connected logical chain:

- **SQ1** establishes the exact failure profile of the VM architecture — the baseline evidence.
- **SQ2** tests whether Kubernetes actually fixes what SQ1 measured as broken.
- **SQ3** quantifies the cost of the Kubernetes execution model — the overhead that must be justified.
- **SQ4** synthesises SQ1 through SQ3 into the crossover point — the primary contribution.

### 1.9 Practical Value and Target Audience

These findings give small teams, startups, and engineers a data-based answer to: *at what workload scale does migrating a workflow orchestration system from a VM to Kubernetes become worth the added complexity and overhead?*

### 1.10 Delimitations

This study does not include:

- Comparison between cloud providers (AWS EKS, Azure AKS)
- Comparison between orchestration tools — the focus is on execution model behaviour, not tool selection
- ML model accuracy evaluation
- Multi-process VM configurations — only the default single-process executor is used
- Real or sensitive data — synthetic workloads only
- Production-grade multi-node Kubernetes configurations (unless GCP budget permits the optional cloud validation)

**Ethical statement:** This study uses only synthetic workloads. No personal, sensitive, or proprietary data is collected or processed at any stage.

### 1.11 Thesis Structure

Chapter 2 reviews the literature across three pillars. Chapter 3 defines the method, infrastructure, experimental design, tools, and metrics. Chapter 4 presents the results of all three experiments. Chapter 5 discusses the findings in relation to the research questions and the crossover point. Chapter 6 presents conclusions, practical recommendations, and directions for future research.

---

## 2. Literature Review

This chapter reviews three interconnected research areas that provide the theoretical foundation for the experimental design. Each pillar connects directly to one or more supporting questions. The chapter concludes with a positioning statement identifying the specific gap this thesis fills.

### 2.1 Pillar 1 — Resource Contention and Non-Linear Performance Degradation

*(Theoretical basis for SQ1)*

Resource contention arises when multiple processes compete for finite shared resources — most commonly CPU cycles and memory — on a single host. The defining characteristic relevant to this thesis is that performance degradation under contention is *non-linear*: it does not scale proportionally with load but accelerates disproportionately as resource utilisation approaches capacity limits.

Nanda et al. (1991) provide the foundational empirical framework for this phenomenon in shared-memory multiprocessors. They introduce two normalised metrics — *efficiency* and *overhead factor* — to quantify the gap between ideal parallel speedup and actual performance when concurrent processes share memory resources. Their key finding is that contention-induced overhead compounds multiplicatively rather than additively, and can be decomposed into identifiable components: software synchronisation overhead, lock contention, and hardware memory access contention. This decomposition is directly relevant to understanding VM failure modes: when Dagster's process executor runs concurrent jobs, the overhead includes OS-level process scheduling, shared memory access contention, and I/O channel arbitration.

Arora (2023) extends contention analysis to multicore processors, demonstrating that shared resource contention is inherently non-deterministic — it can influence the temporal behaviour of tasks in unpredictable ways. A task executing on one core competes with co-running tasks for access to shared caches, memory bus, and main memory. The work shows that contention depends not only on the number of concurrent tasks but also on memory access patterns and arbitration policies. Critically, Arora demonstrates that contention effects can cause timing violations that cascade through dependent tasks — the same cascading failure mode expected in a shared-process Dagster executor where one job's memory exhaustion can terminate the entire orchestration process.

Casalicchio (2019) brings contention theory into the container domain, demonstrating that when multiple container instances run on the same host, they generate "interference in the contention of physical resources." Under concurrent workloads with CPU utilisation above 75%, response times under the default Kubernetes Horizontal Pod Autoscaler (KHPA) are 2 to 3 orders of magnitude higher than under a contention-aware algorithm. This finding confirms that resource contention remains a severe problem even in containerised environments when containers share a host.

**Research connection:** SQ1 identifies the empirical concurrency threshold at which non-linear contention collapse occurs for Dagster pipeline workloads on a single VM. The literature predicts the collapse will be sudden rather than gradual.

### 2.2 Pillar 2 — Kubernetes Performance Overhead and Fault Isolation

*(Theoretical basis for SQ2 and SQ3)*

This pillar combines two tightly related concerns: the overhead Kubernetes introduces and the fault isolation it provides. Both are trade-offs of the same architectural decision.

**Scheduling and startup overhead.** A substantial body of research documents the performance overhead of containerisation and Kubernetes orchestration. The primary sources of overhead relevant to this study are pod scheduling latency — the time between job submission and pod assignment to a node — and container startup time — the time between pod assignment and first application instruction. Choi et al. (2021) cite Google Borg data showing a median container startup latency of 25 seconds, with 90th-percentile microservice startup at approximately 15 seconds. Liu et al. (2024) report that scheduling latency has become a new bottleneck in Kubernetes-based systems, particularly for short-duration workloads where fixed overhead constitutes a large fraction of total execution time. For a workflow orchestration system like Dagster using the Kubernetes Run Launcher, each pipeline run pays this overhead cost — a cost that does not exist in the native VM process executor.

**Fault isolation and blast radius.** A foundational principle of distributed systems design is that failures should be contained within the smallest possible boundary. The *blast radius* — the scope of a system affected by a single failure — is central to reliability architecture (Čilić et al., 2023). In a single-VM shared execution environment, the blast radius of any individual job failure is potentially the entire system: a job that exhausts memory can trigger an out-of-memory kill that terminates all running jobs. In the Kubernetes pod model, each job runs with enforced resource limits, and a failing pod is terminated without directly affecting other pods. However, Casalicchio (2019) demonstrates that pod isolation is not absolute — containers on the same host still generate interference through physical resource contention even when they have defined resource limits.

**Research connection:** SQ2 empirically tests whether pod isolation contains failures at the workflow execution level. SQ3 quantifies the scheduling overhead at each concurrency level. Together, they provide the data needed to compute the crossover point (SQ4).

### 2.3 Pillar 3 — Autoscaling Behaviour and Response Latency

*(Contextual basis for understanding Kubernetes operational behaviour)*

Kubernetes Horizontal Pod Autoscaler (HPA) scales pod count based on observed CPU or memory metrics, while the cluster autoscaler provisions new nodes when scheduling demand exceeds current capacity. Both mechanisms introduce reaction latency absent from a fixed-capacity VM deployment.

Nguyen et al. (2020) provide a comprehensive empirical analysis of HPA's operational behaviour, revealing that scaling decisions are sensitive to metric scraping periods, cluster size, and the type of metric used — knowledge "not available on the official website and other sources." Tran et al. (2022) survey the state of the art and identify that default HPA has "slow adaptation performances against dynamic workloads" because it triggers scaling only after thresholds are exceeded. Yuan and Liao (2024) demonstrate that predictive scaling reduced cold start time by 1 hour 41 minutes compared to purely reactive HPA, illustrating the magnitude of reactive scaling's performance cost. Li et al. (2025) identify that Kubernetes default scaling mechanisms "fail to effectively distinguish and manage resource consumption of idle containers, leading to resource waste and degraded system performance."

**Research connection:** While this thesis does not include autoscaling as a separate experiment (due to scope constraints), autoscaling behaviour is observed during the spike workload level in Experiment 2 and reported as supplementary data. The literature contextualises those observations.

### 2.4 Positioning Statement — The Gap This Thesis Fills

Each pillar has been studied independently. Resource contention theory is well-established (Nanda et al., 1991; Arora, 2023). Kubernetes overhead is measured at the infrastructure level (Casalicchio, 2019; Liu et al., 2024). Autoscaling behaviour is documented (Nguyen et al., 2020; Tran et al., 2022; Choi et al., 2021). Fault isolation principles are understood architecturally (Čilić et al., 2023).

What is missing — and what this thesis provides — is a study that:

1. Connects resource contention and Kubernetes overhead at the **application-level workflow execution layer**, not the infrastructure level
2. Measures the **same workload** on **both architectures** across a range of concurrency levels
3. Identifies a specific **crossover threshold** where the migration becomes net beneficial
4. Uses **real pipeline orchestration workloads** (Dagster), not HTTP benchmarks or CPU stress tests
5. Runs on **real infrastructure** under controlled conditions, not simulations

No existing study provides engineers with a data-backed answer to "at what workload level does the Kubernetes migration become worth it for pipeline orchestration systems?" This thesis fills that gap.

---

## 3. Method and Experimental Design

### 3.1 Research Design

This study follows a controlled experimental design with a before-and-after comparison structure. The baseline condition is Dagster deployed on a single VM using the default process executor. The comparison condition is Dagster deployed on Kubernetes using the Kubernetes Run Launcher. Identical workloads are applied to both conditions and results are compared across all defined metrics.

### 3.2 Infrastructure Strategy — Local-First with Optional Cloud Validation

A critical design decision in this thesis is the **local-first infrastructure strategy**, which addresses budget uncertainty and maximises experimental control.

#### 3.2.1 Primary Environment: Local Infrastructure

All experiments are designed to run entirely on the researcher's local machine using:

- **VM Baseline:** A Linux virtual machine provisioned via **Multipass** (Ubuntu), configured with fixed CPU and memory limits (e.g., 4 vCPU, 8 GB RAM) to simulate a constrained production VM. Dagster is deployed with the default process executor.
- **Kubernetes Comparison:** A **Kind** (Kubernetes in Docker) cluster running on the same physical host, configured with resource limits matching the VM. Dagster is deployed with the Kubernetes Run Launcher via Helm.

This approach provides:
- **Zero cloud cost** — no budget dependency or risk of mid-experiment credit exhaustion
- **Full control** — exact CPU/memory allocation is enforced and reproducible
- **Faster iteration** — no cloud provisioning delays between experiment runs
- **Reproducibility** — any researcher with a comparable machine can replicate the setup

The shared physical host is an intentional design choice: it ensures both environments have access to the same underlying hardware, making the comparison about *execution model architecture* (shared process vs. isolated pods) rather than about hardware differences.

#### 3.2.2 Optional Cloud Validation Phase

If GCP budget permits (free tier credits or education grants), a subset of experiments will be repeated on:

- **VM:** Google Compute Engine instance (e2-standard-2: 2 vCPU, 8 GB RAM)
- **Kubernetes:** Google Kubernetes Engine (GKE) standard cluster with Kubernetes Run Launcher

Cloud results serve as a **directional validation** of local findings, not as the primary dataset. If cloud validation is not possible, this is documented as a delimitation, and the thesis argues that the architectural comparison (shared vs. isolated execution) is valid regardless of whether the underlying host is a laptop or a cloud instance — a position supported by the infrastructure-agnostic nature of resource contention theory (Nanda et al., 1991).

#### 3.2.3 Infrastructure Specifications

| Component | VM Baseline | Kubernetes (Kind) |
|-----------|-----------|-------------------|
| Provisioning | Multipass (Ubuntu 22.04) | Kind v0.20+ on Docker |
| CPU | 4 vCPU (fixed) | 4 vCPU (node resource limit) |
| Memory | 8 GB RAM (fixed) | 8 GB RAM (node resource limit) |
| Dagster executor | Default ProcessExecutor | K8sRunLauncher via Helm |
| Resource isolation | None (shared process) | Per-pod CPU/memory requests and limits |
| Autoscaling | Not applicable | HPA enabled (observed, not primary experiment) |
| IaC | Shell script or Multipass config | Kind config YAML + Helm |

### 3.3 Tool Stack

The following tools are required to execute this thesis. All are open source or freely available.

#### 3.3.1 Infrastructure Tools

| Tool | Purpose | Version |
|------|---------|---------|
| **Docker Desktop** | Container runtime for Kind and Dagster images | Latest stable |
| **Kind** (Kubernetes in Docker) | Local Kubernetes cluster for comparison environment | v0.20+ |
| **Multipass** | Lightweight Ubuntu VM provisioning for baseline environment | Latest stable |
| **Helm** | Package manager for deploying Dagster on Kubernetes | v3.x |
| **kubectl** | Kubernetes CLI for cluster management and pod inspection | Matching K8s version |

#### 3.3.2 Application and Orchestration

| Tool | Purpose |
|------|---------|
| **Dagster** (OSS) | Workflow orchestration framework — the system under test |
| **Dagster Helm chart** | Official Helm chart for Kubernetes deployment with Run Launcher |
| **Python 3.11+** | Runtime for Dagster pipelines and test harness |
| **Dagster GraphQL API** | Programmatic triggering of concurrent pipeline runs |

#### 3.3.3 Measurement and Observability

| Tool | Purpose |
|------|---------|
| **Prometheus** | Metrics collection from Kubernetes (CPU, memory, pod states) |
| **cAdvisor** | Container-level resource usage metrics |
| **kubectl top** / **docker stats** | Quick resource utilisation snapshots |
| **Python (pandas, matplotlib)** | Data analysis and chart generation |
| **Custom Python test harness** | Automated concurrent run submission, metric collection, CSV export |

#### 3.3.4 Development and Documentation

| Tool | Purpose |
|------|---------|
| **Git + GitHub** | Version control for all code, configurations, and data |
| **GitHub Actions** (optional) | CI pipeline for automated deployment validation |
| **LaTeX** | Thesis document formatting |
| **VS Code** | Primary development environment |

### 3.4 Operational Definitions

**Reliability:** Three measurable properties: (1) *job success rate* — percentage of Dagster runs completing without error at each concurrency level; (2) *failure isolation* — whether one failing job measurably affects other concurrently running jobs; (3) *MTTR* — time in seconds from failure detection to successful job re-execution.

**System Stability:** Measured primarily through *execution time variance* — the standard deviation of job execution time across repeated runs at each concurrency level. A system with high variance is operationally unstable even if its mean execution time is acceptable.

**Operational Overhead:** Three measurable components: (1) *pod scheduling latency* — time from Dagster job submission to pod entering running state; (2) *container startup time* — time from pod running state to first job instruction executing; (3) *net execution time delta* — difference in total end-to-end execution time between VM and Kubernetes for identical jobs at identical concurrency levels.

**Crossover Point:** Defined through two complementary thresholds:
- *Reliability crossover:* VM success rate drops below 95%
- *Performance crossover:* Kubernetes total execution time (including overhead) becomes lower than VM execution time under contention
- *Combined crossover:* Both conditions are simultaneously met

### 3.5 Workload Definition

Workloads are defined precisely to ensure reproducibility and to simulate realistic pipeline execution resource consumption patterns. Six concurrency levels provide sufficient data points to identify the degradation curve and crossover region.

#### Table 3.1: Defined Workload Levels

| Level | Concurrent Jobs | Per-Job CPU | Per-Job Memory | Job Description |
|-------|----------------|-------------|----------------|-----------------|
| L1 | 1 | 0.25 CPU | 256 MB | Baseline: generates and sorts 500K random integers |
| L2 | 2 | 0.25 CPU | 256 MB | Light concurrency |
| L3 | 3 | 0.50 CPU | 512 MB | Moderate: reads 50 MB CSV, performs transformations, writes output |
| L4 | 5 | 0.50 CPU | 512 MB | Heavy concurrency with same per-job profile |
| L5 | 7 | 1.00 CPU | 1 GB | Stress: computes SHA-256 hashes of 5M strings sequentially |
| L6 — Spike | 10 | 0.50 CPU | 512 MB | Burst exceeding single-node capacity |

Each workload level is run **3 times** per environment. Results are reported as mean and standard deviation. For levels near the expected crossover (L4, L5), an additional 2 runs may be added if time permits to improve confidence.

**Workload design rationale:**
- L1–L2 establish the no-contention baseline where VM is expected to be faster
- L3–L4 represent the transition zone where contention begins
- L5–L6 represent the stress zone where VM collapse is expected
- Both CPU-bound and memory-bound work patterns are included because they trigger different failure modes: CPU contention degrades performance gradually while memory exhaustion causes sudden termination

### 3.6 Test Harness

A critical component of this thesis is the automated test harness — a Python script that:

1. Uses the **Dagster GraphQL API** to submit N pipeline runs simultaneously via `concurrent.futures.ThreadPoolExecutor`
2. Polls run status via the API until all runs complete or fail
3. Records per-run timestamps: submission time, start time, end time, final status
4. On Kubernetes: records pod scheduling latency and container startup time via `kubectl` timestamps
5. On VM: records process spawn time and CPU/memory utilisation via `psutil`
6. Exports all data to CSV for analysis

This harness ensures that concurrent runs are submitted within a tight time window (< 1 second spread) and that all metrics are collected programmatically — no manual observation of the Dagit UI.

### 3.7 Experimental Design

Three core experiments are defined. Each addresses one or more supporting questions. A deliberate failure injection is folded into Experiment 2 to test blast radius without requiring a separate experiment.

#### 3.7.1 Experiment 1 — VM Degradation Profile (answers SQ1)

**Setup:** Dagster deployed on the Multipass VM with default process executor.

**Procedure:** Run all six workload levels (L1–L6). Each level is repeated 3 times. Record: job success rate, mean execution time, execution time standard deviation, CPU utilisation, memory utilisation, and MTTR for any failures.

**Goal:** Produce the VM degradation curve — identifying the exact concurrency level at which success rate drops below 95% and documenting the shape of the degradation (gradual vs. collapse).

#### 3.7.2 Experiment 2 — Kubernetes Isolation and Blast Radius (answers SQ2)

**Setup:** Kind cluster with Kubernetes Run Launcher. Identical resource profiles to Experiment 1.

**Procedure:**
- **Part A — Isolation comparison:** Run identical workload levels (L1–L6) as Experiment 1, 3 repetitions each. Record same metrics.
- **Part B — Blast radius test (folded in):** At level L4 (5 concurrent jobs), after all jobs are running, deliberately kill one pod mid-execution using `kubectl delete pod --force`. Measure: (a) number of other running jobs affected, (b) time until surviving jobs complete, (c) success rate of surviving jobs. Repeat on VM using `kill -9` on one process. Compare blast radius between environments.
- **Part C — Spike observation (folded in):** At L6 (10 concurrent jobs, exceeding single-node capacity), observe and record: how many jobs are delayed pending scheduling, how long until all jobs begin executing, any job failures due to scheduling timeout. This provides supplementary autoscaling data without a dedicated experiment.

**Goal:** Calculate the delta in job success rate, execution time variance, and blast radius between VM and Kubernetes at each concurrency level.

#### 3.7.3 Experiment 3 — Overhead Measurement and Crossover Point (answers SQ3, SQ4)

**Setup:** Both VM and Kind environments running identical single jobs for overhead isolation, then compared across all concurrency levels.

**Procedure:**
- At each concurrency level, record pod scheduling latency and container startup time on Kubernetes (from pod event timestamps)
- Calculate net execution time difference between VM and Kubernetes per job per level
- Plot both overhead cost (Kubernetes) and contention cost (VM) against concurrency level on the same chart
- Identify the reliability crossover, performance crossover, and combined crossover point

**Goal:** Produce the crossover chart and identify the primary contribution — the crossover point.

### 3.8 Metrics Summary

#### Table 3.2: Complete Metrics Table

| Metric | Definition | VM | K8s | Answers |
|--------|-----------|-----|-----|---------|
| Job success rate | % runs completing without error | ✓ | ✓ | SQ1, SQ2 |
| Mean execution time | End-to-end time per run | ✓ | ✓ | SQ1, SQ2, SQ3 |
| Execution time variance | Std deviation under load | ✓ | ✓ | SQ1, SQ2 |
| CPU utilisation | Per-job CPU consumption | ✓ | ✓ | SQ1, SQ2 |
| Memory utilisation | Per-job memory consumption | ✓ | ✓ | SQ1, SQ2 |
| MTTR | Failure to successful re-run | ✓ | ✓ | SQ1, SQ2 |
| Failure blast radius | Does one failure affect others? | ✓ | ✓ | SQ2 |
| Pod scheduling latency | Submission to pod running | — | ✓ | SQ3 |
| Container startup time | Pod running to job executing | — | ✓ | SQ3 |
| Net execution time delta | VM vs K8s per job per level | ✓ | ✓ | SQ3, SQ4 |
| Reliability crossover | Level where VM success < 95% | ✓ | — | SQ4 |
| Performance crossover | Level where K8s time < VM time | ✓ | ✓ | SQ4 |

### 3.9 Validity Statement

The VM and Kubernetes environments share the same physical host. This is a methodological strength, not a weakness: it controls for hardware differences and ensures the comparison isolates *execution model architecture* rather than hardware capability.

All experiments use synthetic workloads under local infrastructure constraints. Results may not generalise directly to all workflow systems or all cloud environments. However, the behavioural patterns identified — the failure degradation curve, the blast radius reduction, the scheduling overhead, and the crossover point — are expected to be directionally relevant for similar pipeline orchestration frameworks under comparable concurrency conditions, as supported by the infrastructure-agnostic nature of resource contention theory (Nanda et al., 1991).

Three repetitions per workload level provide an indication of variability but are insufficient for full statistical significance testing. Results are reported as directional findings rather than statistically confirmed effects. This is acknowledged as a limitation.

If results are inconsistent across experimental runs, that inconsistency is documented and analysed as a finding rather than suppressed as error.

---

## 4. Results

*(To be completed after experimental phase.)*

### 4.1 Experiment 1 Results — VM Degradation Profile (SQ1)

#### Table 4.1: VM Deployment Results by Workload Level

| Level | Concurrent Jobs | Success Rate (%) | Mean Time (s) | StdDev (s) | CPU (%) | Memory (MB) |
|-------|----------------|-----------------|----------------|------------|---------|-------------|
| L1 | 1 | | | | | |
| L2 | 2 | | | | | |
| L3 | 3 | | | | | |
| L4 | 5 | | | | | |
| L5 | 7 | | | | | |
| L6 | 10 | | | | | |

### 4.2 Experiment 2 Results — Kubernetes Isolation (SQ2)

*(Results tables for Part A, Part B blast radius comparison, and Part C spike observation.)*

### 4.3 Experiment 3 Results — Overhead and Crossover Point (SQ3, SQ4)

*(Results tables and the crossover chart.)*

---

## 5. Discussion

*(To be completed after experimental phase.)*

### 5.1 Discussion of SQ1 — The VM Failure Threshold

This section discusses the measured failure threshold against resource contention theory from Pillar 1 (Nanda et al., 1991; Arora, 2023; Casalicchio, 2019). It addresses whether the collapse was non-linear as predicted and at what concurrency level it occurred.

### 5.2 Discussion of SQ2 — Pod Isolation Effectiveness

This section evaluates whether pod isolation delivered the theoretical blast radius reduction predicted by distributed systems fault isolation principles (Čilić et al., 2023). It compares execution time variance between VM and Kubernetes and discusses the deliberate failure injection results.

### 5.3 Discussion of SQ3 — Kubernetes Scheduling Overhead

This section discusses the measured overhead against literature values. Choi et al. (2021) report 25-second median container startup; Liu et al. (2024) identify scheduling as a new bottleneck. This section compares those infrastructure-level findings to the application-level overhead observed in Dagster pipeline execution.

### 5.4 Discussion of SQ4 — The Crossover Point

This section presents and interprets the primary contribution. It discusses at what concurrency level each crossover threshold was reached, what it means for engineering migration decisions, and whether the result was consistent with theoretical predictions. If the VM outperformed Kubernetes across all levels, this section discusses why and what it implies.

### 5.5 Trade-off Analysis

This section synthesises all findings into a balanced trade-off analysis: what the Kubernetes migration improves, what it costs, and under what conditions each architecture is more appropriate. This section directly answers the main research question.

### 5.6 Limitations

- Local infrastructure (Kind, Multipass) does not replicate cloud-specific behaviours such as network latency between nodes, cloud disk I/O performance, or managed control plane characteristics
- Synthetic workloads may not capture all real-world pipeline behaviour patterns
- Single physical host means the Kind cluster cannot demonstrate true multi-node scaling
- Three repetitions provide directional findings, not statistically significant effects
- Dagster as representative system — other workflow frameworks may behave differently
- If GCP validation was not performed, cloud-specific crossover may differ

---

## 6. Conclusions

*(To be completed after experimental phase.)*

### 6.1 Summary of Findings

### 6.2 Answer to the Main Research Question

### 6.3 Practical Recommendations

Based on the experimental findings, the following recommendations are offered:

1. Use the crossover point data to make evidence-based VM-to-Kubernetes migration decisions
2. Measure execution time *variance*, not just mean performance, when evaluating system stability
3. Account for Kubernetes scheduling overhead when estimating job execution time, particularly for short-duration jobs
4. Test blast radius containment before assuming pod isolation prevents cascading failures

### 6.4 Future Research

1. Repeat experiments on a cloud provider (GKE, EKS, or AKS) to validate whether the crossover point shifts in a managed multi-node environment
2. Test with real production workloads — data ingestion, transformation, and model inference pipelines — instead of synthetic workloads
3. Compare crossover points across different workflow orchestration frameworks (Airflow, Prefect, Argo Workflows)

---

## References

Arora, J. (2023). *Shared Resource Contention-Aware Schedulability Analysis of Hard Real-Time Systems*. PhD Thesis, CISTER Research Centre, Polytechnic Institute of Porto.

Casalicchio, E. (2019). A study on performance measures for auto-scaling CPU-intensive containerized applications. *Cluster Computing*, 22, 995–1006. https://doi.org/10.1007/s10586-018-02890-1

Choi, B., Park, J., Lee, C., & Han, D. (2021). pHPA: A Proactive Autoscaling Framework for Microservice Chain. *APNet 2021*. https://doi.org/10.1145/3469393.3469401

Čilić, I., Krivić, P., Podnar Žarko, I., & Kušek, M. (2023). Performance Evaluation of Container Orchestration Tools in Edge Computing Environments. *Sensors*, 23(8), 4008. https://doi.org/10.3390/s23084008

Li, H., Rao, W., Hu, B., Tian, Y., & Shen, J. (2025). Energy-aware elastic scaling algorithm for microservices in Kubernetes clouds. *Journal of Network and Computer Applications*, 242, 104218. https://doi.org/10.1016/j.jnca.2025.104218

Liu, Q., Yang, Y., Du, D., Xia, Y., Zhang, P., Feng, J., Larus, J. R., & Chen, H. (2024). Harmonizing Efficiency and Practicability: Optimizing Resource Utilization in Serverless Computing with Jiagu. *2024 USENIX Annual Technical Conference*.

Nanda, A. K., Shing, H., Tzen, T.-H., & Ni, L. M. (1991). Resource Contention in Shared-Memory Multiprocessors: A Parameterized Performance Degradation Model. *Journal of Parallel and Distributed Computing*, 12, 313–328.

Nguyen, T.-T., Yeom, Y.-J., Kim, T., Park, D.-H., & Kim, S. (2020). Horizontal Pod Autoscaling in Kubernetes for Elastic Container Orchestration. *Sensors*, 20(16), 4621. https://doi.org/10.3390/s20164621

Tran, M.-N., Vu, D.-D., & Kim, Y. (2022). A Survey of Autoscaling in Kubernetes. *International Conference on Ubiquitous and Future Networks (ICUFN)*.

Yuan, H. & Liao, S. (2024). A Time Series-Based Approach to Elastic Kubernetes Scaling. *Electronics*, 13(2), 285. https://doi.org/10.3390/electronics13020285

---

## Appendix A: Kind Cluster Configuration

```yaml
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
    kubeadmConfigPatches:
      - |
        kind: JoinConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            system-reserved: "cpu=500m,memory=512Mi"
            kube-reserved: "cpu=500m,memory=512Mi"
```

## Appendix B: Dagster Helm Values (Kubernetes Run Launcher)

```yaml
# values.yaml
dagster:
  runLauncher:
    type: K8sRunLauncher
    config:
      k8sRunLauncher:
        jobNamespace: dagster
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "1000m"
            memory: "1Gi"
```

## Appendix C: Test Harness Pseudocode

```python
import concurrent.futures
import time
import requests  # for Dagster GraphQL API

DAGSTER_GRAPHQL_URL = "http://localhost:3000/graphql"

def submit_run(job_name, run_config):
    """Submit a single Dagster run via GraphQL API."""
    mutation = """
    mutation LaunchRun($input: LaunchRunInput!) {
        launchRun(input: $input) {
            run { runId status }
        }
    }
    """
    # ... submit and return run_id, submission_timestamp

def poll_run_status(run_id):
    """Poll until run completes or fails. Return final status + timestamps."""
    # ... poll GraphQL API for run events

def run_experiment(concurrency_level, job_name, run_config):
    """Submit N runs concurrently and collect all metrics."""
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency_level) as pool:
        futures = [pool.submit(submit_run, job_name, run_config)
                   for _ in range(concurrency_level)]
        run_ids = [f.result() for f in futures]

    # Poll all runs to completion
    for run_id in run_ids:
        result = poll_run_status(run_id)
        results.append(result)

    # Export to CSV
    export_to_csv(results, f"exp_{concurrency_level}.csv")
    return results
```

## Appendix D: Experiment Data Collection Template

| Run | Level | Concurrent | Env | Success % | Mean (s) | StdDev (s) | CPU % | Mem (MB) | Pod Sched (s) | Container Start (s) |
|-----|-------|-----------|-----|-----------|----------|------------|-------|----------|---------------|-------------------|
| 1 | L1 | 1 | VM | | | | | | — | — |
| 1 | L1 | 1 | K8s | | | | | | | |
| ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |

---

## 4-Week Execution Plan

| Week | Focus | Deliverables |
|------|-------|-------------|
| **Week 1** (Mar 20–26) | Infrastructure + Harness | Multipass VM running Dagster ✓ Kind cluster running Dagster ✓ Test harness script working ✓ Can trigger and measure concurrent runs ✓ |
| **Week 2** (Mar 27–Apr 2) | Experiments | Exp 1 complete (all 6 levels × 3 reps) ✓ Exp 2 complete (all 6 levels × 3 reps + blast radius + spike obs) ✓ Exp 3 complete (overhead measurements + crossover chart) ✓ All data in CSV ✓ |
| **Week 3** (Apr 3–9) | Analysis + Writing | Chapter 4 (Results) with tables + charts ✓ Chapter 5 (Discussion) connecting results to literature ✓ Crossover point analysis ✓ Appendices populated ✓ |
| **Week 4** (Apr 10–16) | Finish + Submit | Abstract, Introduction, Conclusion finalised ✓ Full proofread ✓ References verified ✓ Optional: GCP validation if budget permits ✓ Submit ✓ |
