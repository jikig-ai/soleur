#!/usr/bin/env bash
# Forward-looking guard: asserts apply-sentry-infra.yml's -target= allow-list
# contains ONLY `sentry_cron_monitor.*` resources. If a future PR adds a
# different sentry resource type (e.g. sentry_issue_alert with conditions{}
# / actions{} array-of-blocks; sentry_uptime_monitor with check_locations{}),
# the destroy-guard-filter-sentry.jq must be extended with a corresponding
# nested-clause BEFORE that resource is auto-applied.
#
# Without this gate, a sentry-side expansion would silently bypass the
# nested-block destroy guard (filter ships with literal `nested_deletes: 0`
# as documented extension point). Closes #4419 review-finding user-impact F2.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/apply-sentry-infra.yml"

# Extract every `-target=<addr>` invocation, strip the address prefix to a
# bare resource type. Empty awk output = no targets, also a fail (the
# allow-list disappeared).
types=$(awk '
  /^[[:space:]]*-target=/ {
    sub(/^[[:space:]]*-target=/, "")
    sub(/\.[^ \\\\]+.*$/, "")
    gsub(/[[:space:]]+|\\\\$/, "")
    if (length) print
  }
' "$WORKFLOW" | sort -u)

if [[ -z "$types" ]]; then
  echo "[FAIL] no -target= entries found in $WORKFLOW" >&2
  exit 1
fi

unexpected=$(echo "$types" | grep -vxF 'sentry_cron_monitor' || true)
if [[ -n "$unexpected" ]]; then
  echo "[FAIL] apply-sentry-infra.yml targets unexpected resource type(s):" >&2
  printf '  %s\n' "$unexpected" >&2
  echo "" >&2
  echo "Before this PR can land, extend tests/scripts/lib/destroy-guard-filter-sentry.jq" >&2
  echo "with a path-specific nested-clause for the new type — see the" >&2
  echo "destroy-guard-filter-web-platform.jq pattern. Then add a corresponding" >&2
  echo "fixture + test case to tests/scripts/test-destroy-guard-counter-sentry.sh." >&2
  exit 1
fi

echo "[ok] apply-sentry-infra.yml targets only sentry_cron_monitor (current filter scope)"
