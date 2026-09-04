# Destroy-guard counter for apply-sentry-infra.yml. Path-specific per the
# #4420 plan-review iteration: NO recursive walk(); each future
# nested-block-bearing resource type gets its own `select(.type == ...)`
# clause documented inline. Mirrors tests/scripts/lib/destroy-guard-filter.jq
# (the github_repository_ruleset case) byte-for-byte where applicable.
#
# CURRENT SCOPE (#6589): apply-sentry-infra.yml plans the FULL ROOT — every
# resource under apps/web-platform/infra/sentry/, plus anything in state with no
# remaining block. It previously planned against a hand-maintained `-target=`
# allow-list; that list is gone, because a deleted .tf block cannot be named in
# it, which made deletion a silent no-op (#4929, #6074).
#
# WHAT THAT WIDENING MEANS FOR THIS FILTER. `sentry_issue_alert` coverage goes
# from 2 addresses (the apply-created BYOK rules) to all 22 declared alerts —
# including the 4 import-only auth_* placeholders. The note below says those
# never appear in a plan diff because their v2 attributes are under
# `ignore_changes`; that assumption now carries 20 more resources than when it
# was written. It is TRUE as measured (a live full-root plan on 2026-07-17
# returned 75 no-ops, 2 deletes, 0 creates, with every one of the 22 alerts
# planning as no-op) and is asserted as an explicit sub-assertion of AC5 rather
# than left as a comment — a load-bearing assumption that only a comment defends
# is how #4929 survived for two months.
#
# The type set in scope is asserted by tests/scripts/test-destroy-guard-sentry-scope-guard.sh
# against `.tf UNION state`. A FOURTH type arriving without a clause here would
# have its array-of-blocks shrink counted as 0 and slip the guard.
#
# At the time of this filter's creation (#4419), `sentry_cron_monitor` exposes
# ZERO array-of-blocks:
# `schedule = { crontab = "..." }` is HCL object-attribute syntax (a map
# value), not a block. JSON plan path: `change.before.schedule.crontab`
# (string). Removing schedule = removing the monitor = resource-level delete,
# already caught by `resource_deletes`. `sentry_uptime_monitor` (added to
# scope in #4585) ALSO exposes ZERO array-of-blocks — every attribute is
# scalar (verified against the pinned provider schema: `block_types: []`).
# Notably `assertion_json` is a string built by the
# `provider::sentry::assertion(...)` function, NOT an HCL block, and `owner`
# is a single-nested-attribute object, not an array-of-blocks. So
# `nested_deletes: 0` remains correct for uptime monitors too; an
# uptime-monitor removal is a resource-level delete caught by
# `resource_deletes`. No `select(.type == "sentry_uptime_monitor")` clause
# is needed (it would be dead code).
#
# EXTENDING THIS FILTER: when a future schema change introduces a new
# nested-block-bearing sentry resource, add ONE path-specific clause per
# resource type, mirroring the pattern in
# tests/scripts/lib/destroy-guard-filter-web-platform.jq. Do
# NOT introduce walk().
#
# SCOPE WIDENED #4364: apply-sentry-infra.yml now also targets the 2
# apply-created `sentry_issue_alert` BYOK rules (byok_art_33_breach,
# byok_cap_exceeded). Unlike the 4 import-only auth issue-alerts (whose
# conditions_v2/filters_v2/actions_v2 are under `ignore_changes`, so they
# never appear in a plan diff), the BYOK rules are TF-owned source-of-truth:
# a future edit that removes a `filters_v2`/`conditions_v2`/`actions_v2`
# element produces an array-of-blocks shrink that resource-level
# `resource_deletes` would NOT catch. The `sentry_issue_alert` clause below
# counts that shrink. The v2 attributes serialize as JSON arrays in
# `terraform show -json` change.before/after (provider nested_type nesting=list),
# so `[.<attr>[]?] | length` mirrors the web-platform cloudflare_ruleset.rules
# pattern exactly.
#
# ── resource_creates (#6589) ───────────────────────────────────────────────
# The delete direction was guarded and the create direction was not. Once the
# `-target=` list is gone, the 4 formerly-untargeted import-only alerts come into
# scope, and state/config divergence materialises as an unreviewed CREATE — the
# same billing leak in mirror image (a duplicate live rule, or a monitor
# re-created after someone deleted it in the Sentry UI). So both directions are
# counted.
#
# PURE creates only: `actions == ["create"]`, exactly — not `index("create")`.
# A REPLACE serialises as `["delete","create"]`, and counting it here would be
# double jeopardy: a replace is already a destroy, so it already trips the
# [ack-destroy] gate. Counting it as a create too would fail a correct
# acknowledged plan for a second reason and push the author toward a blanket
# ack. Mirrors AC5's pure-delete SET assertion, which uses the same
# exact-equality shape for the same reason.
#
# ── resource_forgets (#7650 Phase 2) ───────────────────────────────────────
# A `removed { lifecycle { destroy = false } }` block plans as `actions:["forget"]`:
# the address leaves Terraform's management and the live object is left alone.
# NOTHING else in this filter sees it as leaving. It is not a `delete`
# (`resource_deletes` selects `index("delete")`), and for a type with no nested
# clause here — `sentry_cron_monitor` and `sentry_uptime_monitor` both expose
# zero array-of-blocks, by design — the nested arithmetic is 0 too. So without
# this counter a plan that drops every cron monitor out of state scores
# `destroy_count = 0` and the gate prints `PASS (plan destroys nothing)`.
#
# It is counted SEPARATELY from `resource_deletes` and never folded into it,
# because AC4's discrimination depends on `resource_deletes == 0` being the
# thing that says "nothing was actually destroyed" while the forgets are
# acknowledged. Folding the two together makes that sentence unsayable.
#
# `index("forget")` rather than exact `== ["forget"]`: Terraform is documented to
# emit `forget` alone today, but the actions array is a list precisely because it
# composes, and a composed forget is still a departure from management.
#
# Input: `terraform show -json <plan>` document.
# Output: {resource_deletes, resource_creates, resource_forgets, nested_deletes}, all int.

# Count the array-of-blocks v2 surfaces on a sentry_issue_alert side. Sum of
# conditions_v2 + filters_v2 + actions_v2 elements; `($side // {})` null-coalesces
# the resource-create/-delete edges (already excluded by the outer delete guard).
# Count the array-of-blocks surfaces on a sentry_alert side (#7650). Added BEFORE
# any sentry_alert enters a plan: this filter counts nested shrink per-type with no
# walk(), so a type arriving without a clause has its shrink counted as 0 and slips
# the guard silently — the failure mode the scope guard exists to make loud.
#
# Attribute names verified against the provider docs at v0.15.5, not from the
# migration plan's prose (which had the frequency mapping wrong — see the Phase 0
# evidence under knowledge-base/project/specs/fix-7650-sentry-alert-migration/).
#
# FIVE surfaces, and the middle one is easy to miss:
#   trigger_conditions[]         — Attributes List
#   legacy_trigger_conditions[]  — List of STRING, not blocks. Counted anyway because
#                                  the provider documents "when omitted from config
#                                  these will be removed on the next apply": dropping
#                                  an entry silently removes a live trigger type that
#                                  the provider cannot represent natively
#                                  (new_high_priority_issue, existing_high_priority_issue,
#                                  issue_resolution_change). A shrink here is exactly
#                                  the unreviewed deletion this guard is for.
#   action_filters[]             — the filter blocks themselves
#   action_filters[].conditions[]
#   action_filters[].actions[]
#
# Both the container and its contents are counted, so removing a whole action_filter
# registers a larger shrink than removing one condition inside it. Either is > 0,
# which is all the guard needs; the magnitude is only for the operator message.
def sentry_alert_blocks_count($side):
  ($side // {})
  | ([.trigger_conditions[]?] | length)
  + ([.legacy_trigger_conditions[]?] | length)
  + ([.action_filters[]?] | length)
  + ([.action_filters[]?.conditions[]?] | length)
  + ([.action_filters[]?.actions[]?] | length);

def sentry_issue_alert_blocks_count($side):
  ($side // {})
  | ([.conditions_v2[]?] | length)
  + ([.filters_v2[]?] | length)
  + ([.actions_v2[]?] | length);

{
  resource_deletes: ([.resource_changes[]? | select(.change.actions? | index("delete"))] | length),
  # Pure creates only — see the resource_creates note in the header for why a
  # replace (["delete","create"]) is deliberately excluded.
  resource_creates: ([.resource_changes[]? | select(.change.actions? == ["create"])] | length),
  # Every type, no type-specific clause — a forget is type-independent (#7650).
  resource_forgets: ([.resource_changes[]? | select(.change.actions? | index("forget"))] | length),
  nested_deletes: (
    [
      # sentry_issue_alert.{conditions_v2,filters_v2,actions_v2} (#4364)
      (.resource_changes[]?
       | select(.type == "sentry_issue_alert")
       | select(.change.actions? | index("delete") | not)
       | (sentry_issue_alert_blocks_count(.change.before) - sentry_issue_alert_blocks_count(.change.after))
       | select(. > 0)),

      # sentry_alert.{trigger_conditions,legacy_trigger_conditions,action_filters[.conditions,.actions]} (#7650)
      (.resource_changes[]?
       | select(.type == "sentry_alert")
       | select(.change.actions? | index("delete") | not)
       | (sentry_alert_blocks_count(.change.before) - sentry_alert_blocks_count(.change.after))
       | select(. > 0))
    ] | add // 0
  )
}
