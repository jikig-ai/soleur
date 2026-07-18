#!/usr/bin/env bash
# sentry-destroy-counts.sh — the ONE place the sentry destroy arithmetic lives (#6589).
#
# Usage: sentry-destroy-counts.sh <terraform-show-json-file>
#   stdout (on success): four `key=value` lines, eval-able by the caller:
#       resource_deletes=<int>
#       resource_creates=<int>
#       nested_deletes=<int>
#       destroy_count=<int>     # resource_deletes + nested_deletes
#   exit 0: counts parsed and validated
#   exit 1: jq failed, or a counter is not a non-negative integer
#
# ── WHY THIS IS A SCRIPT AND NOT INLINE BASH ───────────────────────────────
# It was inline, in two places, and they drifted — on this PR, in the shape the
# PR itself is about.
#
# `plan_pr` (the PR-time gate) was written by copy-adapting `apply`'s gate block.
# The adaptation carried `resource_deletes`/`nested_deletes`/`resource_creates`
# and DROPPED the `destroy_count=$((...))` line, then went on to read
# `$destroy_count`. Under `set -u` that is an unbound variable: the job died at
# the first read, AFTER a correct plan (`0 to add, 0 to change, 2 to destroy`),
# and the aggregator reported the gate FAILED closed. So the gate was
# permanently red by accident — the exact design this PR rejected on purpose —
# and its whole green path (ack detection, the squash-setting assertion, the
# destroyed-address listing) had never executed even once.
#
# The lesson is not "add the missing line". `test-destroy-guard-regex-parity.sh`
# pins the `[ack-destroy]` regex across 7 sites precisely because drift between a
# predictor and the thing it predicts is invisible to review. The ARITHMETIC
# those same two blocks share had no such pin, and that is where the drift
# landed. A parity test for a second copy would work; ONE copy is better, because
# it makes the divergence unrepresentable rather than merely detectable.
#
# Behaviour is unit-tested by tests/scripts/test-sentry-destroy-counts.sh.
set -euo pipefail

plan_json="${1:?usage: sentry-destroy-counts.sh <terraform-show-json-file>}"
[[ -f "$plan_json" ]] || { echo "::error::sentry-destroy-counts: no such file: $plan_json" >&2; exit 1; }

filter_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/scripts/lib" && pwd)"
filter="$filter_dir/destroy-guard-filter-sentry.jq"
[[ -f "$filter" ]] || { echo "::error::sentry-destroy-counts: filter not found: $filter" >&2; exit 1; }

counts=$(jq -f "$filter" < "$plan_json") || {
  echo "::error::sentry-destroy-counts: jq filter failed over $plan_json" >&2
  exit 1
}

resource_deletes=$(jq -r '.resource_deletes' <<<"$counts")
resource_creates=$(jq -r '.resource_creates' <<<"$counts")
nested_deletes=$(jq -r '.nested_deletes' <<<"$counts")

# Fail-closed numeric validation. An empty value from a jq failure would evaluate
# false in a `-gt 0` test and let a destroying plan through green.
for pair in "resource_deletes:$resource_deletes" "resource_creates:$resource_creates" "nested_deletes:$nested_deletes"; do
  name="${pair%%:*}"; val="${pair#*:}"
  if [[ ! "$val" =~ ^[0-9]+$ ]]; then
    echo "::error::sentry-destroy-counts: ${name}='${val}' is not a non-negative integer — destroy-guard counter parse failed." >&2
    exit 1
  fi
done

printf 'resource_deletes=%s\n' "$resource_deletes"
printf 'resource_creates=%s\n' "$resource_creates"
printf 'nested_deletes=%s\n' "$nested_deletes"
printf 'destroy_count=%s\n' "$((resource_deletes + nested_deletes))"
