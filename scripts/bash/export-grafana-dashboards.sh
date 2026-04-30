#!/usr/bin/env bash
# =============================================================================
# Export live Grafana dashboards back to monitoring/grafana/dashboards/
#
# Use this after editing dashboards in the Grafana UI to persist your changes
# into version control. Exports all dashboards from the "Thesis" folder.
#
# Usage:
#   bash scripts/bash/export-grafana-dashboards.sh
#   make monitoring-export-dashboards
#
# Prerequisites: VM monitoring stack running (make monitoring-up)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DASHBOARDS_DIR="$REPO_ROOT/monitoring/grafana/dashboards"

VM_IP_FILE="$REPO_ROOT/vm-ip.txt"
SSH_KEY="$HOME/.ssh/thesis_vm"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"

if [[ ! -f "$VM_IP_FILE" ]]; then
    echo "[FAIL] vm-ip.txt not found. Is the VM running?"
    exit 1
fi
VM_IP="$(cat "$VM_IP_FILE" | tr -d '[:space:]')"

GRAFANA_URL="http://$VM_IP:3000"
GRAFANA_PASS="${GRAFANA_ADMIN_PASSWORD:-thesis2026}"
AUTH="admin:$GRAFANA_PASS"

echo "==> Exporting Grafana dashboards from $GRAFANA_URL"
echo "    Output: $DASHBOARDS_DIR"
echo ""

# List all dashboards (all folders)
UIDS=$(curl -sf -u "$AUTH" "$GRAFANA_URL/api/search?type=dash-db&limit=100" \
    | python3 -c "import json,sys; [print(d['uid']) for d in json.load(sys.stdin)]")

if [[ -z "$UIDS" ]]; then
    echo "[WARN] No dashboards found in Grafana — is the monitoring stack running?"
    exit 0
fi

for uid in $UIDS; do
    # Get dashboard title for the filename
    TITLE=$(curl -sf -u "$AUTH" "$GRAFANA_URL/api/dashboards/uid/$uid" \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dashboard']['title'].lower().replace(' ', '-').replace('/', '-'))")

    OUTPUT="$DASHBOARDS_DIR/${uid}.json"

    echo "-> Exporting: $TITLE (uid=$uid)"
    curl -sf -u "$AUTH" "$GRAFANA_URL/api/dashboards/uid/$uid" \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
dash = data['dashboard']
# Strip runtime-only fields that should not be stored
dash.pop('version', None)
dash['id'] = None
print(json.dumps(dash, indent=2))
" > "$OUTPUT"

    echo "   Saved: $(basename "$OUTPUT")"
done

echo ""
echo "[OK] Exported ${#UIDS[@]} dashboard(s) to $DASHBOARDS_DIR"
echo "     Review with: git diff monitoring/grafana/dashboards/"
echo "     Commit if satisfied: git add monitoring/grafana/dashboards/ && git commit"
