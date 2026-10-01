#!/usr/bin/env bash
# git-data-rung2-plan-shape.sh <plan.json> <additive|host-only> — Guard 3 (#5274), the single
# chokepoint that decides whether a rung-2 rehearsal plan may be applied. The workflow calls it at
# all three plan steps: seed (additive), payload (host-only), replace arm (host-only).
#
#   additive   Every change is create/read/no-op, and every created address is rehearsal-scoped.
#              The seed phase and every first plan of a run.
#   host-only  The payload phase and the replace arm. Beyond rehearsal-scoped creates, reads and
#              no-ops, the ONLY admitted changes are:
#                - a replace (delete+create, in either order) of exactly hcloud_server.rehearsal,
#                  hcloud_volume_attachment.rehearsal, hcloud_volume_attachment.rehearsal_luks,
#                  and tls_private_key.rehearsal_host_ssh (the replace arm's host-key rotation);
#                - an update of hcloud_firewall_attachment.rehearsal.
#              The three host replaces MUST be present. Any change to either volume is refused: a
#              fresh plaintext volume makes the seed vacuous, and a fresh LUKS volume skips the
#              adopt arm the replace exists to rehearse.
#
# BOTH MODES also refuse any resource_change carrying a non-null `.change.importing`: an import
# plans as `no-op` (or `update`), so the verb deny-list alone would ADMIT a plan that adopts an
# existing object — a production volume, say — into this root, where the teardown destroys it.
#
# DENY-LIST THE INERT VERBS, never allow-list the destructive ones: an action Terraform adds
# later (it grew `forget`) is refused by default. Replace/update addresses are matched EXACTLY.
# A CREATE must be a root-module `<type>.rehearsal` or `<type>.rehearsal_<suffix>` address,
# anchored by regex rather than globbed: the earlier `*.rehearsal|*.rehearsal_*` case glob let `*`
# span dots, so `module.git_data.hcloud_server.rehearsal` read as rehearsal-scoped.
# An unparseable plan fails closed. The plan JSON embeds sensitive variables verbatim, so this
# script reads it and prints only addresses and action verbs.
#
# Exit: 0 admitted · 1 refused (or unparseable) · 64 usage.
set -euo pipefail

usage() { echo "usage: git-data-rung2-plan-shape.sh <plan.json> <additive|host-only>" >&2; exit 64; }
[[ $# -eq 2 ]] || usage
PLAN="$1"; MODE="$2"
case "$MODE" in additive|host-only) ;; *) usage ;; esac
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

bad=0
while IFS= read -r addr; do
  [[ -n "$addr" ]] || continue
  echo "::error::plan-shape: the plan IMPORTS ${addr} — an import plans as no-op/update and would adopt an existing object into the rehearsal root, whose teardown destroys it"
  bad=1
done <<<"$imports"
while IFS= read -r addr; do
  [[ -n "$addr" ]] || continue
  if [[ ! "$addr" =~ ^[a-z0-9_]+\.rehearsal(_[a-z0-9_]+)?$ ]]; then
    echo "::error::plan-shape: the plan would create a NON-rehearsal address: ${addr}"; bad=1
  fi
done <<<"$creates"

if [[ "$MODE" == additive ]]; then
  if [[ -n "$changes" ]]; then
    echo "::error::plan-shape (additive): the plan contains non-additive change(s); this phase may only create, read or no-op:"
    printf '%s\n' "$changes"
    bad=1
  fi
else
  seen_server=0 seen_att=0 seen_att_luks=0
  while IFS=$'\t' read -r addr acts; do
    [[ -n "$addr" ]] || continue
    case "$acts" in
      delete,create|create,delete)
        case "$addr" in
          hcloud_server.rehearsal) seen_server=1 ;;
          hcloud_volume_attachment.rehearsal) seen_att=1 ;;
          hcloud_volume_attachment.rehearsal_luks) seen_att_luks=1 ;;
          tls_private_key.rehearsal_host_ssh) ;;
          *) echo "::error::plan-shape (host-only): a replace of ${addr} is not admitted"; bad=1 ;;
        esac ;;
      update)
        if [[ "$addr" != "hcloud_firewall_attachment.rehearsal" ]]; then
          echo "::error::plan-shape (host-only): an update of ${addr} is not admitted"; bad=1
        fi ;;
      *) echo "::error::plan-shape (host-only): ${addr} ${acts} is not admitted (only the host replace and the firewall-attachment update are)"; bad=1 ;;
    esac
  done <<<"$changes"
  if [[ "$seen_server$seen_att$seen_att_luks" != 111 ]]; then
    echo "::error::plan-shape (host-only): the plan does not replace the host and both attachments (server=${seen_server} attachment=${seen_att} attachment_luks=${seen_att_luks}); a host-only phase that replaces nothing rehearses nothing."
    bad=1
  fi
fi

if [[ "$bad" -ne 0 ]]; then
  echo "::error::plan-shape (${MODE}): refusing to apply."
  exit 1
fi
n_create=$(printf '%s\n' "$creates" | grep -c . || true)
n_change=$(printf '%s\n' "$changes" | grep -c . || true)
echo "plan-shape (${MODE}): admitted — ${n_create} create(s), ${n_change} admitted replace/update change(s), all rehearsal-scoped"
