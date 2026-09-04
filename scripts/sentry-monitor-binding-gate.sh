#!/usr/bin/env bash
# AC11 — assert every `sentry_alert` in a plan binds the EXPECTED issue-stream
# detector.
#
# WHY THIS EXISTS. All 27 adopted rules resolve `monitor_ids` through
# `data.sentry_project_issue_stream_monitor.web_platform` (`first = true`).
# That indirection is deliberate — a hardcoded id cannot notice a rebind — but
# it makes the binding a CORRELATED failure: if the data source ever resolves
# to a different detector (a second issue-stream monitor appears on the
# project, or the provider's ordering shifts), ONE apply repoints all 27 rules
# at once, at a detector that watches nothing.
#
# Nothing else catches that. A scalar change to `monitor_ids` is not a delete,
# not a create, and not a nested-block shrink, so `destroy-guard-filter-sentry.jq`
# reports `destroy_count = 0` and the `[ack-destroy]` gate passes GREEN. The
# operator-visible outcome is total paging silence across all 27 — including
# `byok-art-33-breach`, whose silence stops the GDPR Art. 33 72-hour clock from
# ever starting — with a green apply and no annotation.
#
# Usage: sentry-monitor-binding-gate.sh <plan.json> [expected-detector-id]
# Exit 0 = every sentry_alert binds exactly the expected detector.
# Exit 1 = a binding differs, or the plan could not be read as expected.
set -uo pipefail

PLAN="${1:?usage: sentry-monitor-binding-gate.sh <plan.json> [expected-id]}"
EXPECTED="${2:-1213799}"

if [[ ! -r "$PLAN" ]]; then
  echo "::error::sentry monitor-binding gate: plan JSON not readable at '$PLAN'." >&2
  exit 1
fi

# Read the RESOLVED binding for every sentry_alert row. `.change.after` is the
# post-apply object; on an import row it is the adopted state. Fail closed on a
# null/absent monitor_ids rather than treating it as "nothing to check" — an
# unreadable binding is an UNCHECKED binding, not a passing one.
bindings=$(jq -r '
  [ .resource_changes[]?
    | select(.type == "sentry_alert")
    | { addr: .address,
        ids: (.change.after.monitor_ids // null) } ]
  | .[]
  | "\(.addr)\t\(if .ids == null then "<unreadable>" else (.ids | sort | join(",")) end)"
' "$PLAN") || {
  echo "::error::sentry monitor-binding gate: could not parse '$PLAN'." >&2
  exit 1
}

if [[ -z "$bindings" ]]; then
  echo "sentry monitor-binding gate: no sentry_alert rows in this plan — nothing to check."
  exit 0
fi

checked=0
bad=0
while IFS=$'\t' read -r addr ids; do
  [[ -z "$addr" ]] && continue
  checked=$((checked + 1))
  if [[ "$ids" != "$EXPECTED" ]]; then
    bad=$((bad + 1))
    echo "::error::  $addr binds '$ids', expected '$EXPECTED'" >&2
  fi
done <<< "$bindings"

# Anti-vacuity: a gate that examined nothing must not report success. This is
# a POSITIVE floor on work actually done, not a bound on failures found.
if [[ "$checked" -eq 0 ]]; then
  echo "::error::sentry monitor-binding gate: parsed 0 sentry_alert rows from a non-empty binding set — refusing to report PASS." >&2
  exit 1
fi

if [[ "$bad" -gt 0 ]]; then
  echo "::error::sentry monitor-binding gate: $bad of $checked sentry_alert resource(s) bind a detector other than '$EXPECTED'." >&2
  echo "::error::A correlated rebind darkens every affected paging rule while destroy_count stays 0 and this apply otherwise passes green. Refusing." >&2
  exit 1
fi

echo "sentry monitor-binding gate: PASS ($checked sentry_alert resource(s) all bind detector $EXPECTED)"
exit 0
