# ── prd Supabase project adoption (#9168, ADR-260) ───────────────────────────
#
# ADOPTED, not created. The prd project (ref ifsccnjhymdmidffkzhl — the same
# literal dns.tf's supabase_custom_domain CNAME points at) was created by hand
# and is imported into state rather than declared fresh: without the `import`
# block Terraform would plan a CREATE of a second project. Every attribute
# below is pinned to the LIVE value measured via the Management API on
# 2026-09-28, so the post-import plan is diff-free:
#   GET /v1/projects/ifsccnjhymdmidffkzhl  → name "soleur-web-platform",
#     organization_id "vttwegzidmuaiefjlysl", region "eu-west-1",
#     status ACTIVE_HEALTHY (postgres 17.6)
#   GET …/billing/addons                   → custom_domain only; no compute
#     addon selected, i.e. live instance_size WAS "micro" then
#   GET …/api-keys/legacy                  → {"enabled": true}
#
# `database_password` is REQUIRED by the provider schema yet can never carry
# the real value: the Management API never returns it, so post-import state
# holds null while configuration holds whatever is written here — a permanent
# diff. Worse, the provider's Update PATCHes a dedicated db-password endpoint
# on ANY diff to this attribute, so without `ignore_changes` the first apply
# would ROTATE THE LIVE DATABASE PASSWORD and break every stored DSN (app
# runtime, local dev, support tooling). The "unmanaged-9168" placeholder is
# deliberately never-applied; the lifecycle block is load-bearing, not
# cosmetic. SUPABASE_DB_PASSWORD is intentionally NOT pulled into
# prd_terraform for this.
#
# `legacy_api_keys_enabled` must stay pinned to the measured live value:
# unset/unpinned, the provider's Update can PUT the legacy-keys endpoint and
# disable the JWT anon/service_role keys the app authenticates with.
#
# `instance_size` is "small" — the Micro→Small flip (#9168 follow-up), applied
# while the operator watches; the resize costs ~2 min of downtime. The one-time
# `import {}` block that adopted the project was removed here in the same PR
# (ADR-222 convention — the same shape the #8216 monitor import used in
# uptime-alerts.tf before it was removed): kept past adoption it is not inert —
# a vendor-side deletion of the project would make every untargeted plan
# re-attempt the import against a missing object and abort (the drift
# detector's plan is untargeted).

resource "supabase_project" "prd" {
  organization_id   = "vttwegzidmuaiefjlysl"
  name              = "soleur-web-platform"
  region            = "eu-west-1"
  database_password = "unmanaged-9168" # gitleaks:allow # issue:#9168 placeholder literal, never applied (lifecycle.ignore_changes)
  instance_size     = "small"          # Micro→Small resize (#9168 follow-up)
  # legacy_api_keys_enabled is DEPRECATED in provider ~> 1.11 — Update PUTs
  # /api-keys/legacy on any diff. If Supabase force-migrates projects off
  # legacy keys, the pin may need manual removal rather than an apply.
  legacy_api_keys_enabled = true # measured GET /api-keys/legacy

  lifecycle {
    ignore_changes = [database_password]
    # prevent_destroy like the sibling imports (web-host-birth-environment.tf,
    # git-data-root-key): the apply workflow's destroy ack is a COUNT, not an
    # address list — a ForceNew provider diff on this resource would plan a
    # destroy of the production project under any destroy ack.
    prevent_destroy = true
  }
}
