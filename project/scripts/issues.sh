#!/bin/bash

set -euo pipefail

echo "Syncing issues from markdown..."

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# -------- HELPERS --------

# Returns the issue number if a matching title exists, empty string otherwise.
find_issue_number() {
  local TITLE="$1"
  gh issue list \
    --repo "$REPO" \
    --search "\"$TITLE\" in:title" \
    --state all \
    --json number,title \
    -q ".[] | select(.title == \"$TITLE\") | .number" \
  | head -1
}

parse_field() {
  local FIELD="$1"
  local FILE="$2"
  grep -i "^$FIELD:" "$FILE" | sed "s/^$FIELD:[ ]*//I" | tr -d '\r'
}

build_body() {
  local FILE="$1"
  local STORY_POINTS="$2"
  local DEPENDENCIES="$3"

  # Strip title line and all metadata lines; keep everything else
  local BODY
  BODY=$(sed '1d' "$FILE" \
    | sed '/^Labels:/Id' \
    | sed '/^Story Points:/Id' \
    | sed '/^Dependencies:/Id')

  printf '%s\n\n---\n\n### Story Points\n%s\n\n### Dependencies\n%s\n' \
    "$BODY" "${STORY_POINTS:-N/A}" "${DEPENDENCIES:-None}"
}

sync_issue() {
  local FILE="$1"

  local TITLE
  TITLE=$(head -n 1 "$FILE" | sed 's/^# //')

  local LABELS STORY_POINTS DEPENDENCIES
  LABELS=$(parse_field "Labels" "$FILE" || true)
  STORY_POINTS=$(parse_field "Story Points" "$FILE" || true)
  DEPENDENCIES=$(parse_field "Dependencies" "$FILE" || true)

  local BODY
  BODY=$(build_body "$FILE" "$STORY_POINTS" "$DEPENDENCIES")

  # Build label args — gh issue edit uses --add-label, create uses --label
  local CREATE_LABEL_ARGS=()
  local EDIT_LABEL_ARGS=()
  IFS=',' read -ra LABEL_ARRAY <<< "${LABELS:-}"
  for l in "${LABEL_ARRAY[@]}"; do
    l=$(echo "$l" | xargs)
    if [[ -n "$l" ]]; then
      CREATE_LABEL_ARGS+=(--label "$l")
      EDIT_LABEL_ARGS+=(--add-label "$l")
    fi
  done

  local ISSUE_NUMBER
  ISSUE_NUMBER=$(find_issue_number "$TITLE")

  if [[ -n "$ISSUE_NUMBER" ]]; then
    echo " Updating #${ISSUE_NUMBER}: $TITLE"
    gh issue edit "$ISSUE_NUMBER" \
      --repo "$REPO" \
      --title "$TITLE" \
      --body "$BODY" \
      "${EDIT_LABEL_ARGS[@]}"
  else
    echo " Creating: $TITLE"
    gh issue create \
      --repo "$REPO" \
      --title "$TITLE" \
      --body "$BODY" \
      "${CREATE_LABEL_ARGS[@]}"
  fi
}

# -------- MAIN --------

for file in project/issues/*.md; do
  sync_issue "$file"
done

echo " Done!"
