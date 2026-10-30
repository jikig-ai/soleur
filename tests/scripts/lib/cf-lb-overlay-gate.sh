# cf-lb-overlay-gate.sh — plan grader for cf-lb-overlay.yml's four arms (#11181 F3).
# Sourced, never executed directly. One function per arm; each reads the SAVED plan
# JSON (terraform show -json tfplan) and asserts the change set is EXACTLY what the
# arm is allowed to do — the same "reads the plan, not the flags" posture as
# vector-redeliver-gate.sh.
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
# Every gate FAILS CLOSED: a plan jq can't parse, a change outside the allow-set,
# or any action the arm doesn't permit → rc 1, NOTHING applied.

_cf_lb_gate_json() {
  # $1 plan.json path — must exist and contain a resource_changes array.
  local plan="$1"
  [[ -s "$plan" ]] || { echo "::error::cf-lb-overlay gate: plan JSON missing or empty ($plan)"; return 1; }
  jq -e '.resource_changes | type == "array"' "$plan" >/dev/null 2>&1 || {
    echo "::error::cf-lb-overlay gate: plan JSON has no resource_changes array — cannot grade. Refusing."
    return 1
  }
}

# staging-record: exactly one change = create cloudflare_record.lb_staging.
cf_lb_gate_record() {
  local plan="$1"
  _cf_lb_gate_json "$plan" || return 1
  local bad
  bad=$(jq -r '[.resource_changes[] |
    select(.address != "cloudflare_record.lb_staging" or .change.actions != ["create"])] | length' "$plan")
  local creates
  creates=$(jq -r '[.resource_changes[] | select(.change.actions == ["create"])] | length' "$plan")
  if [[ "$bad" != "0" || "$creates" != "1" ]]; then
    echo "::error::staging-record gate: plan is not exactly 'create cloudflare_record.lb_staging' (out-of-scope-or-wrong-action=$bad, creates=$creates). NOTHING applied."
    return 1
  fi
  echo "cf-lb-overlay gate[staging-record]: 1 create (cloudflare_record.lb_staging), 0 out-of-scope — pass"
}

# staging-overlay: creates ⊆ {RECORD, LB3}; zero deletes/updates/replaces; the LB's
# name must be exactly "lb-staging.soleur.ai" (pins the throwaway hostname so a
# config edit cannot perform the GA overlay on app.soleur.ai).
cf_lb_gate_overlay() {
  local plan="$1"
  _cf_lb_gate_json "$plan" || return 1
  local bad_creates destructive lb_name
  bad_creates=$(jq -r '[.resource_changes[] |
    select(.change.actions == ["create"]) |
    select(.address | IN("cloudflare_record.lb_staging",
      "cloudflare_load_balancer_monitor.lb_staging",
      "cloudflare_load_balancer_pool.lb_staging",
      "cloudflare_load_balancer.lb_staging") | not)] | length' "$plan")
  destructive=$(jq -r '[.resource_changes[] |
    select(.change.actions | (index("delete") or index("update") or index("replace")))] | length' "$plan")
  lb_name=$(jq -r '.resource_changes[] |
    select(.address == "cloudflare_load_balancer.lb_staging") | .change.after.name // ""' "$plan")
  local lb_creates
  lb_creates=$(jq -r '[.resource_changes[] | select(.change.actions == ["create"])] | length' "$plan")
  if [[ "$bad_creates" != "0" || "$destructive" != "0" ]]; then
    echo "::error::staging-overlay gate: plan violates allow-set (out-of-scope creates=$bad_creates, destructive/update changes=$destructive). NOTHING applied."
    return 1
  fi
  if [[ "$lb_name" != "lb-staging.soleur.ai" ]]; then
    echo "::error::staging-overlay gate: cloudflare_load_balancer.lb_staging name is '$lb_name', not 'lb-staging.soleur.ai' — refusing (the throwaway hostname pin is what keeps a config edit off app.soleur.ai). NOTHING applied."
    return 1
  fi
  echo "cf-lb-overlay gate[staging-overlay]: $lb_creates create(s) within allow-set, name=lb-staging.soleur.ai — pass"
}

# staging-teardown: EVERY change is a delete confined to the four staging addresses
# (a `terraform plan -destroy` on this root). Any create/update, or a delete outside
# the set → refuse. Zero changes is a pass (already torn down — idempotent).
cf_lb_gate_teardown() {
  local plan="$1"
  _cf_lb_gate_json "$plan" || return 1
  local bad
  bad=$(jq -r '[.resource_changes[] |
    select(.change.actions != ["delete"] or (.address | IN(
      "cloudflare_record.lb_staging",
      "cloudflare_load_balancer_monitor.lb_staging",
      "cloudflare_load_balancer_pool.lb_staging",
      "cloudflare_load_balancer.lb_staging") | not))] | length' "$plan")
  if [[ "$bad" != "0" ]]; then
    echo "::error::staging-teardown gate: $bad change(s) outside the four-address delete set (non-delete or out-of-scope). NOTHING destroyed."
    return 1
  fi
  echo "cf-lb-overlay gate[staging-teardown]: deletes confined to the staging allow-set — pass"
}

# ga-overlay (PARENT root): creates ⊆ GA3; zero deletes/updates/replaces on anything;
# dependency no-ops (e.g. hcloud_server.web["web-1"] read into the closure by -target
# transitivity) tolerated only as no-op actions.
cf_lb_gate_ga() {
  local plan="$1"
  _cf_lb_gate_json "$plan" || return 1
  local bad_creates destructive
  bad_creates=$(jq -r '[.resource_changes[] |
    select(.change.actions == ["create"]) |
    select(.address | IN("cloudflare_load_balancer_monitor.web",
      "cloudflare_load_balancer_pool.web_1",
      "cloudflare_load_balancer.app") | not)] | length' "$plan")
  destructive=$(jq -r '[.resource_changes[] |
    select(.change.actions | (index("delete") or index("update") or index("replace")))] | length' "$plan")
  if [[ "$bad_creates" != "0" || "$destructive" != "0" ]]; then
    echo "::error::ga-overlay gate: plan violates allow-set (out-of-scope creates=$bad_creates, destructive/update changes=$destructive). NOTHING applied."
    return 1
  fi
  echo "cf-lb-overlay gate[ga-overlay]: creates ⊆ GA overlay set, 0 destructive — pass"
}
