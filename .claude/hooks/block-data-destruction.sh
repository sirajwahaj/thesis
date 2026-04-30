#!/usr/bin/env bash
# .claude/hooks/block-data-destruction.sh
#
# PreToolUse hook — blocks commands that would destroy experiment-critical data.
# Claude Code passes the tool input as JSON on stdin.
# Exit 2 = blocked (Claude Code will refuse to run the command).
# Exit 0 = permitted (Hook did not block).

set -euo pipefail

INPUT=$(cat)

# Extract the command string from JSON
# Expected JSON shape: {"tool_input": {"command": "..."}}
CMD=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('command', ''))
" 2>/dev/null || echo "")

if [[ -z "$CMD" ]]; then
  # Could not parse — allow through (don't block on parse errors)
  exit 0
fi

# ── Block: rm on experiment data ────────────────────────────────────────────
if echo "$CMD" | grep -qE "rm[[:space:]].*(-rf|-fr|-r)[[:space:]].*data/(raw|processed)"; then
  echo "" >&2
  echo "BLOCKED by .claude/hooks/block-data-destruction.sh" >&2
  echo "Cannot delete experiment data in data/raw/ or data/processed/." >&2
  echo "These directories contain irreplaceable experiment outputs." >&2
  echo "If you truly need to delete data, do it manually in a terminal." >&2
  echo "" >&2
  exit 2
fi

# ── Block: rm on workload source ────────────────────────────────────────────
if echo "$CMD" | grep -qE "rm[[:space:]].*(-rf|-fr|-r)[[:space:]].*src/workload"; then
  echo "" >&2
  echo "BLOCKED by .claude/hooks/block-data-destruction.sh" >&2
  echo "Cannot delete src/workload/ — this is the experiment workload definition." >&2
  echo "Deleting it would invalidate all experiment comparability." >&2
  echo "" >&2
  exit 2
fi

# ── Block: rm on results ─────────────────────────────────────────────────────
if echo "$CMD" | grep -qE "rm[[:space:]].*(-rf|-fr|-r)[[:space:]].*results/"; then
  echo "" >&2
  echo "BLOCKED by .claude/hooks/block-data-destruction.sh" >&2
  echo "Cannot delete results/ — run 'make analyze' to regenerate plots." >&2
  echo "If you need to clear stale plots, delete them manually in a terminal." >&2
  echo "" >&2
  exit 2
fi

# ── Block: git reset --hard ──────────────────────────────────────────────────
if echo "$CMD" | grep -qE "git reset --hard"; then
  echo "" >&2
  echo "BLOCKED by .claude/hooks/block-data-destruction.sh" >&2
  echo "'git reset --hard' can discard uncommitted experiment data paths." >&2
  echo "Run this manually in a terminal if you truly intend it." >&2
  echo "" >&2
  exit 2
fi

# ── Block: kubectl delete namespace ──────────────────────────────────────────
if echo "$CMD" | grep -qE "kubectl delete namespace"; then
  echo "" >&2
  echo "BLOCKED by .claude/hooks/block-data-destruction.sh" >&2
  echo "Cannot delete K8s namespaces via agent — use 'make k8s-destroy' after" >&2
  echo "confirming with the user that experiments are complete." >&2
  echo "" >&2
  exit 2
fi

# ── All checks passed ────────────────────────────────────────────────────────
exit 0
