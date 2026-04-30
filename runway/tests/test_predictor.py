"""
tests/test_predictor.py

Unit tests for the trend model.
Run with: pytest tests/test_predictor.py -v
"""
from __future__ import annotations

from datetime import datetime, timedelta

import pytest

from runway.predictor import predict_breach


def _make_runs(durations: list[float], status: str = "SUCCESS") -> list[dict]:
    now = datetime.utcnow()
    return [
        {
            "run_id": f"run_{i}",
            "job_name": "test_job",
            "status": status,
            "duration_s": d,
            "concurrency": 1,
            "started_at": (now - timedelta(hours=len(durations) - i)).isoformat(),
        }
        for i, d in enumerate(durations)
    ]


def test_flat_trend_no_breach():
    runs = _make_runs([60.0] * 20)
    result = predict_breach(runs, sla_threshold_s=120.0)
    assert result.breach_date is None
    assert result.slope_s_per_run < 0.01


def test_growing_trend_predicts_breach():
    # Latency grows by 2s per run: starts at 60, will reach 120 after 30 runs
    durations = [60.0 + i * 2.0 for i in range(20)]
    runs = _make_runs(durations)
    result = predict_breach(runs, sla_threshold_s=120.0, runs_per_day=24.0)
    assert result.breach_date is not None
    assert result.breach_days is not None
    assert result.breach_days > 0


def test_already_above_sla():
    runs = _make_runs([130.0] * 10)
    result = predict_breach(runs, sla_threshold_s=120.0)
    assert result.breach_days == 0 or result.breach_date is not None


def test_too_few_runs_returns_no_prediction():
    runs = _make_runs([60.0] * 3)
    result = predict_breach(runs, sla_threshold_s=120.0)
    assert result.breach_date is None
    assert result.runs_used == 3


def test_failed_runs_excluded_from_trend():
    # Mix of successes and failures — failures should not skew the trend
    success_runs = _make_runs([60.0] * 10, status="SUCCESS")
    failure_runs = _make_runs([999.0] * 5, status="FAILURE")
    all_runs = success_runs + failure_runs
    result = predict_breach(all_runs, sla_threshold_s=120.0)
    # Trend should be flat (only successes used)
    assert result.slope_s_per_run < 1.0
