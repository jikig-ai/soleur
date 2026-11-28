# shellcheck shell=bash
# Sourced birth gate for the bastion-host-create dispatch (#12866, Guard 1; ADR-327 step 2a).
#
# THE ONLY CHECK ON THIS JOB. The per-PR apply HALTs on any host create and excludes every bastion
# address (OPERATOR_APPLIED_EXCLUSIONS); the dispatch job's `if:` is exclusive with it, so nothing
# upstream grades this plan. Every arm below is load-bearing.
#
# PASS (rc=0) iff ALL of:
#   creates == 1, and it is hcloud_server.bastion   one authorization births one named host
#   destroys == 0                                    no delete, replace or forget anywhere
#   out_of_scope == 0                                only bastion-resources.txt addresses change
#   host key never updates or deletes                the pin is fixed from birth (F5); it rotates only
#                                                    by a deliberate act, never as a birth side effect
#   hcloud_server_network.bastion is created         entailed by the server: without it there is no
#   at ip 10.0.1.70, known at plan time              private IP, and step 3's dialer has nothing to dial;
#                                                    bastion.tf fixes local.bastion_private_ip there
#   the firewall attachment binds exactly this       outcome, not verb: on a re-birth after the server
#   firewall to exactly this server                  was lost the attachment survives refresh with
#                                                    server_ids emptied and plans an UPDATE (the hcloud
#                                                    provider's attachment id is the firewall's), so
#                                                    requiring a create would wedge that retry. Read
#                                                    from the plan's CONFIGURATION references; a known
#                                                    value only says how many, the references say which.
#                                                    Same reasoning as git-data-host-birth-gate.sh.
#   no inline firewall_ids on the server             the attachment is the one binding this gate reads
#   no label binding, readably: the attachment's     a label selector (on either side) binds by label,
#   label_selectors and the firewall's apply_to      so it reaches whatever servers carry the label,
#   are empty and known                              which the server-id binding above cannot see
#   hcloud_firewall.bastion has zero rules, readably the deny-all firewall plus the host's own nftables
#                                                    are the whole inbound posture (F8)
#   every listed address is present, create or no-op a partial-birth retry (key and firewall landed
#                                                    in a failed first run) stays legal
#
# An all-no-op plan (already born) is refused by `creates == 0` with a pointer to #12879: the bastion
# is never re-born through this route, it is replaced through bastion-host-replace.
#
# THE ALLOW-SET IS bastion-resources.txt beside this file, read at call time. There is no override:
# nothing in the apply job's environment can point the gate at another list (the suite tests a bad
# list by sourcing a copy of the gate from a scratch directory). The gate also refuses a list that
# does not name every address it grades, so the list
# and the arms below cannot drift apart silently. The anchor outside both is the owner's typed go
# after the plan_only run prints the resource list (Guard 1 Anchor).
#
# Usage:  source tests/scripts/lib/bastion-host-birth-gate.sh
#         bastion_host_birth_gate <plan-json-file>   # 0=PASS, 1=ABORT

# shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _BHBG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_BHBG_DIR}/plan-gate-preamble.sh"
fi
# The create-side checks shared with bastion-host-replace-gate.sh (R3, #12879): sourced UNCONDITIONALLY
# from this file's own directory (see that file's header); a failed source makes the calls return 127.
# shellcheck source=tests/scripts/lib/bastion-gate-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bastion-gate-common.sh"
_BHBG_LIST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bastion-resources.txt"

bastion_host_birth_gate() {
  local plan_json="${1:-}" g="bastion_host_birth_gate"
  local list="$_BHBG_LIST" allow_json
  local want_addr="hcloud_server.bastion" key_addr="tls_private_key.bastion_host_ssh"
  local nic_addr="hcloud_server_network.bastion" att_addr="hcloud_firewall_attachment.bastion" nic_ip="10.0.1.70"
  local creates destroys created_addr out_of_scope key_touched nic_creates offenders a present

  plan_gate_assert_readable     "$g" "$plan_json" || return 1
  plan_gate_assert_classifiable "$g" "$plan_json" || return 1

  bastion_gate_load_allow "$g" "$list" || return 1
  allow_json="$BASTION_GATE_ALLOW_JSON"

  creates=$(jq '[.resource_changes[] | select(.type == "hcloud_server") | select(.change.actions | index("create"))] | length' < "$plan_json" 2>/dev/null)
  destroys=$(jq '[.resource_changes[] | select(.change.actions | index("delete") or index("forget"))] | length' < "$plan_json" 2>/dev/null)
  out_of_scope=$(jq --argjson allow "$allow_json" '[.resource_changes[]
    | select(.change.actions | any(. != "no-op" and . != "read"))
    | select(IN(.address; $allow[]) | not)] | length' < "$plan_json" 2>/dev/null)
  key_touched=$(jq --arg a "$key_addr" '[.resource_changes[] | select(.address == $a)
    | select(.change.actions | any(. == "update" or . == "delete" or . == "forget"))] | length' < "$plan_json" 2>/dev/null)
  nic_creates=$(jq --arg a "$nic_addr" '[.resource_changes[] | select(.address == $a) | select(.change.actions == ["create"])] | length' < "$plan_json" 2>/dev/null)
  bastion_gate_create_side_measure "$g" "$plan_json" || return 1

  plan_gate_assert_numeric "$g" "creates=${creates}" "destroys=${destroys}" "out_of_scope=${out_of_scope}" \
    "key_touched=${key_touched}" "nic_creates=${nic_creates}" || return 1

  echo "${g}: host_creates=${creates} destroys=${destroys} out_of_scope=${out_of_scope} key_touched=${key_touched} nic_creates=${nic_creates} nic_ip_ok=${BGC_NIC_IP_OK} fw_rules=${BGC_FW_RULES} fw_unreadable=${BGC_FW_UNREADABLE} fw_apply_to=${BGC_FW_APPLY_TO} att_labels=${BGC_ATT_LABELS} inline_fw=${BGC_INLINE_FW} att_ok=${BGC_ATT_OK}"

  # Destroys first: a server replace (delete+create) is one create to a counter.
  if [[ "$destroys" -ne 0 ]]; then
    offenders=$(jq -r '[.resource_changes[] | select(.change.actions | index("delete") or index("forget")) | .address] | .[0:10] | join(", ")' < "$plan_json" 2>/dev/null)
    echo "${g}: ABORT — ${destroys} destroy/forget action(s): ${offenders}. A birth is purely additive. Replacing the bastion is bastion-host-replace (#12879), never this route. NOTHING HAS BEEN APPLIED."
    return 1
  fi
  if [[ "$key_touched" -ne 0 ]]; then
    echo "${g}: ABORT — the plan updates or deletes ${key_addr}, the bastion's SSH host key. The key is fixed from birth and never rotates as a side effect (ADR-327, F5); a rotation is the deliberate act in the bastion-host runbook."
    return 1
  fi
  if [[ "$creates" -ne 1 ]]; then
    if [[ "$creates" -eq 0 ]]; then
      echo "${g}: ABORT — no host create in this plan. If every bastion address is a no-op the bastion is already born: use bastion-host-replace (#12879), not a second birth. Otherwise the -target set is mis-scoped."
    else
      echo "${g}: ABORT — ${creates} hcloud_server creates; expected exactly 1. One authorization births one host."
    fi
    return 1
  fi
  created_addr=$(jq -r '[.resource_changes[] | select(.type == "hcloud_server") | select(.change.actions | index("create")) | .address][0]' < "$plan_json" 2>/dev/null)
  if [[ "$created_addr" != "$want_addr" ]]; then
    echo "${g}: ABORT — IDENTITY MISMATCH: the plan births ${created_addr}; this dispatch authorizes only ${want_addr}."
    return 1
  fi
  if [[ "$out_of_scope" -ne 0 ]]; then
    offenders=$(jq -r --argjson allow "$allow_json" '[.resource_changes[] | select(.change.actions | any(. != "no-op" and . != "read"))
      | select(IN(.address; $allow[]) | not) | .address] | .[0:10] | join(", ")' < "$plan_json" 2>/dev/null)
    echo "${g}: ABORT — ${out_of_scope} out-of-scope change(s): ${offenders}. A bastion birth changes only the addresses in bastion-resources.txt."
    return 1
  fi
  if [[ "$nic_creates" -ne 1 ]]; then
    echo "${g}: ABORT — the plan births ${want_addr} but does not create ${nic_addr} (${nic_creates} creates). A new server entails a new NIC attachment; without it the bastion has no private IP. The -target set is mis-scoped."
    return 1
  fi
  # The create-side arms (NIC IP pin, inline firewall_ids, firewall content, label bindings, the
  # attachment binding), shared with the replace gate: bastion-gate-common.sh.
  bastion_gate_create_side_judge "$g" "$plan_json" || return 1
  while IFS= read -r a; do
    [[ -z "$a" ]] && continue
    # create or no-op; update only for the attachment (the re-birth shape its arm above explains).
    present=$(jq --arg a "$a" --arg att "$att_addr" '[.resource_changes[] | select(.address == $a)
      | select((.change.actions | length) > 0 and (.change.actions | all(. == "create" or . == "no-op" or ($a == $att and . == "update"))))] | length' < "$plan_json" 2>/dev/null)
    plan_gate_assert_numeric "$g" "present[${a}]=${present}" || return 1
    if [[ "$present" -eq 0 ]]; then
      echo "${g}: ABORT — ${a} is not in the plan as a create or no-op. Every bastion address must appear unchanged or born: one missing means the -target set is mis-scoped, and an in-place update of an existing bastion resource is not a birth."
      return 1
    fi
  done < <(jq -r '.[]' <<<"$allow_json")

  echo "${g}: PASS — scoped birth of ${want_addr} permitted (1 host create, its NIC created at ${nic_ip}, its zero-rule firewall bound to it by id with no label binding, host key untouched, every bastion address present, 0 destroys, 0 out-of-scope changes)."
  return 0
}
