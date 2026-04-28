#!/usr/bin/env bash
# Detect destructive edits to .claude/settings.json (see #2905).
#
# Reads BASE_REF and HEAD_REF from env. Compares the file at each ref and
# fails if any of these violations are present:
#
#   1. A valid top-level key (hooks, enabledMcpjsonServers, env, permissions,
#      model, additionalDirectories) was deleted.
#   2. An unknown top-level key was introduced (e.g., `sandbox` — the
#      smoking-gun signal that an LLM rewrote the file from a hallucinated
#      schema).
#   3. Any entry was removed from `permissions.allow[*]`.
#
# Exits 0 if the file is unchanged, didn't exist on base (first-add case),
# or no violations were found. Exits 1 with a structured error message
# otherwise. Add the `confirm:claude-config-change` label on the PR to
# bypass; the workflow short-circuits before invoking this script.

set -uo pipefail

: "${BASE_REF:?BASE_REF env var required}"
: "${HEAD_REF:?HEAD_REF env var required}"

VALID_TOP_KEYS='["permissions","env","enabledMcpjsonServers","hooks","model","additionalDirectories"]'

base_settings=$(git show "$BASE_REF:.claude/settings.json" 2>/dev/null || echo '{}')
head_settings=$(git show "$HEAD_REF:.claude/settings.json" 2>/dev/null || echo '{}')

# Validate JSON shape early — bail clean if either side is non-JSON.
if ! jq -e . <<<"$base_settings" >/dev/null 2>&1; then
  echo "::warning::Base .claude/settings.json is not valid JSON; skipping integrity check"
  exit 0
fi
if ! jq -e . <<<"$head_settings" >/dev/null 2>&1; then
  echo "::error::Head .claude/settings.json is not valid JSON"
  exit 1
fi

# Quick exit if file unchanged
if [[ "$base_settings" == "$head_settings" ]]; then
  exit 0
fi

violations=0

# Check 1: Deletion of valid top-level keys
deleted_keys=$(jq -r -n \
  --argjson base "$base_settings" \
  --argjson head "$head_settings" \
  '($base | keys) - ($head | keys) | join(",")')
if [[ -n "$deleted_keys" ]]; then
  echo "::error::Deleted top-level settings keys: $deleted_keys"
  echo "Add label 'confirm:claude-config-change' to override (only with explicit reason). See #2905."
  violations=$((violations + 1))
fi

# Check 2: Introduction of unknown top-level keys
unknown_keys=$(jq -r -n \
  --argjson head "$head_settings" \
  --argjson valid "$VALID_TOP_KEYS" \
  '($head | keys) - $valid | join(",")')
if [[ -n "$unknown_keys" ]]; then
  echo "::error::Introduced unrecognized top-level keys: $unknown_keys"
  echo "Valid keys: permissions, env, enabledMcpjsonServers, hooks, model, additionalDirectories"
  echo "Add label 'confirm:claude-config-change' to override."
  violations=$((violations + 1))
fi

# Check 3: Deletion of permissions.allow[*] entries
deleted_allow=$(jq -r -n \
  --argjson base "$base_settings" \
  --argjson head "$head_settings" \
  '(($base.permissions.allow // []) - ($head.permissions.allow // [])) | join(", ")')
if [[ -n "$deleted_allow" ]]; then
  echo "::error::Deleted permissions.allow entries: $deleted_allow"
  echo "Add label 'confirm:claude-config-change' to override."
  violations=$((violations + 1))
fi

if [[ "$violations" -gt 0 ]]; then
  exit 1
fi
exit 0
