---
globs: ["src/**/*.py", "scripts/**/*.py", "tests/**/*.py"]
---

# Python Conventions

## Version and runtime

- Python **3.12 only** — `requires-python = ">=3.12"` is set in `src/pyproject.toml`
- No `match` syntax backports needed; `match/case` is available
- Virtual environment: `src/.venv/` — activated by `source src/.venv/bin/activate`

## Package management

- **Only `uv`** — never suggest `pip install` directly
- Add a new dependency: `cd src && uv add <package>`
- Dev dependency: `cd src && uv add --dev <package>`
- Lock file: `src/uv.lock` — always commit this file
- Do not modify `src/pyproject.toml` manually for dependencies (use `uv add`)

## Pinned versions — do not change mid-experiment

| Package | Version | Reason |
|---------|---------|--------|
| dagster | 1.12.7 | Experiment comparability |
| dagster-k8s | 1.12.7 | Must match dagster |
| pandas | any | Analysis notebook |
| matplotlib | any | Plot generation |
| scipy | any | Statistical tests |

## Code style

- **Import order** (ruff-enforced):
  1. `from __future__ import annotations` (if used)
  2. stdlib (`os`, `sys`, `hashlib`, `time`, `json`)
  3. Third-party (`dagster`, `pandas`, `requests`)
  4. Local (`from workload import ...`)
- No unused imports in committed code
- f-strings preferred over `.format()` or `%`

## Data collection scripts (`scripts/collect_*.py`, `scripts/export_*.py`)

- Must output CSV with a header row on the first line
- Write to `data/raw/exp{N}/{env}/L{level}/run{rep}/` — exact path structure
- **Never write to** `data/processed/` — that path belongs to `notebooks/analysis.ipynb`
- Use `pathlib.Path` for all file paths (not `os.path.join`)
- Exit code 0 = success, exit code 1 = error (write error message to stderr)

## Dagster jobs (`src/workload/`)

- All Dagster code must be compatible with Dagster 1.12.7
- Do not use `@asset` or Software-Defined Assets — the thesis uses `@job`/`@op` pattern
- The gRPC server port is `4000` — do not change it (Ansible and Helm both reference it)
