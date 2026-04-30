"""
runway/rules.py

Rule engine: maps stress signals to infrastructure recommendations.
Rules are evaluated in priority order; the first match wins.

Rules are data-driven: thresholds come from RunwayConfig and can be overridden
per pipeline in runway.yaml. The crossover thresholds are calibrated against
the experimental data from Wahaj (2026).
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from .predictor import BreachPrediction
from .store import MetricsStore


class Severity(str, Enum):
    OK = "ok"
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


@dataclass
class Recommendation:
    severity: Severity
    title: str
    body: str
    action: str          # short imperative sentence for Slack subject line
    docs_url: str = "https://runway.sh/docs"


def evaluate(
    prediction: BreachPrediction,
    recent_runs: list[dict],
) -> Recommendation:
    """
    Evaluate stress signals and return the highest-priority recommendation.
    Thresholds are based on the experimental crossover findings (Wahaj, 2026).
    """
    success_rate = _success_rate(recent_runs)
    avg_concurrency = _avg_concurrency(recent_runs)

    # Rule 1 — active SLA breach (most urgent)
    if prediction.breach_days is not None and prediction.breach_days <= 3:
        return Recommendation(
            severity=Severity.CRITICAL,
            title="SLA breach imminent",
            body=(
                f"P95 latency is {prediction.current_p95_s}s and trending toward "
                f"your SLA limit of {prediction.sla_threshold_s}s in approximately "
                f"{prediction.breach_days} day(s). Immediate action required."
            ),
            action="Reduce pipeline concurrency or scale infrastructure now",
        )

    # Rule 2 — reliability collapse at high concurrency (crossover framework)
    if avg_concurrency >= 3 and success_rate < 0.95 and _is_vm_deployment(recent_runs):
        return Recommendation(
            severity=Severity.CRITICAL,
            title="VM reliability below threshold at this concurrency level",
            body=(
                f"Success rate is {success_rate:.0%} with {avg_concurrency:.1f} average "
                "concurrent jobs. Research shows VM deployments degrade non-linearly at "
                "≥3 concurrent jobs. This is the K8s migration crossover point."
            ),
            action="Migrate to Kubernetes — the threshold has been reached",
        )

    # Rule 3 — approaching breach (early warning)
    if prediction.breach_days is not None and prediction.breach_days <= 14:
        return Recommendation(
            severity=Severity.WARNING,
            title=f"SLA breach predicted in {prediction.breach_days} days",
            body=(
                f"Latency is growing at {prediction.trend_pct_per_week:+.1f}%/week. "
                f"Estimated breach date: {prediction.breach_date.strftime('%d %b %Y')} "
                f"(range: ±{prediction.confidence_days} days)."
            ),
            action="Review pipeline concurrency and resource limits",
        )

    # Rule 4 — trend warning
    if prediction.trend_pct_per_week > 8:
        return Recommendation(
            severity=Severity.WARNING,
            title="Latency growing faster than 8%/week",
            body=(
                f"P95 latency is increasing at {prediction.trend_pct_per_week:.1f}%/week "
                "over the last run window. No breach predicted within 90 days, but "
                "investigate the root cause before it compounds."
            ),
            action="Add resource limits and check for memory pressure",
        )

    # Rule 5 — success rate declining but no breach yet
    if success_rate < 0.95:
        return Recommendation(
            severity=Severity.WARNING,
            title=f"Success rate below 95% ({success_rate:.0%})",
            body=(
                "This pipeline is failing more than 1 in 20 runs. "
                "Review recent failure logs and add retry logic."
            ),
            action="Add retry policies and failure alerting",
        )

    # All clear
    return Recommendation(
        severity=Severity.OK,
        title="Pipeline healthy",
        body=(
            f"P95 latency: {prediction.current_p95_s}s. "
            f"Success rate: {success_rate:.0%}. "
            f"Trend: {prediction.trend_pct_per_week:+.1f}%/week. "
            "No action needed."
        ),
        action="No action needed",
    )


def _success_rate(runs: list[dict]) -> float:
    if not runs:
        return 1.0
    return sum(1 for r in runs if r["status"] == "SUCCESS") / len(runs)


def _avg_concurrency(runs: list[dict]) -> float:
    if not runs:
        return 1.0
    return sum(r.get("concurrency", 1) for r in runs) / len(runs)


def _is_vm_deployment(runs: list[dict]) -> bool:
    # Heuristic: if no pod_scheduling_latency field, assume VM deployment
    return all("pod_scheduling_latency" not in r for r in runs)
