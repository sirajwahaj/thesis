# Supervisor Feedback on Thesis Proposal
## "When Does Kubernetes Become Worth It?"
**Date:** 2026-03-19  
**Context:** 4-week completion deadline. Student has prior experience with this solution. Supervisor has no prior background on this project.

---

## Overall Assessment

This is a **well-structured, academically serious proposal** with a clear research question, a formally defined primary contribution (the crossover point), and a logical chain connecting five supporting questions. The writing quality is above average for this level. The four-pillar literature structure is clean and each pillar connects explicitly to a research question.

**However, given the 4-week constraint, this proposal is critically overscoped.** You have designed a study that would take 8–10 weeks to execute properly. If you attempt everything as written, you will either deliver incomplete results or sacrifice quality under time pressure. My primary feedback is about what to cut, what to simplify, and what to protect.

I'll organise my feedback as: 🔴 **Critical (must fix)**, 🟡 **Important (strongly recommended)**, 🟢 **Minor (nice to have)**.

---

## 🔴 CRITICAL ISSUES

### 1. You have 6 experiments in 4 weeks — that's not feasible

Let's be honest about what 4 weeks actually looks like:

| Week | What actually needs to happen |
|------|-------------------------------|
| Week 1 | Infrastructure up and working (CDKTF, GKE, Dagster on both VM and K8s) |
| Week 2 | Run experiments, collect data |
| Week 3 | Analyse results, write Results + Discussion |
| Week 4 | Finish writing, review, submit |

That gives you **~5 working days** for actual experimentation. You have 6 experiments, each with 4 workload levels, each repeated 3 times, on 2 environments. That's potentially **6 × 4 × 3 × 2 = 144 individual test runs** plus setup, teardown, data collection, and troubleshooting.

**My recommendation: Reduce to 3 core experiments.**

| Keep | Experiment | Reason |
|------|-----------|--------|
| ✅ | Exp 1 — VM Failure Threshold | Your baseline. Non-negotiable. |
| ✅ | Exp 2 — GKE Pod Isolation | Direct comparison. Non-negotiable. |
| ✅ | Exp 5 — Overhead & Crossover Point | Your primary contribution. Non-negotiable. |
| ⚠️ | Exp 3 — Blast Radius | Merge into Exp 2 — add one `kill -9` / `kubectl delete pod` test during Exp 2's heavy run. Don't make it a separate experiment. |
| ⚠️ | Exp 4 — Autoscaling Response | Simplify to a single observation: submit spike workload, record timestamps. Don't make it a full 3-repetition experiment. Report it as supplementary data in Exp 5. |
| ❌ | Exp 6 — Infrastructure Reproducibility | **Drop it.** It answers SQ5 which is about validating your tooling, not about your research question. Mention CDKTF reproducibility as a methodological note in Chapter 3, not as an experiment. Nobody will examine you on whether CDKTF rebuilds are identical — they'll examine you on the crossover point. |

This reduces you from 6 experiments to 3 core + 2 folded-in observations, saving you ~2 days.

---

### 2. GCP Free Tier will block you — plan for it NOW

You mention free tier constraints as a fallback footnote in Delimitations. **This is your single biggest execution risk** and it's buried in a one-line footnote.

Real talk:
- GKE on free tier gives you **one zonal cluster with autopilot or one standard cluster**, but node hours are limited
- The free tier Compute Engine VM is an **e2-micro (0.25 vCPU, 1 GB RAM)** — you cannot run 5 concurrent Dagster jobs on this. Even an e2-standard-2 (2 vCPU, 8 GB) will struggle with your "heavy" workload of 5 × 1.0 CPU + 5 × 1 GB
- GKE cluster autoscaler adding new nodes costs money the moment you leave the free tier
- If you burn through free credits mid-experiment, you lose your environment

**What to do RIGHT NOW:**
1. Check your exact GCP credit balance today
2. Calculate how many node-hours your experiments need (I estimate 30–50 hours minimum)
3. If free tier is insufficient: apply for GCP education credits ($50–$300), or scope down your VM to something you can actually get, or use **Minikube/kind on a local machine** as the Kubernetes comparison (this changes your story but keeps it honest)
4. **Document your actual infrastructure specs in Chapter 3** — don't say "e2-standard or equivalent free-tier." Say exactly what you're using. Vagueness here will get flagged by any examiner.

---

### 3. Your workload levels are too thin — 1, 3, 5, 10 won't give you a curve

You define 4 workload levels: 1, 3, 5, and 10 concurrent jobs. The crossover point is supposed to be the concurrency level where VM breaks and GKE becomes better. With only 4 data points, you'll get a step function, not a curve. If the crossover happens between 5 and 10, you can't say *where* between 5 and 10.

**Recommendation: Use at least 6 levels.** Add concurrency = 2 and concurrency = 7 or 8. This gives you:

`1, 2, 3, 5, 7, 10`

This costs you a few more runs but gives you a much more credible degradation curve and crossover identification. If time is tight, drop the repetitions from 3 to 2 for the middle levels and keep 3 repetitions only for the levels near the expected crossover.

---

### 4. Your citations are placeholder tags, not actual references

Your literature review contains tags like `(queueing_theory)`, `(k8s_overhead_study)`, `(little_law)`, `(blast_radius)`, `(microservices_reliability)`. These are not real citations. You have 10 research papers in your workspace but none of them appear in the proposal.

**This is the first thing an examiner sees.** A literature review with zero real references signals that the review hasn't been written yet.

**Immediate action:**
- Replace every placeholder with actual paper references from your collection
- You already have a Literature Synthesis document mapping papers to pillars — use it
- At minimum, you need 8–12 real references in Chapter 2

---

## 🟡 IMPORTANT ISSUES

### 5. SQ5 (Infrastructure Reproducibility) does not belong as a research question

SQ5 asks: "Can the complete GKE cluster be rebuilt identically using CDKTF?"

This is not a research question. This is a **tool validation task**. The answer is almost certainly "yes, with minor timestamp/IP differences," and everybody already knows that. It doesn't contribute to your crossover point argument. It doesn't extend knowledge.

**Recommendation:** Remove SQ5 as a research question. Mention CDKTF reproducibility in Section 3.4.3 (Infrastructure) as a methodological choice. If you want, add one paragraph in Limitations saying "Infrastructure was rebuilt once during the study and results were consistent, supporting environmental validity." That's sufficient.

This gives you 4 supporting questions (SQ1–SQ4), which is more than enough and makes your chain tighter:
- SQ1: What breaks? (VM failure profile)
- SQ2: Does K8s fix it? (Pod isolation)
- SQ3: What does K8s cost in scaling response? (Autoscaling lag)
- SQ4: Where's the balance point? (Crossover)

---

### 6. Your crossover point definition has a logical problem

Your formal definition:
> "The concurrent workload level at which (1) the VM job success rate drops below 95% **AND** (2) the GKE total execution time becomes lower than the VM execution time under active contention."

The **AND** makes this very strict. Consider this scenario:
- At concurrency = 5: VM success rate = 97% (above 95%), but VM execution time is already 3× slower than GKE due to contention
- At concurrency = 7: VM success rate = 60%, GKE is clearly better in every way

Under your definition, the crossover is at 7, not at 5. But any engineer would say "migrate at 5" because the VM is already severely degraded even though it hasn't crossed the 95% threshold.

**Recommendation:** Define it as an **OR** condition, or define two crossover points:
- **Reliability crossover:** VM success rate drops below 95%
- **Performance crossover:** GKE total execution time (including overhead) becomes lower than VM execution time under contention
- **Combined crossover:** The level at which BOTH conditions are met

Report all three. This is more nuanced and more useful. It also protects you if your data shows one condition being met much earlier than the other.

---

### 7. No mention of how you'll actually trigger concurrent Dagster runs

This is a practical gap. You say "submit X concurrent jobs" but never specify how. Dagster doesn't have a built-in "run N jobs at once" command. You need:

- A script that uses the Dagster GraphQL API or CLI to launch N runs simultaneously
- A way to ensure they actually start concurrently (not sequentially with a queue)
- A way to collect per-run metrics programmatically (not manually reading Dagit UI)

**Recommendation:** Add a subsection to Chapter 3 describing your test harness. Something like:

> "A Python test script uses the Dagster GraphQL API to submit N pipeline runs simultaneously via threading. Run status, execution time, and failure data are collected via the Dagster events API and written to a CSV file for analysis."

This is ~10 lines of description but it shows the examiner you've thought about execution mechanics.

---

### 8. Standard deviation across 3 repetitions is statistically weak

You say "experiments are repeated three times per level and results reported with standard deviation." Three repetitions gives you very low statistical power. The standard deviation of 3 data points has a huge confidence interval — it's essentially meaningless for detecting small differences.

**Practical reality:** 3 reps is acceptable for a YH thesis given your time constraint, but **acknowledge the limitation explicitly** in Section 3.7 (Validity Statement). Say something like:

> "Three repetitions per workload level provide an indication of variability but are insufficient for full statistical significance testing. Results are reported as directional findings rather than statistically confirmed effects."

This shows the examiner you understand the limitation rather than being unaware of it.

---

### 9. The "Future Research" section gives away scope creep thinking

You mention NLP transformers, model inference, text embedding — none of which relate to this thesis. This reads like you're already thinking about the next project before finishing this one.

**Recommendation:** Shorten future research to 3 bullet points maximum:
1. Testing with real production workloads (not synthetic)
2. Comparing crossover points across other orchestration frameworks
3. Testing on multi-node configurations with larger workload ranges

Remove the NLP/transformer references entirely. They signal distraction.

---

## 🟢 MINOR ISSUES

### 10. Abstract is solid but too long for a YH thesis

Your abstract is ~200 words, which is appropriate. But it tries to mention every element (CDKTF, Helm, standard deviation, five research questions). For a YH thesis, focus the abstract on: problem → approach → primary contribution. Three sentences.

### 11. Table 3.1 job types are vague

"Simple data loop" and "Data processing" and "CPU-bound computation" don't tell me what the jobs actually *do*. When you implement them, document the actual operations:
- "Generates and sorts a list of 1M random integers in memory"
- "Reads a 100MB CSV, performs column transformations, writes output"
- "Computes SHA-256 hashes of 10M strings sequentially"

This makes your workloads reproducible.

### 12. Appendix code is placeholder

Appendices A, B, C, D are all placeholders. This is fine for a proposal, but **these must contain real code in the final submission.** Plan to populate them during Week 1 when your infrastructure is up.

### 13. Missing: ethics/data handling statement

Even with synthetic data, most thesis programmes require a brief statement that no personal or sensitive data is used. Add one sentence in Delimitations or Chapter 3.

---

## 4-WEEK ACTION PLAN

Given everything above, here's what I'd recommend as your weekly plan:

### Week 1 (March 19–25): Infrastructure + Literature
- [ ] CDKTF stack working: GKE cluster deploys, Dagster runs on it
- [ ] VM baseline working: Dagster deployed, can run a single job
- [ ] Test harness script: can trigger N concurrent runs and collect metrics
- [ ] Replace all placeholder citations with real references
- [ ] Confirm GCP budget is sufficient for all experiments

### Week 2 (March 26–April 1): Experiments
- [ ] Exp 1: VM Failure Threshold — all 6 concurrency levels, 2–3 reps each
- [ ] Exp 2: GKE Pod Isolation — same levels, include one blast radius test at heavy level
- [ ] Exp 5: Overhead & Crossover Point — measure per-job overhead, compute crossover
- [ ] Supplementary: One spike-level autoscaling observation
- [ ] Export all data to CSV, begin charts

### Week 3 (April 2–8): Results + Discussion
- [ ] Write Chapter 4 (Results) with actual data, tables, and charts
- [ ] Write Chapter 5 (Discussion) — connect results to each SQ and literature
- [ ] Write Crossover Point analysis with chart
- [ ] Fill Appendices with real code and data

### Week 4 (April 9–15): Finish + Submit
- [ ] Write/revise Abstract, Introduction, Conclusion
- [ ] Proofread entire document
- [ ] Ensure all references are complete and correctly formatted
- [ ] Buffer days for unexpected issues
- [ ] Submit

---

## SUMMARY: Top 5 Things to Do Immediately

| Priority | Action |
|----------|--------|
| 1 | **Check GCP credits today.** If insufficient, change plan before writing more code. |
| 2 | **Cut Experiment 6 and demote SQ5.** It's not a research question. |
| 3 | **Add concurrency levels 2 and 7** to get a real curve. |
| 4 | **Replace placeholder citations** with actual papers this week. |
| 5 | **Build your test harness script** — the ability to trigger and measure N concurrent runs is your single most important engineering task. |

---

## Final Note

This is a good proposal with a clear contribution. The crossover point concept is genuinely useful and the four-pillar structure is clean. Your problem is not quality — it's **scope vs. time**. Every day you spend on something that isn't core (like Exp 6, or worrying about NLP future work) is a day stolen from the 3 experiments that actually matter.

Focus ruthlessly. Ship the crossover point. Everything else is decoration.

Good luck.
