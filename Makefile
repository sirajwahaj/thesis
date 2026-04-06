# ==========================
# Makefile for Thesis Project
# ==========================

# Variables
TEX_MAIN = docs/main.tex
PDF_OUT  = docs/thesis.pdf
FIGURES  = docs/figures
RESULTS  = results

# Default target
all: pdf

# --------------------------
# Build PDF
# --------------------------
pdf: copy-figures
	@echo "Building PDF..."
	latexmk -pdf -interaction=nonstopmode -output-directory=docs $(TEX_MAIN)
	@echo "PDF built at $(PDF_OUT)"

# --------------------------
# Copy latest results figures
# --------------------------
copy-figures:
	@echo "Copying latest figures from $(RESULTS) to $(FIGURES)..."
	mkdir -p $(FIGURES)
	cp -u $(RESULTS)/* $(FIGURES)/ || true

# --------------------------
# Clean temporary LaTeX files
# --------------------------
clean:
	@echo "Cleaning temporary LaTeX files..."
	latexmk -C -output-directory=docs $(TEX_MAIN)

# --------------------------
# Sync GitHub Labels
# --------------------------
labels:
	@echo "Syncing GitHub labels..."
	bash project/scripts/labels.sh

# --------------------------
# Sync GitHub Issues
# --------------------------
issues:
	@echo "Syncing GitHub issues..."
	bash project/scripts/issues.sh

# --------------------------
# Experiments
# --------------------------
exp1-vm:
	@echo "Running Experiment 1 — VM Degradation..."
	bash scripts/run_experiment.sh exp1 vm

exp2a-k8s:
	@echo "Running Experiment 2A — K8s Isolation..."
	bash scripts/run_experiment.sh exp2a k8s

exp2b-blast:
	@echo "Running Experiment 2B — Blast Radius (both environments)..."
	bash scripts/run_experiment.sh exp2b vm
	bash scripts/run_experiment.sh exp2b k8s

exp2c-spike:
	@echo "Running Experiment 2C — Spike Observation..."
	bash scripts/run_experiment.sh exp2c k8s

experiments: exp1-vm exp2a-k8s exp2b-blast exp2c-spike
	@echo "All experiments complete."

dry-run:
	@echo "=== Dry run: Experiment 1 (VM) ==="
	bash scripts/run_experiment.sh exp1 vm --dry-run
	@echo "=== Dry run: Experiment 2A (K8s) ==="
	bash scripts/run_experiment.sh exp2a k8s --dry-run

# --------------------------
# Analysis
# --------------------------
analyze:
	@echo "Running analysis..."
	python3 scripts/analyze_results.py

.PHONY: all pdf copy-figures clean labels issues \
        exp1-vm exp2a-k8s exp2b-blast exp2c-spike experiments dry-run analyze
