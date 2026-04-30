"""
runway/config.py

Configuration loader. Reads runway.yaml from the working directory
and merges with environment variables (env vars take precedence).
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

import yaml


DEFAULT_CONFIG_PATH = Path("runway.yaml")


@dataclass
class RunwayConfig:
    slack_token: str = ""
    slack_channel: str = "#data-alerts"
    database_url: str = "sqlite:///~/.runway/metrics.db"
    sla_multiplier: float = 2.0          # breach threshold = baseline * sla_multiplier
    concurrency_alert_threshold: int = 3  # VM crossover threshold from thesis
    min_runs_for_prediction: int = 5
    max_horizon_days: int = 90
    pipeline_names: list[str] = field(default_factory=list)  # [] = all pipelines

    @classmethod
    def load(cls, path: Path = DEFAULT_CONFIG_PATH) -> "RunwayConfig":
        data: dict = {}
        if path.exists():
            with open(path) as f:
                data = yaml.safe_load(f) or {}

        config = cls(
            slack_token=os.getenv("SLACK_TOKEN", data.get("slack_token", "")),
            slack_channel=os.getenv("SLACK_CHANNEL", data.get("slack_channel", "#data-alerts")),
            database_url=os.getenv("DATABASE_URL", data.get("database_url",
                                                              "sqlite:///~/.runway/metrics.db")),
            sla_multiplier=float(data.get("sla_multiplier", 2.0)),
            concurrency_alert_threshold=int(data.get("concurrency_alert_threshold", 3)),
            min_runs_for_prediction=int(data.get("min_runs_for_prediction", 5)),
            max_horizon_days=int(data.get("max_horizon_days", 90)),
            pipeline_names=data.get("pipeline_names", []),
        )
        return config
