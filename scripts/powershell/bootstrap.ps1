# =============================================================================
# Bootstrap (Windows): Cross-Platform Benchmarking Environment Setup
#
# Entry point for Windows. Detects environment, installs Chocolatey and all
# required dependencies, and creates the VirtualBox VM for the thesis
# benchmarking environment.
#
# Usage (run as Administrator in PowerShell):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\scripts\bootstrap.ps1
#   .\scripts\bootstrap.ps1 -SkipVM         # Skip VM creation
#   .\scripts\bootstrap.ps1 -DepsOnly       # Only install dependencies
#   .\scripts\bootstrap.ps1 -ValidateOnly   # Validate without installing
# =============================================================================

param(
    [switch]$SkipVM,
    [switch]$DepsOnly,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = Split-Path -Parent $ScriptDir

# ---- Banner ----
Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  THESIS BENCHMARKING — Bootstrap (Windows)" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Host OS:   Windows ($([Environment]::OSVersion.VersionString))"
Write-Host "  Arch:      $([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)"
Write-Host "  Repo:      $RepoRoot"
Write-Host ""

# ---- Require Administrator ----
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "❌ This script must be run as Administrator." -ForegroundColor Red
    Write-Host "   Right-click PowerShell → 'Run as administrator'" -ForegroundColor Yellow
    exit 1
}

# ---- Helper functions ----
function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-ChocoPackage {
    param([string]$PackageName, [string[]]$ExtraArgs = @())
    if (choco list --local-only $PackageName 2>$null | Select-String $PackageName) {
        Write-Host "  ✅ $PackageName already installed"
    } else {
        Write-Host "  → Installing $PackageName..."
        & choco install $PackageName -y --no-progress @ExtraArgs | Out-Null
        Write-Host "  ✅ $PackageName installed"
    }
}

# =============================================================================
# (1) Install Chocolatey
# =============================================================================
Write-Host "── Chocolatey ─────────────────────────────────────────────────"
if (-not (Test-Command choco)) {
    if ($ValidateOnly) {
        Write-Host "❌ choco: NOT FOUND" -ForegroundColor Red
    } else {
        Write-Host "→ Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "✅ Chocolatey installed"
    }
} else {
    Write-Host "✅ Chocolatey $(choco --version)"
}

# =============================================================================
# (2) Install dependencies
# =============================================================================
Write-Host ""
Write-Host "── Installing dependencies ────────────────────────────────────"

if ($ValidateOnly) {
    $RequiredTools = @("kubectl", "helm", "ansible-playbook", "python3", "python", "git", "VBoxManage")
    $Errors = @()
    foreach ($tool in $RequiredTools) {
        if (Test-Command $tool) {
            Write-Host "  ✅ $tool"
        } else {
            Write-Host "  ❌ $tool: NOT FOUND" -ForegroundColor Red
            $Errors += $tool
        }
    }
    # Check Docker Desktop
    if (Test-Command docker) {
        Write-Host "  ✅ Docker Desktop ($(docker --version))"
    } else {
        Write-Host "  ❌ docker: NOT FOUND (Docker Desktop required)" -ForegroundColor Red
        $Errors += "docker"
    }
    if ($Errors.Count -gt 0) {
        Write-Host ""
        Write-Host "❌ Validation failed — missing: $($Errors -join ', ')" -ForegroundColor Red
        Write-Host "   Run: .\scripts\bootstrap.ps1   (to install everything)" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host ""
        Write-Host "✅ All dependencies installed." -ForegroundColor Green
        exit 0
    }
}

# Package: Docker Desktop (provides docker, kubectl)
Install-ChocoPackage "docker-desktop"

# Package: VirtualBox
Install-ChocoPackage "virtualbox"

# Package: kubectl (standalone, in case Docker Desktop doesn't add it)
Install-ChocoPackage "kubernetes-cli"

# Package: Helm
Install-ChocoPackage "kubernetes-helm"

# Package: kind
Install-ChocoPackage "kind"

# Package: Python 3.12
Install-ChocoPackage "python312"

# Package: Ansible (via pip is more reliable on Windows)
if (-not (Test-Command ansible-playbook)) {
    Write-Host "  → Installing Ansible via pip..."
    & python -m pip install --upgrade ansible
    Write-Host "  ✅ Ansible installed via pip"
} else {
    Write-Host "  ✅ ansible-playbook already available"
}

# Package: Git
Install-ChocoPackage "git"

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# =============================================================================
# (3) Validate Docker Desktop is running
# =============================================================================
Write-Host ""
Write-Host "── Docker Desktop ─────────────────────────────────────────────"
if (Test-Command docker) {
    try {
        docker ps | Out-Null
        Write-Host "✅ Docker Desktop is running"
    } catch {
        Write-Host "⚠️  Docker Desktop is installed but not running." -ForegroundColor Yellow
        Write-Host "   Please start Docker Desktop, then re-run: .\scripts\bootstrap.ps1 -SkipVM"
    }
} else {
    Write-Host "⚠️  Docker Desktop not found in PATH. Restart PowerShell after install."  -ForegroundColor Yellow
}

# =============================================================================
# (4) Create data directories
# =============================================================================
Write-Host ""
Write-Host "── Data directories ───────────────────────────────────────────"
$DataDirs = @(
    "data\raw\exp1-vm-degradation\vm",
    "data\raw\exp2-kubernetes-isolation\part-a",
    "data\raw\exp2-kubernetes-isolation\part-b-blast-radius\vm",
    "data\raw\exp2-kubernetes-isolation\part-b-blast-radius\k8s",
    "data\raw\exp2-kubernetes-isolation\part-c-spike",
    "data\raw\exp3-overhead-crossover",
    "data\processed",
    "results"
)
foreach ($dir in $DataDirs) {
    $full = Join-Path $RepoRoot $dir
    if (-not (Test-Path $full)) {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
    }
}
Write-Host "✅ data/ directories ready"

# =============================================================================
# (5) Create VM (unless --SkipVM or --DepsOnly)
# =============================================================================
if (-not $DepsOnly -and -not $SkipVM) {
    Write-Host ""
    & "$ScriptDir\create-vm-windows.ps1"
}

# =============================================================================
# Summary
# =============================================================================
Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ✅ Bootstrap complete" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    make vm-provision    # Ansible: install Python, Dagster, PostgreSQL on VM"
Write-Host "    make k8s-setup       # Kind cluster + Metrics Server + Dagster on K8s"
Write-Host "    make experiments     # Run all 4 experiments"
Write-Host ""
