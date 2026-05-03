#!/usr/bin/env python3
"""
Collect pod lifecycle timestamps for scheduling overhead analysis.

Parses Kubernetes pod status and events to isolate:
  - submitted_ts: pod creation timestamp (submitted to K8s API)
  - scheduled_ts: pod scheduled to a node (PodScheduled condition)
  - running_ts:   pod containers running (pod phase = Running)
  - job_start_ts: job execution started (ContainersReady condition)

Required CSV columns per data-pipeline rules:
  run_id, pod_name, submitted_ts, scheduled_ts, running_ts, job_start_ts

Contribution to RQ: Directly answers SQ3 — pod scheduling latency (submitted_ts
to scheduled_ts) and container startup time (scheduled_ts to running_ts) are
isolated from job execution time.

Usage:
    python collect_pod_timing.py --output data/raw/exp2/k8s/L1/run1/pod_timing.csv
    python collect_pod_timing.py --output timing.csv --namespace dagster
"""

import argparse
import csv
import json
import os
import subprocess
import sys
from datetime import datetime


def parse_iso_timestamp(ts: str) -> str:
    """Normalise ISO 8601 timestamp to UTC isoformat. Returns '' on failure."""
    if not ts:
        return ""
    ts = ts.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(ts)
        return dt.isoformat()
    except ValueError:
        return ts


def get_run_id_from_labels(pod: dict) -> str:
    """Extract Dagster run_id from pod labels/annotations."""
    labels = pod.get("metadata", {}).get("labels", {})
    annotations = pod.get("metadata", {}).get("annotations", {})
    # Dagster K8s run pods have a label like dagster/run-id or run_id
    for key in ("dagster/run-id", "run_id", "run-id"):
        if key in labels:
            return labels[key]
        if key in annotations:
            return annotations[key]
    return ""


def collect_pod_timing(namespace: str, output_file: str) -> None:
    """Collect pod lifecycle timestamps for scheduling overhead analysis."""
    os.makedirs(os.path.dirname(output_file) or ".", exist_ok=True)

    result = subprocess.run(
        ["kubectl", "get", "pods", "-n", namespace, "-o", "json"],
        capture_output=True, text=True,
    )

    if result.returncode != 0:
        print(f"Error running kubectl: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    try:
        pods = json.loads(result.stdout).get("items", [])
    except json.JSONDecodeError as e:
        print(f"Error parsing kubectl JSON output: {e}", file=sys.stderr)
        sys.exit(1)

    with open(output_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "run_id",
            "pod_name",
            "submitted_ts",
            "scheduled_ts",
            "running_ts",
            "job_start_ts",
        ])

        for pod in pods:
            pod_name = pod["metadata"]["name"]
            run_id = get_run_id_from_labels(pod)

            # Only include Dagster run pods (skip infrastructure pods)
            if not run_id:
                continue

            # submitted_ts = pod creation time (submitted to K8s API)
            submitted_ts = parse_iso_timestamp(
                pod["metadata"].get("creationTimestamp", "")
            )

            # Parse status conditions
            conditions = {
                c["type"]: c.get("lastTransitionTime", "")
                for c in pod.get("status", {}).get("conditions", [])
            }

            # scheduled_ts = when K8s scheduler assigned the pod to a node
            scheduled_ts = parse_iso_timestamp(conditions.get("PodScheduled", ""))

            # running_ts = when pod phase first became Running
            # Use the startTime from pod status as it represents when containers started
            running_ts = parse_iso_timestamp(
                pod.get("status", {}).get("startTime", "")
            )

            # job_start_ts = when all containers were ready (job executing)
            job_start_ts = parse_iso_timestamp(conditions.get("ContainersReady", ""))

            writer.writerow([
                run_id,
                pod_name,
                submitted_ts,
                scheduled_ts,
                running_ts,
                job_start_ts,
            ])

    print(f"Wrote {len([p for p in pods if get_run_id_from_labels(p)])} run pod records to {output_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Collect K8s pod timing data")
    parser.add_argument("--output", required=True, help="Output CSV file path")
    parser.add_argument("--namespace", default="dagster", help="K8s namespace")
    args = parser.parse_args()
    collect_pod_timing(args.namespace, args.output)
