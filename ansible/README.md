# Ansible — What It Is and How It Works

> **Complete beginner?** Start with the "What is Ansible?" section.
> **Just want to know what each file does?** Jump to "Directory Map" below.

---

## What is Ansible?

Ansible is an **automation tool** that lets you run a list of tasks on one or more remote
machines over SSH — without installing anything on those machines first.

Think of it like a recipe book:

- You write **tasks** in plain YAML (e.g. "install Docker", "add ubuntu user to docker group").
- Ansible reads the recipe and SSHs into the target machine to run each task.
- If a task has already been done (e.g. Docker is already installed), Ansible skips it safely.
- At the end, every machine that Ansible touched ends up in the exact same state.

**You do not need to know Linux commands by heart.** Ansible's built-in modules
(`apt`, `systemd`, `user`, `copy`, etc.) handle the low-level details for you.

---

## How does it fit into this project?

```
Your Mac (runs Ansible)
     │
     │  SSH  (no password — uses ~/.ssh/thesis_vm key)
     ▼
thesis-vm (Ubuntu 22.04 — Multipass VM on your Mac)
     │
     └─ Ansible installs Docker CE + Docker Compose
          Then: make deploy  →  docker compose up  →  all containers start
```

When you run `make vm-up`, the script:
1. Creates the VM via Multipass
2. Injects your SSH key
3. Runs `ansible-playbook playbooks/provision-vm.yml`
   → Docker CE is installed on the VM

After that, **everything runs in Docker containers** — Dagster, PostgreSQL, the workload job.
Ansible's only job is to put Docker on the VM.

---

## Directory Map

```
ansible/
├── ansible.cfg                   ← Global Ansible settings (read first)
├── inventory.ini                 ← Auto-generated: "where is the VM?"
├── inventory.ini.template        ← Template for inventory.ini
├── playbooks/
│   └── provision-vm.yml          ← The main recipe: "what to install"
└── roles/
    └── docker/
        └── tasks/
            └── main.yml          ← Step-by-step Docker CE install
```

---

## File-by-file Explanation

### `ansible.cfg` — Settings file

```ini
[defaults]
roles_path = roles          # look for roles in ansible/roles/
inventory = inventory.ini   # default inventory file
host_key_checking = False   # don't ask "do you trust this host?" on first connect
```

**Why it matters:** Without `roles_path = roles`, Ansible would look for the `docker` role
in global system paths and fail with "role not found". This file makes everything work
from the `ansible/` directory.

---

### `inventory.ini` — The target machine list

```ini
[thesis_vm]
thesis-vm ansible_host=192.168.64.3 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/thesis_vm ...
```

- `[thesis_vm]` is a **group name** — a label for a set of machines.
- `ansible_host` is the IP address of the VM.
- `ansible_user=ubuntu` means "log in as the ubuntu user".
- `ansible_ssh_private_key_file` is the path to the SSH private key.

**Auto-generated** by `scripts/bash/vm-up.sh` — do NOT edit by hand.
It is in `.gitignore` so your local IP never gets committed.

---

### `inventory.ini.template` — Placeholder version

The template used to document the expected format. Actual values are written
at runtime by `vm-up.sh`. You do not need to touch this.

---

### `playbooks/provision-vm.yml` — The main recipe

This is the entry point. It defines **what happens** on the VM when you run `make vm-up`.

```
Play: "Provision Thesis VM — Docker CE"
  │
  ├─ pre_tasks:
  │     1. Assert Ubuntu 22.04              ← safety check
  │     2. Write apt clock-skew workaround  ← fixes "not valid yet" apt errors
  │     3. Sync NTP clock                   ← Multipass VMs can start with drift
  │     4. Update apt cache                 ← refresh package list
  │     5. Install basic tools (curl, git…) ← needed before Docker can be installed
  │
  ├─ roles:
  │     docker  ←  delegates to roles/docker/tasks/main.yml
  │
  └─ post_tasks:
        1. Verify docker info               ← prove Docker is running
        2. Verify docker compose version    ← prove Compose plugin works
        3. Print summary                    ← confirm ready
```

**Key concepts:**

| Term | Plain English |
|------|--------------|
| `hosts: thesis_vm` | Run on the machine(s) in the `[thesis_vm]` group |
| `become: true` | Use `sudo` for tasks that need root access |
| `gather_facts: true` | Collect info about the VM (OS version, architecture, etc.) |
| `pre_tasks` | Steps that run BEFORE the role |
| `roles` | Reusable collections of tasks (like calling a function) |
| `post_tasks` | Steps that run AFTER the role — used for verification |

---

### `roles/docker/tasks/main.yml` — How Docker CE is installed

This is the actual step-by-step recipe for installing Docker.
Each `-` block is one task.

```
Step 1:  apt install ca-certificates curl gnupg lsb-release
         (tools needed to safely download Docker's GPG key)

Step 2:  mkdir /etc/apt/keyrings
         (create a secure folder for the key)

Step 3:  Download Docker's GPG key → /etc/apt/keyrings/docker.asc
         (so apt can verify Docker packages are authentic)

Step 4:  Detect architecture (arm64 or amd64)
         (the apt repo URL is different for each chip)

Step 5:  Detect Ubuntu codename (jammy for 22.04)
         (the apt repo URL also depends on the OS version)

Step 6:  Add Docker's apt repository
         deb [...] https://download.docker.com/linux/ubuntu jammy stable

Step 7:  apt install docker-ce docker-ce-cli containerd.io
                     docker-buildx-plugin docker-compose-plugin

Step 8:  systemctl enable --now docker
         (start Docker daemon and make it start on boot)

Step 9:  usermod -aG docker ubuntu
         (add ubuntu user to docker group, so docker works without sudo)

Step 10: Wait for /var/run/docker.sock to appear
         (socket file proves the daemon is ready)

Step 11: docker --version          ← print for confirmation
Step 12: docker compose version    ← print for confirmation
```

---

## How a Task Actually Works

Every Ansible task follows this pattern:

```yaml
- name: Install Docker CE           # ← description shown in terminal output
  ansible.builtin.apt:              # ← the module (built-in apt package manager)
    name:                           # ← module parameters
      - docker-ce
      - docker-ce-cli
    state: present                  # ← "ensure it's installed"
    update_cache: true              # ← run apt-get update first
```

**Key module types used:**

| Module | What it does |
|--------|-------------|
| `apt` | Installs/removes packages (`apt install`) |
| `get_url` | Downloads a file from the internet |
| `file` | Creates directories, sets permissions |
| `apt_repository` | Adds a new apt source to the system |
| `systemd` | Starts/stops/enables system services |
| `user` | Manages Linux user accounts and groups |
| `wait_for` | Pauses until a file or port is ready |
| `command` | Runs any shell command |
| `debug` | Prints a message to the terminal |
| `copy` | Writes a file with specific content |
| `assert` | Checks a condition; fails if false |

---

## Common Questions

**Q: What does `changed_when: false` mean?**
A: Some tasks always report "changed" even if nothing actually changed
(e.g. running `docker --version`). `changed_when: false` tells Ansible
"this task never modifies anything — don't show it as a change."

**Q: What does `ignore_errors: true` mean?**
A: If the task fails, keep going anyway. Used for the NTP sync step
because some VMs don't have `systemd-timesyncd` (harmless to ignore).

**Q: What does `become: true` mean?**
A: Run this task with `sudo`. Required for installing packages, writing
system files, and managing services.

**Q: What does `become_user: ubuntu` mean?**
A: After gaining root access, switch back to the `ubuntu` user to run
this specific task (e.g. `docker --version` should work for the ubuntu user).

**Q: What happens if I run `make vm-up` twice?**
A: Nothing bad. Ansible is **idempotent** — if Docker is already installed,
it skips those steps. The playbook is safe to run multiple times.

---

## Running Ansible Manually

You normally don't need to do this — `make vm-up` and `make vm-provision` handle it.
But if you want to run the playbook directly:

```bash
# From the ansible/ directory (so ansible.cfg is picked up automatically)
cd ansible/

# Run the full provisioning playbook
ansible-playbook -i inventory.ini playbooks/provision-vm.yml

# Run with verbose output (shows every task in detail)
ansible-playbook -i inventory.ini playbooks/provision-vm.yml -v

# Check what WOULD happen without actually doing it
ansible-playbook -i inventory.ini playbooks/provision-vm.yml --check

# Test SSH connectivity to the VM
ansible thesis_vm -i inventory.ini -m ping
```

Expected output for `ping`:
```
thesis-vm | SUCCESS => {
    "ping": "pong"
}
```

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `role 'docker' was not found` | Running from wrong directory | `cd ansible/` first, or use `make vm-up` |
| `Release file not valid yet` | VM clock is behind | Fixed automatically by the NTP pre-task |
| `SSH connection refused` | VM not running | `multipass start thesis-vm` |
| `UNREACHABLE` | Wrong IP in inventory.ini | Run `make vm-up` to regenerate inventory |
| `Permission denied (publickey)` | SSH key not injected | `make vm-up` re-injects the key |
