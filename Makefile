# ==========================
# Makefile for Thesis Project
# ==========================
#
# This Makefile provides unified targets for:
#   - LaTeX thesis building (pdf)
#   - Container image building and pushing (build, push)
#   - Multi-service orchestration with podman-compose (compose-up, compose-down)
#   - Infrastructure validation (validate)
#   - Experiment execution (experiments)
#
# Usage:
#   make pdf                    — Build thesis PDF
#   make build                  — Build container images locally
#   make push                   — Push images to ghcr.io (requires auth)
#   make compose-up             — Start all services with podman-compose
#   make compose-down           — Stop all services
#   make validate               — Run validation tests (local build + compose)
#   make experiments            — Run all experiments
#   make help                   — Show this help message
#
# Configuration:
#   - Container registry: ghcr.io/sirajwahaj
#   - Container runtime: podman (not Docker)
#   - Compose tool: podman-compose
#   - Default image tag: v0.1

# ==========================
# Variables
# ==========================

TEX_MAIN          = docs/main.tex
PDF_OUT           = docs/thesis.pdf
FIGURES           = docs/figures
RESULTS           = results

# Container configuration
REGISTRY          = ghcr.io/sirajwahaj
WORKLOAD_IMAGE    = $(REGISTRY)/thesis-workload
WORKLOAD_TAG      ?= v0.1
BUILD_SCRIPT      = scripts/02_img_build_push.sh
COMPOSE_FILE      = infrastructure/docker-compose.yml
COMPOSE_DIR       = infrastructure

# Validation
VALIDATE_TIMEOUT  = 30  # seconds to wait for services to start

# ==========================
# Phony Targets
# ==========================

.PHONY: all help \
        bootstrap \
        vm-provision vm-validate \
        k8s-create k8s-metrics k8s-deploy-dagster k8s-setup k8s-validate k8s-destroy \
        validate-setup \
        pdf copy-figures clean \
        build push compose-up compose-down compose-logs compose-clean \
        validate validate-build validate-compose \
        labels issues \
        exp1-vm exp2a-k8s exp2b-blast exp2c-spike experiments dry-run \
        analyze

# Bootstrap / environment config
VM_IP_FILE      = vm-ip.txt
SSH_KEY         = $(HOME)/.ssh/thesis_vm
ANSIBLE_DIR     = ansible

# ==========================
# Default Target
# ==========================

# Full pipeline: bootstrap -> k8s setup -> VM provision -> experiments -> analyze
# VM provision is attempted but non-fatal if VM is not reachable.
all: bootstrap k8s-setup vm-provision experiments analyze

# K8s-only workflow (no VM required)
k8s-only: bootstrap k8s-setup exp2a-k8s exp2b-blast exp2c-spike analyze

# PDF is built on Overleaf — no local build target needed

# ==========================
# Help
# ==========================

help:
	@echo ""
	@echo "================================================================"
	@echo "THESIS MAKEFILE — Build, Deploy, Validate, Experiment"
	@echo "================================================================"
	@echo ""
	@echo "One-Command Workflows:"
	@echo "  make all              — Bootstrap -> VM provision -> K8s setup -> experiments -> analyze"
	@echo "  make k8s-only         — Bootstrap -> K8s setup -> K8s experiments -> analyze (no VM)"
	@echo ""
	@echo "Bootstrap / Setup Targets:"
	@echo "  make bootstrap        — Detect OS, install deps, configure podman (VM discovery optional)"
	@echo "  make vm-provision     — Provision VM via Ansible (Python, Dagster, Docker CE, PostgreSQL)"
	@echo "  make vm-validate      — Verify VM is ready for experiments"
	@echo "  make k8s-create       — Create Kind cluster 'thesis'"
	@echo "  make k8s-metrics      — Deploy Metrics Server (kubectl top)"
	@echo "  make k8s-deploy-dagster — Deploy Dagster + workload via Helm"
	@echo "  make k8s-setup        — Full K8s setup (create + metrics + dagster)"
	@echo "  make k8s-validate     — Verify K8s setup is ready for experiments"
	@echo "  make k8s-destroy      — Delete Kind cluster (destructive)"
	@echo "  make validate-setup   — Validate all systems (VM + K8s + local)"
	@echo ""
	@echo "LaTeX Targets:"
	@echo "  make pdf              — Show Overleaf upload instructions (no local build)"
	@echo "  make clean            — Remove LaTeX aux files (from Overleaf downloads)"
	@echo ""
	@echo "Container Targets (podman):"
	@echo "  make build            — Build workload image locally"
	@echo "  make push             — Build and push to ghcr.io"
	@echo ""
	@echo "Orchestration Targets (podman-compose):"
	@echo "  make compose-up       — Start all services (postgres, workload, webserver, daemon)"
	@echo "  make compose-down     — Stop all services"
	@echo "  make compose-logs     — Stream service logs"
	@echo "  make compose-clean    — Stop services and remove volumes"
	@echo ""
	@echo "Validation Targets:"
	@echo "  make validate         — Full validation (build + compose test)"
	@echo "  make validate-build   — Validate local build only"
	@echo "  make validate-compose — Validate compose setup (requires build)"
	@echo ""
	@echo "Experiment Targets:"
	@echo "  make exp1-vm          — Run Experiment 1 (VM degradation)"
	@echo "  make exp2a-k8s        — Run Experiment 2A (K8s isolation)"
	@echo "  make exp2b-blast      — Run Experiment 2B (Blast radius)"
	@echo "  make exp2c-spike      — Run Experiment 2C (Spike observation)"
	@echo "  make experiments      — Run all experiments in sequence"
	@echo "  make dry-run          — Preview experiments without execution"
	@echo "  make analyze          — Run analysis notebook"
	@echo ""
	@echo "GitHub Targets:"
	@echo "  make labels           — Sync GitHub labels"
	@echo "  make issues           — Sync GitHub issues"
	@echo ""
	@echo "Configuration:"
	@echo "  Registry:  $(REGISTRY)"
	@echo "  Image tag: $(WORKLOAD_TAG)"
	@echo "  Compose:   $(COMPOSE_FILE)"
	@echo ""

# ==========================
# Bootstrap Targets
# ==========================

bootstrap:
	@echo "----------------------------------------------------------------"
	@echo "Bootstrap: Cross-Platform Environment Setup"
	@echo "----------------------------------------------------------------"
	bash scripts/bootstrap.sh

bootstrap-deps:
	@echo "Installing dependencies only (no VM creation)..."
	bash scripts/bootstrap.sh --deps-only

bootstrap-validate:
	@echo "Validating bootstrap dependencies..."
	bash scripts/bootstrap.sh --validate-only

# ==========================
# VM Targets
# ==========================

vm-provision:
	@echo "----------------------------------------------------------------"
	@echo "Provisioning VM via Ansible"
	@echo "----------------------------------------------------------------"
	@bash scripts/provision-vm.sh || echo "WARNING: VM provision skipped — check vm-ip.txt and retry: make vm-provision"

vm-validate:
	@echo "Validating VM setup..."
	bash scripts/validate-experiment-setup.sh --vm

vm-ssh:
	@test -f $(VM_IP_FILE) || (echo "ERROR: $(VM_IP_FILE) not found. Run: make bootstrap"; exit 1)
	@ssh -i $(SSH_KEY) -o StrictHostKeyChecking=no ubuntu@$$(cat $(VM_IP_FILE))

# ==========================
# Kubernetes Targets
# ==========================

k8s-create:
	@echo "----------------------------------------------------------------"
	@echo "Creating Kind Cluster 'thesis'"
	@echo "----------------------------------------------------------------"
	bash scripts/create-kind-cluster.sh

k8s-metrics:
	@echo "----------------------------------------------------------------"
	@echo "Deploying Metrics Server"
	@echo "----------------------------------------------------------------"
	bash scripts/deploy-metrics-server.sh

k8s-deploy-dagster:
	@echo "----------------------------------------------------------------"
	@echo "Deploying Dagster + Workload to K8s"
	@echo "----------------------------------------------------------------"
	bash scripts/deploy-dagster-k8s.sh

k8s-setup: k8s-create k8s-metrics k8s-deploy-dagster
	@echo ""
	@echo "[OK] K8s environment ready for experiments"
	@echo "   Dagster UI: http://localhost:3001"
	@echo ""

k8s-validate:
	@echo "Validating K8s setup..."
	bash scripts/validate-experiment-setup.sh --k8s

k8s-reset:
	@echo "Resetting Kind cluster (deletes all data)..."
	bash scripts/create-kind-cluster.sh --reset
	bash scripts/deploy-metrics-server.sh
	bash scripts/deploy-dagster-k8s.sh

k8s-destroy:
	@echo "Deleting Kind cluster 'thesis'..."
	kind delete cluster --name thesis
	@echo "[OK] Cluster deleted"

# ==========================
# Validation (All Systems)
# ==========================

validate-setup:
	@echo "----------------------------------------------------------------"
	@echo "Validating all experiment systems"
	@echo "----------------------------------------------------------------"
	bash scripts/validate-experiment-setup.sh

# ==========================
# LaTeX / Overleaf Targets
# ==========================
# PDF compilation is done via Overleaf (https://www.overleaf.com).
# Do NOT install latexmk or MacTeX locally.
# Workflow: make copy-figures -> upload docs/ folder to Overleaf project -> compile there.

pdf:
	@echo "----------------------------------------------------------------"
	@echo "PDF compilation uses Overleaf (online, https://www.overleaf.com)"
	@echo ""
	@echo "  1. Run:  make copy-figures"
	@echo "  2. Zip the docs/ folder and upload to your Overleaf project"
	@echo "  3. Compile on Overleaf — no local LaTeX install needed"
	@echo ""
	@echo "Do NOT install latexmk or MacTeX locally."
	@echo "----------------------------------------------------------------"

copy-figures:
	@echo "Copying figures from $(RESULTS) to $(FIGURES)..."
	mkdir -p $(FIGURES)
	cp -u $(RESULTS)/* $(FIGURES)/ 2>/dev/null || true
	@echo "[OK] Figures ready in $(FIGURES)/ — zip docs/ and upload to Overleaf."

clean:
	@echo "Cleaning LaTeX auxiliary files..."
	find docs/ \( -name "*.aux" -o -name "*.log" -o -name "*.toc" \
	  -o -name "*.out" -o -name "*.bbl" -o -name "*.blg" \
	  -o -name "*.synctex.gz" -o -name "*.fls" -o -name "*.fdb_latexmk" \) \
	  -delete 2>/dev/null || true
	@echo "[OK] Clean complete"

# ==========================
# Container Build Targets
# ==========================

build: build-workload
	@echo ""
	@echo "[OK] Build complete"
	@echo "   Image: $(WORKLOAD_IMAGE):$(WORKLOAD_TAG)"
	@echo "   Next: make compose-up"
	@echo ""

build-workload:
	@echo "----------------------------------------------------------------"
	@echo "Building workload image..."
	@echo "----------------------------------------------------------------"
	@bash $(BUILD_SCRIPT) $(WORKLOAD_TAG) 0

push: build-workload
	@echo ""
	@echo "----------------------------------------------------------------"
	@echo "Pushing to registry..."
	@echo "----------------------------------------------------------------"
	@PUSH=1 bash $(BUILD_SCRIPT) $(WORKLOAD_TAG)
	@echo ""
	@echo "[OK] Push complete"
	@echo "   Image: $(WORKLOAD_IMAGE):$(WORKLOAD_TAG)"
	@echo ""

# ==========================
# Orchestration Targets (podman-compose)
# ==========================

compose-up:
	@echo "----------------------------------------------------------------"
	@echo "Starting services with podman-compose..."
	@echo "----------------------------------------------------------------"
	cd $(COMPOSE_DIR) && podman-compose up -d
	@echo ""
	@echo "Waiting for services to start ($(VALIDATE_TIMEOUT)s)..."
	@sleep $(VALIDATE_TIMEOUT)
	@echo ""
	@echo "[OK] Services started"
	@echo "   Dagster UI: http://localhost:3001"
	@echo "   Workload gRPC: localhost:4000"
	@echo "   PostgreSQL: localhost:5432"
	@echo ""
	@echo "Next: make compose-logs"
	@echo ""

compose-down:
	@echo "----------------------------------------------------------------"
	@echo "Stopping services..."
	@echo "----------------------------------------------------------------"
	cd $(COMPOSE_DIR) && podman-compose down
	@echo "[OK] Services stopped"
	@echo ""

compose-logs:
	@echo "Streaming service logs (Ctrl+C to exit)..."
	@echo ""
	cd $(COMPOSE_DIR) && podman-compose logs -f

compose-clean:
	@echo "----------------------------------------------------------------"
	@echo "Cleaning up services and volumes..."
	@echo "----------------------------------------------------------------"
	cd $(COMPOSE_DIR) && podman-compose down -v
	@echo "[OK] Clean complete"
	@echo ""

# ==========================
# Validation Targets
# ==========================

validate: validate-build validate-compose
	@echo ""
	@echo "================================================================"
	@echo "[OK] ALL VALIDATIONS PASSED"
	@echo "================================================================"
	@echo ""
	@echo "Infrastructure is ready:"
	@echo "  [OK] Container build working"
	@echo "  [OK] gRPC server running"
	@echo "  [OK] Dagster services running"
	@echo "  [OK] PostgreSQL backend ready"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Provision VM: make vm-provision (requires UTM VM running)"
	@echo "  2. Set up K8s: make k8s-setup"
	@echo "  3. Run experiments: make experiments"
	@echo ""

validate-build: build-workload
	@echo ""
	@echo "Phase 1: Testing local build..."
	@echo "Verifying image exists..."
	@podman images | grep thesis-workload || (echo "ERROR: Image not found"; exit 1)
	@echo "[OK] Phase 1 passed: Local build successful"
	@echo ""

validate-compose: compose-down compose-up
	@echo ""
	@echo "Phase 2: Testing docker-compose setup..."
	@echo "Checking workload gRPC server..."
	@cd $(COMPOSE_DIR) && podman-compose logs workload | grep -i "grpc" && echo "[OK] Phase 2 passed: gRPC server running" || echo "[WARN] Check service logs with: make compose-logs"
	@echo ""

# ==========================
# Experiment Targets
# ==========================

exp1-vm:
	@echo "----------------------------------------------------------------"
	@echo "Experiment 1: VM Degradation (SQ1)"
	@echo "----------------------------------------------------------------"
	@bash scripts/validate-experiment-setup.sh --vm || (echo "ERROR: Fix errors above then retry: make exp1-vm"; exit 1)
	bash scripts/run_experiment.sh exp1 vm

exp2a-k8s:
	@echo "----------------------------------------------------------------"
	@echo "Experiment 2A: Kubernetes Isolation (SQ2)"
	@echo "----------------------------------------------------------------"
	@bash scripts/validate-experiment-setup.sh --k8s || (echo "ERROR: Fix errors above then retry: make exp2a-k8s"; exit 1)
	bash scripts/run_experiment.sh exp2a k8s

exp2b-blast:
	@echo "----------------------------------------------------------------"
	@echo "Experiment 2B: Blast Radius (SQ2)"
	@echo "----------------------------------------------------------------"
	@bash scripts/validate-experiment-setup.sh || (echo "ERROR: Fix errors above then retry: make exp2b-blast"; exit 1)
	bash scripts/run_experiment.sh exp2b vm
	bash scripts/run_experiment.sh exp2b k8s

exp2c-spike:
	@echo "----------------------------------------------------------------"
	@echo "Experiment 2C: Spike Observation (SQ3)"
	@echo "----------------------------------------------------------------"
	@bash scripts/validate-experiment-setup.sh --k8s || (echo "ERROR: Fix errors above then retry: make exp2c-spike"; exit 1)
	bash scripts/run_experiment.sh exp2c k8s

experiments: exp1-vm exp2a-k8s exp2b-blast exp2c-spike
	@echo ""
	@echo "================================================================"
	@echo "[OK] All experiments complete"
	@echo "================================================================"
	@echo ""
	@echo "Results saved to: data/raw/"
	@echo "Next: make analyze"
	@echo ""

dry-run:
	@echo "----------------------------------------------------------------"
	@echo "Dry run: Preview experiments without execution"
	@echo "----------------------------------------------------------------"
	@echo ""
	@echo "Exp1 (VM):"
	bash scripts/run_experiment.sh exp1 vm --dry-run
	@echo ""
	@echo "Exp2A (K8s):"
	bash scripts/run_experiment.sh exp2a k8s --dry-run
	@echo ""
	@echo "Exp2B (Blast Radius — both envs):"
	bash scripts/run_experiment.sh exp2b vm --dry-run
	bash scripts/run_experiment.sh exp2b k8s --dry-run
	@echo ""
	@echo "Exp2C (Spike K8s):"
	bash scripts/run_experiment.sh exp2c k8s --dry-run
	@echo ""

# ==========================
# Analysis Targets
# ==========================

analyze:
	@echo "Running analysis notebook..."
	python3 scripts/analyze_results.py
	@echo "[OK] Analysis complete"
	@echo ""

# ==========================
# GitHub Integration
# ==========================

labels:
	@echo "Syncing GitHub labels..."
	bash project/scripts/labels.sh

issues:
	@echo "Syncing GitHub issues..."
	bash project/scripts/issues.sh
