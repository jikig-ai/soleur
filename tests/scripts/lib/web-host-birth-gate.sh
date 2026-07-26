# shellcheck shell=bash
# Sourced birth gate for the web-host CREATE dispatch (#6730).
#
# THE INVERSE OF web2-retire-gate.sh. That gate permits destroys and requires
# host_creates == 0; this one requires EXACTLY ONE host create and permits no
# destroys at all. Its header carries the warning that binds this file: never grade
# one operation's plan against another operation's allow-set. They are siblings by
# shape and opposites by contract.
#
# WHY THIS GATE EXISTS AT ALL. Every automated route to `hcloud_server.web` HALTs on
# `host_creates > 0` (#6416: the per-PR apply can reach the server but not its
# `hcloud_server_network` attachment, so a birth there yields a host with no private
# IP and, transiently, no firewall). That HALT is correct and stays. This dispatch is
# the ONE route granted the capability, and this gate is the price: the HALT is not
# removed, it is INVERTED — "must never create a host" becomes "must create exactly
# the one host that was authorized, and nothing else."
#
# A NEW DISPATCH JOB INHERITS NOTHING. The per-PR HALT is a separate inline copy in
# the `apply` job, whose `if:` is mutually exclusive with every dispatch job. So this
# gate is not defense-in-depth behind an existing check — for this job it is the ONLY
# check. Treat every branch as load-bearing.
#
# PASS (rc=0) iff ALL of:
#   creates        == 1                exactly one hcloud_server is born
#   created address == the requested   the born host is the one authorized
#   destroys       == 0                purely additive; no delete/replace/forget
#   reboot_updates == 0                no live host is power-cycled by the birth
#   out_of_scope   == 0                nothing outside the birth fan-out changes
#   NIC + volume attachment each create — the two members the server's own creation
#                                        entails; their absence IS #6416 / data loss
#
# The first five are PROHIBITIONS; the sixth is a REQUIREMENT. A gate built only from
# prohibitions cannot make a birth safe — it constrains what the plan may ALSO do, never
# what it must do — and this gate shipped that way until review found it accepted a plan
# whose only entry was the server create.
#
# WHY IDENTITY AND NOT JUST A COUNT. A count-only gate passes a plan that births
# exactly one host that is not the one requested. `hcloud_server.web["web-1"]` is the
# singleton behind the app.soleur.ai A record with no failover partner; birthing it
# by a mis-scoped `-target` would be a total outage, and it reads identical to a
# correct web-2 birth in every count-based check. The identity comparison is the arm
# that makes this gate worth having.
#
# WHY "NO DESTROYS" AND NOT "FEW DESTROYS". A replace is `["delete","create"]` — one
# create to a naive counter, while destroying a live host. Counting destroys
# separately and requiring zero is what separates a birth from a replace. Scoped
# host REPLACEMENT is a different operation with a different gate; it does not
# borrow this one.
#
# WHY A REBOOT ARM ON A CREATE-ONLY OPERATION. The birth `-target` set is not closed
# over the fleet. `hcloud_firewall_attachment.web` is a SINGLETON whose `server_ids`
# is `[for h in hcloud_server.web : h.id]`, and it MUST ride the birth — omit it and
# the new host boots with no firewall, which is half of the #6416 failure mode. But
# targeting it drags every `hcloud_server.web` instance into the plan, web-1
# included. A `placement_group_id` / `server_type` delta on web-1 then power-cycles
# the sole live origin behind app.soleur.ai, with zero destroys and a host-create
# count of exactly 1 — invisible to every other arm. Same surface as the #5911
# `reboot_updates` counter in destroy-guard-filter-web-platform.jq, and scoped to the
# same two attributes: `location`/`datacenter` force a full REPLACE, which shows up
# as a delete and is already caught by the destroy arm.
#
# WHY AN ALLOW-SET RATHER THAN NESTED-BLOCK COUNTERS. The sibling per-PR guard counts
# deletions *inside* five Cloudflare block arrays, because that path legitimately
# changes Cloudflare resources and only the shrinkage is suspicious. This path
# changes NONE of them, so the stronger and simpler contract is that no such address
# may appear in the plan at all. That subsumes nested-block shrinkage without
# re-implementing five provider-schema-shaped counters that would drift on the next
# provider major (the v4→v5 `ingress_rule` rename is already documented as pending).
#
# FAIL-CLOSED. A missing file, unparseable JSON, a null `resource_changes`, or an
# empty host key all ABORT. This gate authorizes creating a billing host on the
# production network; "I could not check" must never read as "it is fine".
#
# Usage:  source tests/scripts/lib/web-host-birth-gate.sh
#         web_host_birth_gate <plan-json-file> <web-host-key>   # 0=PASS, 1=ABORT

web_host_birth_gate() {
  local plan_json="$1" host_key="${2:-}"
  local want_addr creates destroys created_addr reboot_updates out_of_scope
  local offenders

  if [[ -z "$host_key" ]]; then
    echo "web_host_birth_gate: ABORT — no host key supplied. The gate cannot verify WHICH host is being born without the request it is grading against, and a birth gate that does not check identity is a count check wearing a costume."
    return 1
  fi

  if [[ ! -f "$plan_json" ]]; then
    echo "web_host_birth_gate: ABORT — plan JSON not found: ${plan_json}"
    return 1
  fi

  want_addr="hcloud_server.web[\"${host_key}\"]"

  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  #
  # `resource_changes[]?` tolerates the key being absent, which is why the null-guard
  # below is a SEPARATE explicit check: `null | length` is 0 in jq and `-eq 0` would
  # read a degraded document as "no creates" — the same fail-open shape that makes a
  # 200-with-null-body pass a count check. An unreadable plan is an abort, not a zero.
  if ! jq -e 'has("resource_changes") and (.resource_changes | type == "array")' \
       < "$plan_json" >/dev/null 2>&1; then
    echo "web_host_birth_gate: ABORT — jq filter failed on ${plan_json}: the document is unparseable or has no resource_changes array. Fail-closed: an unreadable plan is not evidence of a safe one."
    return 1
  fi

  # Every entry MUST carry an ARRAY .change.actions before any counter reads one.
  #
  # jq's `null | index("delete")` returns null rather than erroring, so an entry missing
  # `.change.actions` is silently DROPPED by the destroy and out-of-scope selects — a
  # resource that vanishes from the work-list instead of failing closed. What that hides
  # is precisely a destroy the gate cannot see.
  #
  # MEASURED, not assumed: deleting this check makes a no-actions plan PASS (the suite's
  # mutation proves it). An earlier draft of this comment claimed the numeric
  # counter-validation below was a sufficient backstop and that this check merely improved
  # the message. That was wrong, and it is the comfortable kind of wrong — "something else
  # would catch it" is the standard justification for weakening a guard.
  #
  # Scoped to ALL types, not just hcloud_server as in the sibling stock-preflight gate,
  # because the destroy and out-of-scope arms read every entry's actions.
  if jq -e '[.resource_changes[] | select((.change.actions | type) != "array")] | length > 0' \
       < "$plan_json" >/dev/null 2>&1; then
    offenders=$(jq -r '[.resource_changes[] | select((.change.actions | type) != "array") | .address] | .[0:10] | join(", ")' < "$plan_json" 2>/dev/null)
    echo "web_host_birth_gate: ABORT — unclassifiable plan entry: ${offenders} has no array .change.actions, so it cannot be classified as create/destroy/no-op. Fail-closed: an entry the gate cannot read is not evidence of a safe plan — a destroy hiding in an unreadable entry is exactly what this refuses to wave through."
    return 1
  fi

  creates=$(jq '[.resource_changes[] | select(.type == "hcloud_server") | select(.change.actions | index("create"))] | length' < "$plan_json" 2>/dev/null)

  # Any destroy-shaped action ANYWHERE in the plan, not just on hcloud_server: a birth
  # that deletes a sibling volume or attachment is not the additive operation that was
  # authorized. "forget" counts — a `removed{}` state-drop abandons a live billing
  # resource, which is not a destroy but is equally not a birth.
  destroys=$(jq '[.resource_changes[] | select(.change.actions | index("delete") or index("forget"))] | length' < "$plan_json" 2>/dev/null)

  # Reboot-forcing IN-PLACE update on ANY hcloud_server. TYPE-scoped, not
  # address-scoped: web-1 is the host this arm is really about, but git_data /
  # inngest / registry hold volumes whose power-cycle is no cheaper. Selecting
  # `actions == ["update"]` exactly never double-counts a replace (that carries a
  # "delete" and the destroy arm already owns it) and never fires on the create.
  reboot_updates=$(jq '[.resource_changes[]
    | select(.type == "hcloud_server")
    | select(.change.actions == ["update"])
    | select(.change.before.placement_group_id != .change.after.placement_group_id
          or .change.before.server_type       != .change.after.server_type)] | length' \
    < "$plan_json" 2>/dev/null)

  # Anything CHANGED whose address is not in this birth's fan-out. `no-op` entries
  # are excluded by listing the four mutating actions explicitly rather than negating
  # "no-op" — terraform also emits `read` for data sources, which is not a change
  # either, and an allow-list of verbs stays correct as the action vocabulary grows.
  #
  # IN(...) is exact-equality membership. `contains`/`inside` would substring-match,
  # so a bare `hcloud_server.web` — the whole for_each map — would satisfy the
  # keyed `hcloud_server.web["web-2"]` member and wave the entire fleet through.
  out_of_scope=$(jq -r --arg k "$host_key" '
    [ "hcloud_server.web[\"\($k)\"]",
      "hcloud_server_network.web[\"\($k)\"]",
      "hcloud_volume.workspaces[\"\($k)\"]",
      "hcloud_volume_attachment.workspaces[\"\($k)\"]",
      "hcloud_firewall_attachment.web",
      "betteruptime_heartbeat.web_zot_consumer[\"\($k)\"]",
      "betteruptime_heartbeat.web_nic_guard[\"\($k)\"]",
      "doppler_secret.web_zot_consumer_url[\"\($k)\"]",
      "doppler_secret.web_nic_guard_url[\"\($k)\"]" ] as $allow
    | [ .resource_changes[]
        | select(.change.actions | any(. == "create" or . == "update" or . == "delete" or . == "forget"))
        | select(IN(.address; $allow[]) | not) ] | length' \
    < "$plan_json" 2>/dev/null)

  for v in "$creates" "$destroys" "$reboot_updates" "$out_of_scope"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "web_host_birth_gate: ABORT — counter parse failed (creates='${creates}' destroys='${destroys}' reboot_updates='${reboot_updates}' out_of_scope='${out_of_scope}'). Fail-closed."
      return 1
    fi
  done

  echo "web_host_birth_gate: requested=${host_key} host_creates=${creates} destroys=${destroys} reboot_updates=${reboot_updates} out_of_scope=${out_of_scope}"

  if [[ "$creates" -ne 1 ]]; then
    if [[ "$creates" -eq 0 ]]; then
      echo "web_host_birth_gate: ABORT — no host create in this plan. The dispatch asked to birth '${host_key}' and the plan births nothing: either the host already exists (a no-op the gate must not rubber-stamp) or the -target set is mis-scoped."
    else
      echo "web_host_birth_gate: ABORT — ${creates} hcloud_server creates; expected exactly 1. The -target set has escaped its scope; one authorization births one host."
    fi
    return 1
  fi

  if [[ "$destroys" -ne 0 ]]; then
    echo "web_host_birth_gate: ABORT — ${destroys} destroy/forget action(s). A birth is purely ADDITIVE. A replace (delete+create) reads as one create to a count check while destroying a live host; scoped host replacement is a different operation with its own gate and does not borrow this one."
    return 1
  fi

  created_addr=$(jq -r '[.resource_changes[] | select(.type == "hcloud_server") | select(.change.actions | index("create")) | .address][0]' < "$plan_json" 2>/dev/null)

  if [[ "$created_addr" != "$want_addr" ]]; then
    echo "web_host_birth_gate: ABORT — IDENTITY MISMATCH: the plan births ${created_addr} but the dispatch authorized ${want_addr} (key '${host_key}'). A count-only check passes this plan. If the born host is web-1, applying it would create the singleton behind the app.soleur.ai A record, which has no failover partner."
    return 1
  fi

  if [[ "$reboot_updates" -ne 0 ]]; then
    echo "web_host_birth_gate: ABORT — ${reboot_updates} reboot-forcing in-place update(s) on a LIVE hcloud_server (placement_group_id or server_type). A birth must not power-cycle a running host. This is reachable because hcloud_firewall_attachment.web is a singleton over the whole for_each map, so targeting it pulls every web host into the plan — including web-1, the sole live origin behind app.soleur.ai. Apply the reboot as its own maintenance-window operation, not as a side effect of a birth."
    return 1
  fi

  if [[ "$out_of_scope" -ne 0 ]]; then
    offenders=$(jq -r --arg k "$host_key" '
      [ "hcloud_server.web[\"\($k)\"]",
        "hcloud_server_network.web[\"\($k)\"]",
        "hcloud_volume.workspaces[\"\($k)\"]",
        "hcloud_volume_attachment.workspaces[\"\($k)\"]",
        "hcloud_firewall_attachment.web",
        "betteruptime_heartbeat.web_zot_consumer[\"\($k)\"]",
        "betteruptime_heartbeat.web_nic_guard[\"\($k)\"]",
        "doppler_secret.web_zot_consumer_url[\"\($k)\"]",
        "doppler_secret.web_nic_guard_url[\"\($k)\"]" ] as $allow
      | [ .resource_changes[]
          | select(.change.actions | any(. == "create" or . == "update" or . == "delete" or . == "forget"))
          | select(IN(.address; $allow[]) | not) | .address ] | .[0:10] | join(", ")' \
      < "$plan_json" 2>/dev/null)
    echo "web_host_birth_gate: ABORT — ${out_of_scope} out-of-scope change(s), outside the birth fan-out for '${host_key}': ${offenders}. One authorization births one host and touches only that host's nine addresses. A sibling host's volume, or a Cloudflare ruleset riding along, is a different operation that has not been authorized here."
    return 1
  fi

  # ── REQUIREMENT ARM ────────────────────────────────────────────────────────────
  #
  # Every arm above is a PROHIBITION. Prohibitions alone cannot make a birth safe: they
  # constrain what the plan may ALSO do, never what it must do. Without this arm the gate
  # passed a plan whose only entry was the server create — a host with no private IP and,
  # transiently, no firewall, which is #6416 verbatim, the failure this path exists to
  # prevent. The allow-set could not close it: it says these addresses are PERMITTED to
  # change, not that they must.
  #
  # WHY THESE TWO AND NOT ALL NINE. Both are bound to the server's id
  # (`hcloud_server_network.web[k]` and `hcloud_volume_attachment.workspaces[k]` reference
  # `hcloud_server.web[k].id`), so a NEW server implies a NEW instance of each — the
  # implication holds by construction, which is what makes the requirement safe to assert.
  # The other six do not have it:
  #   • hcloud_volume.workspaces[k] can legitimately pre-exist. A retry after a partial
  #     apply that created the volume but not the server re-plans the volume as a no-op,
  #     and that retry is the documented recovery path — requiring its create would break
  #     the one case the apply-failure message tells the operator is safe.
  #   • hcloud_firewall_attachment.web is a fleet singleton: it UPDATES (server_ids grows),
  #     it does not create.
  #   • the four web-probe resources are per-key but may pre-exist for the same
  #     partial-apply reason as the volume.
  #
  # So the rule is not "require the fan-out", it is "require exactly those members whose
  # existence the server's own creation entails". Anything looser breaks a legitimate
  # retry; anything tighter is unenforceable.
  local required_addr required_creates
  for required_addr in \
    "hcloud_server_network.web[\"${host_key}\"]" \
    "hcloud_volume_attachment.workspaces[\"${host_key}\"]"; do
    required_creates=$(jq --arg a "$required_addr" \
      '[.resource_changes[] | select(.address == $a) | select(.change.actions | index("create"))] | length' \
      < "$plan_json" 2>/dev/null)
    if [[ ! "$required_creates" =~ ^[0-9]+$ ]]; then
      echo "web_host_birth_gate: ABORT — counter parse failed for required address ${required_addr} (got '${required_creates}'). Fail-closed."
      return 1
    fi
    if [[ "$required_creates" -ne 1 ]]; then
      echo "web_host_birth_gate: ABORT — the plan births ${want_addr} but does NOT create ${required_addr} (${required_creates} creates; expected exactly 1). A server without its private NIC comes up with no private-net IP and, transiently, no firewall — that is #6416, and it looks exactly like a successful apply. A server without its volume attachment writes /mnt/data to the ROOT DISK behind a fail-open mount, serves normally, and loses every workspace the first time the real volume mounts over it. Both are entailed by the server's own creation, so their absence means the -target set is mis-scoped, not that they were deliberately omitted."
      return 1
    fi
  done

  echo "web_host_birth_gate: PASS — scoped birth of ${want_addr} permitted (exactly 1 host create + its private NIC + its volume attachment, 0 destroys, 0 reboots, 0 out-of-scope changes, identity matches the dispatch request '${host_key}')."
  return 0
}
