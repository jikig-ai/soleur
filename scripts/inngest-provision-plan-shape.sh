#!/usr/bin/env bash
# inngest-provision-plan-shape.sh <plan.json> <additive|nic-attach> — the single chokepoint
# that decides whether an inngest-provision rehearsal plan (#9175) may be applied. The
# workflow calls it at both plan steps: Phase A (additive) and Phase B (nic-attach).
# Mirrors git-data-rung2-plan-shape.sh (#5274), the same guard for the rung-2 rehearsal.
#
#   additive    Every change is create/read/no-op, every created address is
#               rehearsal-scoped, AND no hcloud_server_network create is present —
#               Phase A must birth the host WITHOUT the private NIC; an accidental
#               attachment here is caught at plan cost, not at the evidence gate
#               ~20 minutes later on a paid host.
#   nic-attach  The Phase-B toggle. Beyond rehearsal-scoped creates, reads and no-ops, the
#               ONLY admitted change is a create of hcloud_server_network.rehearsal[0] —
#               that resource's `count = var.nic_attached ? 1 : 0` is the forced race's
#               second arm, and the address MUST be present: a Phase-B plan that adds nothing
#               rehearses nothing. A replace/update of any other address (say, the host
#               itself being force-replaced by a user_data edit) means the second apply is
#               not the attach-only delta the evidence claims it is.
#
# BOTH MODES also refuse any resource_change carrying a non-null `.change.importing`: an
# import plans as `no-op` (or `update`), so the verb deny-list alone would ADMIT a plan that
# adopts an existing object — a production network, say — into this root, where the teardown
# destroys it.
#
# DENY-LIST THE INERT VERBS, never allow-list the destructive ones: an action Terraform adds
# later (it grew `forget`) is refused by default. Replace/update addresses are matched
# EXACTLY. A CREATE must be a root-module `<type>.rehearsal`, `<type>.rehearsal_<suffix>` or
# counted `<type>.rehearsal[N]` address, anchored by regex rather than globbed — the rung-2
# guard's earlier `*.rehearsal|*.rehearsal_*` glob let `*` span dots, so
# `module.git_data.hcloud_server.rehearsal` read as rehearsal-scoped.
# An unparseable plan fails closed. The plan JSON embeds sensitive variables verbatim, so
# this script reads it and prints only addresses and action verbs.
#
# Exit: 0 admitted · 1 refused (or unparseable) · 64 usage.
set -euo pipefail

usage() { echo "usage: inngest-provision-plan-shape.sh <plan.json> <additive|nic-attach>" >&2; exit 64; }
[[ $# -eq 2 ]] || usage
PLAN="$1"; MODE="$2"
case "$MODE" in additive|nic-attach) ;; *) usage ;; esac
[[ -r "$PLAN" ]] || { echo "::error::plan-shape: cannot read ${PLAN}" >&2; exit 1; }

if ! jq -e 'type == "object" and (has("resource_changes") or has("format_version"))' "$PLAN" >/dev/null 2>&1; then
  echo "::error::plan-shape: could not parse the plan JSON — refusing to read an unparseable plan as a clean one."
  exit 1
fi

# One line per non-inert change: <address><TAB><actions joined by ,>. Order-normalised for the
# replace test below; `create,delete` (create_before_destroy) is still a replace.
changes="$(jq -r '.resource_changes[]? | select(.change.actions | map(select(. != "create" and . != "read" and . != "no-op")) | length > 0) | "\(.address)\t\(.change.actions | join(","))"' "$PLAN")"
creates="$(jq -r '.resource_changes[]? | select(.change.actions == ["create"]) | .address' "$PLAN")"
imports="$(jq -r '.resource_changes[]? | select((.change.importing // null) != null) | .address' "$PLAN")"

reads="$(jq -r '.resource_changes[]? | select(.change.actions == ["read"] or .change.actions == ["no-op"]) | .address' "$PLAN")"

bad=0
# Inert-verb lane is NOT unconditional: reads and no-ops are denied outside an allowlist.
# The only sanctioned external read is data.hcloud_network.private; a data.doppler_* read
# would land prod secret VALUES in this root's state/plan output, and data.external/http
# would execute or fetch under the apply environment's credentials.
while IFS= read -r addr; do
  [[ -n "$addr" ]] || continue
  case "$addr" in
    data.hcloud_network.private) ;;
    *.rehearsal|*.rehearsal_*|*.rehearsal[[]*[]]) ;;
    *) echo "::error::plan-shape: inert change on a non-rehearsal, non-sanctioned address: ${addr} — only data.hcloud_network.private may read outside this root"; bad=1 ;;
  esac
done <<<"$reads"
while IFS= read -r addr; do
  [[ -n "$addr" ]] || continue
  echo "::error::plan-shape: the plan IMPORTS ${addr} — an import plans as no-op/update and would adopt an existing object into the rehearsal root, whose teardown destroys it"
  bad=1
done <<<"$imports"
while IFS= read -r addr; do
  [[ -n "$addr" ]] || continue
  if [[ ! "$addr" =~ ^[a-z0-9_]+\.rehearsal(_[a-z0-9_]+)?(\[[0-9]+\])?$ ]]; then
    echo "::error::plan-shape: the plan would create a NON-rehearsal address: ${addr}"; bad=1
  fi
done <<<"$creates"

if [[ "$MODE" == additive ]]; then
  if [[ -n "$changes" ]]; then
    echo "::error::plan-shape (additive): the plan contains non-additive change(s); this phase may only create, read or no-op:"
    printf '%s\n' "$changes"
    bad=1
  fi
  # PHASE A MUST BE NIC-ABSENT — not merely rehearsal-scoped. `additive` otherwise admits
  # any `.rehearsal` create, so a Phase-A plan that accidentally included the NIC would pass
  # this gate and be caught only ~20 min later by the evidence gate, on a paid host. Refuse
  # it here, where the cost is zero.
  while IFS= read -r addr; do
    [[ -n "$addr" ]] || continue
    if [[ "$addr" =~ ^hcloud_server_network\. ]]; then
      echo "::error::plan-shape (additive): the plan creates ${addr} — Phase A must birth the host WITHOUT a private NIC; the attachment belongs to Phase B only."
      bad=1
    fi
  done <<<"$creates"
  if ! printf '%s\n' "$creates" | grep -q .; then
    echo "::error::plan-shape (additive): the plan creates NOTHING — a vacuous Phase-A birth rehearses nothing."
    bad=1
  fi
else
  # nic-attach: `changes` holds only NON-create verbs (the jq filter above), so any entry is a
  # refusal outright; and `creates` must be exactly {hcloud_server_network.rehearsal[0]} —
  # present, and alone.
  while IFS=$'\t' read -r addr acts; do
    [[ -n "$addr" ]] || continue
    echo "::error::plan-shape (nic-attach): ${addr} (${acts}) is not admitted — the Phase-B delta is exactly the NIC-attachment create"; bad=1
  done <<<"$changes"
  while IFS= read -r addr; do
    [[ -n "$addr" ]] || continue
    if [[ "$addr" != "hcloud_server_network.rehearsal[0]" ]]; then
      echo "::error::plan-shape (nic-attach): a create of ${addr} is not admitted — the Phase-B delta is exactly the NIC attachment"; bad=1
    fi
  done <<<"$creates"
  if ! printf '%s\n' "$creates" | grep -qxF 'hcloud_server_network.rehearsal[0]'; then
    echo "::error::plan-shape (nic-attach): the plan does not create hcloud_server_network.rehearsal[0] — a Phase-B apply that attaches nothing rehearses nothing."
    bad=1
  fi
fi

if [[ "$bad" -ne 0 ]]; then
  echo "::error::plan-shape (${MODE}): refusing to apply."
  exit 1
fi
n_create=$(printf '%s\n' "$creates" | grep -c . || true)
n_change=$(printf '%s\n' "$changes" | grep -c . || true)
echo "plan-shape (${MODE}): admitted — ${n_create} create(s), ${n_change} admitted non-create change(s), all rehearsal-scoped"
