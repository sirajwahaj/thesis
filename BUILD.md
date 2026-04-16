# Build, Push & Deploy Guide

This document explains how to build the thesis infrastructure using the unified Makefile workflow.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Prerequisites](#prerequisites)
3. [Build Workflow](#build-workflow)
4. [Container Build](#container-build)
5. [Registry Push](#registry-push)
6. [Orchestration](#orchestration)
7. [Validation](#validation)
8. [Troubleshooting](#troubleshooting)
9. [Advanced Usage](#advanced-usage)

---

## Quick Start

```bash
# 1. Build thesis workload container
make build

# 2. Validate the build works locally
make validate-build

# 3. Start all services with podman-compose
make compose-up

# 4. Verify services are running
make validate-compose

# 5. View logs (Ctrl+C to exit)
make compose-logs

# 6. Stop services when done
make compose-down
```

**Expected Output:**
- ✅ Workload image builds successfully
- ✅ Services start without errors
- ✅ Dagster UI accessible at http://localhost:3000
- ✅ gRPC server running on localhost:4000

---

## Prerequisites

### Required Tools

1. **podman** (container runtime, not Docker)
   - Install: https://podman.io/docs/installation
   - Verify: `podman --version`
   - On macOS: `brew install podman`
   - On Ubuntu: `apt-get install podman`

2. **podman-compose** (orchestration)
   - Install: `pip3 install podman-compose`
   - Verify: `podman-compose --version`

3. **Python 3.12+** (for analysis scripts)
   - Check: `python3 --version`

4. **make** (workflow automation)
   - Included on macOS and Linux
   - Windows: `choco install make`

### Optional Tools (for experiments)

- **Multipass** (VM provisioning for Experiment 1)
  - Install: https://multipass.run/
- **Kind** (Kubernetes cluster for Experiment 2A-2C)
  - Install: https://kind.sigs.k8s.io/docs/user/quick-start/
- **kubectl** (K8s interaction)
  - Install: `brew install kubectl`

### Registry Authentication (for push only)

To push images to `ghcr.io/sirajwahaj`:

```bash
podman login ghcr.io
# Enter username: sirajwahaj
# Enter password: <personal access token>
```

Generate a personal access token:
- GitHub → Settings → Developer settings → Personal access tokens
- Scopes: `write:packages`, `read:packages`, `delete:packages`

---

## Build Workflow

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MAKEFILE WORKFLOW                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  make build ──→ 02_img_build_push.sh ──→ podman build       │
│     ✓                                          ✓             │
│   Local image in podman registry               Workload      │
│                                                image ready   │
│                                                              │
│  make push  ──→ 02_img_build_push.sh ──→ podman build        │
│     ✓                                      + podman push     │
│   Image pushed to ghcr.io                     ✓              │
│                                         ghcr.io/sirajwahaj   │
│                                         /thesis-workload     │
│                                                              │
│  make compose-up ──→ docker-compose.yml ──→ podman-compose  │
│     ✓                                           ✓            │
│   Services start in containers            postgres ready    │
│                                            workload gRPC    │
│                                            dagster services │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Container Structure

**Workload Container** (`src/Containerfile`)

- **Base**: `python:3.12-slim`
- **Package Manager**: `uv` (fast Python dependency manager)
- **Dependencies**: 
  - `dagster>=1.12.22` (orchestration)
  - `dagster-grpc>=1.12.22` (gRPC server)
  - `dagster-postgres>=0.28.22` (PostgreSQL backend)
  - `dagster-webserver>=1.12.22` (UI)
- **Workload**: CPU-bound job (SHA-256 hashing for 30 seconds)
- **Entrypoint**: `dagster-grpc` on port 4000

**Composition** (`Infrastr/docker-compose.yml`)

- `postgres:16` — Database backend
- `workload:4000` — gRPC server (loads workload definitions)
- `dagster-webserver:3000` — UI & API
- `dagster-daemon` — Job execution engine

---

## Container Build

### Building Locally

```bash
# Build with default tag (v0.1)
make build

# Build with custom tag
make build WORKLOAD_TAG=v0.2

# Build specific script (for debugging)
bash scripts/02_img_build_push.sh v0.1 0
```

**What Happens:**
1. `02_img_build_push.sh` validates podman installation
2. Resolves paths relative to repository root
3. Validates `src/Containerfile` exists
4. Runs `podman build` from `src/` directory
5. Stores image in local podman registry

**Expected Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔨 Building: ghcr.io/sirajwahaj/thesis-workload:v0.1
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Build context: /Users/sirajulhaqwahaj/thesis/src
Dockerfile:    /Users/sirajulhaqwahaj/thesis/src/Containerfile

[1/8] STEP 1: FROM python:3.12-slim
...
[8/8] STEP 8: CMD ["dagster-grpc", "-h", "0.0.0.0", "-p", "4000", "-w", "/opt/dagster/app"]
COMMIT ghcr.io/sirajwahaj/thesis-workload:v0.1
✅ Build successful: ghcr.io/sirajwahaj/thesis-workload:v0.1
```

### Build Configuration

**File Structure Required:**
```
src/
├── Containerfile              ✓ Container image definition
├── pyproject.toml             ✓ Python dependencies
├── uv.lock                    ✓ Locked dependency versions
├── workload/
│   ├── __init__.py            ✓ Package entry point
│   └── workload_job.py        ✓ CPU-bound job definition
├── dagster.yaml               ✓ Dagster configuration
└── workspace.yaml             ✓ gRPC workspace config
```

**Key Points:**
- `Containerfile` uses `uv` for fast, reproducible builds
- Virtual environment activated so `dagster-grpc` command available
- `dagster-grpc` command starts server on 0.0.0.0:4000
- All config files (`dagster.yaml`, `workspace.yaml`) copied into image

---

## Registry Push

### Pushing to ghcr.io

```bash
# Build and push in one command
make push

# Or explicit steps:
make build                        # Build locally
make push WORKLOAD_TAG=v0.2       # Push with custom tag
```

**Prerequisites:**
- Registry authentication: `podman login ghcr.io`
- Repository access: User must have write access to `ghcr.io/sirajwahaj/thesis-workload`

**Expected Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 Pushing: ghcr.io/sirajwahaj/thesis-workload:v0.1
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Getting image source signatures
Copying blob ...
...
✅ Push successful: ghcr.io/sirajwahaj/thesis-workload:v0.1
```

### Verifying Push Success

```bash
# List images in ghcr.io (requires authentication)
podman search ghcr.io/sirajwahaj/thesis-workload --filter-tags

# Pull image to verify it's accessible
podman pull ghcr.io/sirajwahaj/thesis-workload:v0.1
```

---

## Orchestration

### Starting Services

```bash
# Start all services
make compose-up

# This starts:
# - PostgreSQL 16 (database backend)
# - Workload gRPC server (loads job definitions)
# - Dagster webserver (UI on :3000)
# - Dagster daemon (job execution)
```

**Expected Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 Starting services with podman-compose...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Creating network dagster_network
Creating container postgres
Creating container workload
Creating container dagster-webserver
Creating container dagster-daemon

⏳ Waiting for services to start (30s)...

✅ Services started
   Dagster UI: http://localhost:3000
   Workload gRPC: localhost:4000
   PostgreSQL: localhost:5432

Next: make compose-logs
```

### Monitoring Services

```bash
# Stream logs from all services (Ctrl+C to exit)
make compose-logs

# Or specific service:
cd Infrastr && podman-compose logs -f workload
```

### Stopping Services

```bash
# Stop but keep volumes (database data persists)
make compose-down

# Stop and remove volumes (clean slate)
make compose-clean
```

---

## Validation

### Full Validation

```bash
# Run all validation tests
make validate

# This executes:
# 1. validate-build: Local build test
# 2. validate-compose: Compose + services test
```

### Phase 1: Local Build

```bash
make validate-build

# Checks:
# ✓ Image exists in podman registry
# ✓ Image has correct tag
# ✓ Image metadata is valid
```

### Phase 2: Orchestration

```bash
make validate-compose

# Checks:
# ✓ docker-compose.yml loads
# ✓ Services start without errors
# ✓ gRPC server logs show startup
# ✓ Ports are accessible
```

**Expected Success Criteria:**
- All containers running: `podman ps | grep -E "workload|dagster|postgres"`
- No error logs in services
- Dagster UI loads at http://localhost:3000
- gRPC server reports ready in logs

---

## Troubleshooting

### Build Issues

**Problem:** `podman: command not found`
```bash
# Solution: Install podman
brew install podman                    # macOS
sudo apt-get install podman            # Ubuntu/Debian
sudo yum install podman               # RHEL/CentOS
```

**Problem:** `src/Containerfile: No such file or directory`
```bash
# Solution: Run from repository root
cd /Users/sirajulhaqwahaj/thesis
make build
```

**Problem:** `Dockerfile: permission denied`
```bash
# Solution: Ensure script has execution permission
chmod +x scripts/02_img_build_push.sh
make build
```

**Problem:** Build hangs on `uv sync`
```bash
# Solution: Check network connectivity, or manually build with verbose output
bash scripts/02_img_build_push.sh v0.1 0
```

### Push Issues

**Problem:** `authentication required`
```bash
# Solution: Authenticate with registry
podman login ghcr.io
# Enter credentials when prompted
make push
```

**Problem:** `denied: permission denied`
```bash
# Solution: Verify you have write access to the registry
# GitHub → Settings → Developer settings → Personal access tokens
# Verify scopes: write:packages, read:packages, delete:packages
podman logout ghcr.io
podman login ghcr.io
make push
```

### Orchestration Issues

**Problem:** `podman-compose: command not found`
```bash
# Solution: Install podman-compose
pip3 install podman-compose
podman-compose --version
```

**Problem:** Port 3000 or 5432 already in use
```bash
# Solution: Stop conflicting services or modify docker-compose.yml
lsof -i :3000                          # Find process using port 3000
kill <PID>                             # Kill the process
make compose-up
```

**Problem:** Services fail to start with `image not found`
```bash
# Solution: Ensure workload image was built first
make build
make compose-up
```

**Problem:** Dagster UI loads but shows "Connection refused"
```bash
# Solution: Verify gRPC server is running
cd Infrastr && podman-compose logs workload | grep -i grpc
cd Infrastr && podman-compose ps
```

### Network Issues

**Problem:** Containers can't communicate (gRPC connection refused)
```bash
# Solution: Verify network is properly configured
cd Infrastr && podman-compose ps
cd Infrastr && podman network inspect dagster_network

# If network missing, recreate:
make compose-clean
make compose-up
```

---

## Advanced Usage

### Custom Build Parameters

```bash
# Build with specific tag and immediately push
make push WORKLOAD_TAG=v0.2-experimental

# Build only (don't push)
bash scripts/02_img_build_push.sh v0.2-test 0

# Push existing local image
PUSH=1 bash scripts/02_img_build_push.sh v0.1
```

### Dry Run Experiments

```bash
# Preview experiments without execution
make dry-run

# This shows:
# - Experiment configuration
# - Workload parameters
# - Data collection paths
# - Expected duration
```

### Manual Service Management

```bash
# Start individual service (for debugging)
cd Infrastr && podman-compose up -d postgres
cd Infrastr && podman-compose up -d workload
cd Infrastr && podman-compose up -d dagster-webserver

# Rebuild service (useful if dependencies changed)
cd Infrastr && podman-compose up -d --build workload

# View resource usage
podman stats
```

### Inspect Built Image

```bash
# List local images
podman images | grep thesis-workload

# Inspect image metadata
podman inspect ghcr.io/sirajwahaj/thesis-workload:v0.1

# Run interactive shell in container
podman run -it ghcr.io/sirajwahaj/thesis-workload:v0.1 /bin/bash

# Test workload import
podman run -it ghcr.io/sirajwahaj/thesis-workload:v0.1 \
  python -c "from workload import thesis_workload; print(thesis_workload)"
```

### CI/CD Integration

**For GitHub Actions:**
```yaml
- name: Build and push thesis workload
  run: |
    podman login ghcr.io -u sirajwahaj -p ${{ secrets.GITHUB_TOKEN }}
    make push WORKLOAD_TAG=${{ github.sha }}
```

---

## Performance Notes

### Build Time

- **First build**: 2-3 minutes (downloads base image, installs dependencies)
- **Subsequent builds**: 30-60 seconds (uses layer cache)
- **Push time**: Depends on network speed, typically 1-2 minutes for full image

### Resource Requirements

- **Disk**: ~2GB per image (Python 3.12-slim + dependencies)
- **Memory**: 1-2GB during build
- **Network**: Stable connection recommended for push

### Optimization Tips

- **Enable buildkit**: Faster builds with better caching
  ```bash
  BUILDKIT_PROGRESS=plain make build
  ```
- **Use local registry cache**: Avoid re-pushing
  ```bash
  podman images | grep thesis-workload
  ```
- **Prune old images**: Save disk space
  ```bash
  podman image prune -a --filter "until=24h"
  ```

---

## Next Steps

After successful build and validation:

1. **Run Experiment 1 (VM Degradation)**
   ```bash
   make exp1-vm
   ```

2. **Set up Kubernetes (for Experiments 2A-2C)**
   ```bash
   kind create cluster --name thesis-cluster
   make exp2a-k8s
   ```

3. **Analyze Results**
   ```bash
   make analyze
   ```

---

## References

- **Makefile**: `/Makefile` (all targets documented in `make help`)
- **Build Script**: `scripts/02_img_build_push.sh`
- **Container Definition**: `src/Containerfile`
- **Compose Configuration**: `Infrastr/docker-compose.yml`
- **Experiment Runner**: `scripts/run_experiment.sh`

---

## Support

For issues or questions:

1. Check [Troubleshooting](#troubleshooting) section
2. Review logs: `make compose-logs`
3. Run validation: `make validate`
4. Check script output for detailed error messages

