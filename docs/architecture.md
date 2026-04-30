# Architecture — Cross-Platform Benchmarking Environment

## System Overview

The thesis benchmarking environment compares two execution models:

1. **VM execution** — Dagster runs jobs as OS processes on a single Ubuntu VM
2. **K8s execution** — Dagster runs jobs as isolated Kubernetes Pods on a Kind cluster

Both environments run on the same physical machine (or equivalent hardware) with matched resource allocations to ensure fair comparison.

---

## Bootstrap Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  make bootstrap  (entry point)                                       │
│  scripts/bootstrap.sh (macOS) | scripts/bootstrap.ps1 (Windows)     │
└───────────────┬─────────────────────────────────────────────────────┘
                │ detects OS
        ┌───────┴───────┐
        │               │
        ▼               ▼
   macOS               Windows
   setup-macos.sh      setup-windows.ps1
        │               │
        ▼               ▼
   Homebrew            Chocolatey
   podman              docker-desktop
   kind                virtualbox
   kubectl             kubernetes-cli
   helm                helm
   ansible             kind
   multipass           python312
   python@3.13         ansible (via pip)
        │               │
        ▼               ▼
   (Multipass + Ubuntu 22.04) (VirtualBox + Ubuntu x86-64 ISO)
        │               │
        └───────┬───────┘
                ▼
           vm-ip.txt
           (saved VM IP address)
```

---

## VM Environment

```
┌─────────────────────────────────────────────────────────────────────┐
│  make vm-provision                                                   │
│  scripts/provision-vm.sh → generates ansible/inventory.ini          │
└───────────────┬─────────────────────────────────────────────────────┘
                ▼
   ansible-playbook provision-vm.yml
                │
       ┌────────┴──────────────────────────┐
       │
  roles/docker
  - Docker CE (Ubuntu package)
  - Docker Compose plugin
  - ubuntu user added to docker group
       │
  All Dagster services run as Docker containers (docker-compose)
  - webserver, daemon, PostgreSQL, gRPC workload server
  - DockerRunLauncher spawns each job as isolated Docker container
```

**Experiment flow on VM:**
```
Experiment runner (host)
        │  SSH
        ▼
  thesis-vm (Ubuntu 22.04, 4 vCPU, 4 GB)
        │
  Dagster Webserver (localhost:3001)
        │  gRPC
  Dagster Workload Server (0.0.0.0:4000)
        │  docker run (DockerRunLauncher)
  Docker container → cpu_burn() → SHA-256 for 30s → memory_pressure() → 400MB + hashing for 30s
        │  1 vCPU (nano_cpus), 1 GB mem_limit
        │
  PostgreSQL 16 (run history)
```

---

## Kubernetes Environment

```
┌─────────────────────────────────────────────────────────────────────┐
│  make k8s-setup                                                      │
└───────────────┬─────────────────────────────────────────────────────┘
                │
        ┌───────┼───────────────┐
        ▼       ▼               ▼
  k8s-create  k8s-metrics  k8s-deploy-dagster
create-kind    deploy-       deploy-dagster-k8s.sh
-cluster.sh    metrics-
               server.sh

Kind Cluster 'thesis' (single-node)
┌─────────────────────────────────────────────────────────────────────┐
│  Namespace: dagster                                                  │
│                                                                      │
│  ┌──────────────┐   gRPC   ┌──────────────────────────────────────┐ │
│  │   Webserver  │ ──────→  │  Workload gRPC Server                │ │
│  │  (NodePort   │          │  (dagster api grpc -m workload)       │ │
│  │   30001)     │          └──────────────────────────────────────┘ │
│  └──────────────┘                                                    │
│         │                                                            │
│         │ PostgreSQL                                                  │
│  ┌──────────────┐                                                    │
│  │  PostgreSQL  │                                                    │
│  │  (Bitnami)   │                                                    │
│  └──────────────┘                                                    │
│                                                                      │
│  ┌──────────────┐  launch pod  ┌─────────────────────────────────┐  │
│  │    Daemon    │ ──────────→  │  Run Pod (K8sRunLauncher)        │  │
│  │  (K8sRunLau- │              │  thesis-workload:latest          │  │
│  │   ncher)     │  isolated    │  cpu_burn() ~ 30s                │  │
│  └──────────────┘              │  1 vCPU limit, 1 Gi memory limit │  │
│                                └─────────────────────────────────┘  │
│                                                                      │
│  Namespace: kube-system                                              │
│  Metrics Server (kubectl top pod/node)                               │
└─────────────────────────────────────────────────────────────────────┘

Host:5001 ← kind-registry (local image registry for loading images)
Host:3001 ← Kind NodePort mapping (Dagster UI)
```

**Experiment flow on K8s:**
```
Experiment runner (host)
        │  kubectl / API
        ▼
  Kind cluster 'thesis'
        │
  Dagster Daemon (K8sRunLauncher)
        │  creates Pod
        ▼
  Run Pod (isolated) → cpu_burn() → SHA-256 for 30s
        │  completes / fails
  Pod lifecycle: Pending → Running → Completed/Failed
        │  metrics
  Metrics Server → kubectl top pod (CPU/mem data)
        │  pod events
  Pod events → collect_pod_timing.py (scheduling latency)
```

---

## Data Flow

```
Experiment (run_experiment.sh)
        │
  ┌─────┴──────────────────────────────────────────┐
  │  trigger_dagster_runs.py  (N concurrent runs)  │
  │  collect_vm_metrics.py    (CPU/mem every 1s)   │
  │  collect_k8s_metrics.sh   (kubectl top 2s)     │
  │  collect_pod_timing.py    (scheduling latency) │
  │  export_dagster_runs.py   (success rate, time) │
  └─────┬──────────────────────────────────────────┘
        │
  data/raw/exp{N}/{env}/L{level}/run{rep}/
  ├── dagster_runs.csv    (success rate, execution time)
  ├── vm_metrics.csv      (CPU %, memory %)
  ├── k8s_metrics.csv     (pod CPU/mem)
  ├── pod_timing.json     (scheduling + startup latency)
  └── blast_radius.csv    (failure containment data)
        │
  notebooks/analysis.ipynb
        │
  results/*.png  →  docs/figures/  →  LaTeX thesis
```

---

## Resource Allocation Matching

Both environments are deliberately configured with matched resource limits:

| Resource | VM | K8s |
|----------|-----|-----|
| Total vCPUs | 4 | 4 (Kind node) |
| Total RAM | **4 GB** (constrained) | 8 GB (Kind node) |
| Per-run CPU | 1 vCPU (nano_cpus=1e9, Docker) | 1 vCPU limit (K8sRunLauncher) |
| Per-run RAM | unrestricted (OOM test) | **600Mi limit** (blast radius containment) |
| Memory per job | 400 MB (memory_pressure op) | 400 MB (same, pod limit prevents cascade) |
| Execution isolation | Docker container (per-job) | K8s Pod (isolated namespaces) |
| Failure isolation | Container-level via Docker daemon | Pod-level (kill pod, others continue) |

This matching ensures that any performance difference is attributable to the execution model (Docker on a single-host daemon vs. Kubernetes pod scheduling), not hardware or resource-limit differences.

---

## Design Decisions

### Why Multipass on macOS?

- Multipass provides a simple CLI for Ubuntu VM management on macOS (both Intel and Apple Silicon)
- `multipass launch` creates a VM with one command; no GUI or ISO management required
- VM IP is queryable via `multipass info thesis-vm` — no ARP scan or mDNS needed
- Works with Ansible over SSH using the default `ubuntu` user (cloud-init)

### Why VirtualBox on Windows?

VirtualBox is the most widely available free hypervisor on Windows x86-64. Docker Desktop with WSL2 cannot be used as the primary VM because it shares the host kernel and does not provide true process isolation comparable to a separate VM.

### Why Ansible (Not Terraform)?

- Terraform is designed for infrastructure provisioning (cloud, DNS, networking) with state management
- Ansible is designed for configuration management (what software goes on a machine)
- A single VM provisioning task is idempotent configuration — Ansible is the right tool
- Simpler learning curve; playbooks are readable YAML
- No state file to manage or lose

### Why Kind (Not minikube)?

- Kind (`kubernetes-in-docker`) is lighter and faster for single-node clusters
- minikube spins up a full VM inside the VM — double virtualisation overhead
- Kind mounts the Docker/podman socket directly; no extra hypervisor layer
- Kind clusters are ephemeral and reproducible (`make k8s-destroy && make k8s-create`)

### Why Helm for Dagster on K8s?

- The official Dagster Helm chart handles complex multi-component deployment (webserver, daemon, grpc servers, RBAC, ConfigMaps)
- Custom Helm chart (`dagster-thesis`) wraps a minimal subset of what's needed
- Declarative: `make k8s-reset` fully recreates the environment from the same chart
- Easier to version and reproduce than imperative `kubectl apply` chains

---

## VM IP Auto-Discovery

With Multipass (macOS), the VM IP is retrieved directly via the Multipass CLI:

```bash
multipass info thesis-vm | awk '/^IPv4:/ {print $2}'
```

This is saved to `vm-ip.txt` automatically by `scripts/setup-macos.sh` and
`scripts/provision-vm.sh` on every run. On Windows (Vagrant + VirtualBox), the
VM IP is written to `vm-ip.txt` by `scripts/bootstrap.ps1`.

**IP resolution order in `provision-vm.sh`:**
1. `$VM_IP` environment variable (explicit override)
2. `multipass info thesis-vm` (auto-detect from Multipass on macOS)
3. `vm-ip.txt` (fallback from last known good IP)
4. Error and exit — asking user to run `make bootstrap`

---

## Container Runtime — Role Clarification

The thesis uses containers in **both** environments. The comparison is about container-orchestration
architecture, not containers vs. bare processes.

### macOS host — Multipass + Docker CLI

```
macOS host
  └─ Multipass VM 'thesis-vm'   ← Ubuntu 22.04 VM (Docker CE inside)
       └─ docker build           ← builds workload image (src/Containerfile)
       └─ docker push            ← pushes to localhost:5001 (local Kind registry)
            └─ Kind cluster pulls image for K8s run pods
```

The workload image is built inside the Multipass VM (where Docker CE is installed via Ansible). Both environments (VM and K8s) consume this same OCI image.

### Ubuntu VM — Docker CE + DockerRunLauncher

```
Ubuntu VM
  └─ Dagster Webserver  ← Python process
  └─ Dagster Daemon     ← Python process
  └─ gRPC server        ← Python process (systemd: thesis-workload.service)
       └─ DockerRunLauncher: each job = `docker run --name dagster-run-<id>`
            └─ cpu_burn() in isolated Docker container
               1 vCPU (nano_cpus), 1 GB mem_limit, auto_remove=true
```

Docker CE is installed on the VM by Ansible (`ansible/roles/docker/`). Each Dagster job run is
a separate Docker container, isolated from siblings by Docker's cgroup limits.

### Kind cluster — K8sRunLauncher

```
Kind cluster
  └─ Dagster Daemon (K8sRunLauncher)
       └─ kubectl create pod ← each job = Kubernetes pod
            └─ thesis-workload:latest (same OCI image)
               1 vCPU limit, 1 Gi memory limit
               Full pod namespace isolation
```

### Why both use containers

The research question is: "At what workload level does migrating from a **single-VM Docker executor**
to a **Kubernetes Run Launcher** become net beneficial?"

| Dimension | VM (DockerRunLauncher) | K8s (K8sRunLauncher) |
|-----------|------------------------|----------------------|
| Job runtime | Docker container | Kubernetes pod |
| Resource limits | Docker `nano_cpus` + `mem_limit` | K8s `requests`/`limits` |
| Failure blast radius | Docker daemon mediates; containers can cascade | Pod failure is contained |
| Scheduling overhead | Docker daemon start only | Pod scheduling + container start |
| Infrastructure complexity | Single daemon on one host | Full K8s control plane |

This comparison is more realistic than process-vs-pod: it reflects real migration decisions
(moving from Docker-hosted Dagster to Kubernetes-hosted Dagster).

### Summary

| Where | Tool | Purpose |
|-------|------|---------|
| macOS host | Multipass | Ubuntu 22.04 VM for DockerRunLauncher experiments |
| macOS host | kind + kubectl | Run K8s cluster for K8s experiments |
| Ubuntu VM | Docker CE + DockerRunLauncher | Each Dagster job = Docker container |
| Ubuntu VM | systemd | Manage Dagster gRPC server + webserver + daemon |

---

*See [setup.md](setup.md) for macOS setup instructions.*
*See [setup-windows.md](setup-windows.md) for Windows setup instructions.*
*See [multipass-alternative.md](multipass-alternative.md) for the lightweight alternative.*
