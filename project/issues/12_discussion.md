# [THESIS-012] Write Discussion and Conclusions

Labels: latex
Story Points: 5
Dependencies: THESIS-011

## Description
Write the discussion chapter (SQ1–SQ4 analysis, limitations, tradeoff discussion) and conclusions chapter (answer, recommendations, future research).

## Acceptance Criteria
- [ ] Each SQ gets its own section with clear answer based on data
- [ ] Limitations section addresses: shared physical host, Kind vs real GKE, workload simplicity
- [ ] Tradeoff section discusses when NOT to use K8s
- [ ] Conclusions directly answer the main RQ with the identified crossover point
- [ ] Recommendations for engineering teams
- [ ] Future research section (multi-node, production GKE, IO-bound workloads)

## Notes
SQ answer format (from docs/chapters/03-method/metrics.tex):
SQ1 is answered at concurrency level L?, where VM job success rate first dropped
below 95%, recording ??% success rate (mean execution time: ??s ± ??s).
Templates available in `notebooks/thesis-012-discussion.ipynb`.
