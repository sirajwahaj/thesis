#!/usr/bin/env python3
"""
Non-interactive analysis runner.

Executes notebooks/analysis.ipynb in-place using nbconvert so that
`make analyze` works headlessly (e.g. in CI or on the experiment host)
while the notebook remains the single source of truth for all analysis.

All outputs (CSVs, PNGs) are written by the notebook itself to:
  - data/processed/   (summary tables, p-values)
  - results/          (plots, copied to docs/figures/ by `make copy-figures`)

Usage:
    python scripts/analyze_results.py
    python scripts/analyze_results.py --notebook notebooks/analysis.ipynb
    python scripts/analyze_results.py --notebook notebooks/analysis.ipynb --timeout 600

For interactive analysis open the notebook directly:
    code notebooks/analysis.ipynb
"""

import argparse
import subprocess
import sys
import os


def run_notebook(notebook_path: str, timeout: int = 600) -> int:
    """
    Execute a Jupyter notebook in-place via nbconvert.
    The executed notebook is saved back to the same file so outputs are
    preserved for inspection in VS Code.
    """
    try:
        import nbformat  # noqa: F401 — just check it's installed
    except ImportError:
        print("Installing nbconvert + nbformat...")
        subprocess.run(
            [sys.executable, "-m", "pip", "install", "-q", "nbconvert", "nbformat"],
            check=True,
        )

    cmd = [
        sys.executable, "-m", "nbconvert",
        "--to", "notebook",
        "--execute",
        "--inplace",
        f"--ExecutePreprocessor.timeout={timeout}",
        "--ExecutePreprocessor.kernel_name=python3",
        notebook_path,
    ]

    print(f"Executing notebook: {notebook_path}")
    print(f"Timeout: {timeout}s\n")

    result = subprocess.run(cmd)
    return result.returncode


def main() -> None:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    parser = argparse.ArgumentParser(
        description="Run the analysis notebook non-interactively (headless)."
    )
    parser.add_argument(
        "--notebook",
        default=os.path.join(repo_root, "notebooks", "analysis.ipynb"),
        help="Path to the analysis notebook (default: notebooks/analysis.ipynb)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=600,
        help="Cell execution timeout in seconds (default: 600)",
    )
    args = parser.parse_args()

    if not os.path.exists(args.notebook):
        print(f"Error: notebook not found at {args.notebook}")
        sys.exit(1)

    rc = run_notebook(args.notebook, args.timeout)

    if rc == 0:
        print("\nAnalysis complete.")
        print("  Outputs  → data/processed/")
        print("  Figures  → results/")
        print(f"  Notebook → {args.notebook}  (outputs saved in-place)")
        print()
        print("Run `make copy-figures` to copy PNGs into docs/figures/ for LaTeX.")
    else:
        print(f"\nNotebook execution failed (exit code {rc}).")
        print("Open notebooks/analysis.ipynb in VS Code to debug interactively.")
        sys.exit(rc)


if __name__ == "__main__":
    main()


if __name__ == "__main__":
    main()
