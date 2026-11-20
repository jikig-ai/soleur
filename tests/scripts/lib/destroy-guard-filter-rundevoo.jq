# Destroy-guard counter for apply-rundevoo-infra.yml (#12971). Path-specific
# per the #4420 convention: NO recursive walk(); each nested-block-bearing
# resource type gets its own `select(.type == ...)` clause documented inline.
#
# INVENTORY (verified against the locally dumped cloudflare/cloudflare 4.52.10
# provider schema, `block_types` per resource):
#   cloudflare_zone          — block_types: []  (zone/account_id/type/plan are
#                              scalars; meta/name_servers are computed)
#   cloudflare_zone_dnssec   — block_types: []  (all attributes scalar/computed)
#   cloudflare_record        — block_types: ["data", "timeouts"]
# `data` is the MaxItems:1 nested block carrying the typed payload of
# structured records (SRV/LOC/CAA/TLSA/... — service, proto, target, lat/long,
# tag, ...). Shrinking it plans as `actions:["update"]` — the resource stays,
# so resource_deletes sees nothing — while the live record's payload is
# silently rewritten. That IS an unreviewed deletion of record content; the
# `cloudflare_record` clause below counts it per the #4420 per-surface rule.
# `timeouts` is an operation-level block only (how long the provider waits on
# the API): dropping it changes no live state and is deliberately NOT counted.
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
# ── undecidable_actions ────────────────────────────────────────────────────
# The web-platform sibling HALTs on a resource_change whose actions is empty
# or not an array — the count predicates can't classify it, and an
# unclassifiable change must never score 0 and green the gate (an ack cannot
# rescue it either; the counts script exits before emitting). Terraform
# doesn't emit that shape today; the clause exists so the day it does, the
# gate is already armed.
#
# Input: `terraform show -json <plan>` document.
# Output: {plan_ok, resource_deletes, resource_forgets, nested_deletes,
#          undecidable_actions}, all int except plan_ok (bool).

# `data` serializes as a one-element array in change.before/after (SDKv2
# TypeList MaxItems:1); the object/array/empty normalisation keeps the count
# honest if the marshalling ever differs.
def _blockcount($v): if $v == null then 0 elif ($v | type) == "array" then ($v | length) else 1 end;

def cloudflare_record_shrink($before; $after):
  ($before // {}) as $b | ($after // {}) as $a
  | (_blockcount($b.data) - _blockcount($a.data));

{
  plan_ok: has("resource_changes"),
  resource_deletes: ([.resource_changes[]? | select(.change.actions? | index("delete"))] | length),
  # Every type, no type-specific clause — a forget is type-independent.
  resource_forgets: ([.resource_changes[]? | select(.change.actions? | index("forget"))] | length),
  undecidable_actions: ([.resource_changes[]? | select((.change.actions? | type) != "array" or (.change.actions | length) == 0)] | length),
  nested_deletes: (
    [
      # cloudflare_record.data — the typed-payload block (MaxItems:1); a
      # shrink rewrites live record content under an "update" action.
      (.resource_changes[]?
       | select(.type == "cloudflare_record")
       | select(.change.actions? | index("delete") | not)
       | cloudflare_record_shrink(.change.before; .change.after)
       | select(. > 0))
    ] | add // 0
  )
}
