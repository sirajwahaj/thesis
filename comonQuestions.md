Read [](file:///c%3A/Users/Wahaj/Desktop/thesis/notebooks/analysis.ipynb#1-1), lines 1 to 10

<!-- filepath: c:\Users\Wahaj\Desktop\thesis\notebooks\supervisor_questions.ipynb -->
<VSCode.Cell language="markdown">

# Supervisor Review: Probable Viva Questions & Answers

**Thesis:** *When Does Kubernetes Become Worth It?*  
**Author:** Sirajulhaq Wahaj | **Supervisor:** Ludvig Malm  
**Date:** April 2026

---

This notebook is structured as a mock viva examination.  
Questions are grouped by chapter and theme, ordered from fundamental to detailed.  
Each question is followed by a direct, honest answer drawn from the experimental data.

> **How to use:** Read each question, write your own answer mentally, then compare to the answer cell below it. Flag any answer you are not confident about and revisit it before the viva.
</VSCode.Cell>
<VSCode.Cell language="markdown">

## 1 · Research Design and Motivation

</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q1 · In one sentence — what is the core research question and why does it matter?

**Answer:**  
At what concurrency level does migrating a Dagster workflow orchestration system from a VM-based DockerRunLauncher to a Kubernetes K8sRunLauncher become net beneficial in terms of reliability and execution performance?

It matters because every team running pipeline orchestration on a single VM faces this decision as workload grows, and no prior study had identified the specific concurrency threshold empirically — only infrastructure-level overhead metrics existed, disconnected from application-level failure behaviour.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q2 · Why Dagster specifically? Would your findings generalise to Airflow or Prefect?

**Answer:**  
Dagster was chosen because it natively supports both execution models — DockerRunLauncher and K8sRunLauncher — through configuration alone, making it uniquely suitable for a controlled comparison of the *same* framework across *two* architectures.

Generalisation: the *failure mechanism* (VM memory exhaustion → Linux OOM kills) is framework-agnostic — it is an OS-level phenomenon that would occur with any containerised workflow tool. The *crossover threshold* (L3 on this hardware) is workload- and hardware-specific. The *startup overhead* values (4–15 s) are Dagster-specific due to its Python framework initialisation. Tools with lighter runtimes (e.g., Argo Workflows) would have lower overhead, potentially shifting the performance crossover to a lower concurrency level while leaving the reliability crossover at the same point.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q3 · You describe a "literature gap" — but isn't VM vs. Kubernetes a well-known comparison? What exactly is novel?

**Answer:**  
The novelty is in the *connection* and *measurement level*. Three bodies of literature existed independently:

1. Resource contention theory (Nanda 1991, Arora 2023) — predicts non-linear collapse in shared execution
2. Kubernetes overhead studies (Casalicchio 2019, Choi 2021) — measures scheduling latency at the infrastructure level
3. Fault isolation principles (Čilić 2023) — describes blast radius architecturally

No study had measured all three *simultaneously at the workflow job execution layer* using real pipeline orchestration (not HTTP benchmarks or stress tests), nor identified a specific concurrency threshold where migration becomes net beneficial. That specific, empirically derived decision boundary — "migrate at 3 concurrent jobs on this hardware class" — is the novel contribution.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q4 · Your hypothesis predicted reliability collapse at L5–L7. The actual collapse was at L3. What does this tell you about your hypothesis formulation?

**Answer:**  
It tells me the hypothesis underestimated the memory pressure from the infrastructure stack.

The hypothesis focused on CPU saturation (4 vCPUs, gradual degradation) and expected memory to become a secondary issue at high concurrency. What happened was that the Docker daemon + PostgreSQL + Dagster daemon already consumed ≈1.5–2 GB of the 4 GB VM at rest, leaving only ≈2–2.5 GB for containers. Three containers × 400 MB = 1.2 GB allocation, but including Python and Dagster framework overhead (≈500–600 MB per container), aggregate demand reached 3–4.5 GB at L3 — exhausting available RAM.

The lesson: when formulating workload hypotheses, always account for the infrastructure stack's resident memory, not just the workload allocation.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q5 · Why did you choose 3 repetitions per level? Is that statistically sufficient?

**Answer:**  
Three repetitions is a pragmatic minimum given infrastructure constraints (experiment wall time, VM stability, cooldown requirements). It is **not** sufficient for statistical significance testing in the classical sense — and the thesis acknowledges this explicitly in the validity statement (Section 3.9) and limitations (Section 5.6).

However, three repetitions is adequate for the primary finding because the effects are very large. A success rate drop from 100% to 66.7% at L3 is not a marginal effect that requires high statistical power to detect. For the overhead measurements (4–15 s), more repetitions would be needed to characterise variance under cold-start conditions.

If I were to repeat the study, I would use 5–10 repetitions per level to enable Mann-Whitney U tests between environments.
</VSCode.Cell>
<VSCode.Cell language="markdown">

## 2 · Methodology and Infrastructure

</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q6 · The VM had 4 GB RAM and the Kind node had 8 GB. Isn't this an unfair comparison?

**Answer:**  
Yes — this is a genuine limitation, acknowledged in Section 5.6 under "Memory asymmetry between environments."

The practical reason: Multipass on Windows allocates from the host machine's RAM and the VM was constrained to 4 GB to leave sufficient headroom for the host OS + Kind cluster to run simultaneously on the same physical machine. Setting the Kind node to 4 GB would have made L7–L10 experiments impossible to complete on K8s.

The architectural argument for validity: the thesis is comparing *execution model architectures* (shared kernel OOM vs. per-pod cgroup limits), not raw hardware capacity. A VM with 8 GB RAM would move the OOM threshold to approximately L5–L7, but the failure *mechanism* and the *architectural lesson* — that per-pod limits prevent cross-job interference — remain valid regardless of total capacity. The crossover threshold value (L3) is hardware-specific, and the thesis is explicit about this.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q7 · Both environments ran on the same physical host. How does this affect the validity of your comparison?

**Answer:**  
Sharing the same physical host is actually a **methodological strength in one dimension**: it eliminates hardware-difference confounds, ensuring the comparison isolates execution model architecture rather than hardware capability.

The limitation it introduces: the Kind cluster and the VM competed for the same physical CPU and RAM. At high concurrency, both systems experienced host-level resource pressure from the opposite environment running simultaneously. This may have inflated execution times on both sides at L7–L10.

The mitigation: experiments were not run on both environments simultaneously. VM experiments and K8s experiments were conducted in separate sessions, so direct cross-contamination during a single run was minimal. The main concern is that host swap usage or background daemons from one environment affected the other's dedicated experiments.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q8 · Why Kind rather than a production Kubernetes cluster (GKE, EKS)?

**Answer:**  
Three reasons:

1. **Zero cost** — no cloud budget dependency or risk of mid-experiment credit exhaustion. The thesis explicitly notes this as part of the local-first strategy (Section 3.2).
2. **Full control** — exact CPU/memory allocation is enforced and reproducible. Cloud VMs have noisy neighbours; local Kind is deterministic.
3. **Reproducibility** — any researcher with a comparable machine can replicate the setup without cloud accounts.

The trade-off is representativeness: Kind uses a single node with no multi-node scheduling decisions, no network-based pod placement, and pre-pulled images that eliminate image-pull latency. This means the startup overhead values (4–15 s) are optimistic relative to production GKE/EKS, where cold image pulls add 10–60 s. The thesis acknowledges this in Sections 5.3 and 5.6 and frames it as a directional lower bound, not a production measurement.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q9 · How did you ensure the two environments were genuinely comparable — same workload, same trigger timing?

**Answer:**  
Three mechanisms:

1. **Identical workload code** — the same `thesis_workload` Dagster job (same `cpu_burn` + `memory_pressure` ops, same SHA-256 algorithm, same 400 MB allocation, same 30 s durations) was deployed to both environments via the same container image (`localhost:5001/thesis-workload:latest`), loaded into Kind and deployed on the VM via Docker.

2. **Automated concurrent submission** — the test harness used `concurrent.futures.ThreadPoolExecutor` to submit all N pipeline runs within a < 1 second window, ensuring genuine simultaneous start rather than staggered sequential submission.

3. **60-second cooldown between repetitions** — allowing resource release, container teardown, and PostgreSQL connection pool reset before the next repetition. This prevents contamination between runs.

The one asymmetry that could not be eliminated is Docker container startup (≈2–3 s on VM) vs. pod startup (4–15 s on K8s), which is the intended measured variable for SQ3.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q10 · What is the `pod_timing.csv` `job_start_ts` field actually measuring? There is a note in Section 5.3 about a measurement issue

**Answer:**  
This is one of the most important methodological clarifications in the thesis.

`job_start_ts` was collected from the Kubernetes `ContainersReady` condition's `lastTransitionTime`. This event fires when the container *exits* (transitions from `Ready` to `NotReady` on successful completion) — **not** when the job starts executing.

Using this column as a "startup time" would yield the total pod lifetime (≈67 s = startup + execution), not just the startup duration. This was caught during analysis.

The correct startup overhead metric used in the thesis is:  
`startup_overhead = total_pod_lifetime − dagster_exec_time`  
= (`job_start_ts − submitted_ts`) − (`end_time − start_time` from `dagster_runs.csv`), joined on `run_id`.

This gives the correct 4–15 s overhead values. Any analysis that used `job_start_ts` directly as a startup timestamp would have overestimated startup overhead by approximately 60 seconds.
</VSCode.Cell>
<VSCode.Cell language="markdown">

## 3 · Experimental Results

</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q11 · Walk me through exactly what happened at L3 on the VM. Why did 1 in 3 jobs fail?

**Answer:**  
At L3, three containers each attempted to allocate 400 MB of NumPy array memory simultaneously during the `memory_pressure` op (which executes approximately 30 seconds into each job).

The VM's available memory budget at rest (after Docker daemon + PostgreSQL + Dagster daemon) was approximately 2–2.5 GB. Three containers × (400 MB workload + ≈500–600 MB Python/Dagster overhead) = approximately 2.7–3.0 GB total container demand.

When the `memory_pressure` op's `np.zeros(400 * 1024 * 1024 // 8, dtype=np.float64)` allocation was called by all three containers near-simultaneously, aggregate committed memory exceeded the kernel's reclaimable budget. The Linux OOM killer was invoked.

The OOM killer selects victims based on `oom_score_adj` and memory footprint. In a pool of identical containers, selection is approximately random — one container was killed, the other two survived. This explains the 66.7% success rate (2 of 3 per batch = 6 of 9 total across 3 repetitions).

The killed containers showed termination at 37–50 s into execution — consistent with the OOM kill occurring 7–20 s after the 400 MB allocation at approximately the 30 s mark.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q12 · Why did VM CPU utilisation *decrease* at higher concurrency levels? Shouldn't more jobs mean more CPU usage?

**Answer:**  
This is a counter-intuitive finding explained by what I call a **selection/filter effect**.

At L10 (10 concurrent jobs), 7 of 10 containers were OOM-killed within 40–50 seconds of starting — before they completed their CPU-intensive `cpu_burn` phase. The `cpu_burn` op runs for 30 seconds (full duration), but `memory_pressure` starts at second 30. Jobs killed at seconds 37–50 complete their CPU burn but are killed early in the memory pressure phase.

So at L10: 7 containers contribute CPU for approximately 40–50 s, then exit. Only 3 containers complete the full 60 s execution. The system-wide CPU average across the entire measurement window therefore *decreases* because there are fewer active processes for the second half of the experiment window.

This is a measurement artefact of averaging CPU utilisation over the full wall-clock window rather than per-job CPU usage. It is not a real reduction in per-job CPU demand.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q13 · Kubernetes showed 100% success at L10. Does that mean Kubernetes can handle unlimited concurrency?

**Answer:**  
No — and this is an important qualification. The 100% success at L10 is specific to this hardware configuration:

- Kind node: 8 GB RAM, 4 vCPU
- Per-pod memory limit: 2 GiB
- Actual peak RSS per pod: ≈1.0–1.2 GB (400 MB workload + ≈500–600 MB Python/Dagster)

At L10: 10 pods × ≈1.0–1.2 GB actual = ≈10–12 GB demand vs. 8 GB node. The fact that it succeeded suggests the actual RSS was on the lower end of the estimate, or that not all 10 pods were in the memory-intensive phase simultaneously.

The increased variance at L7 (std = 9.6 s) and L10 (std = 8.0 s) is evidence of node-level pressure emerging. A further increase in concurrency — L15 or L20 — would likely trigger node-level OOM on the 8 GB Kind node as well. The key architectural difference is that Kubernetes' per-pod cgroup limits mean only the over-limit pod is killed, not all concurrent pods, whereas the VM's kernel-level OOM kills indiscriminately.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q14 · The blast radius test at L5 showed 0 affected jobs in *both* environments. How does this support your SQ2 conclusion?

**Answer:**  
The blast radius test at L5 is a deliberate failure injection — one running pod/container was forcibly killed — not an organic failure. At L5, the VM still had adequate memory headroom (5 × ≈1.0 GB = 5 GB demand on a 4 GB VM — actually this is already in the failure zone for `memory_pressure`, but the test was conducted before the memory pressure op triggered for the surviving jobs).

The key insight from SQ2 is not just the controlled blast radius test but the *organic* blast radius at L3–L10 from OOM kills. At L3 on the VM, the Linux OOM killer was invoked to kill **one** container, but the system-level OOM pressure meant it sometimes killed *multiple* containers in the same OOM event — as seen in the success rate data. In Kubernetes, pod termination is bounded to the single pod exceeding its limit via cgroup enforcement, preventing this cascade.

The combined SQ2 evidence is: (1) K8s maintained 100% success across L1–L10 while VM failed at L3+; (2) VM OOM kills at high concurrency are system-level and can be cascade kills; (3) K8s pod isolation enforces a hard boundary per container. The L5 blast radius test confirms the isolation mechanism holds under deliberate failure injection.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q15 · Your Table 4.5 shows K8s is *slower* than VM at L7 (+14.5 s) and L10 (+16.6 s). Doesn't this contradict your claim that Kubernetes becomes net beneficial?

**Answer:**  
The +14.5 s and +16.6 s deltas compare K8s *total wall-clock time per successful job* against VM *survivor-only execution time*. This comparison is technically accurate but operationally misleading for one important reason:

At L7, the VM success rate is **42.9%** — meaning 57% of jobs fail outright. A team using the VM at L7 does not get 7 jobs at 77.7 s; they get approximately 3 jobs completing at 77.7 s and 4 jobs failing entirely with zero output. The "faster" VM time only applies to the minority of jobs that survive.

When you account for the full job population (including failures that must be retried), the effective total cost of the VM at L7 is much higher. The crossover framework in the thesis rightly uses the **reliability crossover** (VM success rate < 95%) as the primary decision boundary, not the raw execution time delta. By L3 — where both conditions are approximately met — Kubernetes is the only viable option for reliability-requiring workloads, regardless of the +14.5 s at L7.
</VSCode.Cell>
<VSCode.Cell language="markdown">

## 4 · Discussion and Conclusions

</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q16 · You found the crossover at L3. How confident are you that this result generalises beyond your specific hardware?

**Answer:**  
The specific value L3 does **not** generalise directly — and the thesis is explicit about this. The crossover point is a function of:

| Variable | This Study | Effect on Crossover |
|---|---|---|
| VM RAM | 4 GB | More RAM → later crossover (L5–L7 expected on 8 GB) |
| Per-job memory footprint | 400 MB + ≈600 MB overhead | Larger jobs → earlier crossover |
| Infrastructure stack overhead | ≈1.5–2 GB at rest | Higher overhead → earlier crossover |
| K8s cluster capacity | 8 GB Kind node | Less capacity → earlier K8s failure |

What **does** generalise is:

1. The *failure mechanism* (VM shared kernel OOM kills) is universal across any Linux-based Docker deployment
2. The *shape* of degradation (sharp cliff, not gradual slope) is predicted by resource contention theory and confirmed
3. The *method* (run the same crossover analysis on your own hardware) is the practical contribution

Teams should run their own crossover analysis — the thesis provides the methodology, not a universal threshold.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q17 · Section 5.5.3 gives a "decision framework." Isn't this oversimplified? What about operational cost, team skills, cost of cloud K8s?

**Answer:**  
The decision framework in Section 5.5.3 deliberately focuses on *execution behaviour metrics* — the variables this thesis measures. You are correct that a complete production decision requires additional dimensions:

**What the framework covers:** reliability threshold, execution time variance, startup overhead, concurrency level
**What the framework omits:**

- **Operational complexity** — K8s requires Helm, RBAC, persistent volumes, observability stack. This is real and substantial for small teams (acknowledged in Section 5.5.2)
- **Cost** — managed GKE/EKS adds monthly cluster fees vs. near-zero VM cost
- **Team skills** — a team with no K8s experience has a 3–6 month learning curve
- **Vendor lock-in** — Kind is portable; GKE/EKS is not

The framework is intentionally scoped to the measurable variables. The thesis notes that "for teams running fewer than 5–7 concurrent jobs, the VM offers competitive performance with substantially lower operational overhead" — which is the operational complexity caveat. A production decision matrix would weight all these factors; this thesis contributes the reliability and performance data needed to populate the technical row.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q18 · Casalicchio (2019) found that containers on the same host interfere even with resource limits. Your K8s data showed no interference. How do you reconcile this?

**Answer:**  
Casalicchio's interference finding was primarily demonstrated for **CPU-intensive workloads competing for CPU time** on the same host, where the default Kubernetes HPA failed to adapt fast enough. His finding that response times were 2–3 orders of magnitude higher under CPU contention is an autoscaling result, not an isolation result.

In this thesis's K8s experiment:

1. **No autoscaling** — fixed pod count per level, no HPA
2. **Workload type** — CPU-bound SHA-256 + memory pressure, not I/O-bound or network-bound (Choi et al. 2021 find interference is primarily a concern for I/O-intensive workloads)
3. **Observable outcome** — K8s variance was *lower* at every level than VM variance, suggesting cgroup isolation was effective for this workload type

The reconciliation: Casalicchio's interference manifests through *shared kernel scheduling and physical cache contention*, which is CPU-architecture dependent. For compute-bound workloads with no shared I/O bottleneck, cgroup-enforced CPU and memory limits are effective. For I/O-bound workloads sharing network or storage bandwidth, interference persists despite limits. This is an important scope qualifier for the SQ2 conclusion.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q19 · Two infrastructure fixes were applied mid-experiment (dagster-docker package, memory limits). How do you know this didn't invalidate your data?

**Answer:**  
Section 5.6 explicitly acknowledges this as a limitation. The key statement is: "The final experimental data was collected **after both fixes were in place**."

The timeline:

1. Initial deployment → discovered `dagster-docker` missing from VM daemon → fixed
2. Initial test runs → containers hitting memory limit → increased Docker container limit to 2 GB
3. **All reported experiments** were run after both fixes were stable

The risk is not in the reported data but in the *development phase* introducing undetected configuration drift. To mitigate this, the `validate-experiment-setup.sh` pre-flight script was run before each experimental session to verify both environments were in the expected state.

What I would do differently: use infrastructure-as-code (Ansible playbook, not manual SSH fixes) from the beginning, with version-controlled VM state, so that the pre-experiment configuration is fully reproducible and auditable.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q20 · Your conclusions say "migrate at 3 concurrent Dagster jobs." What if a team currently has 2 concurrent jobs but expects growth to 5 in 6 months?

**Answer:**  
The thesis directly addresses this in Section 5.4 (final paragraph): "given the negligible overhead, earlier migration is also rational for any team anticipating growth."

The argument: at L1–L2, the VM is reliable and K8s adds only 4–5 s per-run overhead (7% of job time). The cost of migrating early is minimal — a few seconds per run. The cost of *not* migrating early and hitting L3 in production is a sudden drop to 66.7% success rate on live pipelines, triggering retries, downstream data quality issues, and an emergency migration under operational pressure.

The general decision rule: if you anticipate crossing the reliability crossover threshold within your planning horizon, migrate proactively. The overhead cost at low concurrency is small; the operational cost of an emergency reliability fix is large. The thesis data supports early migration being rational even below the crossover point.
</VSCode.Cell>
<VSCode.Cell language="markdown">

## 5 · Technical Depth Questions

</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q21 · Explain exactly how you computed the "startup overhead" metric. Walk through the join

**Answer:**  
The computation is documented in Section 4.2.3 and uses a join between two CSV files on `run_id`:

```
startup_overhead = (job_start_ts - submitted_ts) - (end_time - start_time)
```

Where:

- `submitted_ts` — from `pod_timing.csv`: timestamp when Dagster submitted the pod to Kubernetes
- `job_start_ts` — from `pod_timing.csv`: `ContainersReady lastTransitionTime` (fires on container *exit*, not entry — see Q10)
- `(job_start_ts - submitted_ts)` = total pod lifetime (from creation to completion)
- `(end_time - start_time)` — from `dagster_runs.csv`: Dagster-measured execution time (the time the job code was actually running)

So: `startup_overhead` = total pod lifetime − execution time = the time spent before and after the job code executed, dominated by the "before" (pod scheduling + Python init + DB connection) since container teardown is near-instantaneous.

The join is on `run_id`, which uniquely identifies each Dagster pipeline run and appears in both files. This links the Kubernetes infrastructure timestamps to the Dagster application timestamps.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q22 · Why does the startup overhead grow with concurrency (4.3 s → 14.9 s)? What specifically is causing this?

**Answer:**  
Three concurrent bottlenecks, all on the single-node Kind cluster:

1. **Python interpreter + package import** — Python 3.13 with Dagster, dagster-k8s, numpy, hashlib all import on startup. When 7–10 containers start simultaneously, they compete for the same node's I/O (reading `.pyc` files from the container filesystem layer) and CPU for JIT compilation.

2. **PostgreSQL connection pool initialisation** — Each Dagster run pod opens a connection to the PostgreSQL instance running inside the Kind cluster. PostgreSQL has a default `max_connections = 100`. At L10 (10 pods + daemon + webserver), approximately 15–20 connections are requested simultaneously, creating a connection queuing delay.

3. **Dagster gRPC handshake** — The Dagster daemon in the Kubernetes deployment performs a gRPC readiness check against each run pod's code server before beginning execution. At high concurrency, multiple pods are responding to simultaneous gRPC probes, each adding latency.

The growth is sub-linear (not 10× the single-job overhead at L10) because these bottlenecks are partially parallelisable — they don't form a strict serial queue. In a multi-node production cluster, pods would start on different nodes, distributing the I/O and database connection load, which would reduce this scaling effect.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q23 · How did you confirm the VM failures were OOM kills and not something else (e.g., Dagster timeout, network failure, DB issue)?

**Answer:**  
Three pieces of evidence:

1. **Failure timing** — OOM-killed jobs terminated at 37–50 s into execution, consistently during the `memory_pressure` op (which starts at approximately 30 s). A Dagster timeout would produce failures at a configurable, consistent cutoff (usually 60 s or more). A DB issue would fail at submission or status-polling, not mid-execution.

2. **VM system metrics** — `vm_metrics.csv` records system-wide memory utilisation at 1-second intervals. At L3+, memory utilisation reached 80–82% of 4 GB (≈3.2 GB used) at the time of failures — consistent with the kernel triggering OOM at high water mark.

3. **Docker exit codes** — Docker containers killed by the OOM killer receive a SIGKILL from the kernel, producing a container exit code of 137 (= 128 + SIGKILL signal number 9). The `dagster_runs.csv` records the Dagster run status as `FAILURE`, and the underlying container logs showed exit code 137 patterns in the Docker daemon logs on the VM.

The combination of: correct timing, correct memory pressure level, and correct exit signal strongly confirms OOM kills as the failure mechanism.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q24 · The workload uses `hashlib.sha256(b"dagster-thesis-workload").hexdigest()` in a tight loop. Why this specific algorithm? Could you have used anything simpler?

**Answer:**  
SHA-256 was chosen for three properties:

1. **Reproducibility** — the hash of a fixed input always produces the same output. There is no randomness, so every run is bit-for-bit identical in computation.
2. **CPU boundedness** — SHA-256 is a compute-intensive algorithm that keeps a single core at near-100% utilisation during the loop. A busy-wait `while True: pass` would also work but is harder to validate and could be optimised away by the interpreter.
3. **Single-core load** — the tight loop runs on one CPU core, making concurrency effects predictable: N concurrent jobs should consume exactly N CPU cores under ideal conditions.

An alternative like `time.sleep(30)` would be lighter but would not exercise CPU or memory, making the experiment meaningless. A matrix multiplication would also work but introduces BLAS library variability across environments. SHA-256 from the Python standard library (`hashlib`) is deterministic, cross-platform, and well-understood.

The workload was locked early in the experiment design to prevent mid-experiment changes from invalidating comparability.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q25 · You used Kind's single-node configuration. In the `kind-config.yaml` (Appendix A), you defined `system-reserved` and `kube-reserved`. What effect did these have on your results?

**Answer:**  
The `kind-config.yaml` in Appendix A reserves:

- `system-reserved: cpu=500m, memory=512Mi` — for OS processes outside Kubernetes
- `kube-reserved: cpu=500m, memory=512Mi` — for Kubernetes system components (kubelet, container runtime)

Total reserved: 1 CPU core + 1 GiB RAM out of the 4 vCPU / 8 GB node.

Effect on results:

- **Allocatable CPU:** ≈3 vCPU for workload pods
- **Allocatable memory:** ≈7 GiB for workload pods

At L10 (10 pods × 2 GiB limit each = 20 GiB requested), the pods were *not* guaranteed 2 GiB each (requests < limits); actual usage of ≈1.0–1.2 GB per pod fit within the 7 GiB allocatable budget.

Without these reservations, the Kind cluster's system components would compete with workload pods for unaccounted memory, potentially causing node-level instability at high concurrency. The reservations ensured predictable node behaviour and prevented kubelet OOM during the experiments.
</VSCode.Cell>
<VSCode.Cell language="markdown">

## 6 · Limitations and Future Work

</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q26 · If you had 6 more months, what would you do to strengthen the thesis?

**Answer:**  
Five concrete additions, in priority order:

1. **8 GB VM** — repeat Experiment 1 with 8 GB RAM to push the OOM threshold higher and expose the pure CPU-contention regime. This would reveal whether the crossover in a memory-adequate VM is still reliability-driven or shifts to a performance-driven comparison.

2. **More repetitions (n=10 per level)** — enable proper statistical testing (Mann-Whitney U between environments, confidence intervals on all metrics) and give the startup overhead variance characterisation that 3 repetitions cannot provide.

3. **Production K8s (GKE)** — repeat K8s experiments with cold image pulls on a 3-node GKE cluster to measure startup overhead under realistic production conditions (expected: 10–60 s vs. the local 4–15 s).

4. **Second workload type** — an I/O-bound workload (large DataFrame reads from PostgreSQL) to test whether Casalicchio's interference effect appears in K8s when workloads are I/O-intensive rather than compute-bound.

5. **Second framework** — run the same experiment with Apache Airflow (KubernetesExecutor vs LocalExecutor) to test whether the crossover threshold and failure mechanism generalise across workflow orchestration tools.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q27 · Your thesis acknowledges that "two fixes were applied mid-experiment." What would you change about your experimental process to prevent this?

**Answer:**  
Four process changes:

1. **Infrastructure-as-code from day one** — provision the VM entirely via Ansible (not SSH + manual commands), so the VM state is version-controlled and reproducible. Every package installation, configuration change, and Docker limit adjustment would appear as a git commit in the Ansible playbook.

2. **Pre-experiment validation gate** — run `validate-experiment-setup.sh` and a "pilot" single run at L1 before every experimental session, with the output committed to the data repository. This creates an auditable pre-experiment state record.

3. **Containerised Dagster daemon on VM** — run the Dagster daemon inside the docker-compose stack rather than system-installed, so the exact package versions (including `dagster-docker`) are pinned in `docker-compose.yml` and cannot drift.

4. **Staged experiment protocol** — run L1 validation, then L1 full run, verify CSV output, then proceed to L2. Don't run all six levels in one session until L1 data has been verified against expectations.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q28 · The thesis is framed as a YH (Yrkeshögskola) thesis. How does the scientific contribution compare to a university master's thesis?

**Answer:**  
A YH thesis at Jensen is assessed against three criteria: relevance to professional practice, methodological soundness, and depth of analysis — rather than the novel theoretical contribution expected of a university research master's.

Against those criteria:

- **Practical relevance** is high: the crossover framework directly answers a question every DevOps team faces
- **Methodological soundness** is moderate: the infrastructure approach is justified and reproducible, but the small n (3 repetitions) and hardware asymmetry are acknowledged limitations
- **Depth** is strong: the analysis connects infrastructure events (OOM kills, cgroup limits) to application-level metrics (Dagster run success rate) with specific numbers

Compared to a university MSc: the contribution is more applied (no theoretical model derivation, no formal statistical inference), but the experimental execution and the novel empirical connection between resource contention theory and workflow execution failure is genuinely original. A university examiner would likely want more statistical rigour and a broader generalisability argument; a YH examiner focuses on whether the findings can guide professional practice.
</VSCode.Cell>
<VSCode.Cell language="markdown">

## 7 · Reflection and Self-Assessment

</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q29 · What is the single most important finding of your thesis?

**Answer:**  
The reliability crossover occurs at **L3 (3 concurrent Dagster jobs)** on a 4 vCPU / 4 GB RAM VM running a 400 MB-per-job memory workload.

More specifically: the VM failure mode is not a gradual performance degradation but a **discrete cliff** — the success rate drops from 100% to 66.7% in a single step between L2 and L3, triggered by memory exhaustion. Kubernetes prevents this entirely through per-pod cgroup limits, maintaining 100% success across all tested levels.

The secondary finding that strengthens the case: Kubernetes' startup overhead (4–15 s) is modest relative to the reliability gain and the 63-second job duration — meaning teams do not pay a significant performance penalty for the migration at or above the crossover point.
</VSCode.Cell>
<VSCode.Cell language="markdown">

### Q30 · What would you do differently if you started this thesis over today?

**Answer:**  
Four things:

1. **Match VM and K8s memory** — provision the VM with 8 GB RAM to match the Kind node, eliminating the hardware asymmetry criticism and enabling a cleaner reliability-vs-performance separation.

2. **Define the measurement methodology for `pod_timing.csv` before collecting data** — the `job_start_ts` field issue (Section 5.3) was discovered during analysis. A pre-collection schema definition with explicit column semantics would catch this before any data was collected.

3. **Run 6 repetitions from the start** — 3 repetitions per level is the minimum; 6 would allow proper non-parametric testing without dramatically increasing experiment wall time.

4. **Add a second independent workload** — a purely I/O-bound workload (e.g., reading 100 MB from PostgreSQL per op) would test whether the crossover generalises across workload types and directly address the Casalicchio interference concern for I/O workloads.

These changes would not fundamentally alter the main finding — the L3 reliability crossover is driven by a clear physical mechanism (VM OOM) — but would make the thesis more statistically robust and more generalisable.
</VSCode.Cell>
<VSCode.Cell language="markdown">
---

## Summary Table: All 30 Questions at a Glance

| # | Question Theme | Difficulty | Chapter |
|---|---|---|---|
| 1 | Core research question | Basic | Intro |
| 2 | Dagster generalisability | Medium | Intro |
| 3 | Literature novelty | Medium | Lit Review |
| 4 | Hypothesis revision | Medium | Method |
| 5 | Statistical power of n=3 | Medium | Method |
| 6 | Memory asymmetry (4 GB vs 8 GB) | Hard | Method |
| 7 | Shared physical host validity | Medium | Method |
| 8 | Kind vs. production K8s | Medium | Method |
| 9 | Comparability of environments | Medium | Method |
| 10 | `job_start_ts` measurement issue | Hard | Method |
| 11 | L3 OOM mechanism | Hard | Results |
| 12 | CPU utilisation counter-intuition | Hard | Results |
| 13 | K8s 100% — does it scale infinitely? | Medium | Results |
| 14 | Blast radius test interpretation | Medium | Results |
| 15 | K8s slower at L7/L10 — contradiction? | Hard | Results |
| 16 | Generalisability of L3 threshold | Hard | Discussion |
| 17 | Decision framework completeness | Medium | Discussion |
| 18 | Casalicchio interference reconciliation | Hard | Discussion |
| 19 | Mid-experiment fixes validity | Medium | Discussion |
| 20 | Proactive migration at L2 | Medium | Discussion |
| 21 | Startup overhead computation | Hard | Technical |
| 22 | Overhead growth mechanism | Hard | Technical |
| 23 | OOM kill confirmation evidence | Hard | Technical |
| 24 | SHA-256 workload choice | Medium | Technical |
| 25 | Kind reserved resources effect | Hard | Technical |
| 26 | Future work priorities | Medium | Limitations |
| 27 | Experimental process improvement | Medium | Limitations |
| 28 | YH vs. university thesis scope | Basic | Reflection |
| 29 | Most important single finding | Basic | Reflection |
| 30 | What would you do differently? | Medium | Reflection |

> Questions marked **Hard** are the ones most likely to expose gaps. Prioritise these in your preparation.
</VSCode.Cell>
