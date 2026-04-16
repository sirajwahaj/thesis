#!/usr/bin/env python3
"""
Launch N concurrent Dagster runs via GraphQL API and wait for all to complete.

Usage:
    python trigger_dagster_runs.py 5
    python trigger_dagster_runs.py 10 --job thesis_workload --level 5 --rep 1 --env k8s
    python trigger_dagster_runs.py 3 --host localhost --port 3001
"""

import argparse
import json
import sys
import time
import urllib.request
import urllib.error

LAUNCH_RUN_MUTATION = """
mutation LaunchRun($executionParams: ExecutionParams!) {
  launchRun(executionParams: $executionParams) {
    ... on LaunchRunSuccess {
      run {
        runId
        status
      }
    }
    ... on PythonError {
      message
    }
    ... on RunConflict {
      message
    }
    ... on InvalidSubsetError {
      message
    }
  }
}
"""

GET_REPO_QUERY = """
query GetRepository {
  repositoriesOrError {
    ... on RepositoryConnection {
      nodes {
        name
        location {
          name
        }
        jobs {
          name
        }
      }
    }
  }
}
"""


def get_repository_location(host: str, port: int, job_name: str) -> tuple[str, str]:
    """Discover repository name and location name from Dagster."""
    try:
        result = graphql_request(host, port, GET_REPO_QUERY, {})
        nodes = result.get("data", {}).get("repositoriesOrError", {}).get("nodes", [])
        for repo in nodes:
            if any(j["name"] == job_name for j in repo.get("jobs", [])):
                return repo["name"], repo["location"]["name"]
        # Fallback: return first repo
        if nodes:
            return nodes[0]["name"], nodes[0]["location"]["name"]
    except Exception as e:
        print(f"  Warning: could not discover repo: {e}", file=sys.stderr)
    # Legacy defaults
    return "__repository__", "workload"


RUN_STATUS_QUERY = """
query RunStatus($runId: ID!) {
  runOrError(runId: $runId) {
    ... on Run {
      runId
      status
    }
    ... on RunNotFoundError {
      message
    }
    ... on PythonError {
      message
    }
  }
}
"""


def graphql_request(host: str, port: int, query: str, variables: dict) -> dict:
    """Send a GraphQL request to the Dagster webserver."""
    url = f"http://{host}:{port}/graphql"
    payload = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def launch_single_run(
    host: str,
    port: int,
    job_name: str,
    level: int,
    rep: int,
    env: str,
    repo_name: str,
    location_name: str,
) -> str | None:
    """Launch one Dagster run and return its run_id, or None on failure."""
    variables = {
        "executionParams": {
            "selector": {
                "repositoryLocationName": location_name,
                "repositoryName": repo_name,
                "jobName": job_name,
            },
            "runConfigData": {},
            "mode": "default",
            "executionMetadata": {
                "tags": [
                    {"key": "concurrency_level", "value": str(level)},
                    {"key": "repetition", "value": str(rep)},
                    {"key": "environment", "value": env},
                ],
            },
        },
    }
    try:
        result = graphql_request(host, port, LAUNCH_RUN_MUTATION, variables)
        data = result.get("data", {}).get("launchRun", {})
        if "run" in data:
            return data["run"]["runId"]
        error_msg = data.get("message", "unknown error")
        print(f"  Launch failed: {error_msg}", file=sys.stderr)
        return None
    except urllib.error.URLError as e:
        print(f"  Connection error: {e}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  Launch error: {e}", file=sys.stderr)
        return None


def get_run_status(host: str, port: int, run_id: str) -> str:
    """Get the current status of a Dagster run."""
    try:
        result = graphql_request(host, port, RUN_STATUS_QUERY, {"runId": run_id})
        data = result.get("data", {}).get("runOrError", {})
        return data.get("status", "UNKNOWN")
    except Exception:
        return "UNKNOWN"


TERMINAL_STATUSES = {"SUCCESS", "FAILURE", "CANCELED"}


def trigger_runs(
    n_concurrent: int,
    host: str,
    port: int,
    job_name: str,
    level: int,
    rep: int,
    env: str,
    wait: bool = True,
    poll_interval: int = 5,
) -> list[str]:
    """Trigger N runs simultaneously and optionally wait for completion."""
    run_ids = []

    # Auto-discover repository and location names
    repo_name, location_name = get_repository_location(host, port, job_name)
    print(f"Launching {n_concurrent} concurrent runs of '{job_name}' "
          f"(level={level}, rep={rep}, env={env}) via {host}:{port}...")
    print(f"  Repository: {repo_name} @ {location_name}")

    for i in range(n_concurrent):
        run_id = launch_single_run(host, port, job_name, level, rep, env,
                                   repo_name, location_name)
        if run_id:
            print(f"  Run {i + 1}/{n_concurrent}: launched ({run_id[:8]}...)")
            run_ids.append(run_id)
        else:
            print(f"  Run {i + 1}/{n_concurrent}: FAILED to launch")
        # Small stagger to avoid overwhelming the scheduler
        time.sleep(0.05)

    print(f"\nAll {n_concurrent} runs triggered. {len(run_ids)}/{n_concurrent} succeeded.")

    if not wait or not run_ids:
        return run_ids

    # Poll until all runs reach a terminal state
    print(f"\nWaiting for {len(run_ids)} runs to complete...")
    pending = set(run_ids)
    statuses: dict[str, str] = {}

    while pending:
        time.sleep(poll_interval)
        still_pending = set()
        for run_id in pending:
            status = get_run_status(host, port, run_id)
            statuses[run_id] = status
            if status not in TERMINAL_STATUSES:
                still_pending.add(run_id)
        pending = still_pending
        done = len(run_ids) - len(pending)
        print(f"  Progress: {done}/{len(run_ids)} complete, {len(pending)} running...")

    # Summary
    success = sum(1 for s in statuses.values() if s == "SUCCESS")
    failed = sum(1 for s in statuses.values() if s == "FAILURE")
    canceled = sum(1 for s in statuses.values() if s == "CANCELED")
    print(f"\nResults: {success} success, {failed} failed, {canceled} canceled")

    return run_ids


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Launch N concurrent Dagster runs")
    parser.add_argument("n", type=int, help="Number of concurrent runs to launch")
    parser.add_argument("--job", default="thesis_workload", help="Dagster job name")
    parser.add_argument("--host", default="localhost", help="Dagster webserver host")
    parser.add_argument("--port", type=int, default=3001, help="Dagster webserver port")
    parser.add_argument("--level", type=int, default=0, help="Concurrency level number")
    parser.add_argument("--rep", type=int, default=1, help="Repetition number")
    parser.add_argument("--env", default="vm", help="Environment (vm or k8s)")
    parser.add_argument("--no-wait", action="store_true",
                        help="Do not wait for runs to complete")
    args = parser.parse_args()

    trigger_runs(
        n_concurrent=args.n,
        host=args.host,
        port=args.port,
        job_name=args.job,
        level=args.level,
        rep=args.rep,
        env=args.env,
        wait=not args.no_wait,
    )
