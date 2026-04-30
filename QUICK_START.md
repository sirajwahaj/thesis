# WORKFLOW QUICK REFERENCE

## One-Time Setup

```bash
# 1. Install tools
brew install podman podman-compose     # macOS
# or: apt-get install podman           # Linux

pip3 install podman-compose

# 2. Authenticate to registry (for push)
podman login ghcr.io
# Enter: sirajwahaj + personal access token
```

## Development Workflow

```bash
# ┌─ BUILD ─────────────────────────────────────┐
# │ Create container image from Containerfile   │
# └─────────────────────────────────────────────┘
make build                              # Build locally

# ┌─ VALIDATE ──────────────────────────────────┐
# │ Test build works + services start correctly │
# └─────────────────────────────────────────────┘
make validate                           # Full validation
# or:
make validate-build                     # Just test build
make validate-compose                   # Just test compose

# ┌─ ORCHESTRATE ───────────────────────────────┐
# │ Start/stop multi-container services         │
# └─────────────────────────────────────────────┘
make compose-up                         # Start all services
make compose-logs                       # View logs
make compose-down                       # Stop services
make compose-clean                      # Stop + remove volumes
```

## Experiment Workflow

```bash
# ┌─ DRY RUN ───────────────────────────────────┐
# │ Preview experiments without execution       │
# └─────────────────────────────────────────────┘
make dry-run

# ┌─ RUN EXPERIMENTS ───────────────────────────┐
# │ Execute in sequence: Exp1 → Exp2A/B/C      │
# └─────────────────────────────────────────────┘
make exp1-vm                            # Exp1: VM Degradation
make exp2a-k8s                          # Exp2A: K8s Isolation
make exp2b-blast                        # Exp2B: Blast Radius
make exp2c-spike                        # Exp2C: Spike Observation
make experiments                        # All in sequence

# ┌─ ANALYZE ───────────────────────────────────┐
# │ Process results                             │
# └─────────────────────────────────────────────┘
make analyze
```

## Registry Workflow

```bash
# ┌─ BUILD & PUSH ──────────────────────────────┐
# │ Build locally, then push to ghcr.io         │
# └─────────────────────────────────────────────┘
make push                               # Build + push (default tag v0.1)
make push WORKLOAD_TAG=v0.2             # Build + push (custom tag)
```

## LaTeX Workflow

```bash
# ┌─ BUILD PDF ─────────────────────────────────┐
# │ Compile thesis document                     │
# └─────────────────────────────────────────────┘
make pdf                                # Build docs/thesis.pdf
make clean                              # Clean LaTeX temp files
```

## GitHub Integration

```bash
make labels                             # Sync GitHub labels
make issues                             # Sync GitHub issues
```

## Help & Documentation

```bash
make help                               # Show all targets + descriptions
cat BUILD.md                            # Detailed build guide
```

---

## Common Scenarios

### "I want to build and test locally"
```bash
make build && make validate-build
```

### "I want to start the full stack"
```bash
make build && make compose-up
# Check: http://localhost:3000
```

### "I want to push to registry"
```bash
podman login ghcr.io                    # One-time auth
make push
```

### "I want to run experiments"
```bash
make validate                           # Prerequisite
make dry-run                            # Preview first
make experiments                        # Execute
make analyze                            # Results
```

### "Something broke, let me clean up"
```bash
make compose-down                       # Stop services
make compose-clean                      # Stop + wipe volumes
podman image prune -a                   # Remove old images
make build && make validate             # Start fresh
```

### "I want to debug services"
```bash
make compose-up
make compose-logs                       # View all logs
# or:
cd Infrastr && podman-compose logs -f workload    # Specific service
```

---

## Key Files

| File | Purpose |
|------|---------|
| `Makefile` | Unified workflow automation |
| `BUILD.md` | Detailed build guide (this) |
| `scripts/02_img_build_push.sh` | Container build script |
| `src/Containerfile` | Container image definition |
| `src/pyproject.toml` | Python dependencies |
| `Infrastr/docker-compose.yml` | Service orchestration |
| `scripts/run_experiment.sh` | Experiment execution |

---

## Diagnostics

```bash
# Check podman installation
podman --version
podman-compose --version

# List images
podman images

# List running containers
podman ps

# Check network
podman network ls

# View image details
podman inspect ghcr.io/sirajwahaj/thesis-workload:v0.1

# Check registry authentication
podman login ghcr.io --get-login
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `podman: command not found` | Install podman: `brew install podman` |
| `podman-compose: command not found` | Install: `pip3 install podman-compose` |
| Port conflict (3000, 5432 in use) | `make compose-clean` then retry |
| Build fails on dependency | Check network, retry build |
| Push authentication fails | `podman login ghcr.io` then retry |
| Services won't start | `make compose-clean && make compose-up` |

