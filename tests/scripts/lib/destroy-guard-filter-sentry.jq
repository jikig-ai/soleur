# Destroy-guard counter for apply-sentry-infra.yml. Path-specific per the
# #4420 plan-review iteration: NO recursive walk(); each future
# nested-block-bearing resource type gets its own `select(.type == ...)`
# clause documented inline. Mirrors tests/scripts/lib/destroy-guard-filter.jq
# (the github_repository_ruleset case) byte-for-byte where applicable.
#
# CURRENT SCOPE: apply-sentry-infra.yml targets `sentry_cron_monitor.*` and
# `sentry_uptime_monitor.*` resources (see apply-sentry-infra.yml `-target=`
# allow-list; uptime monitors added in #4585). At the time of this filter's
# creation (#4419), `sentry_cron_monitor` exposes ZERO array-of-blocks:
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
# Input: `terraform show -json <plan>` document.
# Output: {resource_deletes: int, nested_deletes: int}.

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
