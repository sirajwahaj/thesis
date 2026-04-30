# [THESIS-001] Environment Setup — UTM VM

Labels: setup, infra  
Story Points: 3  
Dependencies: None  

## Description
Create and configure the Ubuntu VM via UTM (Ansible-provisioned) with pinned resource limits. Install Python, Dagster, Docker CE, and PostgreSQL inside the VM. Verify Dagster can run a single job with the DockerRunLauncher (each job = one Docker container on the VM).

## Acceptance Criteria
- [ ] Multipass VM running Ubuntu 22.04 with exactly 4 vCPU, 4 GB RAM
- [ ] Docker CE installed and `docker info` works as ubuntu user
- [ ] Python 3.12, Dagster 1.12.7, PostgreSQL 16 installed
- [ ] `dagster dev` runs and the UI is accessible from the host
- [ ] A single `thesis_workload` job completes successfully as a Docker container
- [ ] Resource limits verified: `nproc` shows 4, `free -h` shows ~4 GB
- [ ] Close all non-essential applications during experiments
- [ ] Record laptop specs (CPU model, RAM, SSD) for thesis methodology