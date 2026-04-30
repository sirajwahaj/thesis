"""
runway/sensor.py

Dagster sensor that attaches to the event log and records per-run metrics.
Add RunwaySensor to your Dagster repository — no other configuration needed.
"""
from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import datetime

from dagster import RunStatusSensorContext, SensorResult, run_status_sensor
from dagster import DagsterRunStatus

from .store import MetricsStore


@dataclass
class RunMetric:
    run_id: str
    job_name: str
    status: str                  # SUCCESS | FAILURE
    duration_s: float            # end_time - start_time in seconds
    concurrency_level: int       # how many jobs ran at the same time
    started_at: datetime
    ended_at: datetime


@run_status_sensor(
    run_status=DagsterRunStatus.SUCCESS,
    name="runway_success_sensor",
)
def runway_success_sensor(context: RunStatusSensorContext) -> SensorResult:
    _record_run(context, status="SUCCESS")
    return SensorResult()


@run_status_sensor(
    run_status=DagsterRunStatus.FAILURE,
    name="runway_failure_sensor",
)
def runway_failure_sensor(context: RunStatusSensorContext) -> SensorResult:
    _record_run(context, status="FAILURE")
    return SensorResult()


def _record_run(context: RunStatusSensorContext, status: str) -> None:
    run = context.dagster_run
    stats = context.instance.get_run_stats(run.run_id)

    start = stats.start_time or time.time()
    end = stats.end_time or time.time()
    duration = end - start

    metric = RunMetric(
        run_id=run.run_id,
        job_name=run.job_name,
        status=status,
        duration_s=duration,
        concurrency_level=_estimate_concurrency(context),
        started_at=datetime.fromtimestamp(start),
        ended_at=datetime.fromtimestamp(end),
    )

    store = MetricsStore()
    store.save(metric)


def _estimate_concurrency(context: RunStatusSensorContext) -> int:
    """Count runs that were active at the same time as this one."""
    run = context.dagster_run
    stats = context.instance.get_run_stats(run.run_id)
    if not stats.start_time or not stats.end_time:
        return 1

    # Query runs that overlapped with this run's time window
    all_runs = context.instance.get_runs()
    count = 0
    for r in all_runs:
        s = context.instance.get_run_stats(r.run_id)
        if s.start_time and s.end_time:
            if s.start_time < stats.end_time and s.end_time > stats.start_time:
                count += 1
    return max(count, 1)
