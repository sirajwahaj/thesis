# [THESIS-013] Final Polish and Submission

Labels: latex, submission
Story Points: 5
Dependencies: THESIS-012

## Description
Proofread and cross-check all six chapters, verify the figures pipeline, compile the PDF on
Overleaf, and submit by the 2026-05-24 deadline. This is the only PLAN.md scope item without
a corresponding ticket.

## Acceptance Criteria
- [ ] Abstract verified: numbers in `frontmatter/abstract.tex` match `data/processed/*.csv`
- [ ] Full proofread pass of chapters 1–6 (spelling, grammar, flow)
- [ ] Cross-check: all values in LaTeX tables match corresponding rows in `data/processed/*.csv`
- [ ] Cross-check: all values in LaTeX prose match the figures and tables in the same section
- [ ] All `.bib` entries in `docs/references.bib` are cited and no citations are undefined
- [ ] `make copy-figures` run and all 7 PNGs confirmed present in `docs/figures/`
- [ ] `docs/` folder zipped and uploaded to Overleaf for compilation (no local LaTeX needed)
- [ ] PDF compiled on Overleaf without errors or warnings (excluding known benign warnings)
- [ ] PDF downloaded and reviewed cover-to-cover
- [ ] Submitted via JENSEN YH portal by 2026-05-24

## Notes
LaTeX compilation: Overleaf online (https://www.overleaf.com). No local `latexmk`/MacTeX required.
Workflow: `make copy-figures` → zip `docs/` → upload to Overleaf → compile → review → submit.

Supervisor review (2026-04-27) confirmed all critical issues resolved. Abstract already written
with correct experimental values (`frontmatter/abstract.tex`).

Figures to confirm in `docs/figures/`:
- `vm_degradation.png`
- `k8s_dashboard.png`
- `k8s_exec_time_distribution.png`
- `k8s_overhead_analysis.png`
- `k8s_success_rate.png`
- `vm_vs_k8s.png`
- `crossover_framework.png`
