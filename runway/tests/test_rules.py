"""
tests/test_rules.py

Unit tests for the recommendation rule engine.
"""
from __future__ import annotations

from runway.predictor import BreachPrediction
from runway.rules import Severity, evaluate


def _prediction(
    breach_days: int | None = None,
    trend_pct: float = 0.0,
    p95: float = 60.0,
    sla: float = 120.0,
) -> BreachPrediction:
    from datetime import datetime, timedelta
    return BreachPrediction(
        job_name="test_job",
        slope_s_per_run=0.0,
        trend_pct_per_week=trend_pct,
        current_p95_s=p95,
        sla_threshold_s=sla,
        breach_date=datetime.utcnow() + timedelta(days=breach_days) if breach_days else None,
        breach_days=breach_days,
        confidence_days=3,
        runs_used=20,
    )


def _runs(n: int = 20, success_rate: float = 1.0, concurrency: int = 1) -> list[dict]:
    successes = int(n * success_rate)
    return (
        [{"status": "SUCCESS", "concurrency": concurrency} for _ in range(successes)]
        + [{"status": "FAILURE", "concurrency": concurrency} for _ in range(n - successes)]
    )


def test_ok_when_healthy():
    result = evaluate(_prediction(), _runs())
    assert result.severity == Severity.OK


def test_critical_imminent_breach():
    result = evaluate(_prediction(breach_days=2), _runs())
    assert result.severity == Severity.CRITICAL


def test_warning_approaching_breach():
    result = evaluate(_prediction(breach_days=10), _runs())
    assert result.severity == Severity.WARNING


def test_warning_high_trend():
    result = evaluate(_prediction(trend_pct=12.0), _runs())
    assert result.severity == Severity.WARNING


def test_critical_vm_concurrency_threshold():
    # 3+ concurrent jobs, <95% success rate → K8s migration recommendation
    pred = _prediction()
    runs = _runs(n=20, success_rate=0.80, concurrency=4)
    result = evaluate(pred, runs)
    assert result.severity == Severity.CRITICAL
    assert "Kubernetes" in result.body or "Kubernetes" in result.action


def test_warning_low_success_rate():
    result = evaluate(_prediction(), _runs(n=20, success_rate=0.90, concurrency=1))
    assert result.severity == Severity.WARNING
