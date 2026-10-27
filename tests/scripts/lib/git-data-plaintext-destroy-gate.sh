# shellcheck shell=bash
# Sourced plan gate for the plaintext git-data volume destroy
# (.github/workflows/git-data-plaintext-volume-destroy.yml; Option B of the W0 route, ADR-239 amendment).
#
# Usage: git_data_plaintext_destroy_gate <plan.json> <expected_volume_id> <live_server_id>
#
# It reads a `terraform show -json <plan>` document and PASSES (rc=0) iff the plan deletes ONLY
# the retired plaintext Hetzner volume and, optionally, its attachment:
#
#   hcloud_volume.git_data             exactly one entry, mode "managed", no deposed, actions
#                                      EXACTLY ["delete"], before.id == 106867358 (a STRING in
#                                      provider state), before.name == soleur-git-data-store
#   hcloud_volume_attachment.git_data  zero or one entry, mode "managed", no deposed, actions EXACTLY
#                                      ["delete"], before.volume_id == 106867358 and before.server_id ==
#                                      <live_server_id> (NUMBERS)
#
# Every other entry must be EXACTLY ["no-op"] or EXACTLY ["read"] — the -target closure pulls the
# server, the module and data sources in as no-op/read, so a literal "non-no-op count" would refuse a
# healthy plan. Anything else (the LUKS volume, hcloud_server.git_data, the passphrase pair, any
# create/update/forget/replace) is out of scope. NO entry at all, even a no-op, may carry
# `previous_address` (a `moved` block) or `change.importing` (an `import` block): those are state
# mutations outside the delete this gate attests. A plan whose top-level `errored` is true is refused.
#
# NOT borrowed from git-data-host-replace-gate.sh / git-data-host-birth-gate.sh: those two DEMAND the
# retired plaintext addresses be re-created, so they refuse any plan that deletes them. They are left
# byte-unchanged and fail closed (their retirement is a tracked follow-up, #11194).
#
# PINS: the VOLUME id (106867358) and name are constants here AND the volume id is an argument ($2, the
# workflow's `expected_volume_id` dispatch input): a weakening that edits one still fails the other, and
# the workflow re-reads the live volume from the Hetzner API in the same job. The SERVER id is NOT a
# constant: a host rotate re-mints the server, so it is passed in ($3) from the probe's live by-name
# resolution (CTO ruling 2026-10-26); the attachment must be bound to that live server. A missing or
# non-numeric $3 refuses (server_pin_missing).
#
# Verdicts are named on the REFUSE line so the failed-run annotation says which counter moved:
#   input_mismatch (the dispatch id is not the pinned volume id), server_pin_missing,
#   out_of_scope_change (any other action, a moved/imported entry, or an errored plan),
#   wrong_volume_identity (the volume entry is missing its pins, deposed, not managed, or duplicated),
#   duplicate_attachment (more than one attachment entry), not_pure_delete,
#   wrong_attachment_binding (attachment not bound to the pinned volume and the live server),
#   volume_delete_missing   (plus the preamble's ABORT lines).
#
# DEGRADED DOCUMENTS: a plan with no `resource_changes` is REFUSED here (plan_gate_assert_readable),
# because `null | length` is 0 in jq and an unreadable document must never read as "nothing changes".
# The "volume already gone" re-dispatch is handled by the WORKFLOW before planning (a 404 + empty name
# list short-circuits plan/gate/apply), never by teaching this gate to accept an empty plan.
#
# CALLERS MUST CHECK THE RETURN CODE (`if ! git_data_plaintext_destroy_gate …; then …`). The function
# returns 1; it does not exit.
#
# shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _GDPDG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_GDPDG_DIR}/plan-gate-preamble.sh"
fi

git_data_plaintext_destroy_gate() {
  local plan_json="$1" expected_id="${2-}" live_server_id="${3-}"
  local pin_volume_id="106867358" pin_volume_name="soleur-git-data-store"
  local counts oos vid vnc vnd att atb vdm verdicts=""

  # `|| return 1` also catches a 127 undefined-function status, so a preamble that failed to source
  # aborts the gate rather than silently skipping the check.
  plan_gate_assert_readable     "git_data_plaintext_destroy_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "git_data_plaintext_destroy_gate" "$plan_json" || return 1

  if ! counts=$(jq -n --arg vid "$pin_volume_id" --arg vname "$pin_volume_name" --arg sid "$live_server_id" \
      --slurpfile p "$plan_json" '
      def ignorable: (.change.actions == ["no-op"]) or (.change.actions == ["read"]);
      def is_vol: .address == "hcloud_volume.git_data";
      def is_att: .address == "hcloud_volume_attachment.git_data";
      # a moved/imported entry mutates state outside the delete this gate attests, even as a no-op
      def moved_or_imported: has("previous_address") or ((.change // {}) | has("importing"));
      $p[0].resource_changes as $rc
      | ([$rc[] | select(is_vol)]) as $vols
      | ([$rc[] | select(is_att)]) as $atts
      | {
          # anything non-ignorable that is NOT one of the two pinned addresses, any moved/imported entry,
          # and an errored plan
          out_of_scope: (([$rc[] | select((is_vol or is_att | not) and (ignorable | not))] | length)
                         + ([$rc[] | select(moved_or_imported)] | length)
                         + (if ($p[0].errored // false) == true then 1 else 0 end)),
          # identity of the volume entry: exactly one, managed, not deposed, pinned id + name.
          # Counted only when a volume entry exists, so volume_delete_missing owns the absent case.
          vol_identity_bad: (
            if ($vols | length) == 0 then 0
            elif ($vols | length) > 1 then 1
            else ($vols[0]
                  | if ((.mode // "") != "managed")
                       or (has("deposed") and ((.deposed // "") != ""))
                       or ((.change.before.id | tostring) != $vid)
                       or ((.change.before.name // "") != $vname)
                    then 1 else 0 end)
            end),
          # the volume entry exists but its actions are not exactly ["delete"] and it is not an
          # ignorable no-op/read (those are volume_delete_missing instead)
          vol_not_pure: ([$vols[] | select(.change.actions != ["delete"] and (ignorable | not))] | length),
          # attachment entries must be exactly one-or-zero, delete-only, managed and live (not deposed),
          # bound to the pinned volume and the live server
          att_count: ($atts | length),
          att_not_pure: ([$atts[] | select(.change.actions != ["delete"])] | length),
          att_bad_binding: ([$atts[]
                              | select(((.change.before.volume_id | tostring) != $vid)
                                       or ((.change.before.server_id | tostring) != $sid)
                                       or ((.mode // "") != "managed")
                                       or (has("deposed") and ((.deposed // "") != "")))]
                            | length),
          # the volume must be positively deleted
          vol_deleted: ([$vols[] | select(.change.actions == ["delete"])] | length)
        }
    ' 2>/dev/null); then
    echo "git_data_plaintext_destroy_gate: ABORT — counter computation failed (jq error). Fail-closed: an uncomputed counter is not a zero."
    return 1
  fi

  oos=$(jq -r '.out_of_scope' <<<"$counts" 2>/dev/null)
  vid=$(jq -r '.vol_identity_bad' <<<"$counts" 2>/dev/null)
  vnc=$(jq -r '.vol_not_pure' <<<"$counts" 2>/dev/null)
  att=$(jq -r '.att_count' <<<"$counts" 2>/dev/null)
  atb=$(jq -r '.att_bad_binding' <<<"$counts" 2>/dev/null)
  vnd=$(jq -r '.att_not_pure' <<<"$counts" 2>/dev/null)
  vdm=$(jq -r '.vol_deleted' <<<"$counts" 2>/dev/null)

  plan_gate_assert_numeric "git_data_plaintext_destroy_gate" \
    "out_of_scope=${oos}" "vol_identity_bad=${vid}" "vol_not_pure=${vnc}" \
    "att_count=${att}" "att_bad_binding=${atb}" "att_not_pure=${vnd}" "vol_deleted=${vdm}" || return 1

  [[ "$expected_id" == "$pin_volume_id" ]] || verdicts+=" input_mismatch"
  [[ "$live_server_id" =~ ^[0-9]+$ ]] || verdicts+=" server_pin_missing"
  [[ "$oos" -eq 0 ]] || verdicts+=" out_of_scope_change"
  [[ "$vid" -eq 0 ]] || verdicts+=" wrong_volume_identity"
  [[ "$att" -le 1 ]] || verdicts+=" duplicate_attachment"
  [[ "$vnc" -eq 0 && "$vnd" -eq 0 ]] || verdicts+=" not_pure_delete"
  [[ "$atb" -eq 0 ]] || verdicts+=" wrong_attachment_binding"
  [[ "$vdm" -ge 1 ]] || verdicts+=" volume_delete_missing"

  if [[ -n "$verdicts" ]]; then
    echo "git_data_plaintext_destroy_gate: REFUSE verdict=${verdicts# } (out_of_scope=${oos} vol_identity_bad=${vid} vol_not_pure=${vnc} att_count=${att} att_not_pure=${vnd} att_bad_binding=${atb} vol_deleted=${vdm}) — this plan is not exactly the pinned plaintext-volume delete; nothing is applied."
    return 1
  fi

  echo "git_data_plaintext_destroy_gate: PASS — plan deletes only hcloud_volume.git_data (${pin_volume_id}, ${pin_volume_name})$([[ "$att" -eq 1 ]] && printf ' and its attachment (live server %s)' "$live_server_id")."
  return 0
}
