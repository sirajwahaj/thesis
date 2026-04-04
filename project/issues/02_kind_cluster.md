# [THESIS-002] Environment Setup — Kind Cluster

Labels: setup, infra  
Story Points: 3  
Dependencies: THESIS-001  

## Description
Create a Kind cluster with resource limits matching the VM. Install metrics-server. Deploy Dagster via Helm with K8sRunLauncher. Verify a single job runs as an isolated pod.

## Acceptance Criteria
- [ ] Kind cluster running with resource limits (LimitRange: 4 CPU, 8 Gi per namespace)
- [ ] Metrics-server deployed and `kubectl top pods` returns data
- [ ] Dagster deployed via Helm with K8sRunLauncher enabled
- [ ] A single `thesis_workload` job launches as a separate Job pod and completes
- [ ] Pod scheduling latency observable via `kubectl describe pod`
- [ ] Pin Helm chart version for reproducibility