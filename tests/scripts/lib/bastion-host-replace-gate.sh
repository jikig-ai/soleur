# shellcheck shell=bash
# Sourced plan gate for the bastion-host-replace dispatch (#12879, Guard 1; ADR-327 step 2b).
#
# THE ONLY CHECK BETWEEN THIS PLAN AND A DESTROY. The per-PR apply excludes every bastion address
# (OPERATOR_APPLIED_EXCLUSIONS) and the dispatch job's `if:` is exclusive with it, so nothing upstream
# grades this plan. Every arm below is load-bearing.
#
# PASS (rc=0) iff the plan matches ONE of two arms:
#
#   replace   (pin = a server id)  the dispatch pin, the Hetzner API and the plan's before.id name the
#             same ONE server (exactly one `soleur-bastion`, label role=bastion), compared as strings:
#             before.id is a string in plan JSON, the API id a number. The plan destroys exactly it
#             and recreates it; its NIC (before.server_id = pin, before.ip 10.0.1.70) is recreated,
#             or a bare create after a partial replace; its firewall attachment updates from
#             before.server_ids [pin], or from [] / null after a partial replace that never re-bound
#             it, or is a bare create (before null), and binds the NEW, still-unknown id (Q-R2).
#   recovery  (pin = none)  no soleur-bastion in the API AND none in prior_state: a bare create. The
#             attachment is a bare create, or an update from before.server_ids [] / null (Q-R1).
#             This departs from web-host-replace-gate.sh, which routes a bare create to the birth
#             route: here only this gate reads the API, so only it can prove zero servers (ADR-327
#             2026-11-28 addendum).
#
# On BOTH arms (Q-R1): an attachment update is graded on its BEFORE as well as its after. Its
# before.server_ids and before.label_selectors must both be present, each an array or null, and
# label_selectors empty: an update away from any other binding strips the deny-all firewall from
# another server; an update from an empty binding removes nothing. A missing before, a missing key or
# a value that is neither an array nor null is ATTACHMENT BEFORE UNREADABLE, never a pass.
#
# On BOTH arms: the host key and the firewall are exactly no-op (a key rotation is #13116), every other
# bastion-resources.txt member is exactly no-op (so an address step 3 or #13113 adds is never
# destroy-eligible by default), nothing outside the list changes, the replacement is cx23 /
# soleur-bastion / role=bastion, and the create-side checks shared with the birth gate hold
# (bastion-gate-common.sh: NIC IP pin, inline firewall_ids, zero-rule firewall, no label binding, the
# attachment binding read from configuration references).
#
# Lost state while Hetzner still holds soleur-bastion is REFUSED (#13117, which depends on #13116:
# losing state loses the host key). There is no third arm.
#
# PER-ADDRESS ACTIONS (the allow-set is bastion-resources.txt beside this file; no override):
#   hcloud_server.bastion               replace: ["delete","create"]           recovery: ["create"]
#   hcloud_server_network.bastion       replace: ["delete","create"]|["create"] recovery: ["create"]
#   hcloud_firewall_attachment.bastion  replace: ["update"]|["create"]         recovery: ["update"]|["create"]
#   every other listed address          ["no-op"]
#
# OUTPUT. Only addresses, actions, ids and attribute names are printed, never a value: on a replace the
# plan JSON carries the host's private key in clear text (the key is a no-op, so prior_state and its
# change hold every private_key_* field). API strings are printed through @json; ids only once they
# match ^[0-9]+$. Every ABORT ends with "NOTHING HAS BEEN DESTROYED — this gate runs before the apply."
#
# Usage:  source tests/scripts/lib/bastion-host-replace-gate.sh
#         bastion_host_replace_gate <plan-json> <expected-id|none> <hetzner-servers-json-file>  # 0 PASS, 1 ABORT
#         bastion_replace_identity <pin|none> <hetzner-servers-json-file> <before-id|none>     # the TOCTOU re-check
#         bastion_replace_next_dispatch <pre-ids|none> <hetzner-servers-json-file|-> <0|1|unread>
#
# The literal addresses, IP, name, role and server type are bastion-gate-common.sh's _BGC_* constants.

# shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _BHRG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_BHRG_DIR}/plan-gate-preamble.sh"
fi
# The create-side checks shared with bastion-host-birth-gate.sh (R3): sourced UNCONDITIONALLY from this
# file's own directory (see that file's header); a failed source makes the calls return 127 and refuse.
# shellcheck source=tests/scripts/lib/bastion-gate-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bastion-gate-common.sh"
_BHRG_LIST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bastion-resources.txt"
# The one copy of the dispatch command template (_bbv_dispatch_line), loaded by next_dispatch only.
_BHRG_BBV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/lib/bastion-boot-verify.sh"
_BHRG_TAIL="NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Next: dispatch with plan_only=true and read the summary's live-id and next-dispatch lines."

_bhrg_abort() { echo "${1}: ABORT — ${2} ${_BHRG_TAIL}"; }

# _bhrg_pin_ok <pin>: the pin's shape, under LC_ALL=C (a locale must not widen [0-9]).
_bhrg_pin_ok() { local LC_ALL=C; [[ "${1:-}" =~ ^([1-9][0-9]{0,11}|none)$ ]]; }

# bastion_replace_identity <pin|none> <servers-doc> <before-id|none> [gate-name]
# The identity both the gate and the TOCTOU step check: count 1, the exact name, role bastion, and
# id == pin == before.id; or count 0 and no before for `none`. Any unreadable document refuses.
bastion_replace_identity() {
  local pin="${1:-}" doc="${2:-}" before="${3:-}" g="${4:-bastion_replace_identity}" n ids
  if ! _bhrg_pin_ok "$pin"; then
    _bhrg_abort "$g" "pin argument malformed: it must be a Hetzner server id (^[1-9][0-9]{0,11}\$) or the literal none."
    return 1
  fi
  if [[ -z "$doc" || ! -f "$doc" ]] || ! jq -e '.servers | arrays' < "$doc" >/dev/null 2>&1; then
    _bhrg_abort "$g" "HETZNER DOCUMENT UNREADABLE: the server read has no .servers array (missing, unparseable or not an array). An unreadable answer is not zero servers."
    return 1
  fi
  n=$(jq '.servers | length' < "$doc" 2>/dev/null)
  plan_gate_assert_numeric "$g" "api_count=${n}" || return 1
  ids=$(jq -r '[.servers[] | (.id | tostring) | if test("^[0-9]+$") then . else "<non-numeric>" end] | join(",")' < "$doc" 2>/dev/null)
  if [[ "$pin" == none ]]; then
    if [[ "$n" -ne 0 ]]; then
      _bhrg_abort "$g" "LOST STATE: pin none but the Hetzner project still holds ${n} soleur-bastion server(s) (ids ${ids:-none}). This route refuses lost state while a server is live: that is #13117, which depends on #13116 (losing state loses the host key). Do not use the birth route either."
      return 1
    fi
    if [[ "$before" != none ]]; then
      _bhrg_abort "$g" "RECOVERY REFUSED: pin none but the plan's hcloud_server.bastion carries a before (state holds it). Pin the id the API reports instead."
      return 1
    fi
    return 0
  fi
  if [[ "$n" -gt 1 ]]; then
    _bhrg_abort "$g" "API COUNT: ${n} servers are named soleur-bastion (ids ${ids}); refusing to guess which one this dispatch may destroy. Inspect the Hetzner project now."
    return 1
  fi
  if [[ "$n" -eq 0 ]]; then
    _bhrg_abort "$g" "IDENTITY MISMATCH: pin=${pin} but the Hetzner project holds no soleur-bastion (api_ids=none, before.id=${before}). If a prior replace destroyed it, re-dispatch with expected_bastion_server_id=none."
    return 1
  fi
  if ! jq -e --arg n "$_BGC_NAME" '.servers[0].name == $n' < "$doc" >/dev/null 2>&1; then
    _bhrg_abort "$g" "API NAME MISMATCH: the server the API returned is named $(jq -c '.servers[0].name | @json' < "$doc" 2>/dev/null), not exactly \"${_BGC_NAME}\" (the ?name= filter is never trusted alone)."
    return 1
  fi
  if ! jq -e --arg r "$_BGC_ROLE" '.servers[0].labels.role == $r' < "$doc" >/dev/null 2>&1; then
    _bhrg_abort "$g" "API ROLE MISMATCH: soleur-bastion's role label is $(jq -c '.servers[0].labels.role | @json' < "$doc" 2>/dev/null), not \"${_BGC_ROLE}\"."
    return 1
  fi
  if ! jq -e '(.servers[0].id | type) == "number" and (.servers[0].id | tostring | test("^[0-9]+$"))' < "$doc" >/dev/null 2>&1; then
    _bhrg_abort "$g" "API ID NOT NUMERIC: the API's server id is not a number."
    return 1
  fi
  if ! jq -e --arg pin "$pin" --arg b "$before" '(.servers[0].id | tostring) == $pin and $pin == $b' < "$doc" >/dev/null 2>&1; then
    _bhrg_abort "$g" "IDENTITY MISMATCH: pin=${pin} api_ids=${ids} before.id=${before}. All three must name the same server: the dispatch input, the live Hetzner API and the plan's hcloud_server.bastion before.id."
    return 1
  fi
  return 0
}

bastion_host_replace_gate() {
  local plan_json="${1:-}" pin="${2-}" doc="${3:-}" g="bastion_host_replace_gate"
  local allow_json arm before_id prior_has out_of_scope bad_actions missing nic_before_ok att_before_ok
  local att_before_unreadable att_before_labels att_rebound shape_type shape_name shape_role offenders api_ids
  local srv="$_BGC_WANT_ADDR" key="$_BGC_KEY_ADDR" nic="$_BGC_NIC_ADDR" att="$_BGC_ATT_ADDR" ip="$_BGC_NIC_IP"
  if ! _bhrg_pin_ok "$pin"; then
    _bhrg_abort "$g" "pin argument malformed: it must be a Hetzner server id (^[1-9][0-9]{0,11}\$) or the literal none."
    return 1
  fi
  arm=replace
  [[ "$pin" == none ]] && arm=recovery

  plan_gate_assert_readable     "$g" "$plan_json" || { _bhrg_abort "$g" "the plan is unreadable (the line above)."; return 1; }
  plan_gate_assert_classifiable "$g" "$plan_json" || { _bhrg_abort "$g" "the plan is unclassifiable (the line above)."; return 1; }
  bastion_gate_load_allow "$g" "$_BHRG_LIST" || { _bhrg_abort "$g" "the allow-set list refused (the line above)."; return 1; }
  allow_json="$BASTION_GATE_ALLOW_JSON"

  before_id=$(jq -r --arg s "$srv" '[.resource_changes[] | select(.address == $s) | .change.before | select(type == "object") | .id | select(. != null) | tostring][0] // "none"' < "$plan_json" 2>/dev/null)
  [[ -n "$before_id" ]] || before_id=unread
  prior_has=$(jq --arg s "$srv" '[(.prior_state // {}) | .. | objects | select(.address? == $s and has("values"))] | length' < "$plan_json" 2>/dev/null)
  out_of_scope=$(jq --argjson allow "$allow_json" '[.resource_changes[]
    | select(.change.actions | any(. != "no-op" and . != "read"))
    | select(IN(.address; $allow[]) | not)] | length' < "$plan_json" 2>/dev/null)
  # The per-address action table (header). A listed address must appear exactly once, with an allowed set.
  bad_actions=$(jq -r --arg arm "$arm" --argjson allow "$allow_json" --arg s "$srv" --arg n "$nic" --arg t "$att" '
    def allowed($a):
      if $a == $s then (if $arm == "replace" then [["delete","create"]] else [["create"]] end)
      elif $a == $n then (if $arm == "replace" then [["delete","create"],["create"]] else [["create"]] end)
      elif $a == $t then [["update"],["create"]]
      else [["no-op"]] end;
    . as $p | [ $allow[] as $a | [$p.resource_changes[] | select(.address == $a)] as $e
      | select(($e | length) == 1 and (any(allowed($a)[]; . == $e[0].change.actions) | not))
      | "\($a) planned \($e[0].change.actions | tojson)" ] | join("; ")' < "$plan_json" 2>/dev/null) || bad_actions="<jq failed>"
  missing=$(jq -r --argjson allow "$allow_json" '. as $p | [ $allow[] as $a | select(([$p.resource_changes[] | select(.address == $a)] | length) != 1) | $a ] | join(", ")' < "$plan_json" 2>/dev/null) || missing="<jq failed>"
  # Replace arm: the NIC record the replace deletes is pinned to the same server.
  nic_before_ok=$(jq --arg pin "$pin" --arg n "$nic" --arg ip "$ip" '[.resource_changes[] | select(.address == $n)
    | select((.change.actions != ["delete","create"])
          or (((.change.before.server_id? // null) | tostring) == $pin and (.change.before.ip? // null) == $ip))] | length' < "$plan_json" 2>/dev/null)
  # Both arms (Q-R1, Q-R2): the attachment's BEFORE, ONE counter (att_before_ok, required == 1). A bare
  # create carries no before; an update's before names both keys, label_selectors [] or null, and
  # server_ids [] or null or, on the replace arm only, exactly [pin]. The two counters after it only
  # choose the ABORT message (UNREADABLE, LABEL BINDING, else PIN); they never pass a plan.
  att_before_ok=$(jq --arg pin "$pin" --arg arm "$arm" --arg t "$att" '[.resource_changes[] | select(.address == $t)
    | select((.change.actions == ["create"] and .change.before == null)
          or (.change.actions == ["update"] and (.change.before | type) == "object"
              and (.change.before | has("server_ids") and has("label_selectors"))
              and (.change.before.label_selectors | . == null or . == [])
              and (.change.before.server_ids | . == null or . == []
                   or ($arm == "replace" and type == "array" and map(tostring) == [$pin]))))] | length' < "$plan_json" 2>/dev/null)
  att_before_unreadable=$(jq --arg t "$att" '[.resource_changes[] | select(.address == $t)
    | select((.change.actions == ["create"] and .change.before != null)
          or (.change.actions == ["update"] and (.change.before
               | if type != "object" then true
                 elif (has("server_ids") and has("label_selectors")) | not then true
                 else ([.server_ids, .label_selectors] | any(type != "array" and type != "null")) end)))] | length' < "$plan_json" 2>/dev/null)
  att_before_labels=$(jq --arg t "$att" '[.resource_changes[] | select(.address == $t) | select(.change.actions == ["update"])
    | select(((.change.before | objects | .label_selectors) // null) | (. != null and . != []))] | length' < "$plan_json" 2>/dev/null)
  # The attachment binds the NEW server: its server_ids stay unknown at plan time (a known old id is a no-op re-bind).
  att_rebound=$(jq --arg t "$att" '[.resource_changes[] | select(.address == $t)
    | select(((.change.after_unknown.server_ids? // null) == true)
          or (((.change.after_unknown.server_ids? // null) == [true]) and ((.change.after.server_ids? // null) == [null])))] | length' < "$plan_json" 2>/dev/null)
  shape_type=$(jq --arg s "$srv" --arg v "$_BGC_TYPE" '[.resource_changes[] | select(.address == $s) | select(.change.after.server_type? == $v)] | length' < "$plan_json" 2>/dev/null)
  shape_name=$(jq --arg s "$srv" --arg v "$_BGC_NAME" '[.resource_changes[] | select(.address == $s) | select(.change.after.name? == $v)] | length' < "$plan_json" 2>/dev/null)
  shape_role=$(jq --arg s "$srv" --arg v "$_BGC_ROLE" '[.resource_changes[] | select(.address == $s) | select(.change.after.labels.role? == $v)] | length' < "$plan_json" 2>/dev/null)
  bastion_gate_create_side_measure "$g" "$plan_json" || { _bhrg_abort "$g" "a shared counter did not evaluate (the line above)."; return 1; }

  plan_gate_assert_numeric "$g" "prior_has=${prior_has}" "out_of_scope=${out_of_scope}" "nic_before_ok=${nic_before_ok}" \
    "att_before_ok=${att_before_ok}" "att_before_unreadable=${att_before_unreadable}" "att_before_labels=${att_before_labels}" \
    "att_rebound=${att_rebound}" "shape_type=${shape_type}" "shape_name=${shape_name}" \
    "shape_role=${shape_role}" || { _bhrg_abort "$g" "a counter did not evaluate (the line above)."; return 1; }

  api_ids=$(jq -r '[.servers[]? | (.id | tostring) | if test("^[0-9]+$") then . else "<non-numeric>" end] | join(",")' < "$doc" 2>/dev/null) || api_ids=unread
  echo "${g}: arm=${arm} pin=${pin} api_ids=${api_ids:-none} before.id=${before_id} prior_has=${prior_has} out_of_scope=${out_of_scope} nic_before_ok=${nic_before_ok} att_before_ok=${att_before_ok} att_before_unreadable=${att_before_unreadable} att_before_labels=${att_before_labels} att_rebound=${att_rebound} shape=${shape_type}/${shape_name}/${shape_role} nic_ip_ok=${BGC_NIC_IP_OK} fw_rules=${BGC_FW_RULES} fw_unreadable=${BGC_FW_UNREADABLE} fw_apply_to=${BGC_FW_APPLY_TO} att_labels=${BGC_ATT_LABELS} inline_fw=${BGC_INLINE_FW} att_ok=${BGC_ATT_OK}"

  bastion_replace_identity "$pin" "$doc" "$before_id" "$g" || return 1
  if [[ "$arm" == recovery ]]; then
    if [[ "$prior_has" -ne 0 ]]; then
      _bhrg_abort "$g" "RECOVERY REFUSED: pin none but prior_state still holds ${srv}. The recovery arm needs no server in state AND none in the API; pin the id the API reports."
      return 1
    fi
  fi
  if [[ "$out_of_scope" -ne 0 ]]; then
    offenders=$(jq -r --argjson allow "$allow_json" '[.resource_changes[] | select(.change.actions | any(. != "no-op" and . != "read"))
      | select(IN(.address; $allow[]) | not) | "\(.address) \(.change.actions | tojson)"] | .[0:10] | join(", ")' < "$plan_json" 2>/dev/null)
    _bhrg_abort "$g" "${out_of_scope} out-of-scope change(s): ${offenders}. A bastion replace changes only the addresses in bastion-resources.txt."
    return 1
  fi
  if [[ -n "$missing" ]]; then
    _bhrg_abort "$g" "${missing} is not in the plan exactly once. Every bastion address must appear in a scoped replace: one missing means the -target set is mis-scoped."
    return 1
  fi
  if [[ -n "$bad_actions" ]]; then
    if [[ "$bad_actions" == *"$key"* ]]; then
      _bhrg_abort "$g" "ACTION NOT ALLOWED: ${bad_actions}. The host key is exactly no-op on this route (ADR-327, F5); a deliberate rotation is #13116 and a key regenerated after lost state is #13117."
    else
      _bhrg_abort "$g" "ACTION NOT ALLOWED: ${bad_actions} (arm ${arm}; the per-address table is in this gate's header)."
    fi
    return 1
  fi
  if [[ "$arm" == replace ]]; then
    if [[ "$nic_before_ok" -ne 1 ]]; then
      _bhrg_abort "$g" "NIC BEFORE PIN: ${nic}'s delete is not of the pinned server's NIC (before.server_id must equal ${pin} and before.ip ${ip}). A NIC mapped onto another server would detach that server from the private network."
      return 1
    fi
  fi
  # The attachment's before, on BOTH arms (Q-R1). The message: unreadable, then a label binding, then the ids.
  if [[ "$att_before_ok" -ne 1 ]]; then
    if [[ "$att_before_unreadable" -ne 0 ]]; then
      _bhrg_abort "$g" "ATTACHMENT BEFORE UNREADABLE: ${att}'s update carries no before object, lacks before.server_ids or before.label_selectors, or holds a value that is neither an array nor null (or a create carries a before). A before the gate cannot read is not evidence of an empty binding."
    elif [[ "$att_before_labels" -ne 0 ]]; then
      _bhrg_abort "$g" "ATTACHMENT BEFORE LABEL BINDING: ${att}'s before.label_selectors is not empty. The update would remove that selector and strip the deny-all firewall from every server carrying the label."
    elif [[ "$arm" == replace ]]; then
      _bhrg_abort "$g" "ATTACHMENT BEFORE PIN: ${att}'s before.server_ids is not [${pin}], [] or null. An attachment mapped onto another server would strip that server's firewall binding."
    else
      _bhrg_abort "$g" "ATTACHMENT BEFORE PIN: ${att}'s before.server_ids is not [] or null on the recovery arm (no bastion exists, so any id it holds is another server's). The update would strip that server's firewall binding."
    fi
    return 1
  fi
  # The create-side arms shared with the birth gate (NIC IP pin, inline firewall_ids, firewall content,
  # label bindings, the attachment binding): bastion-gate-common.sh.
  bastion_gate_create_side_judge "$g" "$plan_json" || { _bhrg_abort "$g" "a shared create-side check refused (the line above)."; return 1; }
  if [[ "$att_rebound" -ne 1 ]]; then
    _bhrg_abort "$g" "ATTACHMENT NOT RE-BOUND: ${att}'s after.server_ids is not the new server's still-unknown id ([null] with after_unknown [true], or wholly unknown). A known id is the old server's."
    return 1
  fi
  if [[ "$shape_type" -ne 1 ]]; then
    _bhrg_abort "$g" "REPLACEMENT SHAPE: after.server_type of ${srv} is not ${_BGC_TYPE}."
    return 1
  fi
  if [[ "$shape_name" -ne 1 ]]; then
    _bhrg_abort "$g" "REPLACEMENT SHAPE: after.name of ${srv} is not ${_BGC_NAME}."
    return 1
  fi
  if [[ "$shape_role" -ne 1 ]]; then
    _bhrg_abort "$g" "REPLACEMENT SHAPE: after.labels.role of ${srv} is not ${_BGC_ROLE}."
    return 1
  fi

  if [[ "$arm" == replace ]]; then
    echo "${g}: PASS — arm=replace: destroy and recreate soleur-bastion server ${pin} (pin = API id = before.id), its NIC recreated at 10.0.1.70, its zero-rule firewall re-bound to the new server by id, host key and firewall no-op, 0 out-of-scope changes."
  else
    echo "${g}: PASS — arm=recovery: create soleur-bastion (no server in the Hetzner project, none in state), its NIC at 10.0.1.70, its zero-rule firewall bound to it by id, host key and firewall no-op, 0 out-of-scope changes."
  fi
  return 0
}

# bastion_replace_next_dispatch <pre-ids|none> <servers-doc|-> <state-server: 0|1|unread>
# The one ready-to-run line the always-run summary prints, from a FRESH read (never a guess):
#   no server anywhere            -> expected_bastion_server_id=none
#   only a new id (not pre-apply) -> that id
#   only a pre-apply id           -> the same pin
# A failed read ("-"), a state read that failed, two servers, a non-numeric id, or the API and state
# disagreeing print a reason and no line.
bastion_replace_next_dispatch() {
  local pre="${1:-}" doc="${2:-}" state="${3:-}" n id line
  [[ "$pre" == none ]] && pre=""
  if [[ "$doc" == - || -z "$doc" || ! -f "$doc" ]] || ! jq -e '.servers | arrays' < "$doc" >/dev/null 2>&1; then
    echo "next dispatch: unread (API read failed); no line to copy"
    return 0
  fi
  if [[ "$state" != 0 && "$state" != 1 ]]; then
    echo "::error::bastion-host-replace: post-failure state read FAILED; no next dispatch"
    return 0
  fi
  n=$(jq '.servers | length' < "$doc" 2>/dev/null)
  if [[ "$n" == 0 ]]; then
    if [[ "$state" == 1 ]]; then
      echo "next dispatch: none applies (state holds hcloud_server.bastion but the Hetzner project shows no soleur-bastion); no line to copy. Read bastion-host.md 'Recovering a failed replace'."
      return 0
    fi
    id=none
  elif [[ "$n" == 1 ]]; then
    id=$(jq -r '.servers[0].id | tostring' < "$doc" 2>/dev/null)
    if ! (LC_ALL=C; [[ "$id" =~ ^[1-9][0-9]{0,11}$ ]]); then
      echo "next dispatch: the API's server id is not numeric; no line to copy"
      return 0
    fi
  else
    echo "next dispatch: ${n} soleur-bastion servers exist; refusing to guess, no line to copy"
    return 0
  fi
  if ! declare -F _bbv_dispatch_line >/dev/null 2>&1 && ! source "$_BHRG_BBV" >/dev/null 2>&1; then
    echo "next dispatch: the dispatch template (scripts/lib/bastion-boot-verify.sh) did not load; no line to copy"
    return 0
  fi
  line="$(_bbv_dispatch_line "$id")"
  if [[ "$id" != none && " ${pre} " == *" ${id} "* ]]; then
    echo "next dispatch (the pre-apply server ${id} is still the live one; same pin; rehearse, then re-run without plan_only): ${line}"
  elif [[ "$id" == none ]]; then
    echo "next dispatch (no soleur-bastion exists: the recovery arm; rehearse, then re-run without plan_only): ${line}"
  else
    echo "next dispatch (a new server ${id} exists; rehearse, then re-run without plan_only): ${line}"
  fi
  return 0
}
