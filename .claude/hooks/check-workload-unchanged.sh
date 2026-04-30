#!/usr/bin/env bash
# .claude/hooks/check-workload-unchanged.sh
#
# PostToolUse hook — warns when workload_job.py is written.
# Modifying the workload changes the CPU load profile, which invalidates
# comparability between VM and K8s experiment results.
#
# Claude Code passes the tool input as JSON on stdin.
# Exit 0 always (warning only, not a hard block).

set -euo pipefail

INPUT=$(cat)

# Extract the file path written from JSON
# Expected JSON shape: {"tool_input": {"path": "..."}}
FILE=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('path', ''))
" 2>/dev/null || echo "")

if [[ -z "$FILE" ]]; then
  exit 0
fi

# ── Warn on workload_job.py ──────────────────────────────────────────────────
if echo "$FILE" | grep -q "workload_job.py"; then
  echo "" >&2
  echo "WARNING: workload_job.py was modified." >&2
  echo "" >&2
  echo "This file defines the experiment workload:" >&2
  echo "  - CPU load: SHA-256 hashing loop" >&2
  echo "  - Duration: WORKLOAD_DURATION_SECONDS (default: 30s)" >&2
  echo "" >&2
  echo "Changing the workload INVALIDATES comparability between VM and K8s results." >&2
  echo "Experiments must be re-run from L1 for both environments if the workload changes." >&2
  echo "" >&2
  echo "Verify this change is intentional and approved by supervisor before committing." >&2
  echo "Run: git diff src/workload/workload_job.py  to review what changed." >&2
  echo "" >&2
fi

# ── Warn on run_experiment.sh ────────────────────────────────────────────────
if echo "$FILE" | grep -q "run_experiment.sh"; then
  # Check specifically if levels or repetitions might have changed
  if grep -q "DEFAULT_LEVELS\|REPETITIONS\|COOLDOWN" "$FILE" 2>/dev/null; then
    echo "" >&2
    echo "WARNING: run_experiment.sh was modified." >&2
    echo "" >&2
    echo "Verify these parameters are still correct:" >&2
    grep -E "DEFAULT_LEVELS|REPETITIONS|COOLDOWN" "$FILE" 2>/dev/null | head -5 >&2
    echo "" >&2
    echo "Expected: DEFAULT_LEVELS=\"1 2 3 5 7 10\"  REPETITIONS=3  COOLDOWN>=60" >&2
    echo "" >&2
  fi
fi

# ── Always exit 0 (warning, not block) ──────────────────────────────────────
exit 0
