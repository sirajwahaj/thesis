# [THESIS-002] Environment Setup — Kind Cluster

Labels: setup, infra
Story Points: 3
Dependencies: THESIS-001

## Description
Create a Kind cluster with resource limits matching the VM. Install metrics-server. Deploy Dagster via Helm with K8sRunLauncher. Verify a single job runs as an isolated pod.

## Acceptance Criteria
- [x] Kind cluster `thesis` running (K8s v1.34.0, context `kind-thesis`)
- [x] Metrics-server deployed and `kubectl top pods` returns data
- [x] Dagster deployed via Helm with K8sRunLauncher enabled (Helm revision 4, dagster 1.12.22)
- [x] A single `thesis_workload` job launches as a separate Job pod and completes
- [x] Pod scheduling latency observable via `kubectl describe pod`
- [ ] LimitRange (4 CPU, 8 Gi) applied to dagster namespace
- [x] Helm chart pinned in `k8s/helm/dagster-thesis/Chart.yaml`

## Notes
Deployed with custom Helm chart at `k8s/helm/dagster-thesis/`. All 4 pods Running:
dagster-daemon, dagster-postgresql, dagster-thesis-webserver (NodePort 3001), dagster-thesis-workload (gRPC 4000).
GraphQL API verified: `{"data":{"version":"1.12.22"}}`.
