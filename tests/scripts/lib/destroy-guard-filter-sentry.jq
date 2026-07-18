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
# Input: `terraform show -json <plan>` document.
# Output: {resource_deletes: int, resource_creates: int, nested_deletes: int}.

# Count the array-of-blocks v2 surfaces on a sentry_issue_alert side. Sum of
# conditions_v2 + filters_v2 + actions_v2 elements; `($side // {})` null-coalesces
# the resource-create/-delete edges (already excluded by the outer delete guard).
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
  nested_deletes: (
    [
      # sentry_issue_alert.{conditions_v2,filters_v2,actions_v2} (#4364)
      (.resource_changes[]?
       | select(.type == "sentry_issue_alert")
       | select(.change.actions? | index("delete") | not)
       | (sentry_issue_alert_blocks_count(.change.before) - sentry_issue_alert_blocks_count(.change.after))
       | select(. > 0))
    ] | add // 0
  )
}
