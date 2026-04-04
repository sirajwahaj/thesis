#!/bin/bash

set -euo pipefail

echo "Syncing GitHub labels..."

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
LABELS_JSON="$(dirname "$0")/../config/labels.json"

if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq."
  exit 1
fi

LABELS=$(jq -c '.[]' "$LABELS_JSON")

while IFS= read -r LABEL; do
  NAME=$(echo "$LABEL" | jq -r '.name')
  COLOR=$(echo "$LABEL" | jq -r '.color')
  DESC=$(echo "$LABEL" | jq -r '.description')

  # Check if label exists
  if gh label list --repo "$REPO" --json name -q ".[].name" | grep -Fxq "$NAME"; then
    echo "Updating label: $NAME"
    gh label edit "$NAME" --repo "$REPO" --color "$COLOR" --description "$DESC"
  else
    echo "Creating label: $NAME"
    gh label create "$NAME" --repo "$REPO" --color "$COLOR" --description "$DESC"
  fi
done <<< "$LABELS"

echo "Labels synced!"