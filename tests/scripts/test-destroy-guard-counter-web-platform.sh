#!/usr/bin/env bash
# Tests for tests/scripts/lib/destroy-guard-filter-web-platform.jq (used
# inline by .github/workflows/apply-web-platform-infra.yml "Terraform plan
# (allow-list, non-SSH resources only)" step). Closes #4419 (sibling of
# #4420 — the github-infra widening).
#
# Five nested-block Cloudflare surfaces plus one reboot-update surface are
# covered:
#   1. cloudflare_ruleset.*                              .rules
#   2. cloudflare_zero_trust_tunnel_cloudflared_config.* .config[0].ingress_rule
#   3. cloudflare_zone_settings_override.*               .settings[0].security_header
#   4. cloudflare_notification_policy.*                  .email_integration
#   5. cloudflare_zero_trust_access_policy.*             .include
#   6. hcloud_server.* reboot-forcing in-place update    placement_group_id /
#                                                        server_type (#5911)
#
# Deterministic; no network. Uses synthesized fixtures plus one captured
# real `terraform show -json` baseline (redacted).
#
# Re-capturing `tfplan-web-platform-real-baseline.json` (e.g. after a
# provider upgrade trips T10) MUST use the canonical Doppler triplet
# (separate AWS_* exports + --name-transformer tf-var) per
# 2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md:
#   cd apps/web-platform/infra
#   ssh-keygen -t ed25519 -f /tmp/ci_ssh_key -N "" -q  # ephemeral; HCL file() at plan time
#   doppler run -p soleur -c prd_terraform -- terraform init -input=false
#   # Targets are the source-of-truth in apply-web-platform-infra.yml.
#   # Extract via:
#   TARGETS=$(awk '/^[[:space:]]*-target=/ { gsub(/\\$/, ""); gsub(/^[[:space:]]+/, ""); print }' \
#               ../../../.github/workflows/apply-web-platform-infra.yml | tr '\n' ' ')
#   AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain) \
#   AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain) \
#     doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
#       terraform plan -no-color -input=false -out=/tmp/tfplan \
#         -var="ssh_key_path=/tmp/ci_ssh_key.pub" $TARGETS
#   terraform show -json /tmp/tfplan > /tmp/raw.json
#   # MANDATORY redaction. Three secret-leak surfaces past `.variables`:
#   #   (1) .output_changes[*].before/after when .{before,after}_sensitive=true
#   #       — Cloudflare Access service-token client_secret (bare hex, no prefix),
#   #         Cloudflare Tunnel connector token (base64 of {a,t,s} JSON),
#   #         BetterStack heartbeat URL with path-segment auth, etc. The sentinel
#   #         regex below is BLIND to bespoke unprefixed token shapes; the only
#   #         reliable scrub is by Terraform's own sensitive-flag.
#   #   (2) .resource_changes[].change.{before,after} for sensitive-type
#   #         resources (doppler_secret.value, tls_private_key.private_key_pem,
#   #         random_id.{b64_*,hex}, github_actions_secret.plaintext_value).
#   #   (3) .planned_values / .prior_state mirror the same fields.
#   # The filter only consumes .resource_changes[].change.actions and the
#   # path-specific nested counts on the 5 vulnerable Cloudflare types — every
#   # other key is dead weight.
#   jq 'del(.variables, .planned_values, .prior_state, .configuration,
#          .relevant_attributes)
#       | (.output_changes // {}) |= with_entries(
#           if (.value.before_sensitive == true or .value.after_sensitive == true)
#           then .value.before = null | .value.after = null | .value.after_unknown = false
#           else . end)
#       | .resource_changes |= map(
#           if (.type | IN("doppler_secret","tls_private_key","random_id",
#                          "github_actions_secret","doppler_service_token",
#                          "cloudflare_zero_trust_access_service_token",
#                          "cloudflare_zero_trust_tunnel_cloudflared",
#                          "betteruptime_heartbeat"))
#           then .change.before = null | .change.after = null
#                | .change.after_unknown = {}
#                | .change.before_sensitive = false | .change.after_sensitive = false
#           else . end)' /tmp/raw.json \
#     > tests/scripts/fixtures/tfplan-web-platform-real-baseline.json
#   # Verify no secret bytes survive (extended sentinel covers Cloudflare /
#   # Doppler / Resend / Sentry bespoke shapes beyond the pre-#4419 set;
#   # MUST still hand-review the resulting JSON for tenancy identifiers the
#   # operator wants stripped — zone_id, account_id, tunnel_id):
#   ! grep -qE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_|ghs_|github_pat_|sbp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|sk_(test|live)_[a-zA-Z0-9]{24,}|sntrys_|dp\.st\.|re_[A-Za-z0-9]{16,}' \
#       tests/scripts/fixtures/tfplan-web-platform-real-baseline.json
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FILTER="$REPO_ROOT/tests/scripts/lib/destroy-guard-filter-web-platform.jq"
FIXTURES="$REPO_ROOT/tests/scripts/fixtures"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1))
    echo "[ok] $label"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label $detail" >&2
  fi
}

# Mirror the workflow's bash pipeline exactly. Returns
# "rdel:ndel:rupd:dcount:rc". Byte-identical to apply-web-platform-infra.yml's
# regex.
_run_gate() {
  local fixture="$1" head_msg="$2"
  local counts rdel ndel rupd dcount ack rc=0
  if ! counts=$(jq -f "$FILTER" < "$fixture" 2>/dev/null); then
    echo "ERROR:ERROR:ERROR:ERROR:99"
    return
  fi
  rdel=$(echo "$counts" | jq -r '.resource_deletes')
  ndel=$(echo "$counts" | jq -r '.nested_deletes')
  rupd=$(echo "$counts" | jq -r '.reboot_updates')
  if [[ ! "$rdel" =~ ^[0-9]+$ ]] || [[ ! "$ndel" =~ ^[0-9]+$ ]] || [[ ! "$rupd" =~ ^[0-9]+$ ]]; then
    echo "PARSE:PARSE:PARSE:PARSE:1"
    return
  fi
  dcount=$((rdel + ndel + rupd))
  ack=false
  if [[ "$head_msg" =~ (^|$'\n')\[ack-destroy\]($|$'\n') ]]; then
    ack=true
  fi
  if [[ "$dcount" -gt 0 ]] && [[ "$ack" != "true" ]]; then
    rc=1
  fi
  echo "$rdel:$ndel:$rupd:$dcount:$rc"
}

if [[ ! -f "$FILTER" ]]; then
  echo "ERROR: $FILTER does not exist — RED phase expected this." >&2
  exit 1
fi

# T1: cloudflare_ruleset rule removal trips guard (the ACME carve-out
# regression shape; rules 13 → 12).
t_ruleset_rule_removal_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-cf-ruleset-rule-removal.json" "feat: trim redirects")
  if [[ "$out" == "0:1:0:1:1" ]]; then
    _report "T1 cloudflare_ruleset.rules removal trips guard (rdel=0 ndel=1 rupd=0 dcount=1 rc=1)" ok
  else
    _report "T1 cloudflare_ruleset.rules removal trips guard" fail "got '$out' want '0:1:0:1:1'"
  fi
}

# T2: cloudflare_zero_trust_tunnel ingress_rule removal trips guard
# (SSH ingress shape; would brick CI deploy pipeline).
t_tunnel_ingress_removal_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-cf-tunnel-ingress-removal.json" "feat: prune ssh ingress")
  if [[ "$out" == "0:1:0:1:1" ]]; then
    _report "T2 cloudflare_zero_trust_tunnel ingress_rule removal trips guard" ok
  else
    _report "T2 cloudflare_zero_trust_tunnel ingress_rule removal trips guard" fail "got '$out' want '0:1:0:1:1'"
  fi
}

# T3: cloudflare_zone_settings_override security_header removal trips
# guard (HSTS off; single-block-shrinkage variant).
t_zone_settings_header_removal_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-cf-zone-settings-header-removal.json" "feat: drop HSTS")
  if [[ "$out" == "0:1:0:1:1" ]]; then
    _report "T3 cloudflare_zone_settings_override security_header removal trips guard" ok
  else
    _report "T3 cloudflare_zone_settings_override security_header removal trips guard" fail "got '$out' want '0:1:0:1:1'"
  fi
}

# T4: cloudflare_notification_policy email_integration removal trips guard.
t_notification_email_removal_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-cf-notification-integration-removal.json" "feat: silence expiry alerts")
  if [[ "$out" == "0:1:0:1:1" ]]; then
    _report "T4 cloudflare_notification_policy email_integration removal trips guard" ok
  else
    _report "T4 cloudflare_notification_policy email_integration removal trips guard" fail "got '$out' want '0:1:0:1:1'"
  fi
}

# T5: cloudflare_zero_trust_access_policy include removal trips guard.
t_access_policy_include_removal_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-cf-access-policy-include-removal.json" "feat: empty access policy")
  if [[ "$out" == "0:1:0:1:1" ]]; then
    _report "T5 cloudflare_zero_trust_access_policy include removal trips guard" ok
  else
    _report "T5 cloudflare_zero_trust_access_policy include removal trips guard" fail "got '$out' want '0:1:0:1:1'"
  fi
}

# T6: no-changes plan passes silently.
t_no_changes_passes() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-web-platform-no-changes.json" "feat: docs only")
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T6 no-changes plan passes (rdel=0 ndel=0 rupd=0 dcount=0 rc=0)" ok
  else
    _report "T6 no-changes plan passes" fail "got '$out' want '0:0:0:0:0'"
  fi
}

# T7: resource-level delete on cloudflare_ruleset — no double-count by
# nested clause (select(.. | not) guard). rdel=1, ndel=0.
t_ruleset_resource_delete_no_double_count() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-cf-ruleset-resource-delete.json" "feat: drop allowlist_ai_crawlers ruleset")
  if [[ "$out" == "1:0:0:1:1" ]]; then
    _report "T7 cloudflare_ruleset resource-delete: no nested double-count" ok
  else
    _report "T7 cloudflare_ruleset resource-delete: no nested double-count" fail "got '$out' want '1:0:0:1:1'"
  fi
}

# T8: mixed plan (1 resource-delete + 1 nested removal across different
# resources) — both counters increment, dcount=2.
t_mixed_delete_and_nested() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-web-platform-mixed.json" "feat: drop www + trim cache rules")
  if [[ "$out" == "1:1:0:2:1" ]]; then
    _report "T8 mixed resource-delete + nested removal sum to 2" ok
  else
    _report "T8 mixed resource-delete + nested removal sum to 2" fail "got '$out' want '1:1:0:2:1'"
  fi
}

# T9: rule ADDITION (before=12, after=13) — select(. > 0) filters
# additions, dcount=0.
t_ruleset_rule_addition_passes() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-cf-ruleset-rule-addition.json" "feat: add /legal/dpa redirect")
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T9 cloudflare_ruleset rule addition is ignored (rdel=0 ndel=0)" ok
  else
    _report "T9 cloudflare_ruleset rule addition is ignored" fail "got '$out' want '0:0:0:0:0'"
  fi
}

# T10: regression anchor against captured real baseline plan.
t_real_baseline_zero() {
  if [[ ! -f "$FIXTURES/tfplan-web-platform-real-baseline.json" ]]; then
    _report "T10 captured real baseline yields destroy_count=0 (regression anchor)" fail \
      "fixture missing — operator must capture per file-header procedure"
    return
  fi
  local out; out=$(_run_gate "$FIXTURES/tfplan-web-platform-real-baseline.json" "")
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T10 captured real baseline yields destroy_count=0 (regression anchor)" ok
  else
    _report "T10 captured real baseline yields destroy_count=0 (regression anchor)" fail "got '$out' want '0:0:0:0:0'"
  fi
}

# T11: nested removal + [ack-destroy] line allows through.
t_ack_destroy_allows_nested() {
  local msg
  msg=$'feat: prune redirects\n\n[ack-destroy]\n\nRefs #4419.'
  local out; out=$(_run_gate "$FIXTURES/tfplan-cf-ruleset-rule-removal.json" "$msg")
  if [[ "$out" == "0:1:0:1:0" ]]; then
    _report "T11 [ack-destroy] line allows nested removal through (rc=0)" ok
  else
    _report "T11 [ack-destroy] line allows nested removal through" fail "got '$out' want '0:1:0:1:0'"
  fi
}

# T12: [ack-destroy] as substring mid-line (NOT line-anchored) must NOT
# satisfy the gate. Pins the (^|\n)\[ack-destroy\]($|\n) regex.
t_ack_destroy_substring_rejected() {
  local msg="chore: discuss [ack-destroy] policy inline"
  local out; out=$(_run_gate "$FIXTURES/tfplan-cf-ruleset-rule-removal.json" "$msg")
  if [[ "$out" == "0:1:0:1:1" ]]; then
    _report "T12 [ack-destroy] substring (not line-anchored) is rejected (rc=1)" ok
  else
    _report "T12 [ack-destroy] substring (not line-anchored) is rejected" fail "got '$out' want '0:1:0:1:1'"
  fi
}

# ---------------------------------------------------------------------------
# 6th surface (#5911): hcloud_server.* reboot-forcing in-place `update`.
# `placement_group_id` / `server_type` change → power-off reboot of the
# RUNNING host with ZERO destroys — invisible to resource_deletes + the 5
# Cloudflare nested clauses. reboot_updates (rupd) counts these. Reuses the
# same `[ack-destroy]` gate (no new token; regex-parity still 6 sites).
# ---------------------------------------------------------------------------

# T13: SINGLETON hcloud_server.web placement_group_id 0 → 987654 in-place
# update trips the guard (rupd=1). Live pre-migration shape (placement-group
# `moved` not yet operator-consumed).
t_hcloud_placement_group_update_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-hcloud-server-placement-group-update.json" "feat: pin web to placement group")
  if [[ "$out" == "0:0:1:1:1" ]]; then
    _report "T13 hcloud_server.web placement_group_id update trips guard (rdel=0 ndel=0 rupd=1 dcount=1 rc=1)" ok
  else
    _report "T13 hcloud_server.web placement_group_id update trips guard" fail "got '$out' want '0:0:1:1:1'"
  fi
}

# T14: after-unknown placement_group_id (resource-reference resolved
# same-plan: after.placement_group_id absent, value in after_unknown, before
# = 0). `0 != null` still trips (errs SAFE — an unknown `after` never yields a
# missed reboot). for_each ["web-1"] shape.
t_hcloud_placement_group_after_unknown_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-hcloud-server-placement-group-after-unknown.json" "feat: rewire placement group")
  if [[ "$out" == "0:0:1:1:1" ]]; then
    _report "T14 hcloud_server placement_group_id after-unknown still trips (0 != null)" ok
  else
    _report "T14 hcloud_server placement_group_id after-unknown still trips" fail "got '$out' want '0:0:1:1:1'"
  fi
}

# T15: server_type cx33 → cx43 in-place update (multi-attr: labels also
# change) trips the guard. Pins that detection keys off the reboot-attr diff
# even when a non-reboot attr also changes.
t_hcloud_server_type_update_trips() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-hcloud-server-type-update.json" "feat: resize web to cx43")
  if [[ "$out" == "0:0:1:1:1" ]]; then
    _report "T15 hcloud_server server_type update trips guard (multi-attr)" ok
  else
    _report "T15 hcloud_server server_type update trips guard" fail "got '$out' want '0:0:1:1:1'"
  fi
}

# T16: location change forces a REPLACE (actions ["delete","create"]) —
# counted by resource_deletes (rdel=1), NOT double-counted by the reboot
# clause (rupd=0). The invariant-not-proxy anchor.
t_hcloud_location_replace_no_double_count() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-hcloud-server-location-replace.json" "feat: move web to fsn1")
  if [[ "$out" == "1:0:0:1:1" ]]; then
    _report "T16 hcloud_server location REPLACE counted by resource_deletes, not reboot clause" ok
  else
    _report "T16 hcloud_server location REPLACE not double-counted" fail "got '$out' want '1:0:0:1:1'"
  fi
}

# T17: in-place update changing a NON-reboot attr only (labels) — reboot
# attrs unchanged. rupd=0 (proves the clause detects the reboot-forcing
# ATTRIBUTE diff, not merely "hcloud_server has an update action").
t_hcloud_noop_attr_update_passes() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-hcloud-server-noop-attr-update.json" "feat: relabel web")
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T17 hcloud_server non-reboot attr update ignored (rupd=0)" ok
  else
    _report "T17 hcloud_server non-reboot attr update ignored" fail "got '$out' want '0:0:0:0:0'"
  fi
}

# T18: CREATE of a 2nd host (hcloud_server.web["web-2"]) — a legit new host,
# not a reboot. reboot clause selects only ["update"], so rupd=0.
t_hcloud_create_passes() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-hcloud-server-create.json" "feat: add web-2 host")
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T18 hcloud_server create (web-2 add) is not a reboot (rupd=0)" ok
  else
    _report "T18 hcloud_server create is not a reboot" fail "got '$out' want '0:0:0:0:0'"
  fi
}

# T19: [ack-destroy] on its own line allows a reboot-forcing update through
# (rc=0). Per the issue's "[ack-destroy]-style acknowledgement" requirement —
# an emergency override, NOT the normal reboot resolution (see the filter
# header + the workflow ::error:: steer to the operator maintenance-window
# apply).
t_hcloud_reboot_ack_allows() {
  local msg
  msg=$'feat: pin web to placement group\n\n[ack-destroy]\n\nRefs #5911.'
  local out; out=$(_run_gate "$FIXTURES/tfplan-hcloud-server-placement-group-update.json" "$msg")
  if [[ "$out" == "0:0:1:1:0" ]]; then
    _report "T19 [ack-destroy] allows reboot-forcing update through (rc=0)" ok
  else
    _report "T19 [ack-destroy] allows reboot-forcing update through" fail "got '$out' want '0:0:1:1:0'"
  fi
}

t_ruleset_rule_removal_trips
t_tunnel_ingress_removal_trips
t_zone_settings_header_removal_trips
t_notification_email_removal_trips
t_access_policy_include_removal_trips
t_no_changes_passes
t_ruleset_resource_delete_no_double_count
t_mixed_delete_and_nested
t_ruleset_rule_addition_passes
t_real_baseline_zero
t_ack_destroy_allows_nested
t_ack_destroy_substring_rejected
t_hcloud_placement_group_update_trips
t_hcloud_placement_group_after_unknown_trips
t_hcloud_server_type_update_trips
t_hcloud_location_replace_no_double_count
t_hcloud_noop_attr_update_passes
t_hcloud_create_passes
t_hcloud_reboot_ack_allows

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
