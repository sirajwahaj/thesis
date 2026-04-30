## Infrastructure Feedback — Alignment with Thesis Goals

**Date**: April 9, 2026  
**Status**: Good foundation, but several issues need fixing

---

## 1. IMMEDIATE ISSUES (BLOCKING)

### 1.1 **File Path Mismatch** — CRITICAL
**Problem**: Containerfile references `workspace.yaml` but file is `workspace.yml` (`.yml` not `.yaml`)

```dockerfile
# WRONG (line 24 in Containerfile)
COPY workspace.yaml $DAGSTER_HOME/workspace.yaml

# SHOULD BE
COPY workspace.yml $DAGSTER_HOME/workspace.yaml
```

**Docker-compose also expects the wrong path**:
```yaml
# In Infrastr/docker-compose.yml (lines 49, 67)
- ./workspace.yaml:/opt/dagster/dagster_home/workspace.yaml:Z
# Should mount: ./src/workspace.yml
```

**Fix**: 
- Rename `src/workspace.yml` → `src/workspace.yaml` (standardize on `.yaml`)
- OR update Containerfile and docker-compose to reference `.yml`

---

### 1.2 **uv Activation Issue** — BLOCKING
**Problem**: `uv venv` + `uv sync` creates a virtual environment, but the Containerfile doesn't activate it before running commands.

```dockerfile
# CURRENT (broken)
RUN uv venv
RUN uv sync --frozen
RUN uv pip install --editable .
# The venv is created but never activated for subsequent RUNs

# SHOULD BE
RUN uv venv
ENV VIRTUAL_ENV=.venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN uv sync --frozen
RUN uv pip install --editable .
```

When the container starts, Dagster won't find the dependencies because they're in `.venv/bin/` but not in `$PATH`.

---

### 1.3 **Missing gRPC Server Implementation** — BLOCKING
**Problem**: `workspace.yaml` says:
```yaml
load_from:
  - grpc_server:
      host: workload
      port: 4000
```

But `workload_job.py` defines a **Dagster `@job` decorator**, not a gRPC server. There's no code that starts a gRPC server on port 4000.

**What you need**:
```python
# In workload/workload_job.py or a new __main__ block
from dagster_grpc import DagsterGrpcServer

if __name__ == "__main__":
    server = DagsterGrpcServer(...)  # Expose workload job via gRPC
    server.run()
```

The `dagster-webserver` container will only load definitions if `workload` exposes them via gRPC on port 4000.

---

## 2. ALIGNMENT WITH THESIS GOALS

### ✅ GOOD — On Track

| Goal | Current State | Assessment |
|---|---|---|
| **Workload is CPU-bound** | `workload_job.py` uses SHA256 in tight loop | Excellent — creates real contention |
| **Containerized** | Containerfile exists for workload image | Good — can push to ghcr.io |
| **Dagster as orchestrator** | Using Dagster 1.12.22 | Correct version, matches proposal |
| **PostgreSQL backend** | docker-compose includes postgres:16 | Good — stateful experiments |
| **Multi-container setup** | postgres, workload, dagster-webserver, daemon | Right pattern for thesis |
| **ghcr.io registry** | docker-compose pulls from ghcr.io | Good for reproducibility |

### ⚠️ CONCERNS — Not Aligned with SQ1–SQ4

| Issue | Impact | Severity |
|---|---|---|
| **No K8s Run Launcher** | Your setup is Docker Compose (local), not K8s. Thesis requires Kind cluster | **HIGH** |
| **No metrics collection** | No `psutil`, `prometheus`, or `kubectl top` scripts to measure job duration/success rate | **HIGH** |
| **No workload harness** | No script to submit 1, 2, 4, 8, 12, 16 concurrent jobs and measure results | **HIGH** |
| **VM baseline missing** | Thesis requires Multipass VM running same Dagster. Only have Docker Compose | **MEDIUM** |
| **gRPC server missing** | Can't load workload definitions into Dagster webserver | **CRITICAL** |

---

## 3. THESIS REQUIREMENTS vs. CURRENT STATE

### Thesis Experiment 1: VM Degradation (SQ1)
**Required**: Deploy Dagster on Multipass VM with process executor; run workload at 6 levels (1, 2, 4, 8, 12, 16 concurrent jobs); measure success rate, execution time variance, CPU/memory.

**Current State**: ❌ No VM. Only have Docker Compose.

**To Fix**:
- Spin up Multipass with 4 vCPU, 8 GB RAM
- Install Python 3.12, Dagster, PostgreSQL  
- Move workload definitions there
- Create a Python script to submit N concurrent jobs and track metrics

---

### Thesis Experiment 2A: Kubernetes Isolation (SQ2)
**Required**: Same workload on Kind cluster with Kubernetes Run Launcher; compare success rate, variance.

**Current State**: ❌ No Kind cluster. Only have Docker Compose.

**To Fix**:
- Install Kind on the same host
- Deploy Dagster with Kubernetes Run Launcher (via Helm)
- Use same workload harness as VM
- Collect `kubectl top` metrics

---

### Thesis Experiment 3: Crossover Analysis (SQ4)
**Required**: Derive the workload level at which:
- (1) VM success rate drops below 95%, AND
- (2) K8s total execution time < VM execution time

**Current State**: ❌ Can't derive without Exp 1 + 2A data.

---

## 4. WHAT YOU HAVE RIGHT

### ✅ Workload Design
The SHA-256 CPU-burn job is **theoretically correct** for creating resource contention:
- Pure CPU, no I/O
- Measurable iterations per second
- Scales with concurrency
- Configurable duration (30s default is reasonable)

### ✅ Docker Multi-Compose Strategy
Using separate services (postgres, workload, webserver, daemon) is the **right architectural pattern**. It's not what the thesis *tests*, but it's good for development/testing the setup.

### ✅ uv + pyproject.toml
Using `uv` for dependency management is **good choice** for reproducibility. But it needs activation in Containerfile.

---

## 5. WHAT NEEDS TO BE ADDED

### 5.1 gRPC Server Implementation
```python
# workload/__init__.py or workload/grpc_server.py
from dagster import define_asset_job, DagsterInstance
from dagster_grpc import DagsterGrpcServer

# OR (simpler):
from dagster import Definitions
from dagster_grpc import DagsterGrpcServer

# Load job
from .workload_job import thesis_workload

defs = Definitions(jobs=[thesis_workload])

if __name__ == "__main__":
    server = DagsterGrpcServer(
        instance=DagsterInstance.get(),
        definitions_module_name="workload"  # or explicit module path
    )
    server.run_server(port=4000, host="0.0.0.0")
```

**Check**: Once running, does `workspace.yaml`'s `grpc_server: workload:4000` load the job?

### 5.2 Workload Harness Script
```python
# scripts/run_experiment.py
import subprocess
import json
import time
from datetime import datetime

def run_concurrent_workload(level: int, reps: int = 3):
    """
    Submit N concurrent jobs to Dagster and measure:
    - job success rate
    - execution time (min, max, mean, std dev)
    - CPU/memory utilization
    """
    results = []
    for rep in range(reps):
        run_ids = []
        start = time.time()
        
        # Submit N jobs in parallel
        for i in range(level):
            # Call Dagster API or GraphQL to launch run
            run_id = dagster_launch_run(job_name="thesis_workload")
            run_ids.append(run_id)
        
        # Poll until all complete
        # Collect metrics: success rate, execution times, resource util
        metrics = collect_metrics(run_ids)
        results.append(metrics)
    
    return aggregate_results(results)
```

### 5.3 Metrics Collection
```python
# scripts/collect_metrics.py
import psutil
import subprocess
import json

def vm_metrics():
    """Collect CPU, memory, load from psutil"""
    return {
        "cpu_percent": psutil.cpu_percent(interval=1),
        "memory_percent": psutil.virtual_memory().percent,
        "load_avg": os.getloadavg(),
    }

def k8s_metrics():
    """Collect from kubectl top and events"""
    # kubectl top pods -n dagster
    # kubectl get events -n dagster
    pass
```

---

## 6. RECOMMENDED FIXES (Priority Order)

### WEEK 1 (Before experiments)
1. ✅ **Fix gRPC server** — without this, Dagster can't load workload
2. ✅ **Fix uv activation** — without this, dependencies won't be found in container
3. ✅ **Rename workspace.yml → workspace.yaml** — standardize file naming
4. ✅ **Test Containerfile builds locally** — `podman build -f Containerfile`
5. ⚠️ **Push images to ghcr.io** — `podman push ghcr.io/sirajwahaj/thesis-workload:v0.1`

### WEEK 2 (Parallel)
6. 🔨 **Set up Multipass VM** — deploy Dagster + PostgreSQL, same config as docker-compose
7. 🔨 **Set up Kind cluster** — deploy Dagster with Kubernetes Run Launcher (Helm)
8. 🔨 **Create workload harness** — submit 1, 2, 4, 8, 12, 16 jobs; collect metrics
9. 🔨 **Test on both VMs** — does workload run? Does it create CPU contention?

### WEEK 3 (Run experiments)
10. 🧪 **Exp 1: VM degradation** — execute 6 levels × 3 reps, collect data
11. 🧪 **Exp 2A: K8s isolation** — execute same, compare results
12. 🧪 **Derive crossover** — plot both degradation curves, find intersection

---

## 7. USING `uv` PROPERLY

### Good ✅
```toml
# pyproject.toml structure is correct
[project]
name = "src"
version = "0.1.0"
requires-python = ">=3.13"
dependencies = ["dagster>=1.12.22", ...]
```

### Needs Fix ❌
```dockerfile
# Current broken pattern
RUN uv venv
RUN uv sync --frozen
# .venv exists but not in $PATH

# Fixed pattern
RUN uv venv
ENV VIRTUAL_ENV=/opt/dagster/app/.venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN uv sync --frozen
RUN uv pip install --editable .

# Alternative (simpler): just use uv directly
RUN uv pip install -e .
# uv handles venv creation internally
```

### Do you need `__init__.py`?
- For `workload/` to be importable as a package: **YES**, add `workload/__init__.py`
- For uv: **NO**, uv doesn't require it

---

## 8. PODMAN-COMPOSE vs DOCKER-COMPOSE

Your `docker-compose.yml` syntax is **fully compatible** with `podman-compose`:
```bash
podman-compose -f Infrastr/docker-compose.yml up -d
# Same as: docker-compose up -d
```

No changes needed. ✅

---

## 9. THESIS ALIGNMENT SUMMARY

| Aspect | Status | Notes |
|---|---|---|
| **Workload design** | ✅ Correct | SHA-256 CPU burn is right |
| **Containerization** | ⚠️ Partially | Needs gRPC + uv fixes |
| **K8s readiness** | ❌ Not ready | No Kind, no K8s Run Launcher |
| **VM baseline** | ❌ Not ready | No Multipass setup |
| **Metrics collection** | ❌ Missing | No data gathering scripts |
| **Crossover analysis** | ❌ Can't do yet | Need Exp 1 + 2A data |
| **ghcr.io registry** | ✅ Right choice | Good for reproducibility |
| **uv packaging** | ⚠️ Needs fix | Activation missing in Containerfile |
| **PostgreSQL backend** | ✅ Correct | Stateful, matches proposal |

---

## 10. NEXT IMMEDIATE ACTION

**TODAY**: 
1. Fix the gRPC server (workload must expose on port 4000)
2. Fix uv activation in Containerfile
3. Rename `workspace.yml` → `workspace.yaml`
4. Test `podman build` locally
5. Verify `docker-compose up` runs without the stat error

**This week**:
6. Push images to ghcr.io
7. Set up Multipass VM and Kind cluster
8. Create workload harness + metrics collection
9. Run first smoke test on both platforms

---

## Questions?

- Is the Dagster version (1.12.22) correct? (Check your LIA1 internship documentation)
- Which podman/docker version are you using?
- Do you have write access to ghcr.io/sirajwahaj?
- Can you spin up Multipass on your MacBook (4 vCPU, 8 GB RAM available)?

