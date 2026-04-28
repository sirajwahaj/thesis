# =============================================================================
# Create VirtualBox VM (Windows)
#
# Creates an Ubuntu 22.04 Server VM via VirtualBox CLI (VBoxManage) for the
# thesis VM benchmarking environment.
# Resources: 4 vCPU, 8 GB RAM, 60 GB disk.
#
# Usage:
#   .\scripts\create-vm-windows.ps1
#   $env:VM_IP="192.168.56.10"; .\scripts\create-vm-windows.ps1 -UseExisting
# =============================================================================

param(
    [switch]$UseExisting
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

$VM_NAME    = "thesis-vm"
$VM_IP_FILE = Join-Path $RepoRoot "vm-ip.txt"
$SSH_KEY    = Join-Path $env:USERPROFILE ".ssh\thesis_vm"
$VM_RAM_MB  = 8192
$VM_CPUS    = 4
$VM_DISK_GB = 60

# Ubuntu 22.04 Server ISO (x86-64)
$ISO_URL    = "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"

Write-Host ""
Write-Host "── VirtualBox VM Setup ────────────────────────────────────────"

# ---- Generate SSH key if not present ----
if (-not (Test-Path $SSH_KEY)) {
    Write-Host "→ Generating thesis SSH key..."
    & ssh-keygen -t ed25519 -f $SSH_KEY -N '""' -C "thesis-vm"
    Write-Host "✅ SSH key created: $SSH_KEY"
} else {
    Write-Host "✅ SSH key exists: $SSH_KEY"
}
$SSH_PUB = Get-Content "${SSH_KEY}.pub"

# ---- Check if VM already SSH-accessible ----
if (Test-Path $VM_IP_FILE) {
    $StoredIP = (Get-Content $VM_IP_FILE).Trim()
    if ($StoredIP) {
        Write-Host "→ Found stored VM IP: $StoredIP — checking SSH..."
        $result = & ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5 "ubuntu@$StoredIP" "echo ok" 2>$null
        if ($result -eq "ok") {
            Write-Host "✅ VM at $StoredIP is SSH-accessible. Nothing to do."
            exit 0
        }
    }
}

if ($UseExisting) {
    $IP = $env:VM_IP
    if (-not $IP) {
        Write-Host "❌ -UseExisting requires `$env:VM_IP to be set." -ForegroundColor Red
        exit 1
    }
    Set-Content -Path $VM_IP_FILE -Value $IP
    Write-Host "✅ Stored VM IP: $IP"
    exit 0
}

# ---- VBoxManage availability check ----
if (-not (Get-Command VBoxManage -ErrorAction SilentlyContinue)) {
    Write-Host "❌ VBoxManage not found. Install VirtualBox first:" -ForegroundColor Red
    Write-Host "   choco install virtualbox -y" -ForegroundColor Yellow
    exit 1
}

# ---- VM Creation Guide ----
Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ACTION REQUIRED: Create Ubuntu VM in VirtualBox" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Download Ubuntu 22.04 Server ISO:"
Write-Host "     $ISO_URL"
Write-Host ""
Write-Host "  2. Run the VirtualBox automated creation (after ISO download):"
Write-Host ""
Write-Host "     # Set path to downloaded ISO:"
Write-Host "     `$ISO=`"C:\Users\$env:USERNAME\Downloads\ubuntu-22.04.5.iso`""
Write-Host ""
Write-Host "     # Create VM"
Write-Host "     VBoxManage createvm --name $VM_NAME --ostype Ubuntu_64 --register"
Write-Host "     VBoxManage modifyvm $VM_NAME --memory $VM_RAM_MB --cpus $VM_CPUS --audio=none"
Write-Host "     VBoxManage modifyvm $VM_NAME --nic1 nat --natpf1 `"ssh,tcp,,2222,,22`""
Write-Host "     VBoxManage createmedium disk --filename `"`$HOME\VirtualBox VMs\$VM_NAME\disk.vdi`" --size $($VM_DISK_GB * 1024) --format VDI"
Write-Host "     VBoxManage storagectl $VM_NAME --name `"SATA`" --add sata --controller IntelAhci"
Write-Host "     VBoxManage storageattach $VM_NAME --storagectl `"SATA`" --port 0 --device 0 --type hdd --medium `"`$HOME\VirtualBox VMs\$VM_NAME\disk.vdi`""
Write-Host "     VBoxManage storagectl $VM_NAME --name `"IDE`" --add ide"
Write-Host "     VBoxManage storageattach $VM_NAME --storagectl `"IDE`" --port 0 --device 0 --type dvddrive --medium `$ISO"
Write-Host "     VBoxManage startvm $VM_NAME"
Write-Host ""
Write-Host "  3. Complete the Ubuntu installer (username: ubuntu, enable SSH server)"
Write-Host ""
Write-Host "  4. After boot, add SSH key inside the VM:"
Write-Host "     mkdir -p ~/.ssh && echo '$SSH_PUB' >> ~/.ssh/authorized_keys"
Write-Host "     chmod 600 ~/.ssh/authorized_keys"
Write-Host ""
Write-Host "  5. Test SSH (VirtualBox uses NAT port forwarding 2222→22):"
Write-Host "     ssh -i $SSH_KEY -p 2222 ubuntu@127.0.0.1"
Write-Host ""
Write-Host "  6. Run with stored IP when ready:"
Write-Host "     `$env:VM_IP=`"127.0.0.1:2222`"; .\scripts\create-vm-windows.ps1 -UseExisting"
Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$UserIP = Read-Host "Enter VM IP (or 127.0.0.1 for NAT port forwarding) when ready (blank to skip)"
if (-not $UserIP) {
    Write-Host ""
    Write-Host "⚠️  Skipped. Run when VM is ready:" -ForegroundColor Yellow
    Write-Host "   `$env:VM_IP=<ip>; .\scripts\create-vm-windows.ps1 -UseExisting" -ForegroundColor Yellow
    exit 0
}

# ---- Validate SSH ----
Write-Host "→ Testing SSH to $UserIP..."
$attempts = 0
do {
    $result = & ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=8 "ubuntu@$UserIP" "echo ok" 2>$null
    $attempts++
    if ($result -ne "ok" -and $attempts -lt 5) {
        Write-Host "   Attempt $attempts/5 failed — retrying in 5s..."
        Start-Sleep -Seconds 5
    }
} while ($result -ne "ok" -and $attempts -lt 5)

if ($result -ne "ok") {
    Write-Host "❌ Cannot SSH to $UserIP after 5 attempts." -ForegroundColor Red
    exit 1
}

Set-Content -Path $VM_IP_FILE -Value $UserIP
Write-Host "✅ VM IP saved to: $VM_IP_FILE"

# ---- Verify resources ----
$nproc = & ssh -i $SSH_KEY -o StrictHostKeyChecking=no "ubuntu@$UserIP" "nproc" 2>$null
$mem   = & ssh -i $SSH_KEY -o StrictHostKeyChecking=no "ubuntu@$UserIP" "free -h | grep 'Mem:' | awk '{print `$2}'" 2>$null
Write-Host "   CPUs: $nproc (expected: 4)"
Write-Host "   RAM:  $mem (expected: ~8G)"

Write-Host ""
Write-Host "✅ VM ready. Next: make vm-provision"
Write-Host ""
