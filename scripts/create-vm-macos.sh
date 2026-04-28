#!/usr/bin/env bash
# =============================================================================
# Create UTM VM (macOS)
#
# Creates an Ubuntu VM via UTM for the thesis VM benchmarking environment.
# Resources: 4 vCPU, 8 GB RAM, 60 GB disk.
#
# UTM does not have a full CLI for automated VM creation, so this script:
#  1. Checks if the VM is already accessible (stored IP or mDNS)
#  2. If not: tries to auto-discover the IP (mDNS -> ARP scan -> ping sweep)
#  3. If auto-discovery fails: prints setup guide + interactive fallback
#  4. Validates SSH connectivity and writes vm-ip.txt
#
# IP discovery order (no manual input in normal flow):
#   1. vm-ip.txt       -- persisted from previous run; re-validated each call
#   2. mDNS            -- thesis-vm.local; works after Ansible installs avahi-daemon
#   3. ARP cache scan  -- checks macOS ARP table for hosts on UTM subnets
#   4. Ping sweep      -- parallel pings populate ARP cache; re-scans after
#   5. Manual fallback -- asks for IP only if all automated methods fail
#
# Usage:
#   bash scripts/create-vm-macos.sh
#   VM_IP=192.168.64.5 bash scripts/create-vm-macos.sh --use-existing
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_IP_FILE="$REPO_ROOT/vm-ip.txt"
SSH_KEY_FILE="$HOME/.ssh/thesis_vm"
SSH_OPTS=(-i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes)
ARCH="$(uname -m)"

# UTM Shared Network (bridge100) assigns 192.168.64.x on Apple Silicon.
# Some UTM configs use 10.0.2.x -- we scan both.
UTM_SUBNETS=("192.168.64" "10.0.2")

USE_EXISTING=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --use-existing) USE_EXISTING=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

ssh_reachable() {
  local ip="$1"
  ssh "${SSH_OPTS[@]}" "ubuntu@${ip}" "echo ok" &>/dev/null
}

arp_candidates() {
  # Return IPs in the macOS ARP cache matching a subnet prefix
  local prefix="$1"
  arp -a 2>/dev/null \
    | grep "(${prefix}\." \
    | grep -v incomplete \
    | awk '{print $2}' \
    | tr -d '()' \
    | sort -t. -k4 -n
}

probe_candidates_parallel() {
  # Try SSH on a list of IPs concurrently; echo the first that responds
  local -a ips=("$@")
  [[ ${#ips[@]} -eq 0 ]] && return 1
  local tmpdir found_ip=""
  tmpdir="$(mktemp -d)"

  local pids=()
  for ip in "${ips[@]}"; do
    (
      if ssh_reachable "$ip" 2>/dev/null; then
        echo "$ip" > "$tmpdir/found"
      fi
    ) &
    pids+=($!)
  done

  local waited=0
  while [[ $waited -lt 8 ]]; do
    sleep 1; waited=$((waited + 1))
    if [[ -f "$tmpdir/found" ]]; then
      found_ip="$(cat "$tmpdir/found")"
      break
    fi
  done

  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  wait "${pids[@]}" 2>/dev/null || true
  rm -rf "$tmpdir"
  [[ -n "$found_ip" ]] && echo "$found_ip"
}

# -----------------------------------------------------------------------------
# Stage 1 -- SSH key
# -----------------------------------------------------------------------------
echo ""
echo "-- UTM VM Setup --------------------------------------------------"

if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "-> Generating thesis SSH key..."
  ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -C "thesis-vm"
  echo "SSH key created: $SSH_KEY_FILE"
else
  echo "SSH key exists: $SSH_KEY_FILE"
fi
SSH_PUBKEY="$(cat "${SSH_KEY_FILE}.pub")"

# -----------------------------------------------------------------------------
# Stage 2 -- --use-existing shortcut
# -----------------------------------------------------------------------------
if [[ "$USE_EXISTING" == "true" ]]; then
  if [[ -z "${VM_IP:-}" ]]; then
    echo "ERROR: --use-existing requires VM_IP environment variable."
    echo "   Example: VM_IP=192.168.64.5 bash scripts/create-vm-macos.sh --use-existing"
    exit 1
  fi
  echo "$VM_IP" > "$VM_IP_FILE"
  echo "Stored VM IP: $VM_IP"
  exit 0
fi

# -----------------------------------------------------------------------------
# Stage 3 -- Auto-discovery
# -----------------------------------------------------------------------------
echo "-> Attempting automatic VM IP discovery..."

discover_vm_ip() {
  local found=""

  # -- 3a. Stored IP in vm-ip.txt --------------------------------------------
  if [[ -f "$VM_IP_FILE" ]]; then
    local stored
    stored="$(cat "$VM_IP_FILE" | tr -d '[:space:]')"
    if [[ -n "$stored" ]]; then
      echo "   [1/4] Checking stored IP: $stored" >&2
      if ssh_reachable "$stored"; then
        echo "$stored"; return 0
      fi
      echo "   WARNING: Stored IP unreachable -- VM may have a new DHCP lease." >&2
    fi
  fi

  # -- 3b. mDNS: thesis-vm.local ---------------------------------------------
  # Requires avahi-daemon on the VM (Ansible installs it automatically).
  # After first provision, this is the most reliable method across reboots.
  echo "   [2/4] mDNS probe: thesis-vm.local ..." >&2
  if ssh "${SSH_OPTS[@]}" "ubuntu@thesis-vm.local" "echo ok" &>/dev/null 2>&1; then
    found="$(ssh "${SSH_OPTS[@]}" "ubuntu@thesis-vm.local" \
      "hostname -I | awk '{print \$1}'" 2>/dev/null || true)"
    if [[ -n "$found" ]]; then
      echo "$found"; return 0
    fi
  fi

  # -- 3c. ARP cache scan ----------------------------------------------------
  # When the VM boots and gets a DHCP lease, macOS adds an ARP entry for it.
  # This costs zero network traffic and completes instantly.
  echo "   [3/4] ARP cache scan (subnets: ${UTM_SUBNETS[*]}) ..." >&2
  local candidates=()
  for subnet in "${UTM_SUBNETS[@]}"; do
    while IFS= read -r ip; do
      [[ -n "$ip" ]] && candidates+=("$ip")
    done < <(arp_candidates "$subnet")
  done

  if [[ ${#candidates[@]} -gt 0 ]]; then
    echo "   ARP candidates: ${candidates[*]}" >&2
    found="$(probe_candidates_parallel "${candidates[@]}" || true)"
    if [[ -n "$found" ]]; then
      echo "$found"; return 0
    fi
  fi

  # -- 3d. Ping sweep -> re-scan ARP -----------------------------------------
  # Sends pings at the first 30 addresses on each UTM subnet in background.
  # This forces the OS to populate the ARP cache and costs ~5 seconds.
  echo "   [4/4] Ping sweep to populate ARP cache (~5s) ..." >&2
  for subnet in "${UTM_SUBNETS[@]}"; do
    for i in $(seq 2 30); do
      ping -c 1 -W 1 "${subnet}.${i}" &>/dev/null &
    done
  done
  wait 2>/dev/null || true
  sleep 1

  candidates=()
  for subnet in "${UTM_SUBNETS[@]}"; do
    while IFS= read -r ip; do
      [[ -n "$ip" ]] && candidates+=("$ip")
    done < <(arp_candidates "$subnet")
  done

  if [[ ${#candidates[@]} -gt 0 ]]; then
    echo "   Post-sweep candidates: ${candidates[*]}" >&2
    found="$(probe_candidates_parallel "${candidates[@]}" || true)"
    if [[ -n "$found" ]]; then
      echo "$found"; return 0
    fi
  fi

  return 1
}

DISCOVERED_IP="$(discover_vm_ip || true)"

if [[ -n "$DISCOVERED_IP" ]]; then
  echo "$DISCOVERED_IP" > "$VM_IP_FILE"
  echo ""
  echo "VM discovered and saved: $DISCOVERED_IP"
  echo "   SSH: ssh -i $SSH_KEY_FILE ubuntu@$DISCOVERED_IP"
  echo "   Next: make vm-provision"
  echo ""
  exit 0
fi

# -----------------------------------------------------------------------------
# Stage 4 -- VM not found: one-time setup guide
# -----------------------------------------------------------------------------
if [[ "$ARCH" == "arm64" ]]; then
  ISO_ARCH="ARM64"
  ISO_URL="https://cdimage.ubuntu.com/releases/22.04/release/ubuntu-22.04.5-live-server-arm64.iso"
else
  ISO_ARCH="x86-64"
  ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
fi

echo ""
echo "================================================================"
echo "  ACTION REQUIRED: Create Ubuntu VM in UTM (one-time setup)"
echo "================================================================"
echo ""
echo "  -- Step 1: Download Ubuntu 22.04 Server ($ISO_ARCH) --"
echo "  $ISO_URL"
echo ""
echo "  -- Step 2: Create VM in UTM --"
echo "  Open UTM -> '+' -> Virtualise -> Linux"
echo "    Boot ISO:   <downloaded ISO>"
echo "    CPU cores:  4"
echo "    RAM:        8192 MB"
echo "    Disk:       60 GB"
echo "    Network:    Shared Network (default)"
echo ""
echo "  -- Step 3: Complete Ubuntu installer --"
echo "    Username:   ubuntu"
echo "    Hostname:   thesis-vm    <- use exactly this (enables mDNS auto-discovery)"
echo "    OpenSSH:    Install OpenSSH server YES"
echo ""
echo "  -- Step 4: Add SSH public key to the VM --"
echo "  In the VM console, run:"
echo ""
echo "    mkdir -p ~/.ssh"
echo "    echo \"$SSH_PUBKEY\" >> ~/.ssh/authorized_keys"
echo "    chmod 600 ~/.ssh/authorized_keys"
echo ""
echo "  -- Step 5: Re-run this script --"
echo "    bash scripts/create-vm-macos.sh"
echo ""
echo "  The script will auto-discover the IP via ARP scan."
echo "  Or provide the IP directly:"
echo "    VM_IP=<ip> bash scripts/create-vm-macos.sh --use-existing"
echo ""
echo "  TIP: find the VM IP from inside the VM:"
echo "    hostname -I | awk '{print \$1}'"
echo ""
echo "================================================================"

# -----------------------------------------------------------------------------
# Stage 5 -- Optional interactive fallback
# -----------------------------------------------------------------------------
echo ""

# Skip interactive prompt in non-interactive mode (piped input, CI, make all, etc.)
if [[ ! -t 0 ]]; then
  echo "Non-interactive mode: skipping VM IP prompt."
  echo "Run manually once the VM is ready: bash scripts/create-vm-macos.sh"
  exit 0
fi

read -rp "Enter VM IP if it is already running (or press Enter to skip): " USER_IP

if [[ -z "$USER_IP" ]]; then
  echo ""
  echo "Skipped. Re-run once the VM is ready:"
  echo "   bash scripts/create-vm-macos.sh"
  exit 0
fi

echo ""
echo "-> Validating SSH connectivity to $USER_IP..."
ATTEMPTS=0
MAX_ATTEMPTS=6
until ssh_reachable "$USER_IP" || [[ $ATTEMPTS -ge $MAX_ATTEMPTS ]]; do
  ATTEMPTS=$((ATTEMPTS + 1))
  echo "   Attempt $ATTEMPTS/$MAX_ATTEMPTS failed -- retrying in 5s..."
  sleep 5
done

if ! ssh_reachable "$USER_IP"; then
  echo ""
  echo "ERROR: Cannot reach VM at $USER_IP via SSH after $MAX_ATTEMPTS attempts."
  echo "   Checklist:"
  echo "   1. VM is running (UTM shows green play button)"
  echo "   2. OpenSSH server was installed during Ubuntu setup"
  echo "   3. SSH public key was added to ~/.ssh/authorized_keys on the VM"
  echo "   4. Run inside VM: hostname -I | awk '{print \$1}'"
  exit 1
fi

echo "$USER_IP" > "$VM_IP_FILE"
echo "SSH confirmed. IP saved: $USER_IP"

echo ""
echo "-> Verifying VM resources..."
NPROC="$(ssh "${SSH_OPTS[@]}" "ubuntu@$USER_IP" "nproc" 2>/dev/null || echo "?")"
MEM="$(ssh "${SSH_OPTS[@]}" "ubuntu@$USER_IP" "free -h | awk '/^Mem:/{print \$2}'" 2>/dev/null || echo "?")"
echo "   CPUs: $NPROC  (expected: 4)"
echo "   RAM:  $MEM  (expected: ~8.0G)"
[[ "$NPROC" != "4" ]] && echo "   WARNING: CPU count mismatch -- check UTM settings"

echo ""
echo "VM is ready."
echo "   IP:   $USER_IP"
echo "   SSH:  ssh -i $SSH_KEY_FILE ubuntu@$USER_IP"
echo "   Next: make vm-provision"
echo ""
