#!/usr/bin/env bash
# rundevoo-destroy-counts.sh — the ONE place the rundevoo destroy arithmetic
# lives (#12971). Mirrors scripts/sentry-destroy-counts.sh (#6589), which
# exists because the same arithmetic inlined in two jobs drifted once already.
#
# Usage: rundevoo-destroy-counts.sh <terraform-show-json-file>
#   stdout (on success): four `key=value` lines, eval-able by the caller:
#       resource_deletes=<int>
#       resource_forgets=<int>
#       nested_deletes=<int>
#       destroy_count=<int>     # resource_deletes + nested_deletes + resource_forgets
#   exit 0: plan parsed, plan_ok true, counters validated
#   exit 1: jq failed, plan_ok false (input was not a plan document), or a
#           counter is not a non-negative integer
#
# `resource_forgets` joins the SUM, not just the report — a counter that is
# emitted but not summed is a report, not a gate. It stays a SEPARATE key from
# `resource_deletes` so a reader can still say "N forgets, zero actual
# deletes" (a forget leaves the live object untouched).
#
# No `resource_creates` key: this root deliberately does not count creates
# (see the filter's header — additive drift is covered by the set-equality
# REST probe, and every resource here is TF-owned). A caller that evals this
# output and reads a missing key dies under `set -u` — the absence is loud,
# which is the point: nobody should be building a create gate out of a
# counter that was never emitted.
#
# Behaviour is unit-tested by tests/scripts/test-destroy-guard-counter-rundevoo.sh.
set -euo pipefail

plan_json="${1:?usage: rundevoo-destroy-counts.sh <terraform-show-json-file>}"
[[ -f "$plan_json" ]] || { echo "::error::rundevoo-destroy-counts: no such file: $plan_json" >&2; exit 1; }

filter_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/scripts/lib" && pwd)"
filter="$filter_dir/destroy-guard-filter-rundevoo.jq"
[[ -f "$filter" ]] || { echo "::error::rundevoo-destroy-counts: filter not found: $filter" >&2; exit 1; }

counts=$(jq -f "$filter" < "$plan_json") || {
  echo "::error::rundevoo-destroy-counts: jq filter failed over $plan_json" >&2
  exit 1
}

plan_ok=$(jq -r '.plan_ok' <<<"$counts")
if [[ "$plan_ok" != "true" ]]; then
  echo "::error::rundevoo-destroy-counts: input is not a plan document (no resource_changes key) — an unread input must never score 0 and green the gate." >&2
  exit 1
fi

resource_deletes=$(jq -r '.resource_deletes' <<<"$counts")
resource_forgets=$(jq -r '.resource_forgets' <<<"$counts")
nested_deletes=$(jq -r '.nested_deletes' <<<"$counts")

for v in "$resource_deletes" "$resource_forgets" "$nested_deletes"; do
  if [[ ! "$v" =~ ^[0-9]+$ ]]; then
    echo "::error::rundevoo-destroy-counts: counter not a non-negative integer (deletes=$resource_deletes forgets=$resource_forgets nested=$nested_deletes)" >&2
    exit 1
  fi
done

printf 'resource_deletes=%s\n' "$resource_deletes"
printf 'resource_forgets=%s\n' "$resource_forgets"
printf 'nested_deletes=%s\n' "$nested_deletes"
printf 'destroy_count=%s\n' "$((resource_deletes + nested_deletes + resource_forgets))"
