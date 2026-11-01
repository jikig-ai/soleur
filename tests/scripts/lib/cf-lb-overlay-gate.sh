# shellcheck shell=bash
# cf-lb-overlay-gate.sh — plan grader for cf-lb-overlay.yml's four arms (#11181 F3).
# Sourced, never executed directly. One function per arm; each reads the SAVED plan
# JSON (terraform show -json tfplan) and asserts the change set is EXACTLY what the
# arm is allowed to do — the same "reads the plan, not the flags" posture as
# vector-redeliver-gate.sh, on the same plan-gate-preamble.sh floor every sibling
# grader carries (the `local plan_json` parameter name is load-bearing: the drift
# derivation in test-plan-gate-preamble.sh scans `*gate*.sh` for it).
#
# Allow-sets (exact addresses — this throwaway root holds nothing else):
#   RECORD = cloudflare_record.lb_staging
#   LB3    = cloudflare_load_balancer_monitor.lb_staging,
#            cloudflare_load_balancer_pool.lb_staging,
#            cloudflare_load_balancer.lb_staging
#   GA3    = cloudflare_load_balancer_monitor.web,
#            cloudflare_load_balancer_pool.web_1,
#            cloudflare_load_balancer.app   (parent root, ga-overlay arm)
#
# Two grading rules, both precedented:
#   NEGATIVE ACTION FILTER (vector-redeliver-gate.sh): only ["no-op"] and ["read"]
#   rows are "not a change". forget/import/moved/empty-[]/future verbs are CHANGES
#   and must satisfy the arm's allow-set — a positive verb list silently admits
#   whatever Terraform adds next.
#   IDENTITY PINS (.change.after): the address allow-set bounds WHICH resources;
#   the after values bound WHAT THEY SAY. A config edit renaming the record to
#   "app"/"*" or pointing the GA pool at another IP passes an address-only gate —
#   the create arms ride infra-privileged, so the pin is the content check.
#
# Every gate FAILS CLOSED: a plan jq can't parse, a change outside the allow-set,
# an unpinned attribute, or any action the arm doesn't permit → rc 1, NOTHING applied.

# shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _CFLB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${_CFLB_DIR}/plan-gate-preamble.sh"
  unset _CFLB_DIR
fi

# Entries that are NOT a change for grading purposes: converged no-ops and deferred
# data-source reads. Everything else (incl. forget/import/moved/[] verbs) is a change.
_CF_LB_CHANGES='[.resource_changes[] | select(.change.actions != ["no-op"] and .change.actions != ["read"])]'

# staging-record: exactly one change = create cloudflare_record.lb_staging, with the
# throwaway hostname pinned — OR zero changes with the record already converged
# (idempotent re-dispatch: a successful first apply + a timed-out settle wait must
# not brick the arm; the overlay arm is the sanctioned next step).
cf_lb_gate_record() {
  local plan_json="$1"
  plan_gate_assert_readable "cf_lb_gate_record" "$plan_json" || return 1
  plan_gate_assert_classifiable "cf_lb_gate_record" "$plan_json" || return 1
  local bad creates rec_noop
  bad=$(jq -r "${_CF_LB_CHANGES} | map(select(.address != \"cloudflare_record.lb_staging\" or .change.actions != [\"create\"])) | length" "$plan_json")
  creates=$(jq -r "${_CF_LB_CHANGES} | map(select(.address == \"cloudflare_record.lb_staging\" and .change.actions == [\"create\"])) | length" "$plan_json")
  rec_noop=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_record.lb_staging" and .change.actions == ["no-op"])] | length' "$plan_json")
  if [[ "$bad" != "0" ]]; then
    echo "::error::staging-record gate: $bad change(s) that are not 'create cloudflare_record.lb_staging' — refusing. NOTHING applied."
    return 1
  fi
  if [[ "$creates" == "1" ]]; then
    local rec_name rec_type rec_proxied
    rec_name=$(jq -r '.resource_changes[] | select(.address == "cloudflare_record.lb_staging" and .change.actions == ["create"]) | .change.after.name // ""' "$plan_json")
    rec_type=$(jq -r '.resource_changes[] | select(.address == "cloudflare_record.lb_staging" and .change.actions == ["create"]) | .change.after.type // ""' "$plan_json")
    rec_proxied=$(jq -r '.resource_changes[] | select(.address == "cloudflare_record.lb_staging" and .change.actions == ["create"]) | .change.after.proxied // false' "$plan_json")
    if [[ "$rec_name" != "lb-staging" || "$rec_type" != "A" || "$rec_proxied" != "true" ]]; then
      echo "::error::staging-record gate: record after={name:${rec_name},type:${rec_type},proxied:${rec_proxied}} is not {name:lb-staging,type:A,proxied:true} — a config edit cannot silently mint a prod-hostname A record. NOTHING applied."
      return 1
    fi
    echo "cf-lb-overlay gate[staging-record]: 1 create (cloudflare_record.lb_staging, name=lb-staging type=A proxied) — pass"
    return 0
  fi
  if [[ "$creates" == "0" && "$rec_noop" -ge 1 ]]; then
    echo "cf-lb-overlay gate[staging-record]: record already converged (no-op) — idempotent re-dispatch; next arm is staging-overlay. Pass."
    return 0
  fi
  echo "::error::staging-record gate: plan is not exactly 'create cloudflare_record.lb_staging' (creates=$creates, record no-op=$rec_noop). If the record already exists, run staging-overlay; if you intend a clean redo, run staging-teardown first. NOTHING applied."
  return 1
}

# staging-overlay: changes ⊆ creates of LB3 ONLY; the record must already exist
# converged (["no-op"]) — staging-record is the mandatory first arm and the
# record→settle→overlay ordering is the GA precondition being rehearsed. The LB's
# name must be exactly "lb-staging.soleur.ai" (the throwaway-hostname pin).
cf_lb_gate_overlay() {
  local plan_json="$1"
  plan_gate_assert_readable "cf_lb_gate_overlay" "$plan_json" || return 1
  plan_gate_assert_classifiable "cf_lb_gate_overlay" "$plan_json" || return 1
  local bad_creates rec_seq lb_name offenders
  bad_creates=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions != [\"create\"] or (.address | IN(\"cloudflare_load_balancer_monitor.lb_staging\",\"cloudflare_load_balancer_pool.lb_staging\",\"cloudflare_load_balancer.lb_staging\") | not))) | length" "$plan_json")
  rec_seq=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_record.lb_staging" and .change.actions == ["no-op"])] | length' "$plan_json")
  lb_name=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer.lb_staging") | .change.after.name // ""] | .[0] // ""' "$plan_json")
  offenders=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions != [\"create\"] or (.address | IN(\"cloudflare_load_balancer_monitor.lb_staging\",\"cloudflare_load_balancer_pool.lb_staging\",\"cloudflare_load_balancer.lb_staging\") | not)) | .address) | join(\", \")" "$plan_json")
  if [[ "$bad_creates" != "0" ]]; then
    echo "::error::staging-overlay gate: $bad_creates change(s) outside the LB3 create set (${offenders}). NOTHING applied."
    return 1
  fi
  if [[ "$rec_seq" == "0" ]]; then
    echo "::error::staging-overlay gate: cloudflare_record.lb_staging is not present-and-converged — the record arm must run first (record→settle→overlay is the ordering being rehearsed). Run arm=staging-record. NOTHING applied."
    return 1
  fi
  if [[ "$lb_name" != "lb-staging.soleur.ai" ]]; then
    echo "::error::staging-overlay gate: cloudflare_load_balancer.lb_staging name is '$lb_name', not 'lb-staging.soleur.ai' — refusing (the throwaway hostname pin is what keeps a config edit off app.soleur.ai). NOTHING applied."
    return 1
  fi
  local lb_creates
  lb_creates=$(jq -r "${_CF_LB_CHANGES} | length" "$plan_json")
  echo "cf-lb-overlay gate[staging-overlay]: $lb_creates create(s) within LB3, record converged, name=lb-staging.soleur.ai — pass"
}

# staging-teardown: EVERY change is a delete confined to the four staging addresses
# (a `terraform plan -destroy` on this root). Deferred data reads (mode:"data"
# ["read"] entries terraform can emit on destroy plans) are not changes. Zero
# changes is a pass (already torn down — idempotent).
cf_lb_gate_teardown() {
  local plan_json="$1"
  plan_gate_assert_readable "cf_lb_gate_teardown" "$plan_json" || return 1
  plan_gate_assert_classifiable "cf_lb_gate_teardown" "$plan_json" || return 1
  local bad offenders
  bad=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions != [\"delete\"] or (.address | IN(\"cloudflare_record.lb_staging\",\"cloudflare_load_balancer_monitor.lb_staging\",\"cloudflare_load_balancer_pool.lb_staging\",\"cloudflare_load_balancer.lb_staging\") | not))) | length" "$plan_json")
  offenders=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions != [\"delete\"] or (.address | IN(\"cloudflare_record.lb_staging\",\"cloudflare_load_balancer_monitor.lb_staging\",\"cloudflare_load_balancer_pool.lb_staging\",\"cloudflare_load_balancer.lb_staging\") | not)) | .address) | join(\", \")" "$plan_json")
  if [[ "$bad" != "0" ]]; then
    echo "::error::staging-teardown gate: $bad change(s) outside the four-address delete set (${offenders}). NOTHING destroyed."
    return 1
  fi
  echo "cf-lb-overlay gate[staging-teardown]: deletes confined to the staging allow-set — pass"
}

# ga-overlay (PARENT root): changes ⊆ creates of GA3. Identity pins carry the same
# weight as the staging pins: the LB must name app.soleur.ai and stay enabled+proxied,
# and the pool's origins must resolve to declared web hosts' addresses (read off the
# no-op server entries -target transitivity pulls into the plan — absent/unreadable
# → refuse). The origins set widened to {web-1, web-2} when the drained member landed
# (2026-11-01): the pin is still the plan-resolved IP set, never a literal.
cf_lb_gate_ga() {
  local plan_json="$1"
  plan_gate_assert_readable "cf_lb_gate_ga" "$plan_json" || return 1
  plan_gate_assert_classifiable "cf_lb_gate_ga" "$plan_json" || return 1
  local bad offenders lb_name lb_enabled lb_proxied web1_ip bad_origins ga_creates
  bad=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions != [\"create\"] or (.address | IN(\"cloudflare_load_balancer_monitor.web\",\"cloudflare_load_balancer_pool.web_1\",\"cloudflare_load_balancer.app\") | not))) | length" "$plan_json")
  offenders=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions != [\"create\"] or (.address | IN(\"cloudflare_load_balancer_monitor.web\",\"cloudflare_load_balancer_pool.web_1\",\"cloudflare_load_balancer.app\") | not)) | .address) | join(\", \")" "$plan_json")
  ga_creates=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions == [\"create\"] and (.address | IN(\"cloudflare_load_balancer_monitor.web\",\"cloudflare_load_balancer_pool.web_1\",\"cloudflare_load_balancer.app\")))) | length" "$plan_json")
  lb_name=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer.app") | .change.after.name // ""] | .[0] // ""' "$plan_json")
  lb_enabled=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer.app") | (.change.after | if has("enabled") then .enabled else true end)] | .[0]' "$plan_json")
  lb_proxied=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer.app") | (.change.after | if has("proxied") then .proxied else true end)] | .[0]' "$plan_json")
  web1_ip=$(jq -r '[.resource_changes[] | select(.address == "hcloud_server.web[\"web-1\"]") | .change.after.ipv4_address // empty] | .[0] // ""' "$plan_json")
  web2_ip=$(jq -r '[.resource_changes[] | select(.address == "hcloud_server.web[\"web-2\"]") | .change.after.ipv4_address // empty] | .[0] // ""' "$plan_json")
  bad_origins=$(jq -r --arg ip1 "$web1_ip" --arg ip2 "$web2_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["create"]) | .change.after.origins[]?.address // ""] | map(select(. != $ip1 and . != $ip2)) | length' "$plan_json")
  if [[ "$bad" != "0" ]]; then
    echo "::error::ga-overlay gate: $bad change(s) outside the GA3 create set (${offenders}). NOTHING applied."
    return 1
  fi
  if [[ "$ga_creates" == "0" ]]; then
    echo "::error::ga-overlay gate: zero GA-trio creates — a plan that grades nothing approves nothing. Refusing."
    return 1
  fi
  if [[ "$lb_name" != "app.soleur.ai" || "$lb_enabled" != "true" || "$lb_proxied" != "true" ]]; then
    echo "::error::ga-overlay gate: cloudflare_load_balancer.app after={name:${lb_name},enabled:${lb_enabled},proxied:${lb_proxied}} is not {name:app.soleur.ai,enabled:true,proxied:true}. NOTHING applied."
    return 1
  fi
  if [[ -z "$web1_ip" ]]; then
    echo "::error::ga-overlay gate: cannot read web-1's ipv4_address from the plan's no-op server entry — cannot verify pool origins. Refusing."
    return 1
  fi
  if [[ "$bad_origins" != "0" ]]; then
    echo "::error::ga-overlay gate: $bad_origins pool origin(s) are outside the plan-resolved set {web-1:${web1_ip},web-2:${web2_ip}} — a repointed origin would send app.soleur.ai traffic elsewhere. NOTHING applied."
    return 1
  fi
  echo "cf-lb-overlay gate[ga-overlay]: $ga_creates GA-trio create(s), name=app.soleur.ai, origins ⊆ {web-1:${web1_ip},web-2:${web2_ip}} — pass"
}

# ga-monitor-fix (PARENT root): exactly ONE change — update of
# cloudflare_load_balancer_monitor.web, and its after-state must be exactly
# {type:"http", port:80, path:"/health", expected_codes:"200"} — the Flexible-SSL
# edge path's real listener (the https/:443 create shape probes a port nothing
# listens on and reports every origin permanently down). A create/delete/replace,
# a second member smuggled beside it, or any drift in the pinned fields → refuse.
cf_lb_gate_ga_monitor_update() {
  local plan_json="$1"
  plan_gate_assert_readable "cf_lb_gate_ga_monitor_update" "$plan_json" || return 1
  plan_gate_assert_classifiable "cf_lb_gate_ga_monitor_update" "$plan_json" || return 1
  local bad offenders updates m_type m_port m_path m_codes
  bad=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions != [\"update\"] or .address != \"cloudflare_load_balancer_monitor.web\")) | length" "$plan_json")
  offenders=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions != [\"update\"] or .address != \"cloudflare_load_balancer_monitor.web\") | .address) | join(\", \")" "$plan_json")
  updates=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions == [\"update\"] and .address == \"cloudflare_load_balancer_monitor.web\")) | length" "$plan_json")
  if [[ "$bad" != "0" ]]; then
    echo "::error::ga-monitor-fix gate: $bad change(s) that are not 'update cloudflare_load_balancer_monitor.web' (${offenders}) — a non-update verb or a second member beside it would launder an ungraded change. NOTHING applied."
    return 1
  fi
  if [[ "$updates" != "1" ]]; then
    echo "::error::ga-monitor-fix gate: expected exactly 1 monitor update, got $updates — a plan that grades nothing approves nothing. Refusing."
    return 1
  fi
  m_type=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_monitor.web" and .change.actions == ["update"]) | .change.after.type // ""] | .[0] // ""' "$plan_json")
  m_port=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_monitor.web" and .change.actions == ["update"]) | .change.after.port // 0] | .[0] // 0' "$plan_json")
  m_path=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_monitor.web" and .change.actions == ["update"]) | .change.after.path // ""] | .[0] // ""' "$plan_json")
  m_codes=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_monitor.web" and .change.actions == ["update"]) | .change.after.expected_codes // ""] | .[0] // ""' "$plan_json")
  if [[ "$m_type" != "http" || "$m_port" != "80" || "$m_path" != "/health" || "$m_codes" != "200" ]]; then
    echo "::error::ga-monitor-fix gate: monitor after={type:${m_type},port:${m_port},path:${m_path},expected_codes:${m_codes}} is not {type:http,port:80,path:/health,expected_codes:200} — the fix exists because :443 has no listener; any other shape re-breaks or widens the probe. NOTHING applied."
    return 1
  fi
  echo "cf-lb-overlay gate[ga-monitor-fix]: monitor update pinned to {http,:80,/health,200} — pass"
}

# ga-pool-update (PARENT root): changes ⊆ updates of {pool web_1, LB app, notification
# policy web_lb_health}; every pool origin address must resolve to a declared
# hcloud_server.web[*] ipv4_address in the plan's no-op entries (never a literal);
# web-2's after-weight must be 0 in `drain` mode. `serve` mode is the window arm —
# the weight gate ran in the job BEFORE plan (the arm's run: ordering is the guard;
# the grader itself is mode-aware only on the drain pin).
cf_lb_gate_ga_pool_update() {
  local plan_json="$1" mode="${2:-drain}"
  plan_gate_assert_readable "cf_lb_gate_ga_pool_update" "$plan_json" || return 1
  plan_gate_assert_classifiable "cf_lb_gate_ga_pool_update" "$plan_json" || return 1
  if [[ "$mode" != "drain" && "$mode" != "serve" ]]; then
    echo "::error::ga-pool-update gate: mode must be drain|serve, got '${mode}'. Refusing."
    return 1
  fi
  local bad offenders updates web1_ip web2_ip bad_origins w2_weight
  bad=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions != [\"update\"] or (.address | IN(\"cloudflare_load_balancer_pool.web_1\",\"cloudflare_load_balancer.app\",\"cloudflare_notification_policy.web_lb_health\") | not))) | length" "$plan_json")
  offenders=$(jq -r "${_CF_LB_CHANGES} | map(select(.change.actions != [\"update\"] or (.address | IN(\"cloudflare_load_balancer_pool.web_1\",\"cloudflare_load_balancer.app\",\"cloudflare_notification_policy.web_lb_health\") | not)) | .address) | join(\", \")" "$plan_json")
  updates=$(jq -r "${_CF_LB_CHANGES} | length" "$plan_json")
  web1_ip=$(jq -r '[.resource_changes[] | select(.address == "hcloud_server.web[\"web-1\"]") | .change.after.ipv4_address // empty] | .[0] // ""' "$plan_json")
  web2_ip=$(jq -r '[.resource_changes[] | select(.address == "hcloud_server.web[\"web-2\"]") | .change.after.ipv4_address // empty] | .[0] // ""' "$plan_json")
  if [[ "$bad" != "0" ]]; then
    echo "::error::ga-pool-update gate: $bad change(s) outside the {pool.web_1, lb.app, notification_policy.web_lb_health} update set (${offenders}). NOTHING applied."
    return 1
  fi
  if [[ "$updates" == "0" ]]; then
    echo "::error::ga-pool-update gate: empty change set — a plan that grades nothing approves nothing. Refusing."
    return 1
  fi
  if [[ -z "$web1_ip" || -z "$web2_ip" ]]; then
    echo "::error::ga-pool-update gate: cannot resolve both web hosts' ipv4_address from the plan's no-op entries (web-1='${web1_ip}' web-2='${web2_ip}') — the origins set is unprovable. Refusing."
    return 1
  fi
  bad_origins=$(jq -r --arg ip1 "$web1_ip" --arg ip2 "$web2_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]?.address // ""] | map(select(. != $ip1 and . != $ip2)) | length' "$plan_json")
  if [[ "$bad_origins" != "0" ]]; then
    echo "::error::ga-pool-update gate: $bad_origins pool origin(s) outside the plan-resolved set {web-1:${web1_ip},web-2:${web2_ip}} — a repointed origin would send app.soleur.ai traffic elsewhere. NOTHING applied."
    return 1
  fi
  if [[ "$mode" == "drain" ]]; then
    w2_weight=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select(.name == "web-2") | .weight // -1] | .[0] // -1' "$plan_json")
    if [[ "$w2_weight" != "0" ]]; then
      echo "::error::ga-pool-update gate[drain]: web-2 after-weight is '${w2_weight}', not 0 — the 0→1 flip is the #6027 window act and rides mode=serve behind the §(c) gate chain, never the drain arm. NOTHING applied."
      return 1
    fi
  fi
  echo "cf-lb-overlay gate[ga-pool-update:${mode}]: $updates update(s) within the pool/LB/policy set, origins ⊆ {web-1:${web1_ip},web-2:${web2_ip}}${mode/drain/, web-2 weight=0} — pass"
}
