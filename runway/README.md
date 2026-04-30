# Runway

**Predictive pipeline monitoring for data engineering teams.**

Runway attaches to your Dagster pipelines and tells you — before it happens — when a pipeline
will breach its SLA and what infrastructure change to make.

---

## The problem

Data pipelines fail in predictable patterns. Latency grows slowly, then suddenly collapses.
Most teams find out when a downstream user reports a stale dashboard, not when the trend
started three weeks earlier.

## What Runway does

1. **Collects** per-run metrics via a zero-config Dagster sensor
2. **Predicts** the SLA breach date using a rolling linear trend model
3. **Recommends** the right infrastructure action, calibrated against empirical
   research on VM vs Kubernetes failure thresholds (Wahaj, 2026)

## Quick start

```bash
cd your-dagster-project
uv add runway-pipeline  # or: pip install runway-pipeline
cp runway.yaml.example runway.yaml
# Edit SLACK_TOKEN and pipeline names
```

In your Dagster repository:
```python
from runway.dagster_integration.sensors import runway_sensors

defs = Definitions(
    jobs=[...],
    sensors=runway_sensors,  # add this line
)
```

That is all. Runway starts collecting data immediately. First prediction after 5 runs.

## Configuration

Copy `config/runway.yaml` to your project root and edit:

```yaml
slack_token: "xoxb-..."
slack_channel: "#data-alerts"
sla_multiplier: 2.0        # breach threshold = 2× your baseline latency
concurrency_alert_threshold: 3   # K8s crossover point
```

## Requirements

- Python 3.13+
- Dagster 1.12.22+
- Slack workspace with bot token (for alerts)

## Development

```bash
uv sync --all-extras
pytest tests/ -v
```

## Research foundation

The recommendation thresholds are calibrated against controlled experiments measuring
VM (DockerRunLauncher) vs Kubernetes (K8sRunLauncher) reliability under increasing
concurrent load. The crossover point — where K8s becomes net beneficial — was
empirically validated at 3 concurrent jobs on 4-vCPU hardware.

**Reference:** Wahaj, S. (2026). *When Does Kubernetes Become Worth It?* JENSEN Yrkeshögskola.

## Licence

Apache 2.0
