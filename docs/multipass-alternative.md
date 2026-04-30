# Multipass VM Setup

> **Multipass is the primary benchmarking environment** used in all thesis experiments.
> The VM is provisioned automatically via Ansible.
>
> ```bash
> make vm-up && make vm-provision
> ```

---

## Setup Overview

Multipass provides a lightweight Ubuntu VM via QEMU on macOS, provisioned automatically:

| Aspect | Spec |
|--------|------|
| VM creation | Automatic (`multipass launch`) |
| OS | Ubuntu 22.04 LTS |
| vCPU | 4 |
| RAM | 4 GB |
| Hypervisor | QEMU / HVF (ARM64 M-series) |
| ARM64 support | Yes (native) |

**This matches the thesis Table 3.1 specification:** 4 vCPU / 4 GB RAM Multipass VM running the DockerRunLauncher.
- Running experiments on a development machine where exact CPU isolation is not critical

---

## Multipass VM Setup

### Prerequisites

Install Multipass (macOS):
```bash
brew install multipass
# or download from https://multipass.run/
```

Install Multipass (Windows):
```powershell
choco install multipass -y
# or download from https://multipass.run/
```

### Create the VM

```bash
multipass launch 22.04 \
  --name thesis-vm \
  --cpus 4 \
  --memory 4G \
  --disk 60G
```

Verify resources:
```bash
multipass exec thesis-vm -- nproc
# Expected: 4

multipass exec thesis-vm -- free -h
# Expected: ~8.0G total

multipass exec thesis-vm -- lsb_release -a
# Expected: Ubuntu 22.04.x LTS
```

### Get VM IP

```bash
multipass info thesis-vm | grep IPv4
# Example: 192.168.64.10
```

### Configure SSH Access

Multipass uses its own key management, but for Ansible compatibility, add a standard SSH key:

```bash
# Generate key if not done yet
test -f ~/.ssh/thesis_vm || ssh-keygen -t ed25519 -f ~/.ssh/thesis_vm -N "" -C "thesis-vm"

# Add public key to VM
multipass exec thesis-vm -- bash -c "
  mkdir -p ~/.ssh
  echo '$(cat ~/.ssh/thesis_vm.pub)' >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
"

# Test SSH
VM_IP=$(multipass info thesis-vm | grep IPv4 | awk '{print $2}')
echo "$VM_IP" > vm-ip.txt
ssh -i ~/.ssh/thesis_vm -o StrictHostKeyChecking=no ubuntu@$VM_IP "echo connected"
```

### Provision with Ansible

Once SSH is configured, provision the VM exactly the same way as the primary setup:

```bash
make vm-provision
```

This uses the same Ansible playbook (`ansible/playbooks/provision-vm.yml`) regardless of whether the VM was created by UTM or Multipass.

### Verify Dagster is Running

```bash
VM_IP=$(cat vm-ip.txt)

# Check systemd service
ssh -i ~/.ssh/thesis_vm ubuntu@$VM_IP "systemctl status thesis-workload"

# Verify gRPC port
ssh -i ~/.ssh/thesis_vm ubuntu@$VM_IP "nc -zv localhost 4000"

# Run Dagster health check
ssh -i ~/.ssh/thesis_vm ubuntu@$VM_IP "/opt/thesis/venv/bin/dagster api grpc-health-check -p 4000"
```

Expected output:
```
● thesis-workload.service - Thesis Dagster gRPC Workload Server
   Active: active (running) since ...
...
Connection to localhost 4000 port [tcp/*] succeeded!
```

### Run Experiments

With the Multipass VM provisioned, experiments run identically:

```bash
make exp1-vm     # VM degradation with Multipass VM
```
## Acceptance Criteria (Multipass Setup)

- [ ] Multipass VM running Ubuntu 22.04 with exactly 4 vCPU, 4 GB RAM
- [ ] Docker CE installed and running (`docker info`)
- [ ] `nproc` shows 4
- [ ] `free -h` shows ~4 GB RAM
- [ ] Can trigger a single `thesis_workload` job via Dagster from within the VM

---

## Stopping / Deleting the VM

```bash
# Stop (preserve data)
multipass stop thesis-vm

# Restart
multipass start thesis-vm

# Delete permanently
multipass delete thesis-vm
multipass purge
# also remove vm-ip.txt:
rm vm-ip.txt
```

---

## Recording Laptop Specifications

For thesis reproducibility, record your host machine specs when using Multipass:

```bash
# macOS
sysctl -n machdep.cpu.brand_string   # CPU model
system_profiler SPHardwareDataType | grep "Memory:"
sw_vers
diskutil info / | grep "Total Size"
```

These should be included in the thesis appendix next to any Multipass-derived data.

---

*See [setup.md](setup.md) for the full setup guide.*
