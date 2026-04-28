---
name: latex-writing
description: "Use when writing or editing LaTeX thesis chapters, adding figures or tables, formatting results for the thesis document, or referencing experiment data in LaTeX prose."
---

# LaTeX Thesis Writing

## File structure

```
docs/
├── main.tex                       ← root — DO NOT restructure
├── references.bib                 ← all citations (9 papers)
├── frontmatter/
│   ├── titlepage.tex
│   └── abstract.tex
├── chapters/
│   ├── 01-introduction/main.tex   ← \input{} hub
│   ├── 02-literature-review/main.tex
│   ├── 03-method/main.tex
│   │   ├── metrics.tex            ← metric definitions (LOCKED)
│   │   └── experiments.tex        ← experiment protocols (LOCKED)
│   ├── 04-results/main.tex        ← fill after experiments complete
│   │   ├── exp1.tex
│   │   ├── exp2.tex
│   │   └── exp3.tex
│   ├── 05-discussion/main.tex
│   └── 06-conclusions/main.tex
├── backmatter/appendices.tex
└── figures/                       ← filled by `make copy-figures` only
```

## Adding a figure

```latex
\begin{figure}[htbp]
  \centering
  \includegraphics[width=0.9\textwidth]{figures/exp1_success_rate.png}
  \caption{Job success rate across concurrency levels, VM environment (Experiment 1).
           Each data point represents the mean of 3 repetitions;
           error bars show ±1 standard deviation.}
  \label{fig:exp1-success-rate}
\end{figure}
```

Figure files must exist in `docs/figures/` before compiling. Run `make copy-figures` first.

Available figure names (once analysis runs): `exp1_success_rate.png`, `exp1_mean_execution_time.png`,
`exp1_execution_time_variance.png`, `exp2a_success_rate.png`, `exp2a_pod_scheduling_latency.png`,
`exp2a_container_startup_time.png`, `exp3_crossover.png`.

## Adding a results table

Values come from `data/processed/*.csv`. Do not hardcode — use a placeholder until data is ready.

```latex
\begin{table}[htbp]
  \centering
  \caption{Execution metrics by concurrency level — VM environment (Experiment 1, $n=3$ per level).
           All times in seconds. CPU and memory as percentage of total system capacity.}
  \label{tab:exp1-vm-results}
  \begin{tabular}{lrrrrrr}
    \toprule
    Level & Jobs & Success (\%) & Mean Time (s) & Std Dev (s) & CPU (\%) & Mem (\%) \\
    \midrule
    L1 & 1  & 100.0 & -- & -- & -- & -- \\
    L2 & 2  & 100.0 & -- & -- & -- & -- \\
    L3 & 3  & --    & -- & -- & -- & -- \\
    L4 & 5  & --    & -- & -- & -- & -- \\
    L5 & 7  & --    & -- & -- & -- & -- \\
    L6 & 10 & --    & -- & -- & -- & -- \\
    \bottomrule
  \end{tabular}
\end{table}
```

## SQ answer format (for discussion chapter)

Use this format consistently for each SQ answer in `docs/chapters/05-discussion/`:

### SQ1
```latex
\paragraph{SQ1: VM degradation threshold}
The VM deployment first exhibited degradation at concurrency level \textbf{L?} (? concurrent jobs),
where the job success rate dropped to ?\%, falling below the 95\% reliability threshold.
At this level, execution time variance increased by ?$\times$ compared to the L1 baseline
(from ?s to ?s standard deviation), and CPU utilisation reached ??\%.
```

### SQ4 / Crossover
```latex
\paragraph{SQ4: Crossover point}
The crossover point --- the level at which Kubernetes becomes net beneficial --- was reached at
concurrency level \textbf{L?} (? concurrent jobs).
At this level, the VM success rate (??\%) fell below the 95\% reliability threshold
(reliability crossover), and the total Kubernetes execution time (??s + ??s scheduling overhead)
was lower than the VM mean execution time (??s) (performance crossover).
The migration therefore becomes net beneficial at ? concurrent workflows.
```

## Citing papers

All 9 papers are in `docs/references.bib`. Use `\cite{key}` or `\citep{key}`.

Common references:
- Kubernetes foundational: `\cite{burns2016borg}`
- Dagster / workflow orchestration: `\cite{dagster2023}`
- Container overhead studies: `\cite{felter2015updated}`

## Build workflow

```bash
make pdf           # latexmk -pdf docs/main.tex → docs/thesis.pdf
make clean         # clean .aux, .log, .out files
make copy-figures  # results/*.png → docs/figures/
```

Always run `make copy-figures` before `make pdf` if plots were regenerated.
