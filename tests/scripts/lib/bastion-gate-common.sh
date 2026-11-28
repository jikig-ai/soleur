# shellcheck shell=bash
# Create-side checks shared by the two bastion plan gates (R3, #12879; ADR-327 steps 2a and 2b).
#
#   tests/scripts/lib/bastion-host-birth-gate.sh     bastion_host_birth_gate   (bastion-host-create)
#   tests/scripts/lib/bastion-host-replace-gate.sh   bastion_host_replace_gate (bastion-host-replace)
#
# Both routes end a plan the same way: one hcloud_server.bastion born with its NIC at 10.0.1.70, its
# zero-rule deny-all firewall bound to it by id through hcloud_firewall_attachment.bastion, and no
# label binding on either side. These are the checks that say so. They were extracted word for word
# from the birth gate (whose header still carries the per-arm reasoning); the one generalization is
# the NIC IP pin, which reads any NIC entry whose actions include a create, because a replace plans
# the NIC ["delete","create"]. The birth gate refuses that shape earlier (its destroys arm, then its
# exact ["create"] nic_creates arm), so the birth verdicts are unchanged. Every function takes the
# calling gate's name, so each message names the gate that refused.
#
# SOURCING. Each gate sources this file UNCONDITIONALLY from its own directory, as
# git-data-host-birth-gate.sh sources git-data-root-key-arm-gate.sh: a `declare -F` guard would let
# an already-defined copy (or a same-named stub) stand in for these checks, and a suite that grades a
# scratch mutant of this file would then grade the original. A failed source leaves the functions
# undefined, so the gate's call returns 127 and refuses.
#
# Functions:
#   bastion_gate_load_allow <gate> <list-file>     sets BASTION_GATE_ALLOW_JSON; 0, or 1 with an ABORT
#   bastion_gate_create_side_measure <gate> <plan> sets the BGC_* counters; 0, or 1 (non-numeric)
#   bastion_gate_create_side_judge <gate> <plan>   the create-side ABORT arms over BGC_*; 0 or 1

# has_unknown: true when any leaf of an after_unknown subtree is `true` (an unknown value).
_BHBG_JQ_UNKNOWN='def has_unknown: if type == "boolean" then . elif type == "array" or type == "object" then any(.[]; has_unknown) else false end;'
_BGC_WANT_ADDR="hcloud_server.bastion"
_BGC_KEY_ADDR="tls_private_key.bastion_host_ssh"
_BGC_NIC_ADDR="hcloud_server_network.bastion"
_BGC_FW_ADDR="hcloud_firewall.bastion"
_BGC_ATT_ADDR="hcloud_firewall_attachment.bastion"
_BGC_NIC_IP="10.0.1.70"

# bastion_gate_load_allow <gate> <list-file>: the allow-set, and the drift check against the five
# addresses both gates grade. The list path is the calling gate's own (no override).
bastion_gate_load_allow() {
  local g="$1" list="$2" allow_json a
  BASTION_GATE_ALLOW_JSON=""
  if [[ ! -s "$list" ]]; then
    echo "${g}: ABORT — the allow-set list ${list} (bastion-resources) is missing or empty. Fail-closed: without it the gate cannot say what this dispatch may change."
    return 1
  fi
  allow_json=$(grep -vE '^[[:space:]]*(#|$)' "$list" | jq -R . | jq -sc .) || allow_json=""
  if [[ -z "$allow_json" || "$allow_json" == "[]" ]]; then
    echo "${g}: ABORT — the allow-set list ${list} (bastion-resources) names no address. Fail-closed."
    return 1
  fi
  for a in "$_BGC_WANT_ADDR" "$_BGC_KEY_ADDR" "$_BGC_NIC_ADDR" "$_BGC_FW_ADDR" "$_BGC_ATT_ADDR"; do
    if ! jq -e --arg a "$a" 'index($a) != null' <<<"$allow_json" >/dev/null 2>&1; then
      echo "${g}: ABORT — ${list} (bastion-resources) does not list ${a}, which this gate grades. The list and the gate's arms have drifted; fix the list, never this check."
      return 1
    fi
  done
  # shellcheck disable=SC2034  # read by the calling gate
  BASTION_GATE_ALLOW_JSON="$allow_json"
  return 0
}

# bastion_gate_create_side_measure <gate> <plan-json>: the counters, each through plan_gate_assert_numeric.
bastion_gate_create_side_measure() {
  local g="$1" plan_json="$2"
  local want_addr="$_BGC_WANT_ADDR" nic_addr="$_BGC_NIC_ADDR" fw_addr="$_BGC_FW_ADDR"
  local att_addr="$_BGC_ATT_ADDR" nic_ip="$_BGC_NIC_IP"
  BGC_NIC_IP_OK="" BGC_FW_RULES="" BGC_FW_UNREADABLE="" BGC_FW_APPLY_TO="" BGC_ATT_LABELS=""
  BGC_INLINE_FW="" BGC_ATT_OK=""
  BGC_NIC_IP_OK=$(jq --arg a "$nic_addr" --arg ip "$nic_ip" "$_BHBG_JQ_UNKNOWN"'[.resource_changes[] | select(.address == $a)
    | select(.change.actions | index("create")) | select(.change.after.ip == $ip)
    | select((.change.after_unknown | type) == "object" and (((.change.after_unknown.ip // false) | has_unknown) | not))] | length' < "$plan_json" 2>/dev/null)
  # Label bindings: any non-empty value, an unknown leaf, or no after_unknown object to say it is known.
  BGC_FW_APPLY_TO=$(jq --arg a "$fw_addr" "$_BHBG_JQ_UNKNOWN"'[.resource_changes[] | select(.address == $a) | select(.change.actions | any(. != "read"))
    | select(((.change.after.apply_to? // []) != [])
          or ((.change.after_unknown | type) != "object")
          or ((.change.after_unknown.apply_to // false) | has_unknown))] | length' < "$plan_json" 2>/dev/null)
  BGC_ATT_LABELS=$(jq --arg a "$att_addr" "$_BHBG_JQ_UNKNOWN"'[.resource_changes[] | select(.address == $a) | select(.change.actions | any(. != "read"))
    | select(((.change.after.label_selectors? // []) != [])
          or ((.change.after_unknown | type) != "object")
          or ((.change.after_unknown.label_selectors // false) | has_unknown))] | length' < "$plan_json" 2>/dev/null)
  BGC_FW_RULES=$(jq --arg a "$fw_addr" '[.resource_changes[] | select(.address == $a) | select(.change.actions | any(. != "read"))
    | if ((.change.after.rule // null) | type) == "array" then (.change.after.rule | length) else 0 end] | add // 0' < "$plan_json" 2>/dev/null)
  # Unreadable = the plan does not disclose the rule set: no object after, no `rule` key, no
  # after_unknown object, an unknown leaf anywhere under after_unknown.rule, or a non-array rule.
  BGC_FW_UNREADABLE=$(jq --arg a "$fw_addr" "$_BHBG_JQ_UNKNOWN"'
    [.resource_changes[] | select(.address == $a) | select(.change.actions | any(. != "read"))
    | select(((.change.after | type) != "object")
          or ((.change.after | has("rule")) | not)
          or ((.change.after_unknown | type) != "object")
          or ((.change.after_unknown.rule // false) | has_unknown)
          or ((.change.after.rule | type) != "array"))] | length' < "$plan_json" 2>/dev/null)
  BGC_INLINE_FW=$(jq --arg a "$want_addr" '
    ([.configuration.root_module.resources[]? | select(.address == $a) | ((.expressions // {}) | has("firewall_ids"))] | any) as $cfg
    | [.resource_changes[] | select(.address == $a)
    | select((((.change.after.firewall_ids // []) | length) > 0) or $cfg)] | length' < "$plan_json" 2>/dev/null)
  BGC_ATT_OK=$(jq --arg a "$att_addr" '
    ([.configuration.root_module.resources[]? | select(.address == $a) | .expressions // {}] | first // {}) as $e
    | (($e.server_ids.references // []) | sort) as $srv
    | (($e.firewall_id.references // []) | sort) as $fw
    | [.resource_changes[] | select(.address == $a)
    | select(.change.actions | all(. == "create" or . == "update" or . == "no-op"))
    | select($srv == ["hcloud_server.bastion", "hcloud_server.bastion.id"])
    | select($fw == ["hcloud_firewall.bastion", "hcloud_firewall.bastion.id"])
    | select((((.change.after.server_ids // []) | length) == 1) or ((.change.after_unknown.server_ids // false) == true))] | length' < "$plan_json" 2>/dev/null)

  plan_gate_assert_numeric "$g" "nic_ip_ok=${BGC_NIC_IP_OK}" "fw_rules=${BGC_FW_RULES}" \
    "fw_unreadable=${BGC_FW_UNREADABLE}" "fw_apply_to=${BGC_FW_APPLY_TO}" "att_labels=${BGC_ATT_LABELS}" \
    "inline_fw=${BGC_INLINE_FW}" "att_ok=${BGC_ATT_OK}" || return 1
  return 0
}

# bastion_gate_create_side_judge <gate> <plan-json>: the create-side ABORT arms, in the birth gate's order.
bastion_gate_create_side_judge() {
  local g="$1" plan_json="$2" nic_planned
  local want_addr="$_BGC_WANT_ADDR" nic_addr="$_BGC_NIC_ADDR" fw_addr="$_BGC_FW_ADDR"
  local att_addr="$_BGC_ATT_ADDR" nic_ip="$_BGC_NIC_IP"
  local nic_ip_ok="$BGC_NIC_IP_OK" fw_rules="$BGC_FW_RULES" fw_unreadable="$BGC_FW_UNREADABLE"
  local fw_apply_to="$BGC_FW_APPLY_TO" att_labels="$BGC_ATT_LABELS" inline_fw="$BGC_INLINE_FW" att_ok="$BGC_ATT_OK"
  plan_gate_assert_numeric "$g" "nic_ip_ok=${nic_ip_ok}" "fw_rules=${fw_rules}" "fw_unreadable=${fw_unreadable}" \
    "fw_apply_to=${fw_apply_to}" "att_labels=${att_labels}" "inline_fw=${inline_fw}" "att_ok=${att_ok}" || return 1
  if [[ "$nic_ip_ok" -ne 1 ]]; then
    nic_planned=$(jq -r --arg a "$nic_addr" '[.resource_changes[] | select(.address == $a) | (.change.after.ip // "unknown at plan time") | tostring][0] // "none"' < "$plan_json" 2>/dev/null)
    echo "${g}: ABORT — ${nic_addr} does not pin the private IP ${nic_ip} (planned: ${nic_planned}). bastion.tf fixes local.bastion_private_ip at ${nic_ip}; any other or unknown address means the configuration drifted."
    return 1
  fi
  if [[ "$inline_fw" -ne 0 ]]; then
    echo "${g}: ABORT — the plan sets firewall_ids inline on ${want_addr}. The bastion's firewall is bound by ${att_addr}, whose binding this gate reads; an inline list bypasses it."
    return 1
  fi
  if [[ "$fw_unreadable" -ne 0 ]]; then
    echo "${g}: ABORT — FIREWALL CONTENT UNREADABLE: the plan does not disclose ${fw_addr}'s rule set (no rule key, an unknown rule leaf, or a non-array rule). A rule set the gate cannot read is not evidence of zero rules."
    return 1
  fi
  if [[ "$fw_rules" -ne 0 ]]; then
    echo "${g}: ABORT — FIREWALL CONTENT: ${fw_addr} carries ${fw_rules} inbound rule(s); it must stay a zero-rule deny-all (F8). Nothing connects to the bastion in step 2."
    return 1
  fi
  if [[ "$fw_apply_to" -ne 0 ]]; then
    echo "${g}: ABORT — LABEL BINDING: ${fw_addr} sets apply_to (or the plan leaves it unknown). A firewall-side binding reaches servers by label or id outside ${att_addr}; the bastion's firewall is bound only there."
    return 1
  fi
  if [[ "$att_labels" -ne 0 ]]; then
    echo "${g}: ABORT — LABEL BINDING: ${att_addr} sets label_selectors (or the plan leaves them unknown). A label selector binds the deny-all firewall to every server carrying that label, which the server-id check cannot see."
    return 1
  fi
  if [[ "$att_ok" -ne 1 ]]; then
    echo "${g}: ABORT — ${att_addr} does not end this plan binding ${fw_addr} to exactly ${want_addr} (read from the plan's configuration references; a missing configuration block cannot be read and refuses). Without that binding the bastion boots with its public IPv4 behind no Hetzner firewall."
    return 1
  fi
  return 0
}
