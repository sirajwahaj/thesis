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
   utm                 python312
   python@3.12         ansible (via pip)
        │               │
        ▼               ▼
   create-vm-macos.sh  create-vm-windows.ps1
   (UTM + Ubuntu ARM64 ISO) (VirtualBox + Ubuntu x86-64 ISO)
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
       │                                   │
  roles/python312              roles/postgresql16
  - Python 3.12 (deadsnakes)   - PostgreSQL 16 (PGDG)
  - venv at /opt/thesis/venv   - dagster role + database
       │
  roles/dagster
  - Dagster 1.12.7 (pip)
  - dagster.yaml + workspace.yaml
  - DAGSTER_HOME = /opt/thesis/dagster_home
       │
  roles/workload
  - Copy workload source to /opt/thesis/workload/
  - systemd service: thesis-workload.service
  - dagster api grpc -h 0.0.0.0 -p 4000 -m workload
```

**Experiment flow on VM:**
```
Experiment runner (host)
        │  SSH
        ▼
  thesis-vm (Ubuntu 22.04, 4 vCPU, 8 GB)
        │
  Dagster Webserver (localhost:3001)
        │  gRPC
  Dagster Workload Server (0.0.0.0:4000)
        │  docker run (DockerRunLauncher)
  Docker container → cpu_burn() → SHA-256 for 30s
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
| Total RAM | 8 GB | 8 GB (Kind node) |
| Per-run CPU | 1 vCPU (nano_cpus=1e9, Docker) | 1 vCPU limit (K8sRunLauncher) |
| Per-run RAM | 1 Gi limit (mem_limit, Docker) | 1 Gi limit (K8sRunLauncher) |
| Execution isolation | Docker container (per-job) | K8s Pod (isolated namespaces) |
| Failure isolation | Container-level via Docker daemon | Pod-level (kill pod, others continue) |

This matching ensures that any performance difference is attributable to the execution model (Docker on a single-host daemon vs. Kubernetes pod scheduling), not hardware or resource-limit differences.

---

## Design Decisions

### Why UTM Instead of VirtualBox on macOS?

VirtualBox does not support ARM64 hypervisor operations on Apple Silicon (M-series) Macs. UTM uses Apple's native Hypervisor.framework (HVF), which:
- Supports native ARM64 guest VMs
- Provides better performance (no binary translation)
- Offers better CPU isolation (critical for SQ1: VM contention experiments)

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

### Why Multipass Is Not the Primary VM?

- Multipass wraps QEMU with resource limits, but contention between QEMU threads and host processes is less predictable than dedicated UTM vCPUs
- For SQ1 (finding the VM contention threshold), we need the most realistic CPU contention model possible
- Multipass is documented as a lightweight alternative for development iteration

### Why Helm for Dagster on K8s?

- The official Dagster Helm chart handles complex multi-component deployment (webserver, daemon, grpc servers, RBAC, ConfigMaps)
- Custom Helm chart (`dagster-thesis`) wraps a minimal subset of what's needed
- Declarative: `make k8s-reset` fully recreates the environment from the same chart
- Easier to version and reproduce than imperative `kubectl apply` chains

---

## VM IP Auto-Discovery

The script `scripts/create-vm-macos.sh` uses a 4-stage discovery pipeline to find the VM's
IP without manual input. This is necessary because UTM has no CLI for querying VM network
addresses.

```
Stage 1: vm-ip.txt         — check persisted IP from previous run (instant, zero network I/O)
Stage 2: mDNS              — thesis-vm.local via avahi-daemon (works after Ansible provision)
Stage 3: ARP cache scan    — macOS ARP table for 192.168.64.x and 10.0.2.x (instant)
Stage 4: Ping sweep        — fire parallel pings at first 30 addresses, re-scan ARP (~5s)
Stage 5: Manual fallback   — interactive prompt, only if all above fail
```

**Why UTM DHCP causes IP changes:**
UTM's Shared Network mode uses QEMU's SLiRP userspace networking (or Apple Hypervisor NAT on
ARM). The VM gets a DHCP lease in the `192.168.64.0/24` range, but leases are not guaranteed
to be stable across VM reboots. UTM does not expose a CLI to query the assigned IP.

**Why mDNS is the long-term solution:**
After `make vm-provision` runs Ansible, `avahi-daemon` is installed and the VM advertises
itself as `thesis-vm.local`. This hostname resolves across reboots without ever touching the
IP, making it the most stable method. The ARP/ping sweep serves as the bootstrap method for
the very first run (before Ansible has provisioned the VM).

---

## Container Runtime — Role Clarification

The thesis uses containers in **both** environments. The comparison is about container-orchestration
architecture, not containers vs. bare processes.

### macOS host — podman

```
macOS host
  └─ podman machine 'thesis'   ← lightweight Linux VM
       └─ podman build          ← builds workload image (src/Containerfile)
       └─ podman push           ← pushes to localhost:5001 (local Kind registry)
            └─ Kind cluster pulls image for K8s run pods
```

Podman on the macOS host builds and pushes the OCI image. Both environments consume this same image.

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
| macOS host | podman machine | Build + push workload image |
| macOS host | kind + kubectl | Run K8s cluster for K8s experiments |
| Ubuntu VM | Docker CE + DockerRunLauncher | Each Dagster job = Docker container |
| Ubuntu VM | systemd | Manage Dagster gRPC server + webserver + daemon |

---

*See [setup.md](setup.md) for macOS setup instructions.*
*See [setup-windows.md](setup-windows.md) for Windows setup instructions.*
*See [multipass-alternative.md](multipass-alternative.md) for the lightweight alternative.*
