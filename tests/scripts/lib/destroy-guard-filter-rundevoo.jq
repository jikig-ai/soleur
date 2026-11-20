# Destroy-guard counter for apply-rundevoo-infra.yml (#12971). Path-specific
# per the #4420 convention: NO recursive walk(); each nested-block-bearing
# resource type gets its own `select(.type == ...)` clause documented inline.
#
# INVENTORY (verified against the locally dumped cloudflare/cloudflare 4.52.10
# provider schema, `block_types` per resource):
#   cloudflare_zone          — block_types: []  (zone/account_id/type/plan are
#                              scalars; meta/name_servers are computed)
#   cloudflare_zone_dnssec   — block_types: []  (all attributes scalar/computed)
#   cloudflare_record        — block_types: []  (content/name/ttl/priority are
#                              scalars; `metadata` is a map attribute, not a
#                              block array)
# NO nested-block surface exists on any type in this root, so
# `nested_deletes` is a literal 0 with no per-type clause. Shipping vacuous
# shrink clauses would be dead code asserting nothing (#4420's rule is
# clauses-only-where-a-surface-exists).
#
# EXTENDING THIS FILTER: a future resource type in this root whose schema has
# a nested block_types array-of-blocks (e.g. cloudflare_ruleset.rules) gets
# ONE path-specific clause here, mirroring
# tests/scripts/lib/destroy-guard-filter-web-platform.jq. Do NOT add walk().
#
# ── resource_creates: DELIBERATELY ABSENT ──────────────────────────────────
# The sentry filter counts pure creates because that root carries import-only
# resources a botched adoption could silently re-create. This root has no
# import-only untargeted surface — every resource is TF-owned and the apply is
# full-root — and additive live drift is covered by a stronger mechanism: the
# `rundevoo-dns-set-equality.sh` REST probe in the drift leg enumerates the
# WHOLE live record set (a plan can never see an out-of-band *added* record;
# set equality can). Counting creates here would only gate the normal
# add-a-record flow behind [ack-destroy] — a blanket-ack training exercise.
#
# ── plan_ok ────────────────────────────────────────────────────────────────
# Distinguishes "a parsed plan with zero destructive changes" from "nothing
# was read" (empty file, wrong document). `terraform show -json` always emits
# a `resource_changes` key (empty array on a clean plan); its absence means the
# input was not a plan document. scripts/rundevoo-destroy-counts.sh refuses to
# emit counts when plan_ok is false — an unread input must never score 0 and
# green the gate.
#
# ── resource_forgets (#7650 Phase 2, carried) ──────────────────────────────
# A `removed { lifecycle { destroy = false } }` block plans as
# `actions:["forget"]`: the address leaves Terraform's management while the
# live object is left alone — for this root, that IS the incident (the zone or
# its mail-hardening records dropped out of management). `index("forget")`,
# not exact equality: a composed actions array is still a departure.
#
# Input: `terraform show -json <plan>` document.
# Output: {plan_ok, resource_deletes, resource_forgets, nested_deletes}, all int
#         except plan_ok (bool).

{
  plan_ok: has("resource_changes"),
  resource_deletes: ([.resource_changes[]? | select(.change.actions? | index("delete"))] | length),
  # Every type, no type-specific clause — a forget is type-independent.
  resource_forgets: ([.resource_changes[]? | select(.change.actions? | index("forget"))] | length),
  # 0 by construction: every type in this root has `block_types: []` on the
  # pinned 4.52.10 schema — no array-of-blocks surface exists to shrink. See
  # the inventory above.
  nested_deletes: 0
}
