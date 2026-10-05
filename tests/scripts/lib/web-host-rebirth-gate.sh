# shellcheck shell=bash
# Sourced plan gate for the single-use web-2 volume REBIRTH (#9372, ADR-263 addendum).
#
# THE THIRD SIBLING. web-host-birth-gate.sh requires zero destroys; web-host-replace-gate.sh requires
# the workspaces volume to SURVIVE; web2_retire_allow (destroy-guard-filter-web-platform.jq) REQUIRES
# the volume destroy. None of those allow-sets describes this operation, and each one's header forbids
# reusing it for another. This gate grades the operation's own contract:
#
#   `pre`        a dry plan on CURRENT state, graded before anything is touched. The server, its private
#                NIC and its volume attachment are replaced; the (empty, plaintext) volume is a NO-OP and
#                is therefore NOT destroyed by this plan; the fleet firewall attachment only UPDATES.
#   `post`       the real plan, taken AFTER the empty volume was deleted through the Hetzner API and
#                forgotten from state. Same replacement, but the volume is CREATED (raw) and so is its
#                attachment. This plan cannot exist before the destructive step, which is why `pre` exists.
#   `post-heal`  a re-dispatch after an apply died with the raw volume already created: the volume is a
#                NO-OP (and must not be the pinned old one), its attachment may already exist.
#
# THE VOLUME IS NEVER DESTROYED BY TERRAFORM. `hcloud_volume.workspaces` carries prevent_destroy, and no
# arm of any mode permits a delete, forget or replace of it: allowed actions are compared as sorted SETS
# and must EQUAL an entry of the address's allow list, so a volume delete is unrepresentable rather than
# merely prohibited.
#
# EVERY DESTROY IS PINNED TO A PHYSICAL ID that the caller captured from Hetzner (never from the plan under
# test): the server's id and name, the NIC's server_id, the attachment's volume_id and server_id.
#
# FAIL CLOSED: a jq that errors inside any arm contributes a violation; an unreadable or unclassifiable
# plan aborts in the shared preamble; non-numeric ids abort.
#
# Usage: web_host_rebirth_gate <pre|post|post-heal> <plan.json> <host-key> <server-id> <volume-id>

_WEB_HOST_REBIRTH_LUKS_PINNED_KEY="web-1"
_WEB_HOST_REBIRTH_VOLUME_SIZE=20
_WEB_HOST_REBIRTH_VOLUME_LABEL_APP="soleur-web-platform"

if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _WHRB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${_WHRB_DIR}/plan-gate-preamble.sh"
fi

# The address -> allowed-action-sets table, shared by the allow-set arm and the requirement arm.
_WEB_HOST_REBIRTH_SPECS='def specs($mode; $k):
  [ {a: "hcloud_server.web[\"\($k)\"]",
     ok: (if $mode == "pre" then [["create","delete"]] else [["create","delete"],["create"]] end)},
    {a: "hcloud_server_network.web[\"\($k)\"]",
     ok: (if $mode == "pre" then [["create","delete"]] else [["create","delete"],["create"]] end)},
    {a: "hcloud_volume_attachment.workspaces[\"\($k)\"]",
     ok: (if $mode == "pre" then [["create","delete"],["create"]]
          elif $mode == "post" then [["create"]]
          else [["create"],["no-op"]] end)},
    {a: "hcloud_volume.workspaces[\"\($k)\"]",
     ok: (if $mode == "post" then [["create"]] else [["no-op"]] end)},
    {a: "hcloud_firewall_attachment.web", ok: [["update"]]} ];'

# Each arm prints one violation per line (nothing when clean). A jq failure prints a "jq-error" line.
_whrb_allow_set() { # <mode> <plan> <key>
  local out
  out=$(jq -r --arg mode "$1" --arg k "$3" "${_WEB_HOST_REBIRTH_SPECS}"'
    specs($mode; $k) as $sp
    | .resource_changes[]
    | . as $r
    | ($sp | map(select(.a == $r.address)) | first) as $s
    | ($r.change.actions | sort) as $act
    | if $s == null then
        (if ($act | any(. == "create" or . == "update" or . == "delete" or . == "forget"))
         then "out-of-scope: \($r.address) actions=\($act | tojson)" else empty end)
      elif ($s.ok | any(.[]; . == $act) | not) then
        "unexpected action: \($r.address) actions=\($act | tojson) (allowed \($s.ok | tojson))"
      else empty end' < "$2" 2>/dev/null) || { echo "jq-error: allow-set"; return 0; }
  [[ -z "$out" ]] || printf '%s\n' "$out"
}

_whrb_required() { # <mode> <plan> <key>
  local out
  out=$(jq -r --arg mode "$1" --arg k "$3" "${_WEB_HOST_REBIRTH_SPECS}"'
    . as $d
    | (specs($mode; $k)[] | .a) as $a
    | ([$d.resource_changes[] | select(.address == $a)] | length) as $n
    | (if $n != 1 then "missing: \($a) entries=\($n) (expected exactly 1)" else empty end),
      ( "hcloud_server.web[\"\($k)\"]" as $want
        | [$d.resource_changes[] | select(.type == "hcloud_server") | select(.change.actions | index("create"))] as $c
        | if ($c | length) != 1 or ($c[0].address != $want)
          then "server creates=\($c | length) address=\($c[0].address // "none") (expected exactly one create of \($want))"
          else empty end )' < "$2" 2>/dev/null) || { echo "jq-error: required"; return 0; }
  [[ -z "$out" ]] || printf '%s\n' "$out"
}

_whrb_reboot() { # <plan>
  local out
  out=$(jq -r '.resource_changes[]
    | select(.type == "hcloud_server")
    | select(.change.actions | index("update"))
    | "reboot: in-place update of \(.address) (placement/server_type changes power-cycle a live host)"' < "$1" 2>/dev/null) \
    || { echo "jq-error: reboot"; return 0; }
  [[ -z "$out" ]] || printf '%s\n' "$out"
}

_whrb_pin_server() { # <plan> <key> <server-id>
  local out
  out=$(jq -r --arg k "$2" --arg sid "$3" '
    .resource_changes[]
    | select(.change.actions | index("delete"))
    | if .address == "hcloud_server.web[\"\($k)\"]" then
        (if ((.change.before.id | tostring) != $sid) or (.change.before.name != "soleur-\($k)")
         then "pin: server destroy id=\(.change.before.id) name=\(.change.before.name) is not the captured server \($sid) / soleur-\($k)" else empty end)
      elif .address == "hcloud_server_network.web[\"\($k)\"]" then
        (if ((.change.before.server_id | tostring) != $sid)
         then "pin: NIC destroy server_id=\(.change.before.server_id) is not the captured server \($sid)" else empty end)
      else empty end' < "$1" 2>/dev/null) || { echo "jq-error: pin-server"; return 0; }
  [[ -z "$out" ]] || printf '%s\n' "$out"
}

_whrb_pin_volume() { # <mode> <plan> <key> <server-id> <volume-id>
  local out
  out=$(jq -r --arg mode "$1" --arg k "$3" --arg sid "$4" --arg vid "$5" '
    .resource_changes[]
    | if (.address == "hcloud_volume_attachment.workspaces[\"\($k)\"]") and (.change.actions | index("delete")) then
        (if ((.change.before.volume_id | tostring) != $vid) or ((.change.before.server_id | tostring) != $sid)
         then "pin: attachment destroy volume_id=\(.change.before.volume_id) server_id=\(.change.before.server_id) is not the pinned volume \($vid) on server \($sid)" else empty end)
      elif (.address == "hcloud_volume.workspaces[\"\($k)\"]") and $mode == "pre" then
        (if ((.change.before.id | tostring) != $vid)
         then "pin: the live volume id=\(.change.before.id) is not the pinned volume \($vid)" else empty end)
      elif (.address == "hcloud_volume.workspaces[\"\($k)\"]") and $mode == "post-heal" then
        (if ((.change.before.id | tostring) == $vid)
         then "pinned: the surviving volume is the pinned plaintext volume \($vid), which must already be gone" else empty end)
      else empty end' < "$2" 2>/dev/null) || { echo "jq-error: pin-volume"; return 0; }
  [[ -z "$out" ]] || printf '%s\n' "$out"
}

_whrb_raw_volume() { # <mode> <plan> <key>
  local out
  [[ "$1" == "pre" ]] && return 0
  out=$(jq -r --arg mode "$1" --arg k "$3" --argjson size "$_WEB_HOST_REBIRTH_VOLUME_SIZE" --arg app "$_WEB_HOST_REBIRTH_VOLUME_LABEL_APP" '
    "hcloud_volume.workspaces[\"\($k)\"]" as $a
    | [ .resource_changes[] | select(.address == $a) ] as $v
    | if ($v | length) != 1 then "volume entries=\($v | length)"
      else $v[0].change as $c
        | (if $mode == "post" then $c.after else $c.before end) as $o
        | ( if $mode == "post-heal" then
              (if ($o.format // null) != null then "volume not raw: format=\($o.format | tojson) on the surviving volume" else empty end)
            else
              (if ($c.after | type) != "object" then "volume not raw: format verdict after-not-object"
               elif $c.after_unknown == null then "volume not raw: format verdict after-unknown-absent"
               elif ($c.after_unknown | if type == "object" then ((.format // false) != false) else true end) then "volume not raw: format verdict format-unknown"
               elif ($c.after | has("format")) and ($c.after.format != null) then "volume not raw: format verdict format=\($c.after.format | tojson)"
               else empty end)
            end ),
          ( if ($o | type) != "object" then empty else
              ( (if $o.name != "soleur-web-platform-data-\($k)" then "volume name \($o.name) is not soleur-web-platform-data-\($k)" else empty end),
                (if $o.size != $size then "volume size \($o.size) is not \($size)" else empty end),
                (if $o.labels != {app: $app} then "volume labels \($o.labels | tojson) are not {app: \($app)}" else empty end) )
            end )
      end' < "$2" 2>/dev/null) || { echo "jq-error: raw-volume"; return 0; }
  [[ -z "$out" ]] || printf '%s\n' "$out"
}

web_host_rebirth_gate() {
  local mode="${1:-}" plan_json="${2:-}" host_key="${3:-}" server_id="${4:-}" volume_id="${5:-}"
  local viol="" nl=$'\n' count

  if [[ "$host_key" == "$_WEB_HOST_REBIRTH_LUKS_PINNED_KEY" ]]; then
    echo "web_host_rebirth_gate: ABORT — this path REFUSES ${host_key} by name. It is the LUKS-pinned live origin; this operation replaces the web-2 standby's EMPTY volume and nothing else. Fail-closed: no plan is read, no other arm runs."
    return 1
  fi

  case "$mode" in
    pre|post|post-heal) ;;
    *) echo "web_host_rebirth_gate: ABORT — mode must be one of pre, post, post-heal (got '${mode}')."; return 1 ;;
  esac
  if [[ -z "$host_key" ]]; then
    echo "web_host_rebirth_gate: ABORT — no host key supplied. The gate cannot verify WHICH host is being reborn without the request it grades against."
    return 1
  fi
  if [[ ! "$server_id" =~ ^[0-9]+$ ]]; then
    echo "web_host_rebirth_gate: ABORT — the captured server id must be numeric (got '${server_id}'). Every destroy is pinned to it."
    return 1
  fi
  if [[ ! "$volume_id" =~ ^[0-9]+$ ]]; then
    echo "web_host_rebirth_gate: ABORT — the pinned volume id must be numeric (got '${volume_id}'). Every volume reference is pinned to it."
    return 1
  fi

  plan_gate_assert_readable     "web_host_rebirth_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "web_host_rebirth_gate" "$plan_json" || return 1

  viol+="$(_whrb_allow_set "$mode" "$plan_json" "$host_key")${nl}"                          # GATE:ALLOW-SET
  viol+="$(_whrb_required "$mode" "$plan_json" "$host_key")${nl}"                           # GATE:REQUIRED
  viol+="$(_whrb_reboot "$plan_json")${nl}"                                                 # GATE:REBOOT
  viol+="$(_whrb_pin_server "$plan_json" "$host_key" "$server_id")${nl}"                    # GATE:PIN-SERVER
  viol+="$(_whrb_pin_volume "$mode" "$plan_json" "$host_key" "$server_id" "$volume_id")${nl}"  # GATE:PIN-VOLUME
  viol+="$(_whrb_raw_volume "$mode" "$plan_json" "$host_key")${nl}"                         # GATE:RAW-VOLUME

  viol="$(printf '%s' "$viol" | sed '/^$/d')"
  count=0
  [[ -z "$viol" ]] || count="$(printf '%s\n' "$viol" | wc -l | tr -d ' ')"
  plan_gate_assert_numeric "web_host_rebirth_gate" "violations=${count}" || return 1

  echo "web_host_rebirth_gate: mode=${mode} key=${host_key} server_pin=${server_id} volume_pin=${volume_id} violations=${count}"
  if [[ "$count" -ne 0 ]]; then
    echo "web_host_rebirth_gate: ABORT — the ${mode} plan is not the exact scoped rebirth of ${host_key}:"
    while IFS= read -r line; do printf '  - %s\n' "$line"; done <<<"$viol"
    return 1
  fi
  echo "web_host_rebirth_gate: PASS — ${mode} plan is the exact scoped rebirth of ${host_key} (server, NIC and attachment replaced; the volume is never destroyed by Terraform; every destroy matches the captured physical ids)."
  return 0
}
