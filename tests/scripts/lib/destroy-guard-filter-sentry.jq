# Destroy-guard counter for apply-sentry-infra.yml. Path-specific per the
# #4420 plan-review iteration: NO recursive walk(); each future
# nested-block-bearing resource type gets its own `select(.type == ...)`
# clause documented inline. Mirrors tests/scripts/lib/destroy-guard-filter.jq
# (the github_repository_ruleset case) byte-for-byte where applicable.
#
# CURRENT SCOPE: apply-sentry-infra.yml targets only `sentry_cron_monitor.*`
# resources (see apply-sentry-infra.yml `-target=` allow-list). At the time
# of this filter's creation (#4419), `sentry_cron_monitor` exposes ZERO
# array-of-blocks: `schedule = { crontab = "..." }` is HCL object-attribute
# syntax (a map value), not a block. JSON plan path:
# `change.before.schedule.crontab` (string). Removing schedule = removing
# the monitor = resource-level delete, already caught by `resource_deletes`.
#
# EXTENDING THIS FILTER: when a future schema change introduces a new
# nested-block-bearing sentry resource (or when the apply scope widens
# to include `sentry_issue_alert` / `sentry_uptime_monitor` with block
# shapes), add ONE path-specific clause per resource type, mirroring the
# pattern in tests/scripts/lib/destroy-guard-filter-web-platform.jq. Do
# NOT introduce walk(). The literal `nested_deletes: 0` below is
# intentional consistency-defense-in-depth and a documented extension
# point — NOT a TODO.
#
# Input: `terraform show -json <plan>` document.
# Output: {resource_deletes: int, nested_deletes: int}.

{
  resource_deletes: ([.resource_changes[]? | select(.change.actions? | index("delete"))] | length),
  nested_deletes:   0
}
