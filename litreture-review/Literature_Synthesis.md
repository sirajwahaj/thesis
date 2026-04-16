# Literature Synthesis for Thesis: "When Does Kubernetes Become Worth It?"

**Thesis focus:** Measuring the crossover point at which migrating workflow orchestration (Dagster) from a shared-VM process executor to isolated Kubernetes pod execution on GKE becomes net beneficial, based on reliability, stability, and execution performance under increasing concurrent workload.

**Papers analyzed:**

| ID | Paper | Year | Authors |
|----|-------|------|---------|
| P1 | "Resource Contention in Shared-Memory Multiprocessors: A Parameterized Performance Degradation Model" | 1991 | Nanda, Shing, Tzen & Ni |
| P2 | "Shared Resource Contention-Aware Schedulability Analysis of Hard Real-Time Systems" (PhD Thesis) | 2023 | Arora |
| P3 | "A Study on Performance Measures for Auto-Scaling CPU-Intensive Containerized Applications" | 2019 | Casalicchio |
| P4 | "Horizontal Pod Autoscaling in Kubernetes for Elastic Container Orchestration" | 2020 | Nguyen, Yeom, Kim, Park & Kim |
| P5 | "A Survey of Autoscaling in Kubernetes" | 2022 | Tran, Vu & Kim |
| P6 | "Performance Evaluation of Container Orchestration Tools in Edge Computing Environments" | 2023 | Čilić, Krivić, Podnar Žarko & Kušek |
| P7 | "A Time Series-Based Approach to Elastic Kubernetes Scaling" | 2024 | Yuan & Liao |
| P8 | "pHPA: A Proactive Autoscaling Framework for Microservice Chain" | 2021 | Choi, Park, Lee & Han |
| P9 | "Harmonizing Efficiency and Practicability: Optimizing Resource Utilization in Serverless Computing with Jiagu" | 2024 | Liu et al. (USENIX ATC) |
| P10 | "Energy-Aware Elastic Scaling Algorithm for Microservices in Kubernetes Clouds" | 2025 | Li, Rao, Hu, Tian & Shen |

---

## 1. Core Theoretical Concepts (Grouped Across Papers)

### 1.1 Resource Contention and Non-Linear Performance Degradation

Resource contention occurs when multiple concurrent processes compete for the same finite shared resources — CPU cycles, memory bandwidth, cache lines, or I/O channels. The defining characteristic of contention, critical to your thesis, is that **performance degradation is non-linear**: it does not scale proportionally with load but instead accelerates disproportionately as resource utilisation approaches capacity limits.

Nanda et al. (P1) provide the foundational empirical framework for this phenomenon. They introduce two normalised metrics — *efficiency* and *overhead factor* — to quantify the gap between ideal parallel speedup and actual performance when concurrent processes share memory resources. Their key finding is that as the number of concurrent processes increases, contention for shared memory introduces queuing delays that compound multiplicatively, not additively. Even hardware-level contention at the interconnection network or bus creates delays that propagate through the entire execution. The study demonstrates this on real multiprocessor systems (BBN Butterfly, Sequent Balance), establishing that **contention-induced overhead can be decomposed into identifiable components**: software synchronisation overhead, lock contention, and hardware memory access contention.

Arora (P2) extends contention analysis to the domain of multicore processors with shared caches, memory buses, and main memory. The dissertation demonstrates that shared resource contention is inherently **non-deterministic** — it can influence the temporal behaviour of tasks in unpredictable ways. A task executing on one core must compete with co-running tasks on other cores for access to shared resources, and this competition makes worst-case execution time analysis extremely difficult. The work shows that contention depends not only on the number of concurrent tasks but also on memory access patterns, cache behaviour, and bus arbitration policies. Critically for your thesis, Arora demonstrates that **the impact of contention is not merely a throughput reduction — it can cause timing violations** that cascade through dependent tasks.

Casalicchio (P3) brings contention theory directly into the container and Kubernetes domain. When multiple container instances run on the same host, they generate "interference in the contention of physical resources." The paper demonstrates that under concurrent workloads with CPU utilisation above 75%, response times under the default Kubernetes Horizontal Pod Autoscaler (KHPA) are **2 to 3 orders of magnitude higher** than those achievable with a contention-aware algorithm (KHPA-A). This finding directly supports your thesis: when containers share a host, resource contention produces extreme performance degradation that standard scaling algorithms fail to mitigate.

**Synthesis for your thesis:** The literature establishes a clear theoretical and empirical basis for why a shared-VM executor collapses under concurrent workload. Contention is non-linear, non-deterministic, and produces cascading failures. These properties are architecture-independent — they apply whether the shared resource is a multiprocessor's memory bus (P1, P2) or a single VM's CPU and memory pool (P3). Your thesis extends this by measuring the specific concurrency threshold at which this collapse occurs for Dagster pipeline workloads.

---

### 1.2 Fault Isolation and Blast Radius

Fault isolation is a foundational principle of distributed systems: failures should be contained within the smallest possible boundary. The *blast radius* refers to the scope of a system affected by a single failure event.

In shared execution environments, the blast radius of any individual failure is potentially the entire system. The literature on resource contention (P1, P2) implicitly demonstrates this: when processes share resources, one process's excessive consumption degrades all co-running processes. In hardware terms, a task that saturates the memory bus creates contention for all tasks on all cores (P2). In software terms, a process that exhausts available memory on a VM can trigger an out-of-memory (OOM) kill that terminates the process executor and all currently running jobs.

Kubernetes pod isolation addresses this architecturally. Each pod runs with enforced resource limits (CPU requests/limits, memory requests/limits), and the OOM killer terminates individual pods without directly affecting other pods on the same node. Čilić et al. (P6) evaluate container orchestration tools and confirm that Kubernetes's scheduling architecture assigns workloads to nodes based on available resources and container-specific requirements, providing a framework for resource isolation. The paper notes that automated orchestration is essential precisely because manual management of dynamic distributed workloads "becomes complex and should be avoided."

However, the literature also reveals that **pod isolation is not absolute**. Casalicchio (P3) demonstrates that containers on the same host still generate interference through physical resource contention even when they have defined resource limits. The relative CPU utilisation metric used by Kubernetes can mask actual resource saturation — containers may report 50% utilisation while the underlying CPU is fully saturated. This means that while Kubernetes reduces blast radius compared to bare process sharing, it does not eliminate contention effects entirely when pods are colocated on the same node.

**Synthesis for your thesis:** The literature provides strong theoretical support for why Kubernetes pod isolation should reduce blast radius compared to shared-VM execution. However, it also cautions that isolation is not complete — pods on the same node still contend for physical resources. Your thesis empirically tests whether this theoretical isolation holds at the workflow execution level, measuring whether one failing Dagster pipeline job actually avoids degrading other concurrently running jobs.

---

### 1.3 Scheduling Overhead and Execution Latency in Kubernetes

Kubernetes introduces multiple layers of overhead that do not exist in native VM process execution. The literature identifies several distinct components:

**Pod scheduling latency:** The time between a job being submitted and a pod being assigned to a node. Liu et al. (P9) report that scheduling latency is a critical bottleneck in serverless environments. Their JIAGU system demonstrates that machine-learning-based scheduling decisions can add ~20ms or more per scheduling event — and this becomes a "new bottleneck" when container initialisation has been optimised to <1ms.

**Container startup latency:** The time between pod assignment and the first application instruction executing. Choi et al. (P8) cite Google Borg data showing that the **median container startup latency is 25 seconds**, with 90th-percentile microservice startup latency at approximately 15 seconds even with state-of-the-art schedulers. This is a substantial fixed cost for every pipeline job in a Kubernetes Run Launcher model.

**Cold start overhead:** Yuan & Liao (P7) demonstrate that reactive scaling mechanisms in Kubernetes trigger scaling operations only when metrics reach certain thresholds, which "results in response delays and can impact the stability of the business, and can even lead to large-scale service interruptions." Their predictive scaling approach reduced cold start time by 1 hour and 41 minutes in their test scenario, indicating the magnitude of potential delay in purely reactive systems.

**Control plane communication overhead:** Kubernetes introduces network namespace isolation costs and control plane API communication overhead that do not exist in native VM execution (P3, P6). For short-duration jobs, these fixed costs represent a proportionally larger fraction of total execution time.

**Synthesis for your thesis:** The literature consistently documents that Kubernetes introduces measurable overhead at every stage of the execution lifecycle. For your thesis, this means the GKE deployment will always be slower than the VM for individual jobs at low concurrency. The central question your thesis answers — *at what concurrency level does this overhead become smaller than the contention penalty on the VM?* — requires exactly the kind of empirical measurement the literature lacks.

---

### 1.4 Autoscaling Behaviour and Response Latency

Autoscaling in Kubernetes involves three mechanisms: Horizontal Pod Autoscaler (HPA), Vertical Pod Autoscaler (VPA), and Cluster Autoscaler (CA). The literature extensively documents that **autoscaling is not instantaneous**, creating a reaction window during which submitted workloads are unprotected.

Nguyen et al. (P4) provide a comprehensive empirical analysis of HPA's operational behaviour. They investigate the difference between Kubernetes Resource Metrics (KRM) and Prometheus Custom Metrics (PCM) and their effect on HPA performance. Their work reveals that HPA's scaling decisions are sensitive to metric scraping periods, cluster size, and the type of metric used — knowledge that is "not available on the official website and other sources." They find that default Resource Metrics are limited to CPU and memory usage of pods and host machines, which may be insufficient for complex workload patterns.

Tran et al. (P5) survey the state of the art in Kubernetes autoscaling and identify fundamental limitations of default HPA: it has "slow adaptation performances against dynamic workloads." They categorise solutions into reactive and proactive approaches, noting that reactive autoscaling (the default) only triggers scaling when thresholds are exceeded, creating an inherent lag. Proactive approaches using machine learning can predict demand but introduce their own complexity and overhead.

Choi et al. (P8) demonstrate that the provisioning time problem compounds in microservice chains: "the further a microservice is located at the back of the chain, the slower it will perceive changes in the workload." Their pHPA framework reduces 99th-percentile latency by up to 70% compared to the default Kubernetes autoscaler during traffic surges. They report that creating microservice instances "involves accessing a file system to fetch system libraries and data files and takes up to tens of seconds."

Li et al. (P10) identify an additional problem: Kubernetes default scaling mechanisms "fail to effectively distinguish and manage resource consumption of idle containers, leading to resource waste and degraded system performance." Idle containers continue consuming resources and create cold start delays when scaling up is needed.

**Synthesis for your thesis:** The literature establishes that autoscaling latency is a real, measurable phenomenon with significant impact on job-level outcomes. For your SQ3 (Autoscaling Response Speed), the literature predicts that during the scale-out window, jobs will be delayed or fail. Your contribution is measuring this window specifically for Dagster pipeline workloads on GKE, under a defined spike scenario — something no existing study has done.

---

### 1.5 Workload-Dependent System Behaviour

A critical insight across the literature is that **the relative advantage of different execution models is not absolute but depends on workload characteristics.**

Casalicchio (P3) demonstrates that the discrepancy between relative and absolute CPU metrics — and thus the failure of default autoscaling — is most severe under high-load conditions (>75% absolute CPU utilisation) with concurrent workloads. Under single-instance, low-load scenarios, the difference is negligible. This directly supports your hypothesis that the VM may outperform GKE at low concurrency.

Yuan & Liao (P7) show that Kubernetes scaling effectiveness depends on workload predictability: their time-series forecasting approach works well for workloads with regular patterns but less so for unpredictable spikes. This suggests that the crossover point may shift depending on workload regularity.

Li et al. (P10) confirm that "elastic scaling algorithms have become fundamental to cloud computing, enabling dynamic resource allocation to meet fluctuating workloads." However, default mechanisms "often fail to address the nuances of microservices architectures, leading to inefficiencies." This workload-specificity of system behaviour is exactly what your thesis measures.

Liu et al. (P9) demonstrate a 54.8% improvement in deployment density over commercial Kubernetes clouds while maintaining QoS, but only through sophisticated scheduling that decouples prediction from decision-making. The default Kubernetes scheduler does not achieve these benefits.

**Synthesis for your thesis:** The literature strongly supports your core premise that system behaviour is workload-dependent. No paper claims Kubernetes is universally superior. Your thesis formalises this through the crossover point — making the workload-dependence measurable rather than assumed.

---

## 2. How the Literature Explains Your Problem

### 2.A Why Single-VM Systems Fail Under Concurrency

The literature provides a three-layer explanation:

1. **Hardware-level contention is fundamental and unavoidable.** Nanda et al. (P1) demonstrate that when concurrent processes share memory resources, queuing delays arise at the hardware interconnection level. These delays are a function of the number of concurrent accessors and cannot be eliminated by software design alone. On a single VM running Dagster's process executor, all pipeline jobs share the same CPU cache hierarchy, memory bus, and physical memory — exactly the conditions studied in P1 and P2.

2. **Contention effects are non-linear and cascading.** Arora (P2) proves that shared resource contention can influence task timing in non-deterministic ways, making worst-case analysis extremely pessimistic. In your Dagster context, this means adding one additional concurrent pipeline job beyond the VM's capacity does not produce a proportional performance decrease — it can produce a cascading failure where the orchestration process itself is terminated.

3. **Standard monitoring metrics mask the severity of the problem.** Casalicchio (P3) demonstrates that Kubernetes's relative CPU utilisation metrics underestimate actual resource saturation. In a VM context, this means that monitoring tools may report acceptable utilisation levels (e.g., 50% CPU) when the underlying hardware is fully saturated, because the metric reflects the *share* rather than the *absolute* utilisation. By the time the problem is visible in monitoring, the system may already be in collapse.

→ **Connection to your system:** Your SQ1 measures exactly the concurrency level at which this collapse occurs for Dagster pipeline workloads. The literature predicts the collapse will be sudden (non-linear), not gradual, and that standard metrics may not provide adequate warning.

---

### 2.B Why Isolation (Kubernetes) Should Improve Reliability

The literature supports the reliability improvement hypothesis through several mechanisms:

1. **Resource limits enforce boundaries.** In the Kubernetes pod model, each pipeline job runs with defined CPU and memory limits. Čilić et al. (P6) confirm that Kubernetes's scheduling assigns workloads to nodes based on available resources and container-specific requirements. Unlike the shared VM model where the process executor is a single point of failure, each Dagster pod is an independent failure domain.

2. **OOM kills are contained.** When a Dagster job exhausts its pod's memory limit, the OOM killer terminates only that pod. In the VM model, the same event can terminate the entire process executor. This is the theoretical blast radius reduction your SQ2 tests.

3. **Horizontal scaling adds capacity.** The HPA and Cluster Autoscaler can add pods and nodes to absorb workload spikes. Tran et al. (P5) and Nguyen et al. (P4) confirm that these mechanisms, while imperfect, provide a capability that simply does not exist in a fixed-capacity VM deployment.

→ **Connection to your system:** Your SQ2 directly tests whether pod isolation contains failures in practice at the workflow execution level, not just at the infrastructure level where existing studies operate.

---

### 2.C Why Kubernetes Introduces Overhead and Trade-offs

The literature is unambiguous that Kubernetes adds measurable cost:

1. **Container startup is slow.** Choi et al. (P8) report 25-second median container startup from Google Borg data. For each Dagster pipeline run dispatched to GKE, this represents a fixed cost that does not exist on the VM, where the process executor spawns local processes in milliseconds.

2. **Scheduling is not free.** Liu et al. (P9) show that scheduling decisions can take 20ms+ with model-based approaches, and the default Kubernetes scheduler uses heuristic policies that are fast but suboptimal. Combined with pod creation, node selection, image pulling, and container initialisation, the total overhead can be tens of seconds per job.

3. **Reactive autoscaling has inherent lag.** Yuan & Liao (P7), Tran et al. (P5), and Choi et al. (P8) all document that default Kubernetes autoscaling is reactive — it triggers only after thresholds are exceeded. This creates a window where jobs are submitted but cannot be scheduled because capacity has not yet been provisioned.

4. **Idle resources waste energy and capacity.** Li et al. (P10) demonstrate that Kubernetes fails to distinguish active from idle containers, causing ongoing resource consumption even when containers are not processing work. For Dagster workloads that are bursty, this means GKE may maintain over-provisioned resources between pipeline runs.

→ **Connection to your system:** Your SQ4 quantifies this overhead at each concurrency level and computes the crossover point where it becomes smaller than the contention penalty on the VM.

---

### 2.D Why System Behaviour Is Workload-Dependent (Not Absolute)

The literature consistently shows that the relative advantage of any architecture depends on workload characteristics:

- At **low concurrency**, the VM has no contention penalty and no scheduling overhead. Casalicchio (P3) shows that single-instance workloads see negligible difference between relative and absolute metrics, meaning contention is not yet a factor.
- At **moderate concurrency**, contention begins but may not yet reach collapse thresholds. The overhead of Kubernetes pod creation may still exceed the contention penalty.
- At **high concurrency**, the VM enters non-linear collapse territory (P1, P2, P3) while Kubernetes distributes workload across pods and nodes. The fixed overhead of pod scheduling becomes proportionally smaller relative to total execution time.

No paper in the literature tests all three regimes with a single system under controlled conditions. **This is exactly the gap your thesis fills.**

---

## 3. What Is Missing in Existing Research (Research Gap)

### What researchers already understand well:

- **Resource contention theory** is well-established. The non-linear, cascading nature of contention under shared resources is thoroughly documented (P1, P2).
- **Kubernetes autoscaling behaviour** at the infrastructure level is well-characterised. HPA, VPA, and CA mechanisms are understood, and their limitations (reactive lag, metric sensitivity) are documented (P3, P4, P5, P7).
- **Container overhead** relative to VMs and bare metal is measured at the infrastructure level (P3, P6, P9).
- **Proactive scaling strategies** using ML/time-series methods can reduce autoscaling lag (P7, P8).
- **Energy and resource efficiency** of scaling algorithms can be optimised (P10).

### What researchers do NOT measure or quantify:

1. **No workload-based crossover analysis.** No paper in the reviewed literature identifies a specific concurrency threshold at which migrating from shared execution to isolated Kubernetes execution becomes net beneficial. Studies compare architectures in isolation (VM performance studies vs. Kubernetes performance studies) but do not measure the *same workload* on *both architectures* across a range of concurrency levels to find the inflection point.

2. **No application-level workflow measurement.** All Kubernetes studies (P3, P4, P5, P6, P7, P8, P9, P10) measure infrastructure-level metrics: pod scheduling latency, CPU utilisation, response time of HTTP services, container startup time. None measures the impact on application-level pipeline orchestration outcomes: job success rate, execution time variance across repeated pipeline runs, failure blast radius at the DAG execution level.

3. **No Dagster or pipeline-specific studies.** The workflow orchestration domain (DAG-based pipeline systems like Dagster, Airflow, Prefect) has no empirical study that compares execution models under controlled workload conditions. Existing orchestration research focuses on scheduling algorithms and DAG optimisation, not on the infrastructure-level execution model.

4. **No real-system measurement under controlled workload progression.** Resource contention theory (P1, P2) uses artificial workloads on specialised hardware. Kubernetes studies (P3, P4, P6) use synthetic HTTP benchmarks or CPU stress tests. No study uses realistic pipeline workloads with defined concurrency levels (e.g., 1, 5, 10, 20 concurrent jobs) on production-grade infrastructure.

5. **No combined measurement of all four pillars.** The literature treats contention, overhead, autoscaling, and fault isolation as separate research domains. No study connects all four to show how they interact under increasing workload in a single system.

### Why your thesis is needed:

> Your thesis occupies the intersection of four independently studied phenomena — resource contention, Kubernetes overhead, autoscaling latency, and fault isolation — and connects them at the application-level workflow execution layer under controlled concurrent workload conditions. The primary contribution (the crossover point) fills a specific, clearly identifiable gap: no existing study provides engineers with a data-backed answer to "at what workload level does the Kubernetes migration become worth it for pipeline orchestration systems?"

---

## 4. How to Use These Papers in Your Thesis

### 4.1 Citation Mapping

| Concept | Papers to Cite | Thesis Section |
|---------|---------------|----------------|
| Resource contention fundamentals | P1, P2 | Background (Pillar 1) |
| Non-linear performance degradation | P1, P2, P3 | Background (Pillar 1), Discussion of SQ1 |
| Container overhead vs. VMs | P3, P6, P9 | Background (Pillar 2) |
| Pod scheduling latency | P8, P9 | Background (Pillar 2), Discussion of SQ4 |
| HPA operational behaviour | P4, P5 | Background (Pillar 3) |
| Autoscaling lag and reactive limitations | P5, P7, P8 | Background (Pillar 3), Discussion of SQ3 |
| Proactive scaling improvements | P7, P8, P10 | Literature Review |
| Container orchestration in distributed environments | P6 | Literature Review |
| Energy-aware and SLA-based scaling | P10 | Literature Review |
| Overcommitment and QoS trade-offs | P9 | Literature Review, Discussion of SQ4 |
| Fault isolation / blast radius (theoretical basis) | P2, P6 | Background (Pillar 4) |
| Workload-dependent performance | P3, P7, P10 | Discussion, Crossover Point Analysis |

### 4.2 Placement Guidance

**Background (Chapter 2, Theoretical Pillars):**
- Use P1 and P2 for Pillar 1 (Resource Contention) — they provide the foundational theory
- Use P3, P9 for Pillar 2 (Kubernetes Overhead) — they measure container-level overhead
- Use P4, P5, P8 for Pillar 3 (Autoscaling) — they characterise HPA behaviour and limitations
- Use P6 and the isolation principles from P2 for Pillar 4 (Fault Isolation)

**Literature Review (positioning and gap identification):**
- Use P5 (survey) to demonstrate the breadth of autoscaling research and its infrastructure-level focus
- Use P7 and P10 to show recent innovations in scaling that still don't address pipeline workloads
- Use P8 to show that even advanced proactive scaling doesn't address the VM-to-K8s crossover question

**Discussion (Chapter 5):**
- Use P1/P2 when discussing your SQ1 results — connect your measured failure threshold to contention theory
- Use P3 when discussing why standard metrics may have masked contention in the VM
- Use P8/P9 when discussing your SQ4 overhead measurements — compare your measured pod scheduling latency to literature values
- Use P4/P5 when discussing your SQ3 autoscaling results — compare your measured reaction window to documented HPA behaviour

### 4.3 Example Sentences for Thesis Writing

**For Pillar 1 (Resource Contention):**
> "Previous research has established that resource contention in shared-memory systems produces non-linear performance degradation, where the overhead from concurrent resource access compounds multiplicatively as utilisation approaches capacity limits (Nanda et al., 1991). Arora (2023) further demonstrates that this contention is non-deterministic, influencing task timing in unpredictable ways that make worst-case analysis extremely challenging."

**For Pillar 2 (Kubernetes Overhead):**
> "Casalicchio (2019) demonstrates that under concurrent workloads with CPU utilisation above 75%, the response time degradation under Kubernetes' default horizontal pod autoscaling is 2 to 3 orders of magnitude greater than under a contention-aware algorithm, highlighting the severity of shared-resource interference even in containerised environments."

> "Liu et al. (2024) report that scheduling latency in Kubernetes-based systems represents a significant bottleneck, particularly for short-duration workloads where fixed overhead constitutes a large fraction of total execution time."

**For Pillar 3 (Autoscaling):**
> "Choi et al. (2021) report that the median container startup latency in Google Borg is 25 seconds, with 90th-percentile microservice startup latency at approximately 15 seconds. This provisioning time creates a reaction window during which submitted jobs cannot be scheduled, a phenomenon that default reactive autoscalers fail to anticipate (Tran et al., 2022; Yuan & Liao, 2024)."

**For the Research Gap:**
> "While existing studies have independently characterised resource contention (Nanda et al., 1991; Arora, 2023), Kubernetes overhead (Casalicchio, 2019; Liu et al., 2024), autoscaling latency (Nguyen et al., 2020; Choi et al., 2021), and fault isolation principles (Čilić et al., 2023), no empirical study has connected these four dimensions at the application-level workflow execution layer to identify the specific workload threshold at which a Kubernetes migration becomes net beneficial."

**For Discussion:**
> "The non-linear contention collapse predicted by queueing theory (Nanda et al., 1991) and confirmed in multicore systems (Arora, 2023) manifests in our experimental results as [describe your SQ1 findings], validating that the shared VM executor's failure mode is fundamentally architectural rather than configuration-dependent."

---

## 5. Key Quotes / Ideas Worth Referencing

### Idea 1: Non-linear contention degradation
**Source:** Nanda et al. (P1)
**Paraphrase:** When concurrent processes share memory resources, the performance degradation is not proportional to the number of processes — it compounds disproportionately due to queuing delays at shared hardware resources, and this degradation can be decomposed into identifiable overhead components.
**Use in thesis:** SQ1 discussion, explaining why VM failure is sudden rather than gradual.

### Idea 2: Non-deterministic temporal behaviour under contention
**Source:** Arora (P2)
**Paraphrase:** Shared resource contention can influence the timing behaviour of tasks in a non-deterministic manner, making it extremely challenging to provide safe bounds on execution time when multiple tasks share hardware resources.
**Use in thesis:** Pillar 1 background, explaining why execution time variance is a key metric.

### Idea 3: Orders-of-magnitude response time inflation
**Source:** Casalicchio (P3)
**Paraphrase:** Under concurrent container workloads with high CPU utilisation, the default Kubernetes autoscaling algorithm produces response times 2 to 3 orders of magnitude higher than a contention-aware algorithm, because relative CPU metrics underestimate actual resource saturation.
**Use in thesis:** Pillar 1 and Pillar 2 background; SQ4 discussion on why standard metrics fail.

### Idea 4: 25-second median container startup
**Source:** Choi et al. (P8), citing Google Borg data
**Paraphrase:** Production container orchestration systems exhibit a median container startup latency of 25 seconds, with 90th-percentile startup at ~15 seconds. This provisioning delay propagates through dependent service chains.
**Use in thesis:** Pillar 2 background; SQ4 overhead measurement comparison.

### Idea 5: Reactive autoscaling's inherent lag
**Source:** Tran et al. (P5), Yuan & Liao (P7)
**Paraphrase:** Default Kubernetes autoscaling has slow adaptation to dynamic workloads because it triggers scaling only after metrics exceed thresholds. This reactive approach creates a temporal gap during which newly submitted workloads are unprotected.
**Use in thesis:** Pillar 3 background; SQ3 autoscaling response discussion.

### Idea 6: Predictive scaling reduces cold start by >1 hour
**Source:** Yuan & Liao (P7)
**Paraphrase:** Compared to purely reactive HPA, a predictive auto-scaling approach based on time-series forecasting reduced cold start time by 1 hour and 41 minutes and reduced service quality fluctuation by 83.3%, demonstrating the magnitude of reactive scaling's performance cost.
**Use in thesis:** Pillar 3 background, illustrating the scale of the autoscaling problem.

### Idea 7: Default scaling mechanisms miss idle container waste
**Source:** Li et al. (P10)
**Paraphrase:** Kubernetes' default scaling mechanisms fail to distinguish between active and idle containers, causing ongoing resource consumption that increases cold start latency and degrades overall system performance for active workloads.
**Use in thesis:** Discussion of overhead trade-offs; SQ4 analysis.

### Idea 8: Scheduling as a new bottleneck
**Source:** Liu et al. (P9)
**Paraphrase:** With container initialisation optimised to sub-millisecond levels, scheduling latency (~20ms or more for model-based approaches) has become a new bottleneck. Commercial clouds still use heuristic scheduling that fails to accurately predict performance, limiting resource utilisation improvement.
**Use in thesis:** Pillar 2 background; SQ4 overhead discussion.

### Idea 9: Kubernetes achieves 54.8% higher density with optimised scheduling
**Source:** Liu et al. (P9)
**Paraphrase:** With sophisticated overcommitment and dual-staged scaling, a serverless system can achieve 54.8% higher deployment density than standard Kubernetes while maintaining QoS — but this requires significant engineering beyond Kubernetes defaults.
**Use in thesis:** Discussion — contextualising that your GKE tests use default Kubernetes, not optimised configurations.

### Idea 10: Edge orchestration confirms scheduling overhead reality
**Source:** Čilić et al. (P6)
**Paraphrase:** Empirical evaluation of container orchestration tools in real network environments (not simulations) shows that Kubernetes and its distributions have potential for effective scheduling across distributed resources, but "some challenges still have to be addressed" for dynamic execution environments.
**Use in thesis:** Literature review — supporting the need for real-system measurement.

---

## 6. Critical Thinking

### 6.1 Limitations of the Reviewed Papers

**P1 (Nanda et al., 1991):**
- Published over 30 years ago using hardware (BBN Butterfly, Sequent Balance) that bears little resemblance to modern cloud VMs or Kubernetes clusters
- Uses artificial replicate workloads, not realistic application workloads
- *However:* The theoretical principles of contention-induced non-linear degradation remain valid regardless of hardware generation

**P2 (Arora, 2023):**
- Focused on hard real-time systems with strict timing constraints — a fundamentally different domain than workflow orchestration
- Analysis is primarily theoretical/analytical, not experimental on cloud infrastructure
- *However:* The formalisation of shared resource contention as non-deterministic and the demonstration of cascading timing effects is directly applicable to your thesis's contention theory

**P3 (Casalicchio, 2019):**
- Tests only CPU-intensive workloads; does not evaluate memory-intensive or I/O-bound workloads typical of data pipelines
- Uses a single virtual machine as the host — does not test multi-node clusters or GKE
- The KHPA-A algorithm proposed is not available in standard Kubernetes; findings about default KHPA's limitations are directly useful, but the solution is not applicable to your setup

**P4 (Nguyen et al., 2020):**
- Tests HPA behaviour in a controlled lab environment, not a production cloud
- Does not measure application-level outcomes (job success, execution variance) — only infrastructure metrics
- Does not compare VM vs. Kubernetes execution

**P5 (Tran et al., 2022):**
- Survey paper without original experimental data
- Categorises existing approaches but does not validate them under controlled conditions
- Does not address pipeline orchestration workloads

**P6 (Čilić et al., 2023):**
- Focused on edge computing environments, which have different constraints (network latency, device heterogeneity) than cloud-based GKE
- Acknowledges that most existing results are based on simulations, and their own work aims to use real network environments — yet their specific testbed conditions differ from GKE

**P7 (Yuan & Liao, 2024):**
- Tests only a single RESTful HTTP application; not representative of batch pipeline workloads
- The predictive scaling approach (Holt-Winter, GRU) requires historical workload patterns that may not exist for ad-hoc pipeline triggering

**P8 (Choi et al., 2021):**
- Focused on microservice chains, which have different scaling dynamics than independent pipeline jobs
- pHPA's proactive allocation is a custom framework, not available in default GKE
- Container startup latency data is from Google Borg (2015 era), which may not reflect current GKE performance

**P9 (Liu et al., 2024):**
- JIAGU is a custom serverless system built on OpenFaaS, not on standard Kubernetes
- Results showing 54.8% density improvement require custom scheduling that is not applicable to default GKE
- Evaluated with traces from Huawei Cloud; generalisability to GKE is uncertain

**P10 (Li et al., 2025):**
- Treats applications as microservices, not as batch pipeline jobs
- Energy consumption is the primary metric, which is secondary to your reliability and performance metrics
- Experimental environment may not match GKE's configuration

### 6.2 Simulation vs. Theory vs. Real Systems

| Paper | Type | Real System? |
|-------|------|-------------|
| P1 | Empirical (real hardware) | Yes — BBN Butterfly, Sequent Balance |
| P2 | Theoretical/analytical | No — mathematical analysis with some simulation |
| P3 | Empirical (real system) | Yes — Docker/Kubernetes on VM |
| P4 | Empirical (lab testbed) | Partially — controlled lab, not production cloud |
| P5 | Survey | N/A — no original experiments |
| P6 | Empirical (real network) | Yes — real edge devices and network |
| P7 | Empirical (deployed application) | Yes — deployed RESTful app on Kubernetes |
| P8 | Empirical (benchmarks) | Partially — open-source benchmarks, not production |
| P9 | Empirical (prototype + traces) | Partially — prototype on OpenFaaS with real traces |
| P10 | Empirical (simulation environment) | Partially — Kubernetes cluster with synthetic workloads |

### 6.3 Why Your Experimental Approach Is Still Necessary

1. **No paper connects all four pillars.** The literature treats contention, overhead, autoscaling, and isolation as separate concerns. Your thesis is the first to measure how they interact in a single system under increasing workload.

2. **No paper measures at the workflow execution level.** All Kubernetes studies measure infrastructure metrics (CPU utilisation, pod scheduling latency, container response time). Your thesis measures *application-level outcomes*: job success rate, execution time variance, failure blast radius for pipeline runs.

3. **No paper uses realistic pipeline workloads.** Existing studies use HTTP benchmarks, CPU stress tests, or synthetic microservice chains. Your thesis uses Dagster pipeline workloads with defined resource profiles — representative of real workflow orchestration.

4. **No paper identifies a crossover point.** The literature documents that VMs have contention problems and Kubernetes has overhead. No paper measures both on the same workload to find the intersection — the specific concurrency level where one becomes better than the other.

5. **No paper tests on GKE with default configurations.** Most studies use custom frameworks (JIAGU, pHPA, KHPA-A) or lab environments. Your thesis tests the actual migration path that engineering teams face: default GKE with Kubernetes Run Launcher.

6. **Contention theory papers are outdated or domain-specific.** P1 is from 1991; P2 is about hard real-time systems. Your thesis provides current, empirically grounded contention measurement for a modern, relevant execution context.

---

## Summary: Your Research Position

Your thesis sits at a clearly defined intersection:

```
Resource Contention Theory (P1, P2)
         ↓
    Predicts VM collapse under load
         ↓
Kubernetes Overhead Studies (P3, P9)       ← Predicts GKE is slower per-job
         ↓
Autoscaling Research (P4, P5, P7, P8, P10) ← Predicts reaction window costs
         ↓
Fault Isolation Principles (P2, P6)        ← Predicts blast radius reduction
         ↓
    ═══════════════════════════════
    ║  YOUR THESIS: CROSSOVER POINT  ║
    ║  Connects all four at the       ║
    ║  workflow execution level        ║
    ║  under controlled workload       ║
    ═══════════════════════════════
```

The literature provides strong theoretical and empirical support for each individual pillar of your thesis. What it does not provide — and what constitutes your research contribution — is the empirical connection between these pillars at the application level, under controlled conditions, with a formally defined metric (the crossover point) that gives engineers actionable guidance.
