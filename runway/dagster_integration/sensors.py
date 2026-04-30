"""
dagster_integration/sensors.py

Drop-in sensors to add to your Dagster repository.

Usage in your repository.py:
    from runway.dagster_integration.sensors import runway_sensors
    
    defs = Definitions(
        jobs=[...],
        sensors=runway_sensors,
    )
"""
from runway.sensor import runway_failure_sensor, runway_success_sensor

runway_sensors = [
    runway_success_sensor,
    runway_failure_sensor,
]

__all__ = ["runway_sensors"]
