"""
runway/predictor.py

Trend model: fits a linear regression over recent run durations,
projects forward to find the SLA breach date.

Returns a BreachPrediction with:
  - slope: seconds/run (positive = latency growing)
  - breach_date: projected date of SLA breach
  - confidence_days: half-width of the 80% confidence interval
  - runs_used: how many runs were in the fit
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timedelta

import numpy as np


@dataclass
class BreachPrediction:
    job_name: str
    slope_s_per_run: float       # how many seconds longer each run is than the last
    trend_pct_per_week: float    # percentage change per week
    current_p95_s: float         # P95 latency of recent runs
    sla_threshold_s: float       # the configured SLA limit
    breach_date: datetime | None # None if no breach predicted in 90 days
    breach_days: int | None      # days until breach (None if no breach)
    confidence_days: int         # half-width of confidence interval (80%)
    runs_used: int


def predict_breach(
    runs: list[dict],
    sla_threshold_s: float,
    max_horizon_days: int = 90,
    runs_per_day: float = 24.0,   # adjust to actual pipeline cadence
) -> BreachPrediction:
    """
    Fit a weighted linear regression on job duration over recent runs.
    Recent runs are weighted more heavily (exponential decay with half-life=10 runs).

    Args:
        runs: list of dicts with keys: duration_s, started_at, status
        sla_threshold_s: SLA breach threshold in seconds
        max_horizon_days: do not project beyond this many days
        runs_per_day: estimated pipeline runs per day (for date projection)

    Returns:
        BreachPrediction
    """
    # Filter to successful runs only (failed runs skew the distribution)
    successful = [r for r in runs if r["status"] == "SUCCESS"]
    if len(successful) < 5:
        # Not enough data for a reliable prediction
        return BreachPrediction(
            job_name=runs[0]["job_name"] if runs else "unknown",
            slope_s_per_run=0.0,
            trend_pct_per_week=0.0,
            current_p95_s=0.0,
            sla_threshold_s=sla_threshold_s,
            breach_date=None,
            breach_days=None,
            confidence_days=999,
            runs_used=len(successful),
        )

    durations = np.array([r["duration_s"] for r in successful], dtype=float)
    n = len(durations)
    x = np.arange(n, dtype=float)

    # Exponential weights: most recent run has weight 1.0, older runs decay
    half_life = 10.0
    weights = np.exp(-np.log(2) / half_life * (n - 1 - x))

    # Weighted least squares
    slope, intercept = _weighted_linear_fit(x, durations, weights)

    # Current P95
    p95 = float(np.percentile(durations, 95))

    # Project forward: how many more runs until SLA is breached?
    if slope <= 0 or intercept + slope * (n + max_horizon_days * runs_per_day) < sla_threshold_s:
        breach_date = None
        breach_days = None
        confidence_days = 0
    else:
        # Solve: intercept + slope * (n + delta_runs) = sla_threshold_s
        delta_runs = (sla_threshold_s - intercept - slope * n) / slope
        delta_days = delta_runs / runs_per_day
        confidence_days = _confidence_interval(durations, slope, delta_runs, runs_per_day)

        if delta_days <= 0:
            # Already past SLA
            breach_days = 0
            breach_date = datetime.utcnow()
        elif delta_days > max_horizon_days:
            breach_date = None
            breach_days = None
            confidence_days = 0
        else:
            breach_days = int(math.ceil(delta_days))
            breach_date = datetime.utcnow() + timedelta(days=breach_days)

    # Trend as % change per week
    baseline = float(durations[:5].mean()) if n >= 5 else float(durations[0])
    trend_pct = (slope * runs_per_day * 7 / baseline * 100) if baseline > 0 else 0.0

    return BreachPrediction(
        job_name=successful[0]["job_name"],
        slope_s_per_run=float(slope),
        trend_pct_per_week=round(trend_pct, 1),
        current_p95_s=round(p95, 1),
        sla_threshold_s=sla_threshold_s,
        breach_date=breach_date,
        breach_days=breach_days,
        confidence_days=confidence_days,
        runs_used=n,
    )


def _weighted_linear_fit(x: np.ndarray, y: np.ndarray,
                          w: np.ndarray) -> tuple[float, float]:
    W = np.diag(w)
    X = np.column_stack([x, np.ones(len(x))])
    result = np.linalg.lstsq(X.T @ W @ X, X.T @ W @ y, rcond=None)
    slope, intercept = result[0]
    return float(slope), float(intercept)


def _confidence_interval(durations: np.ndarray, slope: float,
                          delta_runs: float, runs_per_day: float) -> int:
    """Return half-width of 80% CI in days, based on residual variance."""
    residuals = np.diff(durations)
    std = float(np.std(residuals)) if len(residuals) > 1 else 1.0
    # Propagate uncertainty: ±1.28 * std per run over delta_runs
    uncertainty_s = 1.28 * std * math.sqrt(delta_runs)
    uncertainty_days = int(math.ceil(uncertainty_s / (slope * runs_per_day + 1e-9)))
    return max(1, min(uncertainty_days, 30))
