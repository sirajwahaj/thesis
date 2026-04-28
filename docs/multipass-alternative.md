# Multipass Alternative — Lightweight VM Setup

> ⚠️ **This is an optional, lightweight alternative to the primary benchmarking environment.**
> It is documented for reference, quick iteration, and comparison but is **NOT the primary setup** used in thesis experiments.
>
> **For production experiments, use the primary setup:**
> ```bash
> make bootstrap && make vm-provision && make k8s-setup
> ```

---

## Why Multipass as an Alternative?

Multipass is simpler and faster to set up than UTM, but has limitations that make it unsuitable as the primary benchmarking environment:

| Aspect | Multipass | UTM (Primary) |
|--------|-----------|---------------|
| VM creation | Automatic (one command) | Semi-manual (one-time ISO setup) |
| Resource isolation | Shared with host via QEMU | HVF/UTM hypervisor, better isolation |
| CPU contention experiment fidelity | Lower (shared QEMU threads) | Higher (dedicated vCPUs) |
| ARM64 support (M-series Mac) | Yes (automatic) | Yes (native) |
| Required for Exp1 fidelity | No (results may differ) | Yes |

**For thesis experiments (SQ1: "where does the VM break?"), better CPU isolation is critical.** UTM provides more realistic results.

Multipass is suitable for:
- Quick local testing of scripts
- Iterating on the workload code
- Testing Ansible playbooks before running on the real VM
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
  --memory 8G \
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

> ⚠️ Results from Multipass may differ from UTM due to lower hypervisor isolation.
> Label any data from Multipass clearly if comparing to UTM data.

---

## Acceptance Criteria (Multipass Setup)

- [ ] Multipass VM running Ubuntu 22.04 with exactly 4 vCPU, 8 GB RAM
- [ ] Python 3.12 installed (`python3.12 --version`)
- [ ] Dagster 1.12.7 installed (`/opt/thesis/venv/bin/dagster --version | head -1`)
- [ ] PostgreSQL 16 installed and running (`pg_isready -U dagster -d dagster`)
- [ ] `thesis-workload` systemd service active and listening on port 4000
- [ ] `nproc` shows 4
- [ ] `free -h` shows ~8 GB RAM
- [ ] Can trigger a single `thesis_workload` job via Dagster CLI from within the VM

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

*See [setup.md](setup.md) for the primary (UTM-based) setup guide.*
