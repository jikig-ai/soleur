# Destroy-guard counter for apply-web-platform-infra.yml. Path-specific
# per #4420; NO recursive walk(). Five resource types have array-of-blocks
# or single-block surfaces in the current apply allow-list (verified
# 2026-05-25 via apps/web-platform/infra/*.tf inspection — closes #4419);
# a sixth surface (#5911) counts reboot-forcing in-place updates on
# hcloud_server.*:
#
#   1. cloudflare_ruleset.*                              .rules
#   2. cloudflare_zero_trust_tunnel_cloudflared_config.* .config[0].ingress_rule
#   3. cloudflare_zone_settings_override.*               .settings[0].security_header
#   4. cloudflare_notification_policy.*                  .email_integration
#   5. cloudflare_zero_trust_access_policy.*             .include
#   6. hcloud_server.* reboot-forcing in-place update    placement_group_id /
#                                                        server_type (#5911)
#
# The HIGHEST-impact case is (1) — removing the ACME carve-out
# (cloudflare_ruleset.seo_page_redirects.rules[10] at seo-rulesets.tf)
# would silently re-fire the 2026-05-18 cert-renewal outage on the next
# ~60-day Let's Encrypt renewal cycle.
#
# SCHEMA STABILITY: `terraform show -json change.before` / `change.after`
# are documented contracts
# (https://developer.hashicorp.com/terraform/internals/json-format#change-representation).
# When a single-block (MaxItems: 1) surface is omitted, Terraform encodes
# it as an empty array in the JSON plan — that's why .config[0],
# .settings[0], .email_integration, and .include all index identically
# via `[.<path>[]?] | length`.
#
# SHARP EDGE: `["forget"]` actions (Terraform 1.7+ `removed { lifecycle {
# destroy = false } }` blocks) will trip nested_deletes against this filter
# because `change.actions = ["forget"]` is excluded only from resource_deletes
# (the `index("delete")` check) but `before.rules` is populated while `after`
# is null → positive count. Currently no `removed` blocks in
# apps/web-platform/infra/; if you add one, acknowledge with `[ack-destroy]`
# (operator intent matches) or widen the nested-clause guard to
# `index("delete") + index("forget")`.
#
# PROVIDER PIN: cloudflare/cloudflare ~> 4.0 (currently 4.52.7). Two of
# the five clauses are at risk on a v5 upgrade
# (`ingress_rule` → `ingress` rename; `cloudflare_zone_settings_override`
# removed in v5). See learning
# `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`. When
# bumping to v5, extend the clauses in lockstep and re-capture
# tests/scripts/fixtures/tfplan-web-platform-real-baseline.json.
#
# CAP-COUPLING CONVENTION: this is the third path-specific destroy-guard
# filter (alongside destroy-guard-filter.jq and destroy-guard-filter-sentry.jq).
# A future apply-* workflow MUST follow the same pattern: dedicated
# `destroy-guard-filter-<workflow>.jq`, dedicated
# `test-destroy-guard-counter-<workflow>.sh`, CODEOWNERS rows.
#
# Input: `terraform show -json <plan>` document.
# Output: {resource_deletes: int, nested_deletes: int, reboot_updates: int}.
#
# Each `_count($side)` helper uses `$side` value-binding (jq 1.7+; safe on
# jq 1.8.x). NOT the call-by-name filter-arg shape that crashed v1 of
# #4420 on string-key descent. The `($side // {})` null-coalesce keeps
# the count valid for resources whose `before` or `after` is null
# (resource-create / resource-delete edges that the outer
# `select(.change.actions? | index("delete") | not)` guard already
# excludes from this branch).

def cf_ruleset_rules_count($side):
  ($side // {}) | [.rules[]?] | length;

def cf_tunnel_ingress_count($side):
  ($side // {}) | [.config[]?.ingress_rule[]?] | length;

def cf_zone_security_header_count($side):
  ($side // {}) | [.settings[]?.security_header[]?] | length;

def cf_notif_email_integration_count($side):
  ($side // {}) | [.email_integration[]?] | length;

def cf_access_policy_include_count($side):
  ($side // {}) | [.include[]?] | length;

{
  resource_deletes: ([.resource_changes[]? | select(.change.actions? | index("delete"))] | length),
  nested_deletes: (
    [
      # 1. cloudflare_ruleset.rules
      (.resource_changes[]?
       | select(.type == "cloudflare_ruleset")
       | select(.change.actions? | index("delete") | not)
       | (cf_ruleset_rules_count(.change.before) - cf_ruleset_rules_count(.change.after))
       | select(. > 0)),
      # 2. cloudflare_zero_trust_tunnel_cloudflared_config.config[0].ingress_rule
      (.resource_changes[]?
       | select(.type == "cloudflare_zero_trust_tunnel_cloudflared_config")
       | select(.change.actions? | index("delete") | not)
       | (cf_tunnel_ingress_count(.change.before) - cf_tunnel_ingress_count(.change.after))
       | select(. > 0)),
      # 3. cloudflare_zone_settings_override.settings[0].security_header
      (.resource_changes[]?
       | select(.type == "cloudflare_zone_settings_override")
       | select(.change.actions? | index("delete") | not)
       | (cf_zone_security_header_count(.change.before) - cf_zone_security_header_count(.change.after))
       | select(. > 0)),
      # 4. cloudflare_notification_policy.email_integration
      (.resource_changes[]?
       | select(.type == "cloudflare_notification_policy")
       | select(.change.actions? | index("delete") | not)
       | (cf_notif_email_integration_count(.change.before) - cf_notif_email_integration_count(.change.after))
       | select(. > 0)),
      # 5. cloudflare_zero_trust_access_policy.include
      (.resource_changes[]?
       | select(.type == "cloudflare_zero_trust_access_policy")
       | select(.change.actions? | index("delete") | not)
       | (cf_access_policy_include_count(.change.before) - cf_access_policy_include_count(.change.after))
       | select(. > 0))
    ] | add // 0
  ),
  # 6th surface (#5911): hcloud_server.* reboot-forcing IN-PLACE update.
  # A placement_group_id / server_type change → power-off reboot of the
  # RUNNING host with ZERO destroys → invisible to resource_deletes + the 5
  # Cloudflare nested clauses above. TYPE-scoped select (not address)
  # INTENTIONALLY covers BOTH hcloud_server.web AND hcloud_server.git_data
  # (git-data.tf) — git_data is not target-reachable today but a git_data
  # reboot (holds the LUKS git volume) is MORE disruptive, so
  # defense-in-depth. `location`/`datacenter` force a full REPLACE (actions
  # include "delete") → already caught by resource_deletes and NOT compared
  # here (a REPLACE never matches actions==["update"], so comparing them
  # would be dead code). Selecting ONLY actions==["update"] never
  # double-counts a REPLACE, never false-fires on a CREATE (web-2 add), and
  # never false-fires on a `moved` re-address (serializes as no-op). An
  # `after` value UNKNOWN at plan time (placement_group_id is a resource
  # reference → serialized into change.after_unknown, change.after.<attr>
  # absent → jq yields null) still trips (before != null) — errs SAFE
  # (availability friction, never a missed reboot). KNOWN-UNCOVERED: a future
  # reboot/power-cycle attr (rescue, iso) or a provider upgrade flipping a
  # ForceNew attr to in-place silently returns rupd=0; any new hcloud_server
  # argument must be consciously classified reboot/non-reboot (CODEOWNERS
  # coupling on server.tf + this filter).
  reboot_updates: (
    [ .resource_changes[]?
      | select(.type == "hcloud_server")
      | select(.change.actions == ["update"])
      | select(.change.before.placement_group_id != .change.after.placement_group_id
            or .change.before.server_type       != .change.after.server_type) ]
    | length
  )
}
