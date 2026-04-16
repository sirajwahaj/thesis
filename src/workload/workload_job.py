"""
Thesis workload: a CPU-bound job that runs for a configurable duration.
It computes SHA-256 hashes in a tight loop to create real CPU pressure.

Why SHA-256 hashing?
  - Pure CPU without I/O — creates real CPU contention when multiple
    processes run simultaneously on limited cores.
  - The iteration count provides a secondary metric — if contention
    reduces throughput, iteration count drops.

Duration: 30 seconds per job (default). Configurable via
WORKLOAD_DURATION_SECONDS environment variable.
"""

import dagster
import hashlib
import time
import os


@dagster.op
def cpu_burn(context):
    """CPU-bound workload: compute hashes for WORKLOAD_DURATION_SECONDS."""
    duration = int(os.environ.get("WORKLOAD_DURATION_SECONDS", "30"))
    context.log.info(f"Starting CPU burn for {duration}s")

    start = time.monotonic()
    iterations = 0
    data = b"dagster-thesis-workload"

    while (time.monotonic() - start) < duration:
        hashlib.sha256(data).hexdigest()
        iterations += 1

    elapsed = time.monotonic() - start
    context.log.info(f"Completed: {iterations} hashes in {elapsed:.2f}s")

    return {
        "iterations": iterations,
        "elapsed_seconds": round(elapsed, 2),
        "hostname": os.uname().nodename,
    }


@dagster.job
def thesis_workload():
    cpu_burn()
