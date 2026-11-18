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
_BHBG_LIST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bastion-resources.txt"
# has_unknown: true when any leaf of an after_unknown subtree is `true` (an unknown value).
_BHBG_JQ_UNKNOWN='def has_unknown: if type == "boolean" then . elif type == "array" or type == "object" then any(.[]; has_unknown) else false end;'

bastion_host_birth_gate() {
  local plan_json="${1:-}" g="bastion_host_birth_gate"
  local list="$_BHBG_LIST" allow_json
  local want_addr="hcloud_server.bastion" key_addr="tls_private_key.bastion_host_ssh"
  local nic_addr="hcloud_server_network.bastion" fw_addr="hcloud_firewall.bastion"
  local att_addr="hcloud_firewall_attachment.bastion" nic_ip="10.0.1.70"
  local creates destroys created_addr out_of_scope key_touched nic_creates nic_ip_ok fw_rules fw_unreadable
  local fw_apply_to att_labels inline_fw att_ok offenders a present nic_planned

  plan_gate_assert_readable     "$g" "$plan_json" || return 1
  plan_gate_assert_classifiable "$g" "$plan_json" || return 1

  if [[ ! -s "$list" ]]; then
    echo "${g}: ABORT — the allow-set list ${list} (bastion-resources) is missing or empty. Fail-closed: without it the gate cannot say what this birth may change."
    return 1
  fi
  allow_json=$(grep -vE '^[[:space:]]*(#|$)' "$list" | jq -R . | jq -sc .) || allow_json=""
  if [[ -z "$allow_json" || "$allow_json" == "[]" ]]; then
    echo "${g}: ABORT — the allow-set list ${list} (bastion-resources) names no address. Fail-closed."
    return 1
  fi
  for a in "$want_addr" "$key_addr" "$nic_addr" "$fw_addr" "$att_addr"; do
    if ! jq -e --arg a "$a" 'index($a) != null' <<<"$allow_json" >/dev/null 2>&1; then
      echo "${g}: ABORT — ${list} (bastion-resources) does not list ${a}, which this gate grades. The list and the gate's arms have drifted; fix the list, never this check."
      return 1
    fi
  done

  creates=$(jq '[.resource_changes[] | select(.type == "hcloud_server") | select(.change.actions | index("create"))] | length' < "$plan_json" 2>/dev/null)
  destroys=$(jq '[.resource_changes[] | select(.change.actions | index("delete") or index("forget"))] | length' < "$plan_json" 2>/dev/null)
  out_of_scope=$(jq --argjson allow "$allow_json" '[.resource_changes[]
    | select(.change.actions | any(. != "no-op" and . != "read"))
    | select(IN(.address; $allow[]) | not)] | length' < "$plan_json" 2>/dev/null)
  key_touched=$(jq --arg a "$key_addr" '[.resource_changes[] | select(.address == $a)
    | select(.change.actions | any(. == "update" or . == "delete" or . == "forget"))] | length' < "$plan_json" 2>/dev/null)
  nic_creates=$(jq --arg a "$nic_addr" '[.resource_changes[] | select(.address == $a) | select(.change.actions == ["create"])] | length' < "$plan_json" 2>/dev/null)
  nic_ip_ok=$(jq --arg a "$nic_addr" --arg ip "$nic_ip" "$_BHBG_JQ_UNKNOWN"'[.resource_changes[] | select(.address == $a)
    | select(.change.actions == ["create"]) | select(.change.after.ip == $ip)
    | select((.change.after_unknown | type) == "object" and (((.change.after_unknown.ip // false) | has_unknown) | not))] | length' < "$plan_json" 2>/dev/null)
  # Label bindings: any non-empty value, an unknown leaf, or no after_unknown object to say it is known.
  fw_apply_to=$(jq --arg a "$fw_addr" "$_BHBG_JQ_UNKNOWN"'[.resource_changes[] | select(.address == $a) | select(.change.actions | any(. != "read"))
    | select(((.change.after.apply_to? // []) != [])
          or ((.change.after_unknown | type) != "object")
          or ((.change.after_unknown.apply_to // false) | has_unknown))] | length' < "$plan_json" 2>/dev/null)
  att_labels=$(jq --arg a "$att_addr" "$_BHBG_JQ_UNKNOWN"'[.resource_changes[] | select(.address == $a) | select(.change.actions | any(. != "read"))
    | select(((.change.after.label_selectors? // []) != [])
          or ((.change.after_unknown | type) != "object")
          or ((.change.after_unknown.label_selectors // false) | has_unknown))] | length' < "$plan_json" 2>/dev/null)
  fw_rules=$(jq --arg a "$fw_addr" '[.resource_changes[] | select(.address == $a) | select(.change.actions | any(. != "read"))
    | if ((.change.after.rule // null) | type) == "array" then (.change.after.rule | length) else 0 end] | add // 0' < "$plan_json" 2>/dev/null)
  # Unreadable = the plan does not disclose the rule set: no object after, no `rule` key, no
  # after_unknown object, an unknown leaf anywhere under after_unknown.rule, or a non-array rule.
  fw_unreadable=$(jq --arg a "$fw_addr" "$_BHBG_JQ_UNKNOWN"'
    [.resource_changes[] | select(.address == $a) | select(.change.actions | any(. != "read"))
    | select(((.change.after | type) != "object")
          or ((.change.after | has("rule")) | not)
          or ((.change.after_unknown | type) != "object")
          or ((.change.after_unknown.rule // false) | has_unknown)
          or ((.change.after.rule | type) != "array"))] | length' < "$plan_json" 2>/dev/null)
  inline_fw=$(jq --arg a "$want_addr" '
    ([.configuration.root_module.resources[]? | select(.address == $a) | ((.expressions // {}) | has("firewall_ids"))] | any) as $cfg
    | [.resource_changes[] | select(.address == $a)
    | select((((.change.after.firewall_ids // []) | length) > 0) or $cfg)] | length' < "$plan_json" 2>/dev/null)
  att_ok=$(jq --arg a "$att_addr" '
    ([.configuration.root_module.resources[]? | select(.address == $a) | .expressions // {}] | first // {}) as $e
    | (($e.server_ids.references // []) | sort) as $srv
    | (($e.firewall_id.references // []) | sort) as $fw
    | [.resource_changes[] | select(.address == $a)
    | select(.change.actions | all(. == "create" or . == "update" or . == "no-op"))
    | select($srv == ["hcloud_server.bastion", "hcloud_server.bastion.id"])
    | select($fw == ["hcloud_firewall.bastion", "hcloud_firewall.bastion.id"])
    | select((((.change.after.server_ids // []) | length) == 1) or ((.change.after_unknown.server_ids // false) == true))] | length' < "$plan_json" 2>/dev/null)

  plan_gate_assert_numeric "$g" "creates=${creates}" "destroys=${destroys}" "out_of_scope=${out_of_scope}" \
    "key_touched=${key_touched}" "nic_creates=${nic_creates}" "nic_ip_ok=${nic_ip_ok}" "fw_rules=${fw_rules}" \
    "fw_unreadable=${fw_unreadable}" "fw_apply_to=${fw_apply_to}" "att_labels=${att_labels}" \
    "inline_fw=${inline_fw}" "att_ok=${att_ok}" || return 1

  echo "${g}: host_creates=${creates} destroys=${destroys} out_of_scope=${out_of_scope} key_touched=${key_touched} nic_creates=${nic_creates} nic_ip_ok=${nic_ip_ok} fw_rules=${fw_rules} fw_unreadable=${fw_unreadable} fw_apply_to=${fw_apply_to} att_labels=${att_labels} inline_fw=${inline_fw} att_ok=${att_ok}"

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
