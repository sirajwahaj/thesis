"""
Thesis workload: two-phase CPU + memory job (~60s total).
Phase 1 (cpu_burn): SHA-256 hashing for WORKLOAD_DURATION_SECONDS — LOCKED.
Phase 2 (memory_pressure): 400 MB numpy allocation + hashing — triggers OOM at L5/L6 on 4 GB VM (tests SQ2 blast radius).
"""

import dagster
import hashlib
import os
import platform
import resource
import time

import numpy as np


@dagster.op
def cpu_burn(context):
    """CPU-bound workload: compute hashes for WORKLOAD_DURATION_SECONDS.

    DO NOT MODIFY — this op body is locked for experiment comparability.
    The SHA-256 hash line must remain unchanged.
    """
    duration_raw = os.environ.get("WORKLOAD_DURATION_SECONDS", "30")
    try:
        duration = int(duration_raw)
    except ValueError:
        context.log.warning(f"Invalid WORKLOAD_DURATION_SECONDS='{duration_raw}', defaulting to 30")
        duration = 30
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


@dagster.op
def memory_pressure(context, cpu_result: dict) -> dict:
    """Allocate WORKLOAD_MEMORY_MB of RAM and hash it for WORKLOAD_DURATION_SECONDS.

    Holds the full allocation throughout the phase — triggers OOM at high concurrency
    on a 4 GB VM (L3=3 × 400 MB + infrastructure ~1.5–2 GB exceeds 4 GB RAM).
    On K8s, the 2 GiB per-pod cgroup limit prevents cross-pod memory interference,
    demonstrating blast radius containment (SQ2).
    """
    duration_raw = os.environ.get("WORKLOAD_DURATION_SECONDS", "30")
    memory_mb_raw = os.environ.get("WORKLOAD_MEMORY_MB", "400")
    try:
        duration = int(duration_raw)
    except ValueError:
        context.log.warning(f"Invalid WORKLOAD_DURATION_SECONDS='{duration_raw}', defaulting to 30")
        duration = 30
    try:
        memory_mb = int(memory_mb_raw)
    except ValueError:
        context.log.warning(f"Invalid WORKLOAD_MEMORY_MB='{memory_mb_raw}', defaulting to 400")
        memory_mb = 400

    context.log.info(
        f"Starting memory pressure: allocating {memory_mb} MB, "
        f"hashing for {duration}s (after cpu_burn: {cpu_result.get('elapsed_seconds', '?')}s)"
    )

    # Allocate the full buffer — triggers OOM at high concurrency on a 4 GB VM.
    # 3 concurrent containers × 400 MB each exceeds the 4 GB VM's available headroom
    # (which also runs Docker daemon, PostgreSQL, and Dagster daemon ~1.5–2 GB).
    # On K8s, the 2 GiB per-pod limit enforces hard memory isolation so no single
    # pod's allocation affects others, demonstrating blast radius containment.
    buffer = np.random.bytes(memory_mb * 1024 * 1024)

    start = time.monotonic()
    iterations = 0
    buf_len = len(buffer)

    while (time.monotonic() - start) < duration:
        # Hash a 32-byte chunk at a rotating offset — reads across the buffer
        offset = (iterations * 32) % (buf_len - 32)
        hashlib.sha256(buffer[offset : offset + 32]).hexdigest()
        iterations += 1

    elapsed = time.monotonic() - start

    # Peak resident set size in MB
    # On Linux ru_maxrss is in kilobytes; on macOS it is in bytes
    rss_raw = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    if platform.system() == "Darwin":
        peak_rss_mb = round(rss_raw / (1024 * 1024), 1)
    else:
        # Linux: ru_maxrss is in KB
        peak_rss_mb = round(rss_raw / 1024, 1)

    context.log.info(
        f"Memory phase complete: {iterations} hashes in {elapsed:.2f}s, "
        f"peak RSS {peak_rss_mb} MB"
    )

    # Delete the buffer explicitly so Python releases the memory immediately
    # after this op completes — avoids memory accumulation across runs.
    del buffer

    return {
        "memory_mb_allocated": memory_mb,
        "peak_rss_mb": peak_rss_mb,
        "iterations": iterations,
        "elapsed_seconds": round(elapsed, 2),
        "hostname": os.uname().nodename,
        "cpu_iterations": cpu_result.get("iterations"),
        "cpu_elapsed_seconds": cpu_result.get("elapsed_seconds"),
    }


@dagster.job
def thesis_workload():
    """Two-phase workload: cpu_burn (30s SHA-256) → memory_pressure (30s + 400 MB).

    Total ~60s/run under no contention. At L3+ on a 4 GB VM, Phase 2 triggers OOM
    kills via Linux OOM killer (aggregate demand exceeds 4 GB). On K8s, per-pod
    2 GiB memory limits contain each job's footprint, maintaining 100% success rate.
    """
    cpu_result = cpu_burn()
    memory_pressure(cpu_result)
