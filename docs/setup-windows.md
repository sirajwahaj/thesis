# Setup Guide — Windows

This guide gets you from a clean Windows machine to a fully operational benchmarking environment using VirtualBox and Kind.

> **Note:** All scripts were written to Windows PowerShell/Chocolatey standards but the primary development environment is macOS M2. Report any issues if you encounter Windows-specific failures.

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Windows 10/11 (64-bit) | Professional or Home |
| PowerShell 5.1+ | Built into Windows 10/11 |
| Administrator access | Required for Chocolatey and VirtualBox |
| Internet connection | ~4 GB downloads |
| 80 GB free disk space | VM + containers + data |

---

## Quick Start

Open **PowerShell as Administrator** and run:

```powershell
# Allow scripts to run (set for this session only)
Set-ExecutionPolicy Bypass -Scope Process -Force

# Navigate to repo
cd C:\path\to\thesis

# Step 1: Install all dependencies and create the VM
.\scripts\bootstrap.ps1

# Step 2: Provision the VM via Ansible
make vm-provision

# Step 3: Set up Kubernetes
make k8s-setup

# Step 4: Run experiments
make experiments
```

> **Note:** `make` on Windows requires Git for Windows (installed by bootstrap) or WSL. If `make` is not available, use `mingw32-make`.

---

## Step-by-Step Detail

### Step 1: Bootstrap (`.\scripts\bootstrap.ps1`)

This script:

1. Checks for Administrator privileges
2. Installs Chocolatey (package manager)
3. Installs via Chocolatey:
   - `docker-desktop` (Docker + Kubernetes)
   - `virtualbox` (VM hypervisor)
   - `kubernetes-cli` (kubectl)
   - `kubernetes-helm`
   - `kind`
   - `python312`
   - `git`
4. Installs Ansible via `pip`
5. Creates `data/` directory structure
6. Guides you through VirtualBox VM creation

#### VirtualBox VM Setup

When prompted, create the VM:

**Download ISO:**
- [Ubuntu 22.04 Server AMD64 ISO](https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso) (~1.5 GB)

**Create via VirtualBox Manager (GUI):**
1. Open VirtualBox → New
2. Name: `thesis-vm`, Type: Linux, Version: Ubuntu 64-bit
3. Memory: 8192 MB
4. CPU: 4 (Settings → System → Processor)
5. Disk: 60 GB (VDI, dynamically allocated)
6. Settings → Storage → Add IDE → attach the ISO
7. Settings → Network → Adapter 1 → NAT
8. Settings → Network → Advanced → Port Forwarding:
   - Name: SSH, Host Port: 2222, Guest Port: 22
9. Start VM → Complete Ubuntu installer
   - Username: `ubuntu`, enable SSH server

**Or via PowerShell CLI** (copy from `scripts/create-vm-windows.ps1` output):
```powershell
$ISO = "C:\Users\$env:USERNAME\Downloads\ubuntu-22.04.5.iso"
VBoxManage createvm --name thesis-vm --ostype Ubuntu_64 --register
VBoxManage modifyvm thesis-vm --memory 8192 --cpus 4 --audio=none
VBoxManage modifyvm thesis-vm --nic1 nat --natpf1 "ssh,tcp,,2222,,22"
# ... (full command shown by bootstrap.ps1)
```

**Add SSH key to VM:**
```powershell
# In VirtualBox VM console after Ubuntu boots:
mkdir -p ~/.ssh
# Paste contents of C:\Users\<you>\.ssh\thesis_vm.pub
echo "<PUBLIC_KEY>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Test SSH (via NAT port forwarding):**
```powershell
ssh -i $env:USERPROFILE\.ssh\thesis_vm -p 2222 ubuntu@127.0.0.1
```

---

### Step 2: VM Provisioning (`make vm-provision`)

Uses Ansible to provision the VM. Ansible is installed via pip in Step 1.

If `make` is not available, run directly:
```powershell
bash scripts/provision-vm.sh
# or if using WSL:
wsl bash scripts/provision-vm.sh
```

---

### Step 3: Kubernetes Setup (`make k8s-setup`)

Requires Docker Desktop to be running with Kubernetes enabled:

1. Open Docker Desktop
2. Settings → Kubernetes → Enable Kubernetes → Apply
3. Wait for Kubernetes to start (status bar shows green)

Then:
```powershell
make k8s-setup
# or:
bash scripts/create-kind-cluster.sh
bash scripts/deploy-metrics-server.sh
bash scripts/deploy-dagster-k8s.sh
```

---

## Troubleshooting

### `make` Not Found

Install via Chocolatey:
```powershell
choco install make -y
```

Or use Git Bash (`C:\Program Files\Git\bin\bash.exe`) which includes `make`.

### Ansible Not Found After Install

Restart PowerShell to reload PATH. If still not found:
```powershell
python -m pip install ansible
python -m ansible --version
```

### VirtualBox Conflicts with Hyper-V

Windows 11 Home may have Hyper-V enabled for Docker Desktop. VirtualBox 7+ supports Hyper-V mode:
```powershell
# Enable VirtualBox Hyper-V backend
VBoxManage setextradata global "VBoxInternal2/UseNativeApi" 1
```

### Docker Desktop Kubernetes Not Starting

1. Docker Desktop → Settings → Kubernetes → Reset Kubernetes Cluster
2. Wait 2–3 minutes

### kubectl Not Found

Restart PowerShell after install. If still not found:
```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")
kubectl version --client
```

---

## Limitations vs macOS Setup

| Aspect | macOS | Windows |
|--------|-------|---------|
| VM hypervisor | UTM (native ARM64) | VirtualBox (x86-64) |
| Container runtime | podman (rootless) | Docker Desktop |
| CPU arch | ARM64 or x86-64 | x86-64 only |
| Script language | Bash | PowerShell (bootstrap) + Bash (experiments) |
| Experiment scripts | All native bash | Requires Git Bash or WSL |

---

*See [multipass-alternative.md](multipass-alternative.md) for a lighter Windows setup option.*
