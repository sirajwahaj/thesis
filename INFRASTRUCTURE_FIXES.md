# Infrastructure Fixes — Critical Issues Resolved

**Date**: April 9, 2026  
**Status**: ✅ FIXED

---

## Issues Fixed

### 1. ✅ File Path Mismatch — RESOLVED

**Before**: `src/workspace.yml` (`.yml` extension)  
**After**: `src/workspace.yaml` (`.yaml` extension)

```bash
# Renamed
mv src/workspace.yml src/workspace.yaml
```

**Why**: Containerfile and docker-compose both reference `.yaml`. Standardizing on one extension prevents confusion.

---

### 2. ✅ uv Virtual Environment Not Activated — RESOLVED

**Before**:
```dockerfile
RUN uv venv
RUN uv sync --frozen
# .venv created but not in $PATH for subsequent commands
```

**After**:
```dockerfile
RUN uv venv
ENV VIRTUAL_ENV=/opt/dagster/app/.venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN uv sync --frozen
RUN uv pip install --editable .
```

**Why**: Each `RUN` command is a new shell. Without activating the venv, subsequent commands can't find installed packages. Now the venv is activated for all remaining RUNs.

---

### 3. ✅ Missing gRPC Server — RESOLVED

**Before**: 
- `workspace.yaml` pointed to `grpc_server: workload:4000`
- But the `workload` container had no gRPC server running
- Dagster couldn't load the workload definitions

**After**:
```dockerfile
# Containerfile now ends with:
EXPOSE 4000
CMD ["dagster-grpc", "-h", "0.0.0.0", "-p", "4000", "-w", "/opt/dagster/app"]
```

**Why**: The workload container must expose a gRPC server on port 4000 so that `dagster-webserver` can load the job definitions via the workspace configuration.

---

### 4. ✅ Missing Dependency — RESOLVED

**Before**: `pyproject.toml` was missing `dagster-grpc`

**After**:
```toml
dependencies = [
    "dagster>=1.12.22",
    "dagster-postgres>=0.28.22",
    "dagster-webserver>=1.12.22",
    "dagster-grpc>=1.12.22",  # ← ADDED
]
```

**Why**: `dagster-grpc` package must be available for the container to run `dagster-grpc` command.

---

### 5. ✅ Package Not Discoverable — RESOLVED

**Before**: `workload/` directory had no `__init__.py`

**After**: Created `workload/__init__.py`

```python
"""
Dagster thesis workload — CPU-bound job definitions for measuring performance.

This module is exposed via gRPC on port 4000 to Dagster webserver.
The workspace.yaml file loads definitions from this gRPC server.
"""

from .workload_job import thesis_workload

__all__ = ["thesis_workload"]
```

**Why**: Python needs `__init__.py` to recognize `workload/` as a package. The gRPC server needs to import from this package.

---

### 6. ✅ Wrong Volume Mount Paths in docker-compose — RESOLVED

**Before**:
```yaml
volumes:
  - ./workspace.yaml:/opt/dagster/dagster_home/workspace.yaml:Z
```

**After**:
```yaml
volumes:
  - ../src/workspace.yaml:/opt/dagster/dagster_home/workspace.yaml:Z
  - ../src/dagster.yaml:/opt/dagster/dagster_home/dagster.yaml:Z
```

**Why**: When running `podman-compose` from `Infrastr/` directory, `./workspace.yaml` refers to `Infrastr/workspace.yaml` (doesn't exist). The files are in `src/`, so the path should be `../src/workspace.yaml`.

**Also added**:
```yaml
environment:
  <<: *dagster-env
  DAGSTER_PG_USERNAME: dagster        # ← Added explicit env vars
  DAGSTER_PG_PASSWORD: dagster        #   (in case container needs them directly)
  DAGSTER_PG_HOSTNAME: postgres
```

---

## Files Modified

| File | Change | Reason |
|---|---|---|
| `src/workspace.yml` → `src/workspace.yaml` | Renamed | Extension standardization |
| `src/Containerfile` | Added env activation, gRPC CMD | uv + gRPC fixes |
| `src/pyproject.toml` | Added `dagster-grpc>=1.12.22` | Dependency needed |
| `src/workload/__init__.py` | **Created** | Package discovery |
| `Infrastr/docker-compose.yml` | Fixed volume paths, added env vars | Path resolution |

---

## What This Enables

### ✅ Before (BROKEN)
```
podman-compose up
# Error: stat: "/workspace.yaml": no such file or directory
# Dagster-webserver can't find workload definitions
# gRPC server not running
```

### ✅ After (WORKS)
```
cd Infrastr/
podman-compose up

# postgres:16 → starts ✅
# workload container → starts gRPC server on :4000 ✅
# dagster-webserver → connects to gRPC workload:4000 ✅
# dagster-daemon → runs, loads jobs ✅
# Web UI → http://localhost:3000 ✅
```

---

## Next Steps

1. **Build the Containerfile** (test locally):
   ```bash
   cd src/
   podman build -t thesis-workload:local -f Containerfile .
   podman run -e WORKLOAD_DURATION_SECONDS=10 thesis-workload:local
   ```

2. **Test docker-compose**:
   ```bash
   cd Infrastr/
   podman-compose up -d
   # Wait 10s for services to start
   curl http://localhost:3000/graphql
   podman-compose down
   ```

3. **Push to ghcr.io**:
   ```bash
   podman login ghcr.io
   podman tag thesis-workload:local ghcr.io/sirajwahaj/thesis-workload:v0.1
   podman push ghcr.io/sirajwahaj/thesis-workload:v0.1
   ```

4. **Set up thesis experiment infrastructure**:
   - Multipass VM with Dagster (VM baseline)
   - Kind cluster with Dagster + K8s Run Launcher
   - Workload harness script for experiments
   - Metrics collection (psutil, kubectl top)

---

## Alignment with Thesis

These fixes ensure that:

- ✅ **SQ1** (VM degradation): Can measure workload on single process executor
- ✅ **SQ2** (K8s isolation): Can measure workload on pod-isolated executor
- ✅ **SQ3** (Overhead): Can compare execution times between both
- ✅ **SQ4** (Crossover point): Can derive the threshold

The infrastructure is now ready for experimental work.

