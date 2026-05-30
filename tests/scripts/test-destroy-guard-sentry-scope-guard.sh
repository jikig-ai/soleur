#!/usr/bin/env bash
# Forward-looking guard: asserts apply-sentry-infra.yml's -target= allow-list
# contains ONLY resource types whose nested-block exposure the
# destroy-guard-filter-sentry.jq has been verified to cover. Currently:
# `sentry_cron_monitor.*` and `sentry_uptime_monitor.*` — BOTH expose ZERO
# array-of-blocks (every attribute is scalar; `sentry_uptime_monitor`'s
# `assertion_json` is a function-built string, not an HCL block), so the
# filter's literal `nested_deletes: 0` remains correct for both and no
# path-specific clause is required (uptime added in #4585; see the jq
# filter's CURRENT SCOPE comment for the scalar-attr enumeration).
#
# sentry_issue_alert was added to scope in #4364 (the 2 apply-created BYOK
# rules); it DOES carry array-of-blocks (conditions_v2/filters_v2/actions_v2),
# so destroy-guard-filter-sentry.jq was extended with a matching nested-clause
# in the same PR. Any FURTHER new sentry resource type that carries an
# array-of-blocks must likewise extend the jq filter BEFORE being auto-applied.
#
# COMPENSATING CONTROL FOR BETA-PROVIDER DRIFT: this guard keys on resource
# TYPE, not on live nested-block shape. `sentry_uptime_monitor` is a beta
# resource (v0.15.0-beta2); a future provider bump could graduate it and add
# a real array-of-blocks attribute (e.g. check_locations{}), which this
# type-allow-list would NOT catch on its own. The compensating control is the
# mandatory schema re-validation on every `terraform init -upgrade`, recorded
# in the uptime-monitors.tf BETA STATUS comment — re-confirm `block_types: []`
# there and extend the jq filter if that ever changes.
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

unexpected=$(echo "$types" | grep -vxE 'sentry_cron_monitor|sentry_uptime_monitor|sentry_issue_alert' || true)
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

echo "[ok] apply-sentry-infra.yml targets only sentry_cron_monitor + sentry_uptime_monitor + sentry_issue_alert (current filter scope)"
