# [THESIS-001] Environment Setup — Multipass VM

Labels: setup, infra  
Story Points: 3  
Dependencies: None  

## Description
Create and configure the Ubuntu VM via Multipass with pinned resource limits. Install Python, Dagster, and PostgreSQL inside the VM. Verify Dagster can run a single job with the process executor.

## Acceptance Criteria
- [ ] Multipass VM running Ubuntu 22.04 with exactly 4 vCPU, 8 GB RAM
- [ ] Python 3.12, Dagster 1.12.7, PostgreSQL 16 installed
- [ ] `dagster dev` runs and the UI is accessible from the host
- [ ] A single `thesis_workload` job completes successfully
- [ ] Resource limits verified: `nproc` shows 4, `free -h` shows ~8 GB
- [ ] Close all non-essential applications during experiments
- [ ] Record laptop specs (CPU model, RAM, SSD) for thesis methodology