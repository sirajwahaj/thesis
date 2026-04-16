# Validation Checklist — Infrastructure Ready for Testing

**Goal**: Verify that the infrastructure fixes work and the system is ready for thesis experiments.

---

## Phase 1: Local Build Test (Do This First)

### ✅ Step 1.1: Build Containerfile Locally

```bash
cd /Users/sirajulhaqwahaj/thesis/src
podman build -t thesis-workload:local -f Containerfile .
```

**Expected output**:
```
...
STEP 13/13: CMD ["dagster-grpc", "-h", "0.0.0.0", "-p", "4000", "-w", "/opt/dagster/app"]
COMMIT thesis-workload:local
--> <image_id>
Successfully tagged localhost/thesis-workload:local
```

**If you see errors**:
- `No such file or directory: workspace.yaml` → workspace.yaml wasn't renamed
- `No module named 'workload'` → workload/__init__.py missing
- `No module named 'dagster_grpc'` → dagster-grpc not in dependencies

---

### ✅ Step 1.2: Test Containerfile Runs

```bash
# Test 1: Can the container start?
podman run --rm thesis-workload:local echo "Container starts OK"

# Test 2: Are dependencies installed?
podman run --rm thesis-workload:local python -c "import dagster; print(dagster.__version__)"

# Test 3: Can it find the workload?
podman run --rm thesis-workload:local python -c "from workload import thesis_workload; print('Workload loaded!')"
```

**Expected**:
```
Container starts OK
1.12.22
Workload loaded!
```

---

## Phase 2: Docker-Compose Test

### ✅ Step 2.1: Check File Paths

```bash
cd /Users/sirajulhaqwahaj/thesis/Infrastr
ls -la ../src/workspace.yaml ../src/dagster.yaml
```

**Expected**: Both files exist.

---

### ✅ Step 2.2: Start Services (Using Local Images)

```bash
cd /Users/sirajulhaqwahaj/thesis/Infrastr

# Edit docker-compose.yml temporarily to use local images:
# Change:
#   image: ghcr.io/sirajwahaj/thesis-workload:v0.1
# To:
#   image: thesis-workload:local

# Or override on command line:
podman-compose up \
  -d \
  --file docker-compose.yml \
  -e "image=thesis-workload:local"

# Actually, simpler: just edit the file for testing
nano docker-compose.yml
# Change ghcr.io/sirajwahaj/thesis-workload:v0.1 → thesis-workload:local
# Change ghcr.io/sirajwahaj/thesis-dagster:v0.1 → (use your local dagster image or pull from registry)
```

**For now, focus on postgres + workload**:

```bash
# Start just postgres + workload
podman run -d --name postgres --network dagster_network \
  -e POSTGRES_USER=dagster \
  -e POSTGRES_PASSWORD=dagster \
  -e POSTGRES_DB=dagster \
  postgres:16

podman run -d --name workload --network dagster_network \
  -e DAGSTER_HOME=/opt/dagster/dagster_home \
  thesis-workload:local
```

**Check if workload gRPC server is running**:
```bash
# Connect from another container and test gRPC
podman run --rm --network dagster_network \
  python:3.12-slim \
  python -c "
import socket
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
result = sock.connect_ex(('workload', 4000))
if result == 0:
    print('gRPC server is running on workload:4000')
else:
    print('gRPC server NOT running')
sock.close()
"
```

**Expected**: `gRPC server is running on workload:4000`

---

### ✅ Step 2.3: Clean Up

```bash
podman rm -f postgres workload
podman network rm dagster_network 2>/dev/null || true
```

---

## Phase 3: File Integrity

### ✅ Step 3.1: Verify All Files Exist and Are Correct

```bash
# Check workspace.yaml exists and is valid YAML
cd /Users/sirajulhaqwahaj/thesis/src
cat workspace.yaml

# Expected:
# load_from:
#   - grpc_server:
#       host: workload
#       port: 4000
```

```bash
# Check Containerfile has gRPC
grep -n "dagster-grpc" Containerfile

# Expected:
# Line with: CMD ["dagster-grpc", "-h", "0.0.0.0", "-p", "4000", "-w", "/opt/dagster/app"]
```

```bash
# Check pyproject.toml has dagster-grpc
grep "dagster-grpc" pyproject.toml

# Expected:
# "dagster-grpc>=1.12.22",
```

```bash
# Check workload/__init__.py exists
ls -la workload/__init__.py

# Expected: file should exist
```

```bash
# Check docker-compose volume paths
cd /Users/sirajulhaqwahaj/thesis/Infrastr
grep -A2 "volumes:" docker-compose.yml | head -10

# Expected:
# - ../src/workspace.yaml:/opt/dagster/dagster_home/workspace.yaml:Z
# - ../src/dagster.yaml:/opt/dagster/dagster_home/dagster.yaml:Z
```

---

## Phase 4: Thesis Infrastructure (Next)

### When Ready — Set Up Experimental Environments

```bash
# VM Environment (Multipass)
multipass launch --name thesis-vm --cpus 4 --memory 8G --disk 40G

# Kind Cluster
kind create cluster --name thesis-k8s

# Install Dagster on both + deploy workload
# (See INFRASTRUCTURE_FEEDBACK.md for detailed steps)
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Error: building at STEP "COPY workspace.yaml": no such file or directory` | workspace.yaml not renamed | `cd src && mv workspace.yml workspace.yaml` |
| `ModuleNotFoundError: No module named 'workload'` | workload/__init__.py missing | Create `workload/__init__.py` |
| `ModuleNotFoundError: No module named 'dagster_grpc'` | dagster-grpc not in dependencies | Add `dagster-grpc>=1.12.22` to pyproject.toml |
| `.venv/bin/dagster-grpc: Command not found` | venv not activated | Check Containerfile has `ENV PATH="$VIRTUAL_ENV/bin:$PATH"` |
| `COPY workspace.yaml: file not found in current dir or Dockerfile` | Dockerfile trying to copy from wrong directory | Ensure `COPY workspace.yaml` runs from `src/` directory |
| `gRPC server NOT running` | CMD not starting dagster-grpc | Check Containerfile ends with `CMD ["dagster-grpc", ...]` |
| `volume mount not found` | docker-compose volume paths wrong | Use `../src/workspace.yaml` not `./workspace.yaml` |

---

## Success Criteria

✅ **All of these must be TRUE**:

- [ ] Containerfile builds without errors
- [ ] Container can be run with `podman run`
- [ ] Python dependencies are installed (test with `python -c "import dagster"`)
- [ ] Workload package is discoverable (test with `from workload import thesis_workload`)
- [ ] gRPC server starts on port 4000
- [ ] docker-compose uses correct volume paths (`../src/`)
- [ ] workspace.yaml file exists as `.yaml` (not `.yml`)

---

## Recommendation

**Run Phase 1 and 2 today** to confirm the fixes work.  
**Then proceed to thesis experimental setup** (Multipass + Kind) next.

The infrastructure is now **thesis-ready** once you confirm these tests pass.

