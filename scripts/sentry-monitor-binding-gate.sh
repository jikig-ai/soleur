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
# ADDRESS-AWARE (#8630). One address is exempt from the single-detector rule:
# `sentry_alert.cron_monitor_failure` routes cron-monitor failures and binds the
# `sentry_cron_monitor` detectors instead. It must bind a NON-EMPTY set in which
# every element is the `.values.id` of a `sentry_cron_monitor` in the SAME plan's
# `planned_values.root_module.resources` (the projection refuses child_modules,
# so a monitor anywhere else fails closed here too), never the issue-stream
# detector and never `null` (a monitor created in this plan — the projection's
# unknown-detector floor refuses the same shape). Every other address still binds
# exactly `$EXPECTED`: the correlated-rebind protection is unchanged. Whether
# the count matches the declared monitors is the routing-parity test's job
# (apps/web-platform/test/server/inngest/sentry-cron-monitor-routing-parity.test.ts),
# not this gate's.
#
# Usage: sentry-monitor-binding-gate.sh <plan.json> [expected-detector-id]
# Exit 0 = every sentry_alert binds exactly the expected detector, except the
#          cron-bound address set, which binds only this plan's cron detectors.
# Exit 1 = a binding differs, or the plan could not be read as expected.
set -uo pipefail

PLAN="${1:?usage: sentry-monitor-binding-gate.sh <plan.json> [expected-id]}"
# Provenance of the literal: measured against live prod on 2026-09-04 and
# recorded in knowledge-base/project/specs/fix-7650-sentry-alert-migration/
# phase2-measurements-2026-09-04.md — it is the id
# `data.sentry_project_issue_stream_monitor.web_platform` resolves to, and the
# same value all 27 `.change.after.monitor_ids` carry in the verified plan.
# Both call sites pass no `$2`, so this default IS the invariant in force:
# "every sentry_alert in this root binds one specific detector". Correct today;
# the day a second issue-stream detector is legitimate, this line is the edit.
EXPECTED="${2:-1213799}"
# The cron-bound address set is a LITERAL for the same reason `$EXPECTED` is: a
# PR that adds a second address binding cron detectors must edit this line, and
# that diff is reviewed. Until it does, such an address binds something other
# than `$EXPECTED` and reds below, named as outside this set.
CRON_BOUND_ADDRESSES='["sentry_alert.cron_monitor_failure"]'

if [[ ! -r "$PLAN" ]]; then
  echo "::error::sentry monitor-binding gate: plan JSON not readable at '$PLAN'." >&2
  exit 1
fi

# ROW-COUNT FLOOR, on the whole document. The `-z "$bindings"` branch below used
# to exit 0 with "nothing to check", which made the DOCUMENTED anti-vacuity floor
# further down dead code: it tests `checked -eq 0`, reachable only when
# `$bindings` is non-empty AND the loop parses nothing — impossible. So the real
# vacuity case (a truncated or stub `terraform show -json`) printed a green line.
# It was mitigated only by the create tripwire happening to run first at both
# call sites, i.e. by a NEIGHBOUR'S ordering rather than this gate's own contract.
rows=$(jq -r '(.resource_changes // []) | length' "$PLAN" 2>/dev/null) || rows=""
if [[ ! "$rows" =~ ^[0-9]+$ ]]; then
  echo "::error::sentry monitor-binding gate: could not read .resource_changes from '$PLAN'." >&2
  exit 1
fi
if [[ "$rows" -eq 0 ]]; then
  echo "::error::sentry monitor-binding gate: '$PLAN' has ZERO resource_changes rows — a truncated, targeted or unwritten plan document, not a plan with nothing to check. Refusing to report PASS." >&2
  exit 1
fi

# Read the RESOLVED binding for every sentry_alert row. `.change.after` is the
# post-apply object; on an import row it is the adopted state. Fail closed on a
# null/absent monitor_ids rather than treating it as "nothing to check" — an
# unreadable binding is an UNCHECKED binding, not a passing one.
# `select(index("delete") | not)` — a DELETE row has `.change.after == null`, so
# without this every intentional retirement of a `sentry_alert` reads as an
# "unreadable binding" and reds this gate. This gate runs before the ack and has
# no `[ack-destroy]` path by design, and unlike the adoption assert it does not
# self-retire — so the first PR that deliberately deletes an alert would have hit
# a permanent, un-acknowledgeable refusal. An absent binding is not an unreadable
# one; a delete belongs to the destroy gate, which is where it now goes.
# Each row is emitted as `addr<TAB>shown-ids<TAB>reason`, with an EMPTY reason
# meaning the row complies. `shown-ids` is never empty (`<empty>`,
# `<unreadable>`): a tab is IFS whitespace, so an empty middle field would
# collapse and shift the reason into the ids column.
bindings=$(jq -r --arg expected "$EXPECTED" --argjson cron_bound "$CRON_BOUND_ADDRESSES" '
  [ (.planned_values.root_module.resources // [])[]
    | select(.type == "sentry_cron_monitor")
    | .values.id | select(. != null) | tostring ] as $cron_ids
  | ($cron_ids | length) as $ncron
  | [ .resource_changes[]?
      | select(.type == "sentry_alert")
      | select((.change.actions // []) | index("delete") | not)
      | { addr: .address,
          ids: (.change.after.monitor_ids // null) } ]
  | .[]
  | .addr as $a | .ids as $ids
  | (if $ids == null then "<unreadable>"
     elif ($ids | type) != "array" then "<not-an-array:\($ids | tojson)>"
     elif ($ids | length) == 0 then "<empty>"
     else ($ids | map(if . == null then "<null>" else tostring end) | sort | join(",")) end) as $shown
  | ($cron_bound | any(. == $a)) as $is_cron_bound
  | (if $is_cron_bound then
       if ($ids | type) != "array" then "cron-bound address: monitor_ids is unreadable"
       elif ($ids | length) == 0 then "cron-bound address binds an EMPTY monitor_ids set — it would route no cron monitor"
       else
         ([ $ids[] | select(. == null) ] | length) as $nulls
         | ([ $ids[] | select(. != null) | tostring | select(. == $expected) ] | length) as $has_expected
         | ([ $ids[] | select(. != null) | tostring | select(. as $i | $cron_ids | index([$i]) | not) ] | unique) as $foreign
         | [ (if $nulls > 0 then "carries \($nulls) null element(s) — a detector id that does not exist yet (a monitor created in this plan); route it in a follow-up PR" else empty end),
             (if $has_expected > 0 then "contains the issue-stream detector \u0027\($expected)\u0027 — the cron-failure rule must never page on issue events" else empty end),
             (if ($foreign | length) > 0 then "binds id(s) \($foreign | join(",")) that are not the .values.id of any sentry_cron_monitor in this plan (planned_values carries \($ncron))" else empty end) ]
         | join("; ")
       end
     elif $shown == $expected then ""
     else
       ([ ($ids // [])[]? | select(. != null) | tostring | select(. as $i | $cron_ids | index([$i]) != null) ] | length) as $bound_cron
       | "expected \u0027\($expected)\u0027"
         + (if $bound_cron > 0 then " — it binds \($bound_cron) sentry_cron_monitor detector(s) but is not in the gate\u0027s cron-bound address set (CRON_BOUND_ADDRESSES in scripts/sentry-monitor-binding-gate.sh)" else "" end)
     end) as $why
  | "\($a)\t\($shown)\t\($why)"
' "$PLAN") || {
  echo "::error::sentry monitor-binding gate: could not parse '$PLAN'." >&2
  exit 1
}

if [[ -z "$bindings" ]]; then
  # Reachable only for a non-empty plan carrying no non-delete `sentry_alert`
  # rows. That is legitimate (a plan touching only monitors), and the row-count
  # floor above has already refused the truncated-document case.
  echo "sentry monitor-binding gate: no non-delete sentry_alert rows in this ${rows}-row plan — nothing to check."
  exit 0
fi

checked=0
cron_checked=0
bad=0
while IFS=$'\t' read -r addr ids why; do
  [[ -z "$addr" ]] && continue
  checked=$((checked + 1))
  if [[ -n "$why" ]]; then
    bad=$((bad + 1))
    echo "::error::  $addr binds '$ids' — $why" >&2
  elif [[ "$ids" != "$EXPECTED" ]]; then
    # Only a cron-bound address can comply while binding something else.
    cron_checked=$((cron_checked + 1))
  fi
done <<< "$bindings"

# Anti-vacuity: a gate that examined nothing must not report success. This is
# a POSITIVE floor on work actually done, not a bound on failures found.
if [[ "$checked" -eq 0 ]]; then
  echo "::error::sentry monitor-binding gate: parsed 0 sentry_alert rows from a non-empty binding set — refusing to report PASS." >&2
  exit 1
fi

if [[ "$bad" -gt 0 ]]; then
  echo "::error::sentry monitor-binding gate: $bad of $checked sentry_alert resource(s) break the binding contract (issue-stream rules bind exactly '$EXPECTED'; the cron-bound set binds only this plan's sentry_cron_monitor ids)." >&2
  echo "::error::A correlated rebind darkens every affected paging rule while destroy_count stays 0 and this apply otherwise passes green. Refusing." >&2
  exit 1
fi

if [[ "$cron_checked" -gt 0 ]]; then
  echo "sentry monitor-binding gate: PASS ($checked sentry_alert resource(s): $((checked - cron_checked)) bind detector $EXPECTED, $cron_checked cron-bound bind only this plan's sentry_cron_monitor detectors)"
else
  echo "sentry monitor-binding gate: PASS ($checked sentry_alert resource(s) all bind detector $EXPECTED)"
fi
exit 0
