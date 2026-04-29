#!/usr/bin/env bash
# =============================================================================
# Provision Thesis VM
#
# macOS  → creates a Multipass Ubuntu 22.04 VM (4 vCPU / 4 GB / 20 GB),
#          injects the SSH key, writes vm-ip.txt, generates Ansible inventory,
#          then runs the Docker-only Ansible playbook.
#
#          RAM is intentionally set to 4 GB to create realistic memory pressure:
#          the memory_pressure workload op allocates 400 MB per job, so 7+
#          concurrent jobs (L5/L6) will exhaust available memory and trigger
#          OOM kills — the primary failure mode being tested.
#
# Windows → prints Vagrant instructions (run vagrant up from infrastructure/).
#
# Usage:
#   bash scripts/vm-up.sh
#
# Environment:
#   VM_NAME   (default: thesis-vm)
#   VM_CPUS   (default: 4)
#   VM_MEM    (default: 4G)   ← 4 GB to trigger OOM at L5/L6
#   VM_DISK   (default: 20G)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VM_NAME="${VM_NAME:-thesis-vm}"
VM_CPUS="${VM_CPUS:-4}"
VM_MEM="${VM_MEM:-4G}"
VM_DISK="${VM_DISK:-20G}"

VM_IP_FILE="$REPO_ROOT/vm-ip.txt"
SSH_KEY="$HOME/.ssh/thesis_vm"
ANSIBLE_DIR="$REPO_ROOT/ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory.ini"
PLAYBOOK="$ANSIBLE_DIR/playbooks/provision-vm.yml"

# =============================================================================
# Windows: Vagrant path
# =============================================================================
if [[ "$(uname)" == *"NT"* ]] || [[ "${OS:-}" == "Windows_NT" ]]; then
    echo ""
    echo "================================================================"
    echo "  Windows Detected — Use Vagrant to create the VM"
    echo "================================================================"
    echo ""
    echo "  1. Install VirtualBox: https://www.virtualbox.org/wiki/Downloads"
    echo "  2. Install Vagrant:    https://developer.hashicorp.com/vagrant/downloads"
    echo "  3. Run:"
    echo ""
    echo "       cd infrastructure"
    echo "       vagrant up"
    echo ""
    echo "  The Vagrantfile provisions Docker CE automatically via Ansible."
    echo ""
    echo "  After 'vagrant up':"
    echo "    vagrant ssh -c 'hostname -I | awk \"{print \\\$1}\"' > ../vm-ip.txt"
    echo "    make build && make push && make deploy"
    echo ""
    exit 0
fi

# =============================================================================
# macOS: Multipass path
# =============================================================================
echo ""
echo "================================================================"
echo "  Thesis VM Setup — Multipass (macOS)"
echo "================================================================"
echo ""

# ---- Preflight: check Multipass is installed ----
if ! command -v multipass &>/dev/null; then
    echo "[FAIL] multipass not installed."
    echo ""
    echo "  Install with Homebrew:"
    echo "    brew install --cask multipass"
    echo ""
    echo "  Then re-run: make vm-up"
    exit 1
fi

# ---- Preflight: check Ansible is installed ----
if ! command -v ansible-playbook &>/dev/null; then
    echo "[FAIL] ansible not installed."
    echo ""
    echo "  Install:"
    echo "    brew install ansible"
    echo ""
    echo "  Then re-run: make vm-up"
    exit 1
fi

# ---- Step 1: Generate SSH key if needed ----
if [[ ! -f "$SSH_KEY" ]]; then
    echo "-> Generating thesis SSH key..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "thesis-vm"
    echo "[OK] SSH key: $SSH_KEY"
else
    echo "[OK] SSH key exists: $SSH_KEY"
fi
PUBKEY="$(cat "${SSH_KEY}.pub")"

# ---- Step 2: Create or start VM ----
if multipass info "$VM_NAME" &>/dev/null 2>&1; then
    STATE="$(multipass info "$VM_NAME" 2>/dev/null | awk '/^State:/ {print $2}')"
    if [[ "$STATE" == "Running" ]]; then
        echo "[OK] VM '$VM_NAME' already running"
    else
        echo "-> Starting existing VM '$VM_NAME'..."
        multipass start "$VM_NAME"
        echo "[OK] VM started"
    fi
else
    echo "-> Creating VM '$VM_NAME' (${VM_CPUS} vCPU / ${VM_MEM} RAM / ${VM_DISK} disk, Ubuntu 26.04) [4GB RAM = OOM trigger at L5/L6]..."
    multipass launch \
        --name "$VM_NAME" \
        --cpus "$VM_CPUS" \
        --memory "$VM_MEM" \
        --disk "$VM_DISK" \
        26.04
    echo "[OK] VM created"
fi

# ---- Step 3: Get VM IP ----
echo ""
echo "-> Getting VM IP..."
# Wait for network to be assigned (may take a few seconds after launch)
MAX_WAIT=30
WAITED=0
VM_IP=""
while [[ -z "$VM_IP" && $WAITED -lt $MAX_WAIT ]]; do
    VM_IP="$(multipass info "$VM_NAME" 2>/dev/null | awk '/^IPv4:/ {print $2}')"
    if [[ -z "$VM_IP" ]]; then
        sleep 2
        WAITED=$((WAITED + 2))
    fi
done

if [[ -z "$VM_IP" ]]; then
    echo "[FAIL] Could not get VM IP after ${MAX_WAIT}s."
    echo "   Check VM status: multipass list"
    exit 1
fi

echo "$VM_IP" > "$VM_IP_FILE"
echo "[OK] VM IP: $VM_IP (saved to vm-ip.txt)"

# ---- Step 4: Inject SSH key into VM ----
echo ""
echo "-> Injecting SSH public key into VM..."
multipass exec "$VM_NAME" -- bash -c \
    "mkdir -p ~/.ssh && \
     grep -qxF '${PUBKEY}' ~/.ssh/authorized_keys 2>/dev/null || \
     echo '${PUBKEY}' >> ~/.ssh/authorized_keys && \
     chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
echo "[OK] SSH key injected"

# ---- Step 5: Verify SSH connectivity ----
echo ""
echo "-> Verifying SSH connectivity to $VM_IP..."
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes)
MAX_ATTEMPTS=6
for i in $(seq 1 $MAX_ATTEMPTS); do
    if ssh "${SSH_OPTS[@]}" "ubuntu@$VM_IP" "echo ok" &>/dev/null; then
        echo "[OK] SSH connection verified"
        break
    fi
    if [[ $i -eq $MAX_ATTEMPTS ]]; then
        echo "[FAIL] SSH to ubuntu@$VM_IP failed after $MAX_ATTEMPTS attempts."
        echo "   VM may still be booting. Try: ssh -i $SSH_KEY ubuntu@$VM_IP"
        exit 1
    fi
    echo "   Attempt $i/$MAX_ATTEMPTS failed — retrying in 5s..."
    sleep 5
done

# ---- Step 6: Generate Ansible inventory ----
echo ""
echo "-> Generating Ansible inventory..."
mkdir -p "$ANSIBLE_DIR"
cat > "$INVENTORY_FILE" <<EOF
# Auto-generated by vm-up.sh — do NOT commit (see .gitignore)
[thesis_vm]
thesis-vm ansible_host=${VM_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${SSH_KEY} ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[thesis_vm:vars]
ansible_python_interpreter=/usr/bin/python3
EOF
echo "[OK] Inventory written to $INVENTORY_FILE"

# ---- Step 7: Run Ansible to install Docker ----
echo ""
echo "----------------------------------------------------------------"
echo "-> Installing Docker CE on VM via Ansible..."
echo "----------------------------------------------------------------"
echo ""

# Run from ansible directory so ansible.cfg is picked up
(cd "$ANSIBLE_DIR" && ansible-playbook \
    -i "inventory.ini" \
    "playbooks/provision-vm.yml" \
    -v)

echo ""
echo "================================================================"
echo "[OK] VM is ready"
echo "================================================================"
echo ""
echo "   VM name:    $VM_NAME"
echo "   VM IP:      $VM_IP"
echo "   SSH:        ssh -i $SSH_KEY ubuntu@$VM_IP"
echo "   Dagster UI: http://$VM_IP:3001 (after: make deploy)"
echo ""
echo "Next steps:"
echo "  make build    — build Docker image"
echo "  make push     — push image to ghcr.io"
echo "  make deploy   — pull + start containers on VM"
echo ""
