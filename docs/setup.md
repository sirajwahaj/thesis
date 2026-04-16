# Setup Guide — macOS (Apple Silicon / Intel)

This guide gets you from a clean macOS machine to a fully operational benchmarking environment for the thesis experiments.

## Prerequisites (You Need These First)

| Requirement | Version | Notes |
|-------------|---------|-------|
| macOS | 12+ (Monterey+) | Apple Silicon (M1/M2/M3) or Intel |
| Terminal | any | zsh or bash |
| Internet | — | ~3 GB downloads for ISO + containers |
| disk space | 80 GB free | VM (60 GB) + containers + data |

No other tools need to be installed manually — the bootstrap script handles everything else.

---

## Quick Start

```bash
# Clone the repo (if you haven't already)
git clone https://github.com/sirajwahaj/thesis.git
cd thesis

# Step 1: Install all dependencies and create the VM
make bootstrap

# Step 2: Provision the VM (Python, Dagster, PostgreSQL via Ansible)
make vm-provision

# Step 3: Set up Kubernetes
make k8s-setup

# Step 4: Run all experiments
make experiments

# Step 5: Analyse results
make analyze
```

Or run **everything** in one command:
```bash
make all
```

---

## Step-by-Step Detail

### Step 1: Bootstrap (`make bootstrap`)

This runs `scripts/bootstrap.sh`, which:

1. Detects macOS and routes to `scripts/setup-macos.sh`
2. Installs Homebrew (if not present)
3. Installs: `podman`, `kind`, `kubectl`, `helm`, `ansible`, `python@3.12`, `utm`
4. Creates a podman machine named `thesis` with 4 vCPU, 8 GB RAM
5. Configures `DOCKER_HOST` in `~/.zshrc` for docker-compose compatibility
6. Creates `data/` directory structure
7. Guides you through creating the Ubuntu VM in UTM

#### First-Time UTM VM Setup

When you run `make bootstrap` for the first time, you'll be prompted to create the VM manually (one-time only).

**Download the ISO:**
- **Apple Silicon (M1/M2/M3):** [Ubuntu 22.04 ARM64 Server ISO](https://cdimage.ubuntu.com/releases/22.04/release/ubuntu-22.04.5-live-server-arm64.iso) (~1.2 GB)
- **Intel Mac:** [Ubuntu 22.04 AMD64 Server ISO](https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso) (~1.5 GB)

**Create VM in UTM:**
1. Open UTM → `+` → `Virtualise`
2. Settings:
   - OS: Linux
   - Boot ISO Image: the downloaded ISO
   - CPU: 4 cores
   - Memory: 8192 MB
   - Storage: 60 GB
   - Network: Shared Network
3. Start VM → Complete Ubuntu installer:
   - Username: `ubuntu` / Password: `ubuntu`
   - Hostname: `thesis-vm`
   - Enable OpenSSH server: **YES**
4. After first boot, add your SSH key:
   ```bash
   # In the UTM console / terminal:
   mkdir -p ~/.ssh
   # Paste the contents of ~/.ssh/thesis_vm.pub from your Mac
   echo "<PUBLIC_KEY_FROM_MAC>" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   # Get V IP:
   ip addr show | grep "inet " | grep -v "127.0.0.1"
   ```
5. Return to terminal on Mac and enter the IP when prompted

**After first-time setup, all future `make bootstrap` calls are fully automatic.**

---

### Step 2: VM Provisioning (`make vm-provision`)

Runs `scripts/provision-vm.sh`, which:
1. Reads VM IP from `vm-ip.txt`
2. Generates `ansible/inventory.ini`
3. Installs `community.postgresql` Ansible Galaxy collection
4. Runs `ansible/playbooks/provision-vm.yml`:
   - Python 3.12 (via deadsnakes PPA)
   - PostgreSQL 16 (PGDG)
   - Dagster 1.12.7 (in virtualenv `/opt/thesis/venv`)
   - Workload gRPC server (as systemd service `thesis-workload`)

**Expected output:**
```
PLAY RECAP *****
thesis-vm : ok=25 changed=18 unreachable=0 failed=0
✅ VM Provisioning Complete
```

**Verify:**
```bash
make vm-validate
ssh -i ~/.ssh/thesis_vm ubuntu@$(cat vm-ip.txt) "systemctl status thesis-workload"
```

---

### Step 3: Kubernetes Setup (`make k8s-setup`)

Runs three sub-steps in sequence:

| Sub-command | What it does |
|-------------|-------------|
| `make k8s-create` | Creates Kind cluster `thesis` (single-node) |
| `make k8s-metrics` | Deploys Metrics Server via Helm (`kubectl top pod` support) |
| `make k8s-deploy-dagster` | Builds image, deploys PostgreSQL + Dagster + workload via Helm |

**Expected result:**
```bash
kubectl get pods -n dagster
# NAME                                       READY   STATUS    RESTARTS
# dagster-thesis-postgresql-0                1/1     Running   0
# dagster-thesis-workload-<hash>             1/1     Running   0
# dagster-thesis-webserver-<hash>            1/1     Running   0
# dagster-thesis-daemon-<hash>               1/1     Running   0
```

Dagster UI accessible at **http://localhost:3001**

---

### Step 4: Validate Everything (`make validate-setup`)

Before running experiments, verify all systems:

```bash
make validate-setup
```

Expected output:
```
── Pre-Experiment Validation ─────────────────────────────────
  [VM]
  ✅ vm-ip.txt: 192.168.64.5
  ✅ SSH: ubuntu@192.168.64.5 reachable
  ✅ gRPC server: listening on port 4000
  ✅ systemd service 'thesis-workload': active

  [Kubernetes]
  ✅ Kind cluster 'thesis': exists
  ✅ Namespace 'dagster': exists
  ✅ Dagster pods: 4 running
  ✅ Metrics Server: kubectl top node works

✅ ALL SYSTEMS READY — experiments can run
```

---

## Resource Verification

After provisioning, verify the VM has the correct resources:

```bash
ssh -i ~/.ssh/thesis_vm ubuntu@$(cat vm-ip.txt)

# Inside VM:
nproc                    # Should output: 4
free -h                  # Should show: ~8.0G total
lsb_release -a          # Should show: Ubuntu 22.04.x
python3.12 --version    # Should show: Python 3.12.x
systemctl status thesis-workload  # Should show: active (running)
```

---

## Troubleshooting

### VM SSH Timeout

**Symptom:** `make bootstrap` fails with "Cannot reach VM" after entering IP.

**Fixes:**
1. Ensure UTM VM is running (green circle in UTM)
2. Check OpenSSH is installed: In UTM console, run `systemctl status ssh`
3. Verify SSH key was added to `~/.ssh/authorized_keys` on the VM
4. Check IP is correct: `ip addr show` inside VM

### podman machine Not Starting

**Symptom:** `podman ps` returns "Cannot connect to Podman"

**Fix:**
```bash
podman machine start thesis
source ~/.zshrc   # reload DOCKER_HOST
```

### kubectl top node Returns "Error"

**Symptom:** `kubectl top node` returns `error: Metrics API not available`

**Fix:** Metrics Server takes 1–2 minutes after deployment. Wait and retry:
```bash
kubectl rollout status deployment/metrics-server -n kube-system
kubectl top node
```

### Helm Dependency Update Fails

**Symptom:** `helm dependency update` fails with Bitnami repo error.

**Fix:**
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
make k8s-deploy-dagster
```

### Port 3001 Already in Use

**Symptom:** Dagster webserver fails to start on port 3001.

**Fix:** Stop local compose stack if running:
```bash
make compose-down
make k8s-deploy-dagster
```

---

## Laptop Specification Recording

For thesis reproducibility, record your machine specs:

```bash
# CPU
sysctl -n machdep.cpu.brand_string

# RAM
system_profiler SPHardwareDataType | grep "Memory:"

# macOS version
sw_vers

# Storage
diskutil info / | grep "Total Size"
```

---

## Multipass Alternative

If you prefer a lighter setup for local testing (not for production experiments), see [multipass-alternative.md](multipass-alternative.md).

---

*See [architecture.md](architecture.md) for the system design and design decisions.*
