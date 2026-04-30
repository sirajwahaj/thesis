"""
runway/store.py

Persists run metrics to SQLite (default) or Postgres.
Schema is minimal and append-only — never update, only insert.
"""
from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from .config import RunwayConfig

DEFAULT_DB = Path.home() / ".runway" / "metrics.db"


class MetricsStore:
    def __init__(self, db_path: Path | None = None):
        config = RunwayConfig.load()
        self.db_path = db_path or Path(config.database_url.replace("sqlite:///", ""))
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _init_db(self) -> None:
        with self._conn() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS runs (
                    run_id           TEXT PRIMARY KEY,
                    job_name         TEXT NOT NULL,
                    status           TEXT NOT NULL,
                    duration_s       REAL NOT NULL,
                    concurrency      INTEGER NOT NULL,
                    started_at       TEXT NOT NULL,
                    recorded_at      TEXT NOT NULL
                )
            """)

    def save(self, metric) -> None:  # metric: RunMetric (avoid circular import)
        with self._conn() as conn:
            conn.execute(
                """
                INSERT OR IGNORE INTO runs
                    (run_id, job_name, status, duration_s, concurrency, started_at, recorded_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    metric.run_id,
                    metric.job_name,
                    metric.status,
                    metric.duration_s,
                    metric.concurrency_level,
                    metric.started_at.isoformat(),
                    datetime.utcnow().isoformat(),
                ),
            )

    def get_recent(self, job_name: str, n: int = 30) -> list[dict]:
        with self._conn() as conn:
            rows = conn.execute(
                """
                SELECT run_id, job_name, status, duration_s, concurrency, started_at
                FROM runs
                WHERE job_name = ?
                ORDER BY started_at DESC
                LIMIT ?
                """,
                (job_name, n),
            ).fetchall()
        return [dict(zip(["run_id", "job_name", "status", "duration_s",
                          "concurrency", "started_at"], row))
                for row in rows]

    def get_all_job_names(self) -> list[str]:
        with self._conn() as conn:
            rows = conn.execute("SELECT DISTINCT job_name FROM runs").fetchall()
        return [r[0] for r in rows]

    def _conn(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path)
