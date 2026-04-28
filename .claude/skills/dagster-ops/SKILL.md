---
name: dagster-ops
description: "Use when working with Dagster jobs, runs, assets, sensors, the Dagster UI, K8sRunLauncher configuration, DockerRunLauncher, gRPC server setup, run monitoring, or debugging failed/stuck runs."
---

# Dagster Operations

## Thesis Dagster Setup

| Aspect | VM | K8s |
|--------|-----|-----|
| Executor | DockerRunLauncher (Docker CE) | K8sRunLauncher |
| Config | `/opt/thesis/dagster_home/dagster.yaml` | `k8s/helm/dagster-thesis/values.yaml` |
| gRPC server | systemd `thesis-workload` on port 4000 | Deployment `workload-grpc` in namespace `dagster` |
| Job name | `thesis_workload` | `thesis_workload` |
| Dagster webserver | `http://<vm-ip>:3001` | `http://localhost:30001` (NodePort) |

## Trigger a run via GraphQL (any env)

```bash
curl -s -X POST http://localhost:3001/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { launchRun(executionParams: { selector: { repositoryName: \"__repository__\", repositoryLocationName: \"workload\", jobName: \"thesis_workload\" }, mode: \"default\" }) { run { runId status } } }"
  }' | python3 -m json.tool
```

## Trigger runs via Python script

```bash
python3 scripts/trigger_dagster_runs.py \
  --level 3 \
  --repetition 1 \
  --env vm \
  --host localhost \
  --port 3001
```

## Export run data to CSV

```bash
python3 scripts/export_dagster_runs.py \
  --output data/raw/exp1-vm-degradation/vm/L3/run1/dagster_runs.csv
```

## Check run status

```bash
# All recent runs (last 20)
python3 scripts/export_dagster_runs.py --limit 20 --format table

# Check for failures
python3 scripts/export_dagster_runs.py --status FAILURE --format table
```

## Debug VM runs

```bash
# Check gRPC server health
ssh -i ~/.ssh/thesis_vm ubuntu@$(cat vm-ip.txt) "systemctl status thesis-workload"

# Restart gRPC server
ssh -i ~/.ssh/thesis_vm ubuntu@$(cat vm-ip.txt) "sudo systemctl restart thesis-workload"

# View gRPC server logs
ssh -i ~/.ssh/thesis_vm ubuntu@$(cat vm-ip.txt) "journalctl -u thesis-workload -n 50"

# Check Dagster logs on VM
ssh -i ~/.ssh/thesis_vm ubuntu@$(cat vm-ip.txt) "cat /opt/thesis/dagster_home/logs/*.log | tail -100"
```

## Debug K8s runs

```bash
# List all pods in dagster namespace
kubectl get pods -n dagster

# Get logs from a run pod (name format: dagster-run-<run-id>)
kubectl logs <run-pod-name> -n dagster

# Describe pod (shows scheduling events, resource issues)
kubectl describe pod <run-pod-name> -n dagster

# Get events (shows pull failures, node pressure)
kubectl get events -n dagster --sort-by='.lastTimestamp'

# Check resource usage
kubectl top pods -n dagster
kubectl top nodes

# Get Dagster daemon logs
kubectl logs -l component=dagster-daemon -n dagster -f

# Get webserver logs
kubectl logs -l component=dagster-webserver -n dagster -f
```

## Common failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Run stuck in STARTED | gRPC unreachable | `systemctl restart thesis-workload` |
| K8s pod stuck Pending | Resource pressure | Check `kubectl describe pod`, scale down other runs |
| Run shows FAILURE, pod exit 0 | DAGSTER_HOME env not set in pod | Check `values.yaml` env vars |
| gRPC timeout | VM under heavy load | Wait for cooldown or increase `COOLDOWN` in run_experiment.sh |
| ImagePullBackOff | Image not in local registry | Re-run `make k8s-deploy-dagster` |
| CrashLoopBackOff on daemon | PostgreSQL not ready | Check `kubectl logs` on postgres pod first |

## K8sRunLauncher configuration (values.yaml)

Key fields to know:
```yaml
dagster:
  runLauncher:
    type: K8sRunLauncher
    config:
      jobNamespace: dagster
      loadInclusterConfig: true
      jobImage: localhost:5001/thesis-workload:latest
      envConfigMaps: [dagster-workload-config]

resources:
  limits:
    cpu: "1000m"    # 1 vCPU per run — do not change (calibrated for comparison)
    memory: "1Gi"   # 1 GiB per run — do not change
```

These resource limits are set to match the VM's per-process allocation and must not be changed.
