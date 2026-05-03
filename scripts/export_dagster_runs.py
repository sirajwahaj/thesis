#!/usr/bin/env python3
"""
Export Dagster run records from PostgreSQL for analysis.

Extracts: run_id, status, start_time, end_time, job_name, concurrency_level,
repetition, memory_mb_allocated, peak_rss_mb
from the Dagster runs, run_tags, and event_logs tables.

Required CSV columns per data-pipeline rules:
  run_id, status, start_time, end_time, job_name, concurrency_level, repetition

Additional columns added for memory analysis (SQ1, SQ2):
  memory_mb_allocated  - MB allocated by the memory_pressure op (from event log)
  peak_rss_mb          - peak RSS reported by the memory_pressure op

Usage:
    python export_dagster_runs.py --output data/raw/exp1/vm/L1/run1/dagster_runs.csv
    python export_dagster_runs.py --output runs.csv --host localhost --port 5432
"""

import argparse
import csv
import os
import sys
from datetime import datetime, timezone

try:
    import psycopg2
except ImportError:
    print("Error: psycopg2 is required. Install with: pip install psycopg2-binary")
    sys.exit(1)


def ts_to_iso(value) -> str:
    """Convert a Unix float timestamp or datetime to ISO 8601 string."""
    if value is None:
        return ""
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(float(value), tz=timezone.utc).isoformat()
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def _extract_memory_outputs(cur, run_id: str) -> tuple[str, str]:
    """Extract memory_mb_allocated and peak_rss_mb from the Dagster event log.

    The memory_pressure op outputs these as step success metadata in the
    event_logs table. Returns ('', '') if the op did not complete (e.g. OOM kill).
    """
    try:
        cur.execute("""
            SELECT event_body
            FROM event_logs
            WHERE run_id = %s
              AND dagster_event_type = 'STEP_OUTPUT'
              AND event_body LIKE '%%memory_mb_allocated%%'
            ORDER BY id DESC
            LIMIT 1
        """, (run_id,))
        row = cur.fetchone()
        if not row:
            return "", ""

        import json
        event = json.loads(row[0])
        # Navigate Dagster event structure: event_specific_data → step_output_data → output_value
        # The output value is the dict returned by memory_pressure()
        output = (
            event
            .get("event_specific_data", {})
            .get("output", {})
            .get("value", {})
        )
        if isinstance(output, dict):
            return (
                str(output.get("memory_mb_allocated", "")),
                str(output.get("peak_rss_mb", "")),
            )
        return "", ""
    except Exception:
        # Non-fatal: runs that OOM-killed will not have this event
        return "", ""


def export_dagster_runs(
    host: str,
    port: int,
    user: str,
    password: str,
    dbname: str,
    output_file: str,
) -> None:
    """Export Dagster run records from PostgreSQL to CSV."""
    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)

    try:
        conn = psycopg2.connect(
            host=host, port=port,
            user=user, password=password,
            dbname=dbname,
            connect_timeout=10,
        )
    except psycopg2.OperationalError as e:
        print(f"Error: Cannot connect to PostgreSQL at {host}:{port} — {e}", file=sys.stderr)
        sys.exit(1)

    cur = conn.cursor()

    # Main query — joins run_tags to extract level and repetition stored during triggering
    cur.execute("""
        SELECT
            r.run_id,
            r.status,
            r.start_time,
            r.end_time,
            r.pipeline_name AS job_name,
            COALESCE(
                (SELECT t.value FROM run_tags t
                 WHERE t.run_id = r.run_id AND t.key = 'concurrency_level'
                 LIMIT 1),
                ''
            ) AS concurrency_level,
            COALESCE(
                (SELECT t.value FROM run_tags t
                 WHERE t.run_id = r.run_id AND t.key = 'repetition'
                 LIMIT 1),
                ''
            ) AS repetition
        FROM runs r
        ORDER BY r.create_timestamp
    """)
    rows = cur.fetchall()

    with open(output_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "run_id", "status", "start_time", "end_time",
            "job_name", "concurrency_level", "repetition",
            "memory_mb_allocated", "peak_rss_mb",
        ])
        for row in rows:
            run_id, status, start_time, end_time, job_name, conc_level, repetition = row
            memory_mb, peak_rss = _extract_memory_outputs(cur, run_id)
            writer.writerow([
                run_id,
                status,
                ts_to_iso(start_time),
                ts_to_iso(end_time),
                job_name or "",
                conc_level,
                repetition,
                memory_mb,
                peak_rss,
            ])

    conn.close()
    print(f"Exported {len(rows)} run records to {output_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Export Dagster runs from PostgreSQL")
    parser.add_argument("--output", required=True, help="Output CSV file path")
    parser.add_argument("--host", default=os.environ.get("DAGSTER_PG_HOSTNAME", "localhost"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("DAGSTER_PG_PORT", "5432")))
    parser.add_argument("--user", default=os.environ.get("DAGSTER_PG_USERNAME", "dagster"))
    parser.add_argument("--password", default=os.environ.get("DAGSTER_PG_PASSWORD", "dagster"))
    parser.add_argument("--dbname", default=os.environ.get("DAGSTER_PG_DB", "dagster"))
    args = parser.parse_args()

    export_dagster_runs(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password,
        dbname=args.dbname,
        output_file=args.output,
    )
