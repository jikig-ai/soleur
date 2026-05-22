#!/usr/bin/env bash
# Diff the committed GitHub App manifest against a `GET /app` response and
# classify the divergence into one of three modes. Shared between the
# drift-guard handler (apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts,
# via child_process.spawn) and the contract test
# (apps/web-platform/test/github-app-manifest-drift-guard.test.ts) per the
# plan's Phase 3.3 "share the diff bash" requirement — duplicating the diff
# logic inline in TS means the test asserts behavior not in the handler.
#
# Inputs (env vars):
#   $MANIFEST_FILE  path to apps/web-platform/infra/github-app-manifest.json
#   $RESPONSE_FILE  path to a file containing the `GET /app` JSON response
#
# Output:
#   On no drift  -> exit 0, no stdout.
#   On drift     -> exit 1, single line on stdout: `<mode>:<details>`
#     where <mode> is one of:
#       permission_drift              -> manifest declares X, live App lacks X
#                                        (security regression direction)
#                                        -> workflow translates to ci/auth-broken
#       permission_unexpected_grant   -> live App has Y, manifest doesn't
#                                        (inventory drift, possibly a
#                                         GitHub-side rename)
#                                        -> workflow translates to ci/guard-broken
#       response_shape_unparseable    -> response missing/wrong-shape
#                                        permissions/events fields
#                                        -> workflow translates to ci/guard-broken
#
# Normalization (Sharp Edges in plan):
#   - default_permissions ↔ permissions       (key-name mismatch is real)
#   - default_events      ↔ events            (array; sorted before compare)
#   - missing arrays default to []            (sort-on-empty produces equal [])
#
# Ref #4115.

set -euo pipefail

: "${MANIFEST_FILE:?MANIFEST_FILE env var must be set}"
: "${RESPONSE_FILE:?RESPONSE_FILE env var must be set}"

if [[ ! -r "$MANIFEST_FILE" ]]; then
  echo "diff-github-app-manifest: MANIFEST_FILE $MANIFEST_FILE missing/unreadable" >&2
  exit 2
fi
if [[ ! -r "$RESPONSE_FILE" ]]; then
  echo "diff-github-app-manifest: RESPONSE_FILE $RESPONSE_FILE missing/unreadable" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "diff-github-app-manifest: jq is required but not on PATH" >&2
  exit 2
fi

# Response-shape sanity check FIRST. A malformed response (e.g.,
# `{"message":"Not Found"}` during a GitHub API incident, or `permissions:
# null`) must classify as response_shape_unparseable, NOT permission_drift.
# permission_drift is for SEMANTIC divergence; response_shape_unparseable is
# for MALFORMED responses.
perms_type=$(jq -r '.permissions | type' "$RESPONSE_FILE" 2>/dev/null || echo "missing")
events_type=$(jq -r '.events | type' "$RESPONSE_FILE" 2>/dev/null || echo "missing")
if [[ "$perms_type" != "object" || "$events_type" != "array" ]]; then
  detail="response.permissions=${perms_type} response.events=${events_type}"
  printf 'response_shape_unparseable:%s\n' "$detail"
  exit 1
fi

# Normalize: --sort-keys on the permissions OBJECT (sorts keys lexically).
# For events, --sort-keys does NOT sort array elements; use `| sort` instead.
# The `// {}` and `// []` defaults handle a missing key on either side.
manifest_perms=$(jq --sort-keys -c '.default_permissions // {}' "$MANIFEST_FILE")
response_perms=$(jq --sort-keys -c '.permissions // {}' "$RESPONSE_FILE")
manifest_events=$(jq -c '(.default_events // []) | sort' "$MANIFEST_FILE")
response_events=$(jq -c '(.events // []) | sort' "$RESPONSE_FILE")

# Diff direction classification (plan §Phase 3.2):
#
#   Manifest > Live   -> permission_drift            (we intended X, App lacks X)
#   Live > Manifest   -> permission_unexpected_grant (App has Y, we didn't commit Y)
#
# For permissions, "manifest > live" means a key/value pair exists in
# manifest that isn't in live (different value OR missing key). For events,
# "manifest > live" means an event exists in manifest not in live.
#
# We compute both directions and pick the first mismatch — operator triage
# splits cleanly because the issue body includes the actual diff.

missing_in_live=$(jq -n \
  --argjson manifest "$manifest_perms" \
  --argjson live "$response_perms" \
  '($manifest | to_entries) - ($live | to_entries) | from_entries')
extra_in_live=$(jq -n \
  --argjson manifest "$manifest_perms" \
  --argjson live "$response_perms" \
  '($live | to_entries) - ($manifest | to_entries) | from_entries')

missing_events_in_live=$(jq -n \
  --argjson manifest "$manifest_events" \
  --argjson live "$response_events" \
  '$manifest - $live')
extra_events_in_live=$(jq -n \
  --argjson manifest "$manifest_events" \
  --argjson live "$response_events" \
  '$live - $manifest')

# permission_drift fires when:
#   - a manifest key is absent from live, OR
#   - a manifest event is absent from live's event list, OR
#   - a manifest key has a STRICTER scope than live's grant for that key
#     (e.g., manifest says "write" but live says "read").
# Stricter-scope check: any key present in both with differing values is
# already captured by `missing_in_live` (the {key:value} entry differs), but
# it would ALSO show up in `extra_in_live` because both directions of the
# entry-diff capture it. To classify directionally, treat any value mismatch
# on a shared key as permission_drift (security-regression direction).
shared_keys_with_diff=$(jq -n \
  --argjson manifest "$manifest_perms" \
  --argjson live "$response_perms" \
  '[($manifest | keys_unsorted[]) as $k
    | select(($live | has($k)) and ($manifest[$k] != $live[$k]))
    | {key: $k, manifest: $manifest[$k], live: $live[$k]}]')
shared_diff_count=$(printf '%s' "$shared_keys_with_diff" | jq 'length')

missing_count=$(printf '%s' "$missing_in_live" | jq 'keys | length')
extra_count=$(printf '%s' "$extra_in_live" | jq 'keys | length')
missing_events_count=$(printf '%s' "$missing_events_in_live" | jq 'length')
extra_events_count=$(printf '%s' "$extra_events_in_live" | jq 'length')

# permission_drift takes precedence over permission_unexpected_grant —
# a security regression direction must surface first. A diff that contains
# BOTH directions (e.g., GitHub renamed a permission: old key disappeared,
# new key appeared) is most safely treated as drift on the "manifest declares
# X, live lacks X" axis until operator reconciles.
if (( shared_diff_count > 0 )) || (( missing_count > 0 )) || (( missing_events_count > 0 )); then
  detail=$(jq -nc \
    --argjson scope_diff "$shared_keys_with_diff" \
    --argjson missing_perms "$missing_in_live" \
    --argjson missing_events "$missing_events_in_live" \
    '{scope_diff: $scope_diff, missing_perms: $missing_perms, missing_events: $missing_events}')
  printf 'permission_drift:%s\n' "$detail"
  exit 1
fi

if (( extra_count > 0 )) || (( extra_events_count > 0 )); then
  detail=$(jq -nc \
    --argjson extra_perms "$extra_in_live" \
    --argjson extra_events "$extra_events_in_live" \
    '{extra_perms: $extra_perms, extra_events: $extra_events}')
  printf 'permission_unexpected_grant:%s\n' "$detail"
  exit 1
fi

exit 0
