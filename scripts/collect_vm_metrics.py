#!/usr/bin/env python3
"""
Collect system-wide and per-container VM metrics using psutil + docker.

Writes CSV with: timestamp, system_cpu_pct, system_mem_pct,
system_mem_used_mb, dagster_process_count, docker_container_count

Contribution to RQ: Provides SQ1 data — CPU/memory utilisation
curves that show the degradation profile of Docker container execution.

Usage:
    python collect_vm_metrics.py --output data/raw/exp1/L1/run1/vm_metrics.csv
    python collect_vm_metrics.py --output vm_metrics.csv --interval 2
"""

import argparse
import csv
import os
import signal
import subprocess
import sys
import time

try:
    import psutil
except ImportError:
    print("Error: psutil is required. Install with: pip install psutil")
    sys.exit(1)

# Graceful shutdown on SIGTERM / SIGINT
_running = True


def _shutdown(signum, frame):
    global _running
    _running = False


signal.signal(signal.SIGTERM, _shutdown)
signal.signal(signal.SIGINT, _shutdown)


def _count_docker_containers() -> int:
    """Return count of running Dagster job containers (best-effort, 0 on error)."""
    try:
        result = subprocess.run(
            ["docker", "ps", "-q", "--filter", "label=dagster/image_type=run_worker"],
            capture_output=True, text=True, timeout=2,
        )
        lines = [l.strip() for l in result.stdout.splitlines() if l.strip()]
        return len(lines)
    except Exception:
        return 0


def collect_vm_metrics(output_file: str, interval: float = 1.0):
    """Collect system-wide and per-process metrics every `interval` seconds."""
    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)

    with open(output_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "timestamp",
            "system_cpu_pct",
            "system_mem_pct",
            "system_mem_used_mb",
            "dagster_process_count",
            "docker_container_count",
        ])

        # Prime CPU percent (first call always returns 0.0)
        psutil.cpu_percent(interval=None)

        print(f"Collecting VM metrics to {output_file} every {interval}s...")
        while _running:
            mem = psutil.virtual_memory()
            dagster_procs = [
                p for p in psutil.process_iter(["name", "cmdline"])
                if "dagster" in " ".join(p.info.get("cmdline") or [])
            ]
            writer.writerow([
                time.time(),
                psutil.cpu_percent(interval=None),
                mem.percent,
                round(mem.used / (1024 * 1024), 1),
                len(dagster_procs),
                _count_docker_containers(),
            ])
            f.flush()
            time.sleep(interval)

    print(f"Stopped. Metrics saved to {output_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Collect VM metrics via psutil")
    parser.add_argument("--output", required=True, help="Output CSV file path")
    parser.add_argument("--interval", type=float, default=1.0,
                        help="Collection interval in seconds (default: 1.0)")
    args = parser.parse_args()
    collect_vm_metrics(args.output, args.interval)
