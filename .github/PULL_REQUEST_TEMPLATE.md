## Resolves

<!-- Link the issue this PR closes. Use the full ticket reference. -->
Closes # <!-- e.g. #7 (THESIS-007) -->

---

## Description

<!-- What has been done in this PR? Give a clear, concrete summary of the changes made. -->

---

## Motivation

<!-- Why is this change needed?
     - What does it enable?
     - What happens if we don't do this? -->

---

## Screenshots

<!-- Show how the changes have been tested — command output, notebook output, plots, LaTeX render, etc. -->

---

## Checklist

- [ ] My pull request represents one story (logical piece of work).
- [ ] My pull request is not adding any unused or temporary code, comments, or other content.
- [ ] I have updated appropriate documentation. This may include physical models, Dagster objects' descriptions, dbt descriptions.
- [ ] I have tested my changes thoroughly.
- [ ] Data files are not committed (only `.gitkeep` placeholders).
- [ ] No hardcoded credentials or personal paths.

### Thesis Alignment

- [ ] Change serves at least one of SQ1–SQ4 (or is infrastructure/tooling required for experiments).
- [ ] Research questions, metric definitions, concurrency levels, and workload duration are unchanged.
- [ ] No new tools or dependencies introduced outside the approved stack (Python 3.12, uv, podman, Kind, Dagster 1.12.7).
- [ ] If code changed: notebook (`notebooks/analysis.ipynb`) still runs end-to-end without error.
- [ ] If analysis changed: corresponding LaTeX chapter (`docs/chapters/04-results/`) updated or TODO added.
- [ ] No duplicate implementations created (check existing `scripts/` before adding new ones).
