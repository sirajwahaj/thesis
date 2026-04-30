"""
Dagster thesis workload — CPU-bound job definitions for measuring performance.

This module is exposed via gRPC on port 4000 to Dagster webserver.
The workspace.yaml file loads definitions from this gRPC server.
"""

from .workload_job import thesis_workload

__all__ = ["thesis_workload"]
