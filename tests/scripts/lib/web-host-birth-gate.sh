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
#   creates  == 1                      exactly one hcloud_server is born
#   created address == the requested   the born host is the one authorized
#   destroys == 0                      purely additive; no delete/replace/forget
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
# FAIL-CLOSED. A missing file, unparseable JSON, a null `resource_changes`, or an
# empty host key all ABORT. This gate authorizes creating a billing host on the
# production network; "I could not check" must never read as "it is fine".
#
# Usage:  source tests/scripts/lib/web-host-birth-gate.sh
#         web_host_birth_gate <plan-json-file> <web-host-key>   # 0=PASS, 1=ABORT

web_host_birth_gate() {
  local plan_json="$1" host_key="${2:-}"
  local want_addr creates destroys created_addr

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

  creates=$(jq '[.resource_changes[] | select(.type == "hcloud_server") | select(.change.actions | index("create"))] | length' < "$plan_json" 2>/dev/null)

  # Any destroy-shaped action ANYWHERE in the plan, not just on hcloud_server: a birth
  # that deletes a sibling volume or attachment is not the additive operation that was
  # authorized. "forget" counts — a `removed{}` state-drop abandons a live billing
  # resource, which is not a destroy but is equally not a birth.
  destroys=$(jq '[.resource_changes[] | select(.change.actions | index("delete") or index("forget"))] | length' < "$plan_json" 2>/dev/null)

  for v in "$creates" "$destroys"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "web_host_birth_gate: ABORT — counter parse failed (creates='${creates}' destroys='${destroys}'). Fail-closed."
      return 1
    fi
  done

  echo "web_host_birth_gate: requested=${host_key} host_creates=${creates} destroys=${destroys}"

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

  echo "web_host_birth_gate: PASS — scoped birth of ${want_addr} permitted (exactly 1 host create, 0 destroys, identity matches the dispatch request '${host_key}')."
  return 0
}
