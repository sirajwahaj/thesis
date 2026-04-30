#!/usr/bin/env bash
# =============================================================================
# Push an annotation (event marker) to Grafana.
# Used by run_experiment.sh to mark experiment start/end on dashboards.
#
# Usage:
#   bash scripts/bash/push-grafana-annotation.sh "Exp1 L3 start" "exp1,vm,L3"
#   bash scripts/bash/push-grafana-annotation.sh "Exp1 L3 end"   "exp1,vm,L3" --end
#
# Environment variables:
#   GRAFANA_URL              Grafana base URL (default: http://$VM_IP:3000)
#   GRAFANA_ADMIN_PASSWORD   Grafana admin password (default: thesis2026)
#   GRAFANA_API_KEY          Grafana API key token (overrides user/pass if set)
#
# Arguments:
#   $1  Annotation text (description of the event)
#   $2  Comma-separated tags (e.g. "exp1,vm,L3")
#   $3  Optional --end flag (uses a red color instead of green)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VM_IP_FILE="$REPO_ROOT/vm-ip.txt"

TEXT="${1:-Experiment event}"
TAGS="${2:-experiment}"
IS_END="${3:-}"

# ── Resolve Grafana URL ──────────────────────────────────────────────────────
if [[ -z "${GRAFANA_URL:-}" ]]; then
    if [[ -f "$VM_IP_FILE" ]]; then
        VM_IP="$(cat "$VM_IP_FILE" | tr -d '[:space:]')"
        GRAFANA_URL="http://$VM_IP:3000"
    else
        GRAFANA_URL="http://localhost:3000"
    fi
fi

# ── Build auth header ────────────────────────────────────────────────────────
if [[ -n "${GRAFANA_API_KEY:-}" ]]; then
    AUTH_HEADER="Authorization: Bearer $GRAFANA_API_KEY"
else
    PASS="${GRAFANA_ADMIN_PASSWORD:-thesis2026}"
    AUTH_HEADER="Authorization: Basic $(echo -n "admin:$PASS" | base64)"
fi

# ── Build tags JSON array ────────────────────────────────────────────────────
TAGS_JSON=$(python3 -c "import json; print(json.dumps('$TAGS'.split(',')))")

# ── Color: green for start, red for end ─────────────────────────────────────
if [[ "$IS_END" == "--end" ]]; then
    COLOR="red"
else
    COLOR="green"
fi

# ── Push annotation via Grafana HTTP API ─────────────────────────────────────
NOW_MS=$(python3 -c "import time; print(int(time.time() * 1000))")

PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'time': $NOW_MS,
    'text': '$TEXT',
    'tags': $TAGS_JSON
}))
")

RESPONSE=$(curl -sf -w "\n%{http_code}" \
    -H "Content-Type: application/json" \
    -H "$AUTH_HEADER" \
    -X POST "$GRAFANA_URL/api/annotations" \
    -d "$PAYLOAD" 2>/dev/null) || {
        echo "[WARN] Could not reach Grafana at $GRAFANA_URL — annotation skipped"
        exit 0
    }

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    ID=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id','?'))" 2>/dev/null || echo "?")
    echo "[OK] Grafana annotation created (id=$ID): $TEXT [tags: $TAGS]"
else
    echo "[WARN] Grafana annotation failed (HTTP $HTTP_CODE) — dashboards will not have event markers"
fi
