# Monitoring Stack

PLG + Prometheus monitoring for the thesis benchmarking environment.
Covers both the VM (DockerRunLauncher) and Kind K8s (K8sRunLauncher) experiments.

## Architecture

```
                     ┌──────────────────────────────────────────┐
                     │              GRAFANA :3000               │
                     │  Dashboards: experiment-overview,        │
                     │  dagster-containers, k8s-pods,           │
                     │  comparison (VM vs K8s)                  │
                     └────────┬────────────┬──────────┬─────────┘
                              │            │          │
                   Prometheus │        Loki│     Tempo│
                    :9090     │        :3100│     :3200│
                     │        │            │          │
          ┌──────────┘  ┌─────┘     ┌──────┘    ┌──────┘
          │             │           │           │
   ┌──────▼──────┐ ┌────▼────┐ ┌───▼────┐ ┌───▼─────┐
   │ Prometheus  │ │  Loki   │ │Promtail│ │  Tempo  │
   │ + Recording │ │  Log    │ │ Log    │ │ Tracing │
   │   Rules     │ │  Store  │ │ Agent  │ │  Store  │
   └──────┬──────┘ └─────────┘ └───┬────┘ └─────────┘
          │ scrapes                │ reads
   ┌──────▼──────────────────────────────────────────────────────┐
   │  VM Host                                                    │
   │  node-exporter :9100   cAdvisor :8080   postgres-exp :9187  │
   │  Dagster webserver :3001   Dagster daemon   PostgreSQL :5432 │
   └─────────────────────────────────────────────────────────────┘
          │ federation (optional, when K8S_PROMETHEUS_URL set)
   ┌──────▼──────────────────────────────────────────────────────┐
   │  Kind K8s cluster                                           │
   │  kube-state-metrics   node-exporter (K8s node)             │
   │  Dagster pods (namespace: dagster)                         │
   └─────────────────────────────────────────────────────────────┘

  Pushgateway :9091  ← experiment scripts push batch metrics (run success/fail counts)
  Alertmanager :9093 ← routes alerts to Grafana annotations + Slack (optional)
```

## Services & Ports

| Service          | Port  | Purpose                                       |
|-----------------|-------|-----------------------------------------------|
| Grafana          | 3000  | Dashboards, alerting UI                       |
| Prometheus       | 9090  | Metrics scrape + query                        |
| Alertmanager     | 9093  | Alert routing                                 |
| Loki             | 3100  | Log aggregation                               |
| Tempo            | 3200  | Distributed trace storage                     |
| Tempo OTLP gRPC  | 4317  | Dagster ops send traces here                  |
| Tempo OTLP HTTP  | 4318  | Alternative OTEL endpoint                     |
| Pushgateway      | 9091  | Batch metrics from experiment scripts         |
| node-exporter    | 9100  | VM host CPU/memory/disk/network               |
| cAdvisor         | 8080  | Docker container metrics                      |
| postgres-exporter| 9187  | PostgreSQL query stats + connections          |

## Quickstart

```bash
# 1. Copy and edit the environment file
cp monitoring/.env.monitoring.example monitoring/.env.monitoring
#    At minimum set GRAFANA_ADMIN_PASSWORD

# 2. Start the stack
make monitoring-up

# 3. Open Grafana
open http://<vm-ip>:3000
# Login: admin / <your GRAFANA_ADMIN_PASSWORD>
```

## Environment Variables (`.env.monitoring`)

See [.env.monitoring.example](.env.monitoring.example) for all variables.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GRAFANA_ADMIN_PASSWORD` | Yes | `thesis2026` | Grafana admin password |
| `GRAFANA_API_KEY` | No | — | For Alertmanager → Grafana annotation webhook |
| `POSTGRES_DSN` | Yes | — | `postgresql://user:pass@host:5432/dagster` |
| `K8S_PROMETHEUS_URL` | No | disabled | `host:30090` for Prometheus federation |
| `PROMETHEUS_RETENTION` | No | `15d` | How long Prometheus keeps raw data |
| `SLACK_WEBHOOK_URL` | No | — | Slack alerts (optional) |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | — | `http://<vm-ip>:4317` for Dagster → Tempo |

## Dashboards

| Dashboard | UID | What it shows | Research Question |
|-----------|-----|---------------|-------------------|
| Experiment Overview | `thesis-experiment-overview` | OOM kills, success rate vs SLO, p95 CPU, container count | SQ1, SQ2 |
| Dagster Containers | `thesis-dagster-containers` | Per-container CPU/memory/restarts | SQ1, SQ2 |
| K8s Pods | `thesis-k8s-pods` | Pod scheduling latency, pod phases, resource usage | SQ2, SQ3 |
| VM vs K8s Comparison | `thesis-vm-k8s-comparison` | Side-by-side CPU, OOM, container count, crossover | SQ4 |

## Make Targets

```bash
make monitoring-up           # Deploy to VM
make monitoring-down         # Stop
make monitoring-restart      # Stop + start
make monitoring-status       # Show running containers
make monitoring-logs         # Follow all logs
make monitoring-update       # Hot-reload Prometheus/Alertmanager config (no restart)
make monitoring-validate     # Validate all configs locally + check live health
make monitoring-validate-local  # Validate configs only (no VM needed)
make monitoring-test         # Run promtool unit tests for alert/recording rules
make monitoring-export-dashboards  # Export live Grafana dashboards to monitoring/grafana/dashboards/
make monitoring-export-metrics     # Export Prometheus metrics to data/processed/ CSVs
```

## Prometheus Federation (K8s → VM)

When `K8S_PROMETHEUS_URL` is set (in `.env.monitoring`), Prometheus on the VM will federate
K8s metrics. This allows the VM vs K8s comparison dashboard to work without port-forwarding.

1. Find the Kind node IP: `docker inspect thesis-control-plane | grep IPAddress`
2. In `.env.monitoring`, set: `K8S_PROMETHEUS_URL=<kind-node-ip>:30090`
3. Run `make monitoring-update` to reload the config

## Grafana Annotations (Experiment Timeline Markers)

The experiment runner (`scripts/bash/run_experiment.sh`) automatically calls
`scripts/bash/push-grafana-annotation.sh` at the start and end of each level/repetition.

This creates green (start) and red (end) markers on all Grafana dashboards,
making it easy to correlate resource spikes with specific experiment runs.

To push a manual annotation:
```bash
bash scripts/bash/push-grafana-annotation.sh "my event" "tag1,tag2"
```

## Alert Rules

Alerts fire in Prometheus and route through Alertmanager:

| Alert | Severity | Fires when |
|-------|----------|-----------|
| `HighCpuUsage` | warning | VM CPU > 85% for 2m |
| `CriticalCpuUsage` | critical | VM CPU > 95% for 1m |
| `HighMemoryUsage` | warning | VM memory > 85% for 2m |
| `CriticalMemoryUsage` | critical | VM memory > 95% for 30s |
| `OomKillDetected` | critical | OOM kill event detected |
| `DagsterRunFailed` | warning | Dagster run container exited non-zero |
| `DagsterDaemonCrashed` | critical | No daemon container for 2m |
| `ExperimentStuck` | warning | No new run container for 10min |
| `PostgresConnectionExhaustion` | warning | PG connections > 85% |
| `PostgresConnectionCritical` | critical | PG connections > 95% |

Alerts are also available as Grafana-native rules in
`monitoring/grafana/provisioning/alerting/rules.yml`.

## CI Validation

The `.github/workflows/ci.yml` `validate-monitoring` job runs on every push and:
- Validates `prometheus.yml` with `promtool check config`
- Validates `alerts.yml` and `recording_rules.yml` with `promtool check rules`
- Runs unit tests from `monitoring/prometheus/test_rules.yml` with `promtool test rules`
- Validates Alertmanager config with `amtool check-config`
- Validates all dashboard JSON files are parseable
