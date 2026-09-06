#!/usr/bin/env bash
# Guard A(ii) — no run ever CREATES a `sentry_issue_alert` again (#7650 Phase 2).
#
# Usage: sentry-issue-alert-create-tripwire.sh <plan.json>
# Exit 0 = the plan creates no sentry_issue_alert.
# Exit 1 = it creates one, or the plan could not be read as a plan document.
#
# ── WHY A SEPARATE, NARROW TRIPWIRE ────────────────────────────────────────
# After this PR the repo owns exactly TWO `sentry_issue_alert` resources, and
# both stay behind only because the provider cannot express their trigger
# (`event_unique_user_frequency_count` is absent from `trigger_conditions` at
# 0.15.7 — upstream jianyuan/terraform-provider-sentry issue 950). Every other
# path through that resource type is now a mistake:
#
#   * a re-authored block after someone "restores" one of the 27, which would
#     create a SECOND live rule paging on the same events; or
#   * a failed adoption that Terraform decides to resolve by creating rather
#     than importing.
#
# Both bill, both double-page, and one of them is `byok-art-33-breach` — the
# rule whose silence stops the GDPR Art. 33 72-hour clock from ever starting.
#
# ── WHY IT IS NOT REACHABLE FROM [ack-destroy] ─────────────────────────────
# It is invoked BEFORE the ack is consulted, in both jobs, and it never reads
# the commit message. An unexplained create is a different failure from an
# intended destroy; typing one ack must not wave the other through. Modelled on
# `apex_move_orphans`: a narrow, un-ackable statement sitting on top of the
# broad diff-matched gate rather than inside it.
#
# ── WHY index("create") AND NOT == ["create"] ──────────────────────────────
# A `create_before_destroy` replace serialises as `["create","delete"]` (the
# ordering is not fixed), and a replace of one of the two survivors is still a
# live rule being torn down and rebuilt. `destroy-guard-filter-sentry.jq` uses
# exact equality for `resource_creates` for the opposite and equally deliberate
# reason — there, counting a replace as a create would fail an already-correct
# acknowledged plan twice and train blanket-acking. Here there is no ack to
# erode, so the wider selector is the right one.
#
# Behaviour is unit-tested by tests/scripts/test-sentry-alert-adoption-guards.sh.
set -uo pipefail

PLAN="${1:?usage: sentry-issue-alert-create-tripwire.sh <plan.json>}"

if [[ ! -r "$PLAN" ]]; then
  echo "::error::sentry_issue_alert create tripwire: plan JSON not readable at '$PLAN'." >&2
  exit 1
fi

# Vacuity floor on the guard's own dispatch. A full-root plan ALWAYS carries a
# row per managed resource, no-ops included (the live baseline carries 88), so
# an absent or empty `resource_changes` does not mean "nothing to check" — it
# means this is not the document we think it is, or `terraform show` failed and
# left a stub. A guard that examined nothing must not report success.
rows=$(jq -r '(.resource_changes // []) | length' "$PLAN" 2>/dev/null) || rows=""
if [[ ! "$rows" =~ ^[0-9]+$ ]]; then
  echo "::error::sentry_issue_alert create tripwire: could not read .resource_changes from '$PLAN'." >&2
  exit 1
fi
if [[ "$rows" -eq 0 ]]; then
  echo "::error::sentry_issue_alert create tripwire: '$PLAN' has ZERO resource_changes rows." >&2
  echo "::error::A full-root Sentry plan always carries one row per managed resource, no-ops included. Zero rows means the plan document is truncated, targeted, or was never written — not that there is nothing to check. Refusing to report PASS." >&2
  exit 1
fi

creates=$(jq -r '
  [ .resource_changes[]?
    | select(.type == "sentry_issue_alert")
    | select((.change.actions // []) | index("create"))
    | "\(.address) actions=\((.change.actions // []) | join(","))" ]
  | .[]
' "$PLAN") || {
  echo "::error::sentry_issue_alert create tripwire: could not parse '$PLAN'." >&2
  exit 1
}

if [[ -z "$creates" ]]; then
  echo "sentry_issue_alert create tripwire: PASS (no sentry_issue_alert create in $rows plan row(s))"
  exit 0
fi

count=$(grep -c '' <<<"$creates")
echo "::error::sentry_issue_alert create tripwire: this plan CREATES ${count} sentry_issue_alert resource(s):" >&2
sed 's/^/::error::  /' <<<"$creates" >&2
echo "::error::Only two sentry_issue_alert resources may exist (auth_per_user_loop, sandbox_startup_failure) and both are import-only; the other 27 were adopted as sentry_alert in #7650 Phase 2. A create here means a duplicate live paging rule that bills and double-pages, or an adoption that failed and is being resolved by creating instead of importing. There is NO acknowledgement for this and [ack-destroy] does not reach it: investigate the divergence." >&2
exit 1
