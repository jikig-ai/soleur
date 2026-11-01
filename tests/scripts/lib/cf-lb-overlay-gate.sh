# shellcheck shell=bash
# cf-lb-overlay-gate.sh — plan grader for cf-lb-overlay.yml's six arms (#11181 F3,
# #6027 continuation PR #11766).
# Sourced, never executed directly. One function per arm; each reads the SAVED plan
# JSON (terraform show -json tfplan) and asserts the change set is EXACTLY what the
# arm is allowed to do — the same "reads the plan, not the flags" posture as
# vector-redeliver-gate.sh, on the same plan-gate-preamble.sh floor every sibling
# grader carries (the `local plan_json` parameter name is load-bearing: the drift
# derivation in test-plan-gate-preamble.sh scans `*gate*.sh` for it).
#
# Allow-sets (exact addresses — the staging root holds nothing else; the GA sets
# live in the parent root):
#   RECORD    = cloudflare_record.lb_staging
#   LB3       = cloudflare_load_balancer_monitor.lb_staging,
#               cloudflare_load_balancer_pool.lb_staging,
#               cloudflare_load_balancer.lb_staging
#   GA3       = cloudflare_load_balancer_monitor.web,
#               cloudflare_load_balancer_pool.web_1,
#               cloudflare_load_balancer.app   (parent root, ga-overlay arm, create-only)
#   UPDATE    = cloudflare_load_balancer_monitor.web   (ga-monitor-fix, update-only)
#   POOL-UPD  = cloudflare_load_balancer_pool.web_1 +
#               cloudflare_load_balancer.app           (update-only)
#               + cloudflare_notification_policy.web_lb_health (create|update —
#               a NEW resource on first dispatch, OPERATOR_APPLIED_EXCLUSIONS-listed,
#               so the ga-pool-update arm is its only apply path)
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
# (2026-11-01): the pin is still the plan-resolved IP set, never a literal — AND the
# drained {1,0} shape itself: >=1 origin at each resolved IP, every web-1-IP origin
# at weight 1, every web-2-IP origin at weight 0, none enabled=false (a create that
# lands web-2 hot bypasses the serve-window gate chain).
cf_lb_gate_ga() {
  local plan_json="$1"
  plan_gate_assert_readable "cf_lb_gate_ga" "$plan_json" || return 1
  plan_gate_assert_classifiable "cf_lb_gate_ga" "$plan_json" || return 1
  local bad offenders lb_name lb_enabled lb_proxied web1_ip web2_ip bad_origins ga_creates
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
  if [[ -z "$web1_ip" || -z "$web2_ip" ]]; then
    echo "::error::ga-overlay gate: cannot read both web hosts' ipv4_address from the plan's no-op server entries (web-1='${web1_ip}' web-2='${web2_ip}') — cannot verify pool origins. Refusing."
    return 1
  fi
  if [[ "$bad_origins" != "0" ]]; then
    echo "::error::ga-overlay gate: $bad_origins pool origin(s) are outside the plan-resolved set {web-1:${web1_ip},web-2:${web2_ip}} — a repointed origin would send app.soleur.ai traffic elsewhere. NOTHING applied."
    return 1
  fi
  # DRAINED-SHAPE pins on create, mirroring the drain-mode discipline of
  # cf_lb_gate_ga_pool_update: the GA3 (re)create shape is the drained two-member
  # pool {web-1@web1_ip:1, web-2@web2_ip:0}. A create plan carrying web-2's IP at
  # weight > 0 — or no web-2 origin at all — is the un-drained shape the serve
  # window reaches only THROUGH the §(c) gate chain, never by creation. Presence
  # AND weight bind by resolved IP so a renamed origin cannot dodge them.
  local w1ip_n w2ip_n w1ip_bad w2ip_bad ga_disabled
  w1ip_n=$(jq -r --arg ip1 "$web1_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["create"]) | .change.after.origins[]? | select(.address == $ip1)] | length' "$plan_json")
  w2ip_n=$(jq -r --arg ip2 "$web2_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["create"]) | .change.after.origins[]? | select(.address == $ip2)] | length' "$plan_json")
  w1ip_bad=$(jq -r --arg ip1 "$web1_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["create"]) | .change.after.origins[]? | select(.address == $ip1 and ((.weight | type) != "number" or .weight != 1))] | length' "$plan_json")
  w2ip_bad=$(jq -r --arg ip2 "$web2_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["create"]) | .change.after.origins[]? | select(.address == $ip2 and ((.weight // -1) != 0))] | length' "$plan_json")
  ga_disabled=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["create"]) | .change.after.origins[]? | select((.enabled | if . == null then true else . end | tostring) == "false")] | length' "$plan_json")
  if [[ "$w1ip_n" == "0" ]]; then
    echo "::error::ga-overlay gate: no origin resolves to web-1's plan IP (${web1_ip}) — the create shape must land the serving member; a pool with no web-1 origin serves nothing. NOTHING applied."
    return 1
  fi
  if [[ "$w2ip_n" == "0" ]]; then
    echo "::error::ga-overlay gate: no origin resolves to web-2's plan IP (${web2_ip}) — the create shape must land web-2 as the DRAINED member; a create without it is the un-drained shape the serve window reaches only through the §(c) gate chain. NOTHING applied."
    return 1
  fi
  if [[ "$ga_disabled" != "0" ]]; then
    echo "::error::ga-overlay gate: $ga_disabled origin(s) with enabled=false — a disabled member is not a drained member (drain = weight 0 + health-checked). NOTHING applied."
    return 1
  fi
  if [[ "$w1ip_bad" != "0" ]]; then
    echo "::error::ga-overlay gate: $w1ip_bad origin(s) at web-1's resolved IP (${web1_ip}) carry weight != 1 — the create shape is {web-1:1, web-2:0}. NOTHING applied."
    return 1
  fi
  if [[ "$w2ip_bad" != "0" ]]; then
    echo "::error::ga-overlay gate: $w2ip_bad origin(s) at web-2's resolved IP (${web2_ip}) carry weight != 0 — creating web-2 hot bypasses the serve-window gate chain; the drained member lands at weight 0 only. NOTHING applied."
    return 1
  fi
  echo "cf-lb-overlay gate[ga-overlay]: $ga_creates GA-trio create(s), name=app.soleur.ai, origins ⊆ {web-1:${web1_ip},web-2:${web2_ip}} drained {1,0} — pass"
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

# ga-pool-update (PARENT root): PER-VERB allow-set over {pool web_1, LB app,
# notification policy web_lb_health} — the pool and LB admit ["update"] ONLY; the
# policy admits ["create"] or ["update"] (it is a NEW resource on first dispatch,
# and OPERATOR_APPLIED_EXCLUSIONS-listed, so this arm is its only apply path —
# refusing its create would make the arm's own -target permanently ungradable).
# Replace/delete/forget/empty-[] verbs refuse on all three (the negative filter
# already counts them as changes; the verb check gives them a named refusal).
#
# Origins are graded PRESENCE-AND-PIN, SYMMETRIC BY RESOLVED IP in both modes —
# the subset check alone passed a pool whose after-state dropped web-1, held zero
# origins, or carried a renamed web-2 member, and the name-only pins passed a
# serve plan that dropped web-1's IP entirely, a third member shadowing at a
# pinned IP, a name/IP swap, and a drain plan with web-1 under weight 1:
#   * after.origins must exist and carry >= 1 member (a zero-origin pool is an
#     outage; an absent/null list is unprovable — distinct refusal below);
#   * every member's address resolves to a declared hcloud_server.web[*]
#     ipv4_address from the plan's no-op entries (never a literal);
#   * every member stays enabled != false (via tostring — a string "false" does
#     not escape) — a disabled member is not a drained member;
#   * no duplicate origin names AND no duplicate origin addresses — a shadow
#     member at a pinned IP splits/multiplies its weight invisibly;
#   * a canonical name on the WRONG host's IP refuses (name↔IP binding — the
#     declared shape is {web-1@web1_ip, web-2@web2_ip}, so a swap cannot read as
#     its declared-shape twin);
#   * an origin NAMED web-1 must exist with enabled != false and weight > 0 —
#     without it the pool has no serving member;
#   * >= 1 origin must resolve to EACH of web-1's and web-2's plan IPs.
#
# `drain` pins EVERY origin at web-1's resolved IP to weight 1 and every origin
# at web-2's resolved IP to weight 0 — name-independent, so a renamed origin
# block cannot dodge the pin. `serve` is the #6027 window arm: the §(c) gate
# chain ran in the job BEFORE plan, and the grader pins the declared post-flip
# shape — the web-1-named AND web-2-named origins at weight 1 AND every origin at
# EITHER resolved IP at weight 1 (weights compared as numbers, not strings).
#
# REMNANT-ONLY plans: a graded set with NO pool.web_1 update is admitted iff the
# per-verb allow-set + the attribute pins below pass on whichever entries exist —
# a partial-apply re-dispatch emitting {policy:create} alone must not wedge into
# the ungraded manual apply. The origins pins skip (no pool after-state exists);
# a clear message marks the degraded grade.
#
# Resource after-state pins refuse only EXPLICIT bad values (absent/unknown keys
# are OK): lb.app enabled==false / session_affinity!="none" (ADR-068 correction
# (b.3): an affinity cookie overrides weight 0) / default_pool_ids present-empty
# or carrying any id != the plan-resolved web_1 pool id / fallback_pool_id
# present-and-!= that same id (a literal foreign pool id is a repoint the address
# allow-set cannot see — unresolvable + values present fails closed); pool
# enabled==false / monitor==null-when-present (unbinding the monitor re-blinds
# the signal the monitor-fix arm repairs); policy enabled==false, and on
# ["create"] OR ["update"] a present alert_type must be
# load_balancing_health_alert.
cf_lb_gate_ga_pool_update() {
  local plan_json="$1" mode="${2:-drain}"
  plan_gate_assert_readable "cf_lb_gate_ga_pool_update" "$plan_json" || return 1
  plan_gate_assert_classifiable "cf_lb_gate_ga_pool_update" "$plan_json" || return 1
  if [[ "$mode" != "drain" && "$mode" != "serve" ]]; then
    echo "::error::ga-pool-update gate: mode must be drain|serve, got '${mode}'. Refusing."
    return 1
  fi
  local bad offenders updates pool_updates web1_ip web2_ip
  local origins_n bad_origins disabled_n dup_names dup_addrs misbound w1_ok w1ip_n w2ip_n
  # A change grades clean iff it is an update on the pool or the LB, or a
  # create/update on the notification policy. Anything else — a replace
  # (["delete","create"]), a delete, forget/import, an empty-[] verb list the
  # negative filter already counts as a change, or an out-of-set address — refuses.
  bad=$(jq -r "${_CF_LB_CHANGES} | map(select(
      (.address == \"cloudflare_load_balancer_pool.web_1\" and .change.actions != [\"update\"])
      or (.address == \"cloudflare_load_balancer.app\" and .change.actions != [\"update\"])
      or (.address == \"cloudflare_notification_policy.web_lb_health\" and .change.actions != [\"create\"] and .change.actions != [\"update\"])
      or (.address | IN(\"cloudflare_load_balancer_pool.web_1\",\"cloudflare_load_balancer.app\",\"cloudflare_notification_policy.web_lb_health\") | not)
    )) | length" "$plan_json")
  offenders=$(jq -r "${_CF_LB_CHANGES} | map(select(
      (.address == \"cloudflare_load_balancer_pool.web_1\" and .change.actions != [\"update\"])
      or (.address == \"cloudflare_load_balancer.app\" and .change.actions != [\"update\"])
      or (.address == \"cloudflare_notification_policy.web_lb_health\" and .change.actions != [\"create\"] and .change.actions != [\"update\"])
      or (.address | IN(\"cloudflare_load_balancer_pool.web_1\",\"cloudflare_load_balancer.app\",\"cloudflare_notification_policy.web_lb_health\") | not)
    ) | .address + \"(\" + (.change.actions | join(\"+\")) + \")\") | join(\", \")" "$plan_json")
  updates=$(jq -r "${_CF_LB_CHANGES} | length" "$plan_json")
  pool_updates=$(jq -r "${_CF_LB_CHANGES} | map(select(.address == \"cloudflare_load_balancer_pool.web_1\" and .change.actions == [\"update\"])) | length" "$plan_json")
  web1_ip=$(jq -r '[.resource_changes[] | select(.address == "hcloud_server.web[\"web-1\"]") | .change.after.ipv4_address // empty] | .[0] // ""' "$plan_json")
  web2_ip=$(jq -r '[.resource_changes[] | select(.address == "hcloud_server.web[\"web-2\"]") | .change.after.ipv4_address // empty] | .[0] // ""' "$plan_json")
  if [[ "$bad" != "0" ]]; then
    echo "::error::ga-pool-update gate: $bad change(s) outside the per-verb allow-set {pool.web_1: update, lb.app: update, notification_policy.web_lb_health: create|update} (${offenders}). NOTHING applied."
    return 1
  fi
  if [[ "$updates" == "0" ]]; then
    echo "::error::ga-pool-update gate: empty change set — a plan that grades nothing approves nothing. Refusing."
    return 1
  fi
  if [[ "$pool_updates" == "0" ]]; then
    # REMNANT-ONLY plans (partial-apply re-dispatch): a graded set carrying no
    # pool.web_1 update is NOT refused outright — the per-verb allow-set already
    # bounded every change, and the LB/policy attribute pins below still grade
    # whichever entries exist, so a {policy:create}-only plan is admissible while
    # a {lb.app update enabled:false}-only plan still refuses. The origins pins
    # are skipped only because there is no pool after-state to grade them
    # against; the repair path stays graded, never the ungraded manual apply.
    echo "cf-lb-overlay gate[ga-pool-update:${mode}]: no cloudflare_load_balancer_pool.web_1 change — grading the remaining change(s) only (LB/policy attribute pins still apply)"
  else
    # ORIGINS grading — presence-and-pin, SYMMETRIC BY RESOLVED IP in both modes:
    # the name pins below declare the planned shape {web-1@ip1, web-2@ip2}; the
    # IP pins bind the traffic reality a rename cannot dodge (a serve plan that
    # drops web-1's IP entirely, a third member shadowing at a pinned IP, a
    # name/IP swap, or a drain plan with web-1 under 1 all read as their
    # declared-shape twins under name-only grading — every one refused here).
    if [[ -z "$web1_ip" || -z "$web2_ip" ]]; then
      echo "::error::ga-pool-update gate: cannot resolve both web hosts' ipv4_address from the plan's no-op entries (web-1='${web1_ip}' web-2='${web2_ip}') — the origins set is unprovable. Refusing."
      return 1
    fi
    origins_n=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]?] | length' "$plan_json")
    if [[ "$origins_n" == "0" ]]; then
      echo "::error::ga-pool-update gate: no origins in pool after-state — a pool with zero origins serves nothing, and an absent/null origins list is unprovable. NOTHING applied."
      return 1
    fi
    bad_origins=$(jq -r --arg ip1 "$web1_ip" --arg ip2 "$web2_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | (.address // "")] | map(select(. != $ip1 and . != $ip2)) | length' "$plan_json")
    # enabled via tostring — a STRING "false" must not sail past a boolean-typed
    # comparison (uniform with the pool/LB/policy coercion below).
    disabled_n=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select((.enabled | if . == null then true else . end | tostring) == "false")] | length' "$plan_json")
    dup_names=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | (.name // "")] | group_by(.) | map(select(length > 1)) | length' "$plan_json")
    # A shadow member at a pinned address hides just as well as a shadow name —
    # {web-1@ip1, extra@ip1} splits weight off the declared member invisibly.
    dup_addrs=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | (.address // "")] | group_by(.) | map(select(length > 1)) | length' "$plan_json")
    # Name↔IP binding: a canonical name parked on the OTHER host's IP is the
    # name/IP swap — the declared shape is {web-1@web1_ip, web-2@web2_ip}.
    misbound=$(jq -r --arg ip1 "$web1_ip" --arg ip2 "$web2_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select((.name == "web-1" and .address != $ip1) or (.name == "web-2" and .address != $ip2))] | length' "$plan_json")
    w1_ok=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select(.name == "web-1" and ((.enabled | if . == null then true else . end | tostring) != "false") and ((.weight // 0) > 0))] | length' "$plan_json")
    w1ip_n=$(jq -r --arg ip1 "$web1_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select(.address == $ip1)] | length' "$plan_json")
    w2ip_n=$(jq -r --arg ip2 "$web2_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select(.address == $ip2)] | length' "$plan_json")
    if [[ "$bad_origins" != "0" ]]; then
      echo "::error::ga-pool-update gate: $bad_origins pool origin(s) outside the plan-resolved set {web-1:${web1_ip},web-2:${web2_ip}} — a repointed origin would send app.soleur.ai traffic elsewhere. NOTHING applied."
      return 1
    fi
    if [[ "$disabled_n" != "0" ]]; then
      echo "::error::ga-pool-update gate: $disabled_n origin(s) with enabled=false — a disabled member is not a drained member (drain = weight 0 + health-checked); it blinds the per-origin health signal this PR exists to repair. NOTHING applied."
      return 1
    fi
    if [[ "$dup_names" != "0" ]]; then
      echo "::error::ga-pool-update gate: duplicate origin name(s) in the pool after-state — a second name==\"web-2\" entry at weight 1 would hide behind the pinned drained entry. NOTHING applied."
      return 1
    fi
    if [[ "$dup_addrs" != "0" ]]; then
      echo "::error::ga-pool-update gate: duplicate origin address(es) in the pool after-state — a shadow member at a pinned IP splits or multiplies its weight invisibly (the address dup pin is symmetric with the name dup pin). NOTHING applied."
      return 1
    fi
    if [[ "$misbound" != "0" ]]; then
      echo "::error::ga-pool-update gate: $misbound origin(s) carry a canonical name on the WRONG plan IP (web-1 must resolve ${web1_ip}, web-2 must resolve ${web2_ip}) — a name/IP swap would serve web-2's host under web-1's name. NOTHING applied."
      return 1
    fi
    if [[ "$w1_ok" == "0" ]]; then
      echo "::error::ga-pool-update gate: no origin named web-1 with enabled!=false and weight>0 in the after-state — without it the pool has no serving member (an all-zero pool is an outage). NOTHING applied."
      return 1
    fi
    if [[ "$w1ip_n" == "0" ]]; then
      echo "::error::ga-pool-update gate: no origin resolves to web-1's plan IP (${web1_ip}) — a pool whose after-state dropped web-1's address entirely reads as its declared-shape twin under name-only grading. NOTHING applied."
      return 1
    fi
    if [[ "$w2ip_n" == "0" ]]; then
      echo "::error::ga-pool-update gate: no origin resolves to web-2's plan IP (${web2_ip}) — the drained member (drain mode) / flip target (serve mode) is absent from the after-state. NOTHING applied."
      return 1
    fi
    # Per-IP weight pins, weight compared as a NUMBER (a string "1"/"0" is not
    # the declared shape — the bash != "1" comparison it escaped is gone).
    if [[ "$mode" == "drain" ]]; then
      local w1ip_bad w2_bad
      w1ip_bad=$(jq -r --arg ip1 "$web1_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select(.address == $ip1 and ((.weight | type) != "number" or .weight != 1))] | length' "$plan_json")
      w2_bad=$(jq -r --arg ip2 "$web2_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select(.address == $ip2 and ((.weight // -1) != 0))] | length' "$plan_json")
      if [[ "$w1ip_bad" != "0" ]]; then
        echo "::error::ga-pool-update gate[drain]: $w1ip_bad origin(s) at web-1's resolved IP (${web1_ip}) carry weight != 1 — the drained shape is {web-1:1, web-2:0}; a partial web-1 weight splits traffic invisibly. NOTHING applied."
        return 1
      fi
      if [[ "$w2_bad" != "0" ]]; then
        echo "::error::ga-pool-update gate[drain]: $w2_bad origin(s) at web-2's resolved IP (${web2_ip}) carry weight != 0 — the pin binds by resolved IP, not name (a renamed origin cannot dodge it), and the 0→1 flip rides mode=serve behind the §(c) gate chain, never the drain arm. NOTHING applied."
        return 1
      fi
    else
      local w1_w w2named_w w1ip_bad w2ip_bad
      w1_w=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select(.name == "web-1") | .weight // -1] | .[0] // -1' "$plan_json")
      w2named_w=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select(.name == "web-2") | .weight // -1] | .[0] // -1' "$plan_json")
      w1ip_bad=$(jq -r --arg ip1 "$web1_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select(.address == $ip1 and ((.weight | type) != "number" or .weight != 1))] | length' "$plan_json")
      w2ip_bad=$(jq -r --arg ip2 "$web2_ip" '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after.origins[]? | select(.address == $ip2 and ((.weight | type) != "number" or .weight != 1))] | length' "$plan_json")
      if [[ "$w1_w" != "1" ]]; then
        echo "::error::ga-pool-update gate[serve]: the web-1-named origin weight is '${w1_w}', not 1 — the declared post-flip shape is {web-1:1, web-2:1}. NOTHING applied."
        return 1
      fi
      if [[ "$w2named_w" != "1" ]]; then
        echo "::error::ga-pool-update gate[serve]: the web-2-named origin weight is '${w2named_w}', not 1 — the 0→1 flip is the only act this arm exists to apply. NOTHING applied."
        return 1
      fi
      if [[ "$w1ip_bad" != "0" ]]; then
        echo "::error::ga-pool-update gate[serve]: $w1ip_bad origin(s) at web-1's resolved IP (${web1_ip}) carry weight != 1 — the pin binds by resolved IP, not name; a third member at web-1's IP or a partial weight cannot hide behind the named pins. NOTHING applied."
        return 1
      fi
      if [[ "$w2ip_bad" != "0" ]]; then
        echo "::error::ga-pool-update gate[serve]: $w2ip_bad origin(s) at web-2's resolved IP (${web2_ip}) carry weight != 1 — the pin binds by resolved IP, not name, exactly like the drain pin. NOTHING applied."
        return 1
      fi
    fi
  fi
  # Attribute pins — refuse only on EXPLICIT bad values (absent/unknown keys OK).
  # lb.app's after is graded from whichever plan entry carries it (update OR
  # converged no-op): a drifted LB shape fails the arm even when the plan does not
  # touch the LB.
  local lb_enabled lb_affinity lb_pools pool_id lb_pools_foreign lb_fallback pool_enabled pool_monitor pol_enabled pol_alert
  lb_enabled=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer.app") | (.change.after | if has("enabled") then (.enabled | tostring) else "absent" end)] | .[0] // "absent"' "$plan_json")
  if [[ "$lb_enabled" == "false" ]]; then
    echo "::error::ga-pool-update gate: cloudflare_load_balancer.app after.enabled=false — a disabled LB falls back to the bare A record and strands this update. NOTHING applied."
    return 1
  fi
  lb_affinity=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer.app") | .change.after.session_affinity // "absent"] | .[0] // "absent"' "$plan_json")
  if [[ "$lb_affinity" != "absent" && "$lb_affinity" != "none" ]]; then
    echo "::error::ga-pool-update gate: cloudflare_load_balancer.app session_affinity='${lb_affinity}', not \"none\" — ADR-068 correction (b.3): an affinity cookie overrides weight 0 and would route users to the drained host. NOTHING applied."
    return 1
  fi
  # Pool-identity pin (the repoint bound): the LB's pool references are UUIDs —
  # a literal FOREIGN pool id passes every shape check above while repointing
  # app.soleur.ai at a pool this arm never graded. The web_1 pool's own id is
  # read off the pool's change entry (before.id first — it always names the
  # existing pool; after.id as fallback). Present-empty stays refused; absent is
  # allowed; present-with-values pins EVERY element, and an unresolvable pool id
  # with values present fails closed.
  pool_id=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1") | (.change.before.id // .change.after.id // "")] | map(select(. != "")) | .[0] // ""' "$plan_json")
  lb_pools=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer.app") | (.change.after.default_pool_ids // "absent") | if type == "array" then (length | tostring) else "absent" end] | .[0] // "absent"' "$plan_json")
  if [[ "$lb_pools" == "0" ]]; then
    echo "::error::ga-pool-update gate: cloudflare_load_balancer.app default_pool_ids is present-and-empty — an LB with no default pool serves nothing. NOTHING applied."
    return 1
  fi
  if [[ "$lb_pools" != "absent" && "$lb_pools" != "0" ]]; then
    if [[ -z "$pool_id" ]]; then
      echo "::error::ga-pool-update gate: cloudflare_load_balancer.app default_pool_ids carries ${lb_pools} id(s) but the web_1 pool id cannot be resolved from the plan's own entries — an unprovable pool identity fails closed. NOTHING applied."
      return 1
    fi
    lb_pools_foreign=$(jq -r --arg pid "$pool_id" '[.resource_changes[] | select(.address == "cloudflare_load_balancer.app") | (.change.after.default_pool_ids // [])] | .[0] | map(select(. != $pid)) | length' "$plan_json")
    if [[ "$lb_pools_foreign" != "0" ]]; then
      echo "::error::ga-pool-update gate: cloudflare_load_balancer.app default_pool_ids carries ${lb_pools_foreign} id(s) != the plan-resolved web_1 pool (${pool_id}) — a literal foreign pool id repoints app.soleur.ai past every shape pin. NOTHING applied."
      return 1
    fi
  fi
  # fallback_pool_id: the same pin — when present it must BE the resolved web_1
  # pool id (absent allowed; present-empty/absent-id/foreign all refuse).
  lb_fallback=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer.app") | (.change.after | if has("fallback_pool_id") then (.fallback_pool_id // "null") else "absent" end)] | .[0] // "absent"' "$plan_json")
  if [[ "$lb_fallback" != "absent" && ( "$lb_fallback" == "null" || -z "$pool_id" || "$lb_fallback" != "$pool_id" ) ]]; then
    echo "::error::ga-pool-update gate: cloudflare_load_balancer.app fallback_pool_id='${lb_fallback}' does not equal the plan-resolved web_1 pool id ('${pool_id:-unresolvable}') — the degrade path must fall back to web-1's pool, not a foreign or empty id. NOTHING applied."
    return 1
  fi
  pool_enabled=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | (.change.after | if has("enabled") then (.enabled | tostring) else "absent" end)] | .[0] // "absent"' "$plan_json")
  if [[ "$pool_enabled" == "false" ]]; then
    echo "::error::ga-pool-update gate: pool after.enabled=false — a disabled pool serves nothing. NOTHING applied."
    return 1
  fi
  pool_monitor=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_load_balancer_pool.web_1" and .change.actions == ["update"]) | .change.after | if has("monitor") then (.monitor // "null") else "absent" end] | .[0] // "absent"' "$plan_json")
  if [[ "$pool_monitor" == "null" ]]; then
    echo "::error::ga-pool-update gate: pool after.monitor=null — unbinding the monitor re-blinds the very health signal the monitor-fix arm repairs. NOTHING applied."
    return 1
  fi
  pol_enabled=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_notification_policy.web_lb_health" and (.change.actions == ["create"] or .change.actions == ["update"])) | (.change.after | if has("enabled") then (.enabled | tostring) else "absent" end)] | .[0] // "absent"' "$plan_json")
  if [[ "$pol_enabled" == "false" ]]; then
    echo "::error::ga-pool-update gate: notification policy after.enabled=false — a disabled health alert re-creates the silent origin-down incident class this resource exists to page on. NOTHING applied."
    return 1
  fi
  # alert_type pins on BOTH verbs: if CF treats alert_type as ForceNew an update
  # carrying one can never arrive — the pin costs nothing and the grader does not
  # rely on uncited provider mutability.
  pol_alert=$(jq -r '[.resource_changes[] | select(.address == "cloudflare_notification_policy.web_lb_health" and (.change.actions == ["create"] or .change.actions == ["update"])) | .change.after.alert_type // "absent"] | .[0] // "absent"' "$plan_json")
  if [[ "$pol_alert" != "absent" && "$pol_alert" != "load_balancing_health_alert" ]]; then
    echo "::error::ga-pool-update gate: policy create/update carries alert_type='${pol_alert}', not load_balancing_health_alert — a wrong-type policy would page on nothing this arm is about. NOTHING applied."
    return 1
  fi
  local suffix=""
  [[ "$mode" == "drain" ]] && suffix=", web-2 weight=0"
  if [[ "$pool_updates" == "0" ]]; then
    echo "cf-lb-overlay gate[ga-pool-update:${mode}]: $updates remnant change(s) within the pool/LB/policy set, no pool change — LB/policy attribute pins applied — pass"
  else
    echo "cf-lb-overlay gate[ga-pool-update:${mode}]: $updates change(s) within the pool/LB/policy set, origins ⊆ {web-1:${web1_ip},web-2:${web2_ip}}${suffix} — pass"
  fi
}
