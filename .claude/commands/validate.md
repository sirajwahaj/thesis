Run the thesis pre-flight validation and report the results.

Execute the following command:
```bash
bash scripts/validate-experiment-setup.sh
```

Then report:
1. **VM status**: Is the VM reachable via SSH? Is the gRPC server (port 4000) responding? Is `thesis-workload` systemd service active?
2. **K8s status**: Is the `thesis` Kind cluster running? Are Dagster pods (webserver, daemon, postgresql) all in Running state? Is Metrics Server deployed?
3. **Local compose status**: Is the local PostgreSQL container up? Is the local Dagster webserver reachable at http://localhost:3001?

For any failed check, provide:
- The exact error message
- The command to fix it
- Whether it is safe to proceed with experiments despite this failure

If ALL checks pass, state clearly: "All systems ready. Safe to run experiments."
If any check fails, state: "NOT ready for experiments. Fix the above issues first."
