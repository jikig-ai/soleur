#!/usr/bin/env bash
# Guard A(ii) — no run ever CREATES a `sentry_issue_alert` again (#7650 Phase 2).
# Guard 2 (#8451) — no run ever WRITES a `sentry_alert` that carries a legacy
# trigger the provider cannot express.
#
# Usage: sentry-issue-alert-create-tripwire.sh <plan.json>
# Exit 0 = the plan creates no sentry_issue_alert and writes no legacy-trigger
#          sentry_alert.
# Exit 1 = it does, or the plan could not be read as a plan document.
#
# ── WHY A SEPARATE, NARROW TRIPWIRE ────────────────────────────────────────
# The repo owns ZERO `sentry_issue_alert` resources. The last two
# (`auth_per_user_loop`, `sandbox_startup_failure`) were adopted as
# `sentry_alert` in #8451 after Sentry returned HTTP 410 for the legacy
# alert-rule API; `git_data_boot_warning` moved in Phase 3.4 and the other 27 in
# #7650 Phase 2. Every path that creates one now is a mistake:
#
#   * a re-authored block after someone "restores" one of the 27, which would
#     create a SECOND live rule paging on the same events; or
#   * a failed adoption that Terraform decides to resolve by creating rather
#     than importing.
#
# Both bill, both double-page, and one of them is `byok-art-33-breach` — the
# rule whose silence stops the GDPR Art. 33 72-hour clock from ever starting.
#
# ── GUARD 2: THE LEGACY-TRIGGER WRITE (#8451) ──────────────────────────────
# The two adopted rules page on `event_unique_user_frequency_count`, which the
# v0.15.7 provider cannot model (upstream jianyuan/terraform-provider-sentry
# issue 950, fixed on main but in no release; tracked at #7985). Read keeps only
# the TYPE string in `legacy_trigger_conditions`, dropping `{interval,value}`.
# Write (`getTriggerConditions`, shared by Create and Update) re-sends every
# legacy entry as `comparison: true`, so any create, update or replace would
# replace "> N distinct users in <window>" with a boolean, and `terraform plan`
# cannot show it because the threshold never existed in config.
# `ignore_changes = all` means no Update is planned today; this refusal covers
# the day someone narrows it, and every Create (a Sentry-UI delete dropping the
# rule from state, a label rename under [ack-destroy], `-replace`/taint).
# It keys on the LEGACY field, not the trigger type: after the #7985 native
# conversion the provider writes the true threshold and an update is safe.
# An import (`["no-op"]` + `importing`) is a read and is not refused.
#
# WHICH STATES IT READS, and why each (review of #8451):
#   * `after`  — the write itself. ANY legacy entry, not only the three types the
#     fidelity projection excludes: the provider re-sends EVERY legacy entry
#     with `comparison: true`, so a type outside that set loses its parameters
#     the same way.
#   * `before` — the refreshed state. Narrowing `ignore_changes` AND deleting the
#     `legacy_trigger_conditions` line plans an update whose `after` legacy is
#     null while the live rule still carries the trigger: the write would strip
#     the paging trigger outright. The refreshed `before` still shows it.
#   * `after_unknown` — a legacy value computed at apply time cannot be judged
#     at plan time, so it is refused rather than passed.
# The #7985 conversion is not blocked by `before`: it bumps the provider first,
# and a provider that models the trigger reads it into the NATIVE field, so the
# refreshed `before` carries no legacy entry. If a future provider still reads
# it as legacy, the conversion is not safe yet — which is this refusal's job.
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
# ordering is not fixed), and a replace of a live rule is still that rule
# being torn down and rebuilt. `destroy-guard-filter-sentry.jq` uses
# exact equality for `resource_creates` for the opposite and equally deliberate
# reason — there, counting a replace as a create would fail an already-correct
# acknowledged plan twice and train blanket-acking. Here there is no ack to
# erode, so the wider selector is the right one. Guard 2 uses the same wide
# selector for the same reason, plus `update`.
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

legacy_writes=$(jq -r '
  def legacy(x): (x // {}) | (.legacy_trigger_conditions // []) | if type == "array" then . else [tostring] end;
  [ .resource_changes[]?
    | select(.type == "sentry_alert")
    | select((.change.actions // []) | (index("create") or index("update")))
    | legacy(.change.after) as $after
    | legacy(.change.before) as $before
    | ((.change.after_unknown // {}) | if type == "object" then (.legacy_trigger_conditions // false) else false end) as $unknown
    | select(($after | length) > 0 or ($before | length) > 0 or ($unknown != false))
    | "\(.address) actions=\((.change.actions // []) | join(",")) legacy_trigger_conditions after=[\($after | join(","))] before=[\($before | join(","))]\(if $unknown != false then " after=(unknown at plan time)" else "" end)" ]
  | .[]
' "$PLAN") || {
  echo "::error::sentry_issue_alert create tripwire: could not evaluate the legacy-trigger check on '$PLAN'." >&2
  exit 1
}

if [[ -z "$creates" && -z "$legacy_writes" ]]; then
  echo "sentry_issue_alert create tripwire: PASS (no sentry_issue_alert create and no legacy-trigger sentry_alert write in $rows plan row(s))"
  exit 0
fi

if [[ -n "$creates" ]]; then
  count=$(grep -c '' <<<"$creates")
  echo "::error::sentry_issue_alert create tripwire: this plan CREATES ${count} sentry_issue_alert resource(s):" >&2
  while IFS= read -r line; do echo "::error::  $line" >&2; done <<<"$creates"
  echo "::error::No sentry_issue_alert resource may exist: every rule in issue-alerts.tf is a sentry_alert, the last two (auth_per_user_loop, sandbox_startup_failure) adopted in #8451 after the legacy alert-rule API returned HTTP 410. A create here means a duplicate live paging rule that bills and double-pages, or an adoption that failed and is being resolved by creating instead of importing. There is NO acknowledgement for this and [ack-destroy] does not reach it: investigate the divergence." >&2
fi

if [[ -n "$legacy_writes" ]]; then
  count=$(grep -c '' <<<"$legacy_writes")
  echo "::error::sentry_issue_alert create tripwire: this plan WRITES ${count} sentry_alert resource(s) that carry a legacy trigger (before, after, or unknown at plan time):" >&2
  while IFS= read -r line; do echo "::error::  $line" >&2; done <<<"$legacy_writes"
  echo "::error::Provider v0.15.7 keeps only the type string of these triggers in legacy_trigger_conditions and re-sends each one with comparison: true on create and update, so applying this plan would replace the rule's paging threshold (N distinct users in a window) with a boolean, or strip the trigger if the write drops it. terraform plan cannot show that change. Import no-ops are allowed; a create, update or replace is not. The remedy is the #7985 native conversion (a provider release that models the trigger), not an edit to this rule's block. There is NO acknowledgement for this and [ack-destroy] does not reach it." >&2
fi
exit 1
