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
# The web-2 RETIRE gate (#6538) is an EXTRACTED, SOURCED shell function (AC5/AC6) —
# this test calls it DIRECTLY (not a re-derived inline copy), so the bytes the
# operator runs are the bytes under test.
#
# It is graded against web2_retire_allow, which REQUIRES hcloud_volume.workspaces
# ["web-2"] because destroying the data volume IS the retirement. An allow-set is
# specific to ONE operation's contract; the sibling recreate gate that encoded the
# opposite contract (preserve the volume) was deleted with the dispatch sweep
# (#6575, 2026-07-20). Never grade one operation's plan against another's set.
WEB2_RETIRE_GATE_LIB="$REPO_ROOT/tests/scripts/lib/web2-retire-gate.sh"
# shellcheck source=tests/scripts/lib/web2-retire-gate.sh
source "$WEB2_RETIRE_GATE_LIB"
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

# 7th surface (#6416): the `host_creates` HALT. Deliberately a SECOND, SEPARATE
# rc source rather than a 6th field threaded through _run_gate, for two reasons:
#
#   1. _run_gate's "$rdel:$ndel:$rupd:$dcount:$rc" string encodes the ack
#      semantics (rc=1 iff dcount>0 && !ack). The host_creates HALT is
#      ack-INDEPENDENT and sits OUTSIDE the destroy_count sum, so it cannot be
#      expressed by that rc at all — it needs its own.
#   2. Widening the string would touch ~54 counter-string assertions across
#      T1–T28 for zero added signal: host_creates is 0 in every one of them.
#
# Mirrors apply-web-platform-infra.yml's host_creates block exactly. Takes NO
# head_msg parameter — that absence IS the ack-independence, structurally: the
# workflow's HALT never reads HEAD_MSG. T29b proves it against a live
# [ack-destroy] message. Returns "hc:rc".
_run_host_creates_gate() {
  local fixture="$1"
  local counts hc rc=0
  if ! counts=$(jq -f "$FILTER" < "$fixture" 2>/dev/null); then
    echo "ERROR:99"
    return
  fi
  hc=$(echo "$counts" | jq -r '.host_creates')
  # Fail-closed numeric validation: an empty value from a jq failure would
  # silently evaluate false in the `-gt 0` test and let a host create slip past.
  if [[ ! "$hc" =~ ^[0-9]+$ ]]; then
    echo "PARSE:1"
    return
  fi
  if [[ "$hc" -gt 0 ]]; then
    rc=1
  fi
  echo "$hc:$rc"
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

# T18: CREATE of a 2nd host (hcloud_server.web["web-2"]) is not a REBOOT — the
# reboot clause selects only ["update"], so rupd=0. That invariant is unchanged
# and still worth pinning.
#
# What T18 no longer claims (#6416): this fixture used to be named "a legit new
# host" and its 0:0:0:0:0 was read as "…therefore the plan is fine". It is not.
# A `+ create` of hcloud_server on the per-PR apply path is exactly the drift
# that left soleur-web-2 alive with NO private-net attachment — invisible to
# resource_deletes, nested_deletes AND reboot_updates alike. The reboot gate
# passing it is correct; the CONCLUSION that it was therefore legitimate was the
# codified belief this plan overturns. T29 is where that plan shape now HALTs.
t_hcloud_create_is_not_a_reboot() {
  local out; out=$(_run_gate "$FIXTURES/tfplan-hcloud-server-create.json" "feat: add web-2 host")
  if [[ "$out" == "0:0:0:0:0" ]]; then
    _report "T18 hcloud_server create is not a REBOOT (rupd=0; legitimacy is T29's call, not this gate's)" ok
  else
    _report "T18 hcloud_server create is not a REBOOT" fail "got '$out' want '0:0:0:0:0'"
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

# ---------------------------------------------------------------------------
# 7th surface (#6416): `host_creates` — a pure `+ create` of an hcloud_server /
# hcloud_volume on the per-PR apply path.
#
# Why a 7th counter was needed: `-target` is transitive at the RESOURCE level, so
# every allow-listed resource referencing ANY hcloud_server.web instance
# (cloudflare_record.app at dns.tf:16, hcloud_firewall_attachment.web at
# firewall.tf:93) pulls the whole for_each map — web-2 included. A pure create
# has no delete, no nested-block shrinkage and no ["update"], so all three
# existing counters read 0 and the plan sails through. That is how web-2 was born
# on a per-PR apply WITHOUT its hcloud_server_network attachment (#6416): the
# attachment is not itself target-reachable, so the host came up on the public
# IP only and could never reach zot at 10.0.1.30:5000.
#
# The gate is a TRIPWIRE, not a routine gate: host_creates == 0 on every normal
# merge (T30/T31 pin that), so this costs nothing until the drift recurs.
# ---------------------------------------------------------------------------

# T29 (RED→GREEN anchor): the exact plan shape from #6416 — a per-PR
# `hcloud_server.web["web-2"]` create — HALTs. Reuses the EXISTING
# tfplan-hcloud-server-create.json fixture (measured host_creates=1); T18 above
# asserts the same fixture is invisible to all three legacy counters, so this
# pair is the whole argument for the 7th surface in two tests.
t_host_create_halts() {
  local out; out=$(_run_host_creates_gate "$FIXTURES/tfplan-hcloud-server-create.json")
  if [[ "$out" == "1:1" ]]; then
    _report "T29 per-PR hcloud_server create HALTs (hc=1 rc=1 — the #6416 drift shape)" ok
  else
    _report "T29 per-PR hcloud_server create HALTs" fail "got '$out' want '1:1'"
  fi
}

# T29b (no ack bypass): the SAME fixture with a line-anchored [ack-destroy].
# _run_gate returns rc=0 (the legacy gate never even fires — dcount=0), while the
# host_creates gate still returns rc=1. Proves the HALT sits OUTSIDE the
# destroy_count sum and has no ack path: an operator cannot type their way past a
# host create the way they can past a nested-block removal (T11).
t_host_create_no_ack_bypass() {
  local msg
  msg=$'feat: add web-2 host\n\n[ack-destroy]\n\nRefs #6416.'
  local legacy; legacy=$(_run_gate "$FIXTURES/tfplan-hcloud-server-create.json" "$msg")
  local out; out=$(_run_host_creates_gate "$FIXTURES/tfplan-hcloud-server-create.json")
  if [[ "$legacy" == "0:0:0:0:0" && "$out" == "1:1" ]]; then
    _report "T29b [ack-destroy] cannot bypass the host_creates HALT (legacy rc=0, host_creates rc=1)" ok
  else
    _report "T29b [ack-destroy] cannot bypass the host_creates HALT" fail \
      "got legacy='$legacy' (want '0:0:0:0:0') host_creates='$out' (want '1:1')"
  fi
}

# T30 (a REPLACE births a host and must HALT): a location change forces a REPLACE
# (["delete","create"]). It DESTROYS AND RE-CREATES the host — and the reborn host
# has no hcloud_server_network attach, exactly like a fresh create. So it must trip
# host_creates.
#
# This test asserted the OPPOSITE until review (`0:0`, "not double-counted"). That
# was wrong, and it was the guard's most dangerous hole: a replace trips
# resource_deletes, the destroy gate then prints "Add [ack-destroy] to
# acknowledge", and an author acking a legitimate sibling change in the same merge
# would ack the host rebirth through with it — #6416 reproducing THROUGH the guard.
# There was never a double-count to avoid: host_creates is not a term in the
# workflow's destroy_count sum, and the HALT is evaluated first and
# unconditionally, so the destroy gate's count is never reached on this plan.
t_host_replace_halts() {
  local out; out=$(_run_host_creates_gate "$FIXTURES/tfplan-hcloud-server-location-replace.json")
  if [[ "$out" == "1:1" ]]; then
    _report "T30 hcloud_server REPLACE HALTs (hc=1 rc=1 — a reborn host is an unattached host)" ok
  else
    _report "T30 hcloud_server REPLACE HALTs" fail "got '$out' want '1:1'"
  fi
}

# T31 (no false-fire on the steady state): the captured real baseline must read
# host_creates=0, i.e. the tripwire is silent on a normal merge.
t_host_creates_baseline_zero() {
  if [[ ! -f "$FIXTURES/tfplan-web-platform-real-baseline.json" ]]; then
    _report "T31 captured real baseline yields host_creates=0" fail "fixture missing"
    return
  fi
  local out; out=$(_run_host_creates_gate "$FIXTURES/tfplan-web-platform-real-baseline.json")
  if [[ "$out" == "0:0" ]]; then
    _report "T31 captured real baseline yields host_creates=0 (tripwire silent on normal merges)" ok
  else
    _report "T31 captured real baseline yields host_creates=0" fail "got '$out' want '0:0'"
  fi
}

# T32 (fail-closed, not fail-open): a malformed plan document must ABORT, never
# coast. Mirrors the workflow's numeric-parse validation — the block whose own
# comment warns that "empty values from a jq failure would silently evaluate
# false in the `-gt 0` test and let destructive plans slip past the guard".
t_host_creates_parse_failure_fails_closed() {
  local tmp; tmp=$(mktemp)
  printf 'not json at all' > "$tmp"
  local out; out=$(_run_host_creates_gate "$tmp")
  rm -f "$tmp"
  if [[ "$out" == "ERROR:99" ]]; then
    _report "T32 malformed plan document fails CLOSED (rc!=0, never a silent pass)" ok
  else
    _report "T32 malformed plan document fails CLOSED" fail "got '$out' want 'ERROR:99'"
  fi
}

# ---------------------------------------------------------------------------
# T40-T49 — the web-2 RETIRE gate (#6538). Graded against web2_retire_allow (5
# addresses). The 3-address recreate allow-set it used to contrast against was
# deleted with the dispatch sweep (#6575).
#
# THE NO-STRAND INVARIANT (T43). B6.2's local plan destroys 4 web-2 resources +
# updates hcloud_firewall_attachment.web. Terraform applies sequentially and can
# die mid-way, so the gate must accept any RETRY SUBSET (T41/T42) — strict
# equality would fail closed on retry and strand a half-retired host forever.
# But a bare subset rule would also accept the push-apply shape (measured
# 2026-07-17: `0 to add, 1 to change, 1 to destroy` — server destroyed, volume
# NOT in scope), which is the exact hazard: the server dies, the 20 GB volume
# survives and bills forever with nothing attached to it.
#
# The discriminator is an IMPLICATION, not a count:
#     web2_server_destroyed == 1  =>  web2_volume_destroyed == 1
# A plan is computed from CURRENT state, so:
#   - fresh retire  : both in state, both destroyed        -> 1=>1  PASS (T40)
#   - retry (server already gone): server_destroyed=0      -> vacuous PASS (T41/T42)
#   - push-apply shape: server destroyed, volume unscoped  -> 1=>0  ABORT (T43)
# This is subset-safe AND strand-proof with no strict equality.
_run_web2_retire_gate() {
  local fixture="$1" path counts oos srv net vat vol fwu fwd rc
  path="$FIXTURES/$fixture"
  if ! counts=$(jq -f "$FILTER" < "$path" 2>/dev/null); then
    echo "ERROR:99"; return 0
  fi
  oos=$(echo "$counts" | jq -r '.web2_retire_out_of_scope_changes')
  srv=$(echo "$counts" | jq -r '.web2_server_destroyed')
  net=$(echo "$counts" | jq -r '.web2_server_network_destroyed')
  vat=$(echo "$counts" | jq -r '.web2_volume_attachment_destroyed')
  vol=$(echo "$counts" | jq -r '.web2_volume_destroyed')
  fwu=$(echo "$counts" | jq -r '.retire_firewall_attachment_updates')
  fwd=$(echo "$counts" | jq -r '.retire_firewall_attachment_deletes')
  web2_retire_gate "$path" >/dev/null 2>&1 && rc=0 || rc=$?
  # Column order is LOAD-BEARING — every T40-T49 assertion pins this exact tuple.
  # Legend: oos : server_destroyed : network_destroyed : volume_attachment_destroyed :
  #         volume_destroyed : firewall_updates : firewall_deletes : gate_rc.
  echo "$oos:$srv:$net:$vat:$vol:$fwu:$fwd:$rc"
}

# T40: the exact measured B6.2 shape (4 destroys + 1 firewall update) PASSES.
# Measured live 2026-07-17 over the 5-target scope: `0 to add, 1 to change, 4 to destroy`.
t_web2_retire_scoped_passes() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-scoped.json")
  if [[ "$out" == "0:1:1:1:1:1:0:0" ]]; then
    _report "T40 web-2 retire scoped shape PASSES (4 destroys + fw update)" ok
  else
    _report "T40 web-2 retire scoped shape PASSES" fail "got '$out' want '0:1:1:1:1:1:0:0'"
  fi
}

# T41: RETRY after the apply died having destroyed the server — 3 of 4 remain.
# MUST PASS (B1.7): strict equality here strands a half-retired host.
t_web2_retire_retry_3of4_passes() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-retry-3of4.json")
  if [[ "$out" == "0:0:1:1:1:0:0:0" ]]; then
    _report "T41 web-2 retire RETRY (3 of 4 remaining) PASSES — subset, not equality" ok
  else
    _report "T41 web-2 retire RETRY (3 of 4 remaining) PASSES" fail "got '$out' want '0:0:1:1:1:0:0:0'"
  fi
}

# T42: RETRY where only the volume remains. Same destroy COUNT as the stranding
# shape (T43) — only the ADDRESS differs. Proves the gate discriminates by
# address, not by counting destroys.
t_web2_retire_retry_volume_only_passes() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-retry-volume-only.json")
  if [[ "$out" == "0:0:0:0:1:0:0:0" ]]; then
    _report "T42 web-2 retire RETRY (volume only) PASSES — discriminates by address" ok
  else
    _report "T42 web-2 retire RETRY (volume only) PASSES" fail "got '$out' want '0:0:0:0:1:0:0:0'"
  fi
}

# T43: THE STRANDING HAZARD. The measured push-apply shape (server destroyed,
# volume not in scope) fed to the retire gate MUST ABORT. Applying it kills the
# host and leaves a 20 GB orphan volume billing with nothing attached.
t_web2_retire_server_only_strands_volume_aborts() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-server-only-strands-vol.json")
  if [[ "$out" == "0:1:0:0:0:1:0:1" ]]; then
    _report "T43 server-only ABORTS — no-strand invariant (server=>volume)" ok
  else
    _report "T43 server-only ABORTS — no-strand invariant" fail "got '$out' want '0:1:0:0:0:1:0:1'"
  fi
}

# T44: any web-1 touch is out-of-scope -> ABORT. web-1 is the sole live origin.
t_web2_retire_web1_touch_aborts() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-web1-touch.json")
  if [[ "$out" == "1:1:1:1:1:1:0:1" ]]; then
    _report "T44 web-1 delete ABORTS (oos=1)" ok
  else
    _report "T44 web-1 delete ABORTS" fail "got '$out' want '1:1:1:1:1:1:0:1'"
  fi
}

# T45: web-1's VOLUME destroy -> ABORT. Pins the volume counter to the exact
# web-2 address: a bare `hcloud_volume.*` count would let web-1's volume satisfy it.
t_web2_retire_web1_volume_destroy_aborts() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-web1-volume-destroy.json")
  if [[ "$out" == "1:1:1:1:1:1:0:1" ]]; then
    _report "T45 web-1 VOLUME destroy ABORTS (address-pinned, not hcloud_volume.*)" ok
  else
    _report "T45 web-1 VOLUME destroy ABORTS" fail "got '$out' want '1:1:1:1:1:1:0:1'"
  fi
}

# T46: firewall attachment DELETE -> ABORT. The attachment must UPDATE (dropping
# web-2 from server_ids). A delete strips web-1's firewall entirely.
t_web2_retire_firewall_delete_aborts() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-firewall-delete.json")
  if [[ "$out" == "0:1:1:1:1:0:1:1" ]]; then
    _report "T46 firewall attachment DELETE ABORTS (never delete — strips web-1)" ok
  else
    _report "T46 firewall attachment DELETE ABORTS" fail "got '$out' want '0:1:1:1:1:0:1:1'"
  fi
}

# T47: THE ADR-118 BIRTH HAZARD (D1(A), measured 2026-07-17). The proxy-TLS
# resources are ABSENT from state and from Doppler prd — `proxy-tls.tf` is
# "contract before consumer" config that was never applied. So they plan as
# CREATE, not replace/update. They are deliberately ABSENT from web2_retire_allow,
# so any attempt to birth them inside a host retirement trips oos -> ABORT.
# Guards against re-adding `-target=doppler_secret.proxy_tls_cert` to B6.2, which
# would write PROXY_TLS_CERT to prd with NO matching PROXY_TLS_KEY.
t_web2_retire_proxy_tls_birth_aborts() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-proxy-tls-birth.json")
  if [[ "$out" == "2:1:1:1:1:1:0:1" ]]; then
    _report "T47 proxy-TLS create ABORTS (oos=2 — no keyless cert into prd)" ok
  else
    _report "T47 proxy-TLS create ABORTS" fail "got '$out' want '2:1:1:1:1:1:0:1'"
  fi
}

# T48: a no-op plan ABORTS — the gate must not authorize an apply that does
# nothing (the dispatch must be a real, scoped retirement).
t_web2_retire_noop_aborts() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-noop.json")
  if [[ "$out" == "0:0:0:0:0:0:0:1" ]]; then
    _report "T48 no-op plan ABORTS (>=1 member required)" ok
  else
    _report "T48 no-op plan ABORTS" fail "got '$out' want '0:0:0:0:0:0:0:1'"
  fi
}

# T50: THE RESURRECTION HAZARD. A web-2 server REPLACE (delete+create) is entirely
# in-allow-set (oos=0) and does not strand the volume (srv=1 <= vol=1), so the
# no-strand + oos + firewall checks all pass — yet it REBIRTHS the host the retire
# exists to destroy (the #6416 unattached-reborn-host failure mode). The retire
# gate must be as strict as its siblings (the per-PR path's host_creates HALT and
# the recreate gate's web2_server_replaced guard both stop this). A pure retire
# CREATES nothing, so host_creates==0 is the guard; it aborts with oos=0 and
# srv<=vol, uniquely implicating the host_creates check.
t_web2_retire_server_replace_aborts() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-server-replace.json")
  if [[ "$out" == "0:1:1:1:1:1:0:1" ]]; then
    _report "T50 web-2 server REPLACE ABORTS — no resurrection (host_creates==0)" ok
  else
    _report "T50 web-2 server REPLACE ABORTS" fail "got '$out' want '0:1:1:1:1:1:0:1'"
  fi
}

# T49: a Terraform 1.7+ `removed{}` state-drop on the web-2 volume serializes as
# actions==["forget"] — it drops the resource from state WITHOUT destroying the
# real volume. That is the stranding hazard wearing a different hat: the volume
# survives, bills, and Terraform no longer knows about it. "forget" must NOT
# satisfy web2_volume_destroyed.
t_web2_retire_volume_forget_aborts() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-volume-forget.json")
  if [[ "$out" == "0:1:1:1:0:1:0:1" ]]; then
    _report "T49 volume ['forget'] ABORTS — a state-drop is not a destroy" ok
  else
    _report "T49 volume ['forget'] ABORTS" fail "got '$out' want '0:1:1:1:0:1:0:1'"
  fi
}

# T57 — SUBSTRING-COLLISION: an otherwise-perfect retire plan that ALSO touches the
# bare `hcloud_server.web` (no for_each key) must ABORT. This pins the allow-set
# membership test to EXACT equality via IN(.address; web2_retire_allow[]): an
# `inside`/array-`contains` form does SUBSTRING matching, so the bare address would
# false-match `hcloud_server.web["web-2"]` and sail through while a real change to
# the whole for_each map went ungated.
#
# RETARGETED from the web-2-recreate gate (#6575, 2026-07-20). The recreate gate and
# its fixtures were deleted with the dispatch sweep, but this was the ONLY direct test
# of the exact-equality mechanism, and the retire gate uses the same construct — so the
# fixture was re-derived against web2_retire_allow rather than dropped. Deleting it
# would have lowered coverage of a live gate to zero for the sake of removing a dead one.
t_web2_retire_substring_collision_aborts() {
  local out; out=$(_run_web2_retire_gate "tfplan-web2-retire-substring-collision.json")
  if [[ "$out" == "1:1:1:1:1:1:0:1" ]]; then
    _report "T57 bare hcloud_server.web ABORTS (IN() exact-equality, not substring)" ok
  else
    _report "T57 bare hcloud_server.web ABORTS" fail "got '$out' want '1:1:1:1:1:1:0:1'"
  fi
}

# ---------------------------------------------------------------------------
# STRUCTURAL host_creates HALT proofs (#6718) — the grep-over-YAML technique.
#
# The warm_standby job that originally motivated this block was deleted with the
# web-2 dispatch sweep (#6575, 2026-07-20). The technique and its four sharp edges
# still bind the SURVIVING proofs below: T54 (`apply`) and T56 (deploy-pipeline-fix).
#
# WHY A GREP OVER THE YAML AND NOT A COUNTS FIXTURE. `_run_host_creates_gate`
# above is a hand-maintained bash MIRROR of the workflow block (its own header
# says so; nothing enforces the mirror). A fixture therefore proves the MIRROR,
# never the workflow — it would stay green if the real YAML lost the guard
# tomorrow. Only a grep over the workflow can prove the job's own regex. T32 already covers the mirror's parse-failure arm, so this adds the one
# proof that was missing rather than a second copy of one that exists.
#
# WHY THESE JOBS NEED IT. Each -targets a resource referencing hcloud_server.web
# ["web-1"], and `-target` is TRANSITIVE at the resource level, so the server sits
# in the plan graph. Neither passes -var image_name, so a transitive web-1 birth
# would use the mutable :latest default — and web-1 is the sole web host since
# web-2 retired 2026-07-17 (#6538). No automated path may birth it (#6730). Reason about THIS tripwire, never about -target
# membership: "web-1 appears in no -target=" is a recorded invalid inference
# (ADR-114 2026-07-19 amendment item 5).
#
# SHARP EDGES THIS TEST IS BUILT AROUND:
#   SE-1  The block MUST be extracted with flag-based awk. A range address
#         (`awk '/^  <job>:/,/^  [a-z-]+:/'`) SELF-MATCHES: the end
#         pattern is satisfied by the start line, so it yields the heading alone
#         and every `grep -c` over it reads 0 — assertions that pass on an empty
#         body. Non-emptiness is therefore asserted FIRST.
#   SE-2  Never `printf "$block" | grep -q`. Under `set -o pipefail` a matching
#         `grep -q` closes the pipe, the producer takes SIGPIPE (141), and the
#         pipeline exits non-zero DESPITE the match. Here-strings throughout.
#   SE-4  `[[ "null" -gt 0 ]]` is TRUE-shaped and evaluates FALSE: `jq -r` on a
#         missing key yields the string "null", which `[[ ]]` resolves as an
#         unset name to 0. So the ^[0-9]+$ VALIDATION line — not the comparison
#         — is the load-bearing assert. Without it the guard fails OPEN.
#
# Comments are stripped before asserting: a body-grep sees comment prose too,
# and every token below also appears in the explanatory comments around it, so
# an unstripped block would false-PASS on its own documentation.
# ---------------------------------------------------------------------------

WORKFLOW_YML="${REPO_ROOT}/.github/workflows/apply-web-platform-infra.yml"

_job_block() {
  local file="$1" job="$2"
  awk -v job="$job" '
    $0 ~ "^  " job ":([[:space:]]|$)" { inblock = 1; print; next }
    inblock && /^  [A-Za-z_]/ { inblock = 0 }
    inblock && /^[A-Za-z]/    { inblock = 0 }
    inblock { print }
  ' "$file"
}

# ── T56 — the SECOND workflow that reaches hcloud_server.web. ────────────────
#
# apply-deploy-pipeline-fix.yml fires on push:main AND workflow_dispatch and
# runs `terraform apply -auto-approve` over four terraform_data targets that each
# reference hcloud_server.web["web-1"] (server_id / connection host), so -target
# transitivity puts the server in its plan graph, and it passes no -var
# image_name either.
#
# It was UNGUARDED and unenumerated until #6725's review: that PR asserted "no
# automated path can birth a web host" without walking the workflow list. The
# assertion was false. This assert exists so the claim stays checkable rather
# than re-asserted — if someone strips the guard, the enumeration in the sibling
# HALT texts, both ADRs and #6730 all become false again, silently.
t_deploy_pipeline_fix_carries_host_creates_halt() {
  local wf code validation
  wf="${REPO_ROOT}/.github/workflows/apply-deploy-pipeline-fix.yml"
  if [[ ! -f "$wf" ]]; then
    _report "T56 apply-deploy-pipeline-fix carries the host_creates HALT" fail "missing $wf"
    return
  fi
  code="$(grep -vE '^[[:space:]]*#' "$wf" || true)"

  if grep -qE "host_creates=\\\$\\(echo \"\\\$counts\" \| jq -r '\.host_creates'" <<<"$code"; then
    _report "T56a deploy-pipeline-fix parses the .host_creates key" ok
  else
    _report "T56a deploy-pipeline-fix parses the .host_creates key" fail \
      "no exact \`jq -r '.host_creates'\` — this push:main workflow reaches hcloud_server.web[\"web-1\"] transitively"
  fi

  validation="$(grep -E '\[\[ ! "\$host_creates" =~ \^\[0-9\]\+\$ \]\]' <<<"$code" | head -1 || true)"
  if [[ -n "$validation" ]]; then
    _report "T56b deploy-pipeline-fix's host_creates is numerically validated (fail-CLOSED)" ok
  else
    _report "T56b deploy-pipeline-fix validates host_creates" fail \
      "missing the ^[0-9]+\$ guard: jq -r on an absent key yields \"null\" and [[ \"null\" -gt 0 ]] PASSES"
  fi

  if grep -qF '[[ "$host_creates" -gt 0 ]]' <<<"$code"; then
    _report "T56c deploy-pipeline-fix HALTs on host_creates > 0" ok
  else
    _report "T56c deploy-pipeline-fix HALTs on host_creates > 0" fail "no -gt 0 comparison"
  fi

  # The plan must SAVE a plan for the guard to read; without -out the guard reads
  # a stale/absent tfplan and the whole block is decorative.
  if grep -qF '\-out=tfplan' <<<"$code" || grep -qF -- '-out=tfplan' <<<"$code"; then
    _report "T56d deploy-pipeline-fix saves the plan (-out=tfplan) the guard reads" ok
  else
    _report "T56d deploy-pipeline-fix saves the plan the guard reads" fail \
      "no -out=tfplan — \`terraform show -json tfplan\` would have nothing to read"
  fi
}

# ── T55 — the HALT's scope precondition, re-checked on every run. ────────────
#
# The host_creates counter counts hcloud_server AND hcloud_volume creates, but
# every rationale in the shipped HALT text (no -var image_name, mutable :latest,
# cloud-init stage=verify) applies to hcloud_server ONLY. That is sound while
# var.web_hosts holds exactly one key: an additive apply set then
# creates nothing, so host_creates == 0 on every legitimate run.
#
# Add a second key and a job's OWN legitimate volume create trips a HALT
# whose text says "there is NO automated path" — a false dead end on a valid
# dispatch. A tripwire that fires on normal operation is the failure mode that
# gets the tripwire deleted, which is strictly worse than the accident it guards.
#
# The plan caught this as a Phase-0 hard STOP, but that was a PLAN-TIME check
# with nothing re-firing it. This is the same precondition, re-evaluated on
# every CI run (#6725 review, user-impact finding 2).
t_web_hosts_single_key_keeps_halt_scoped() {
  local vars_tf keys
  vars_tf="${REPO_ROOT}/apps/web-platform/infra/variables.tf"
  if [[ ! -f "$vars_tf" ]]; then
    _report "T55 var.web_hosts is single-key (keeps the volume arm sound)" fail "missing $vars_tf"
    return
  fi
  # Count quoted keys inside variable "web_hosts" { … default = { … } }.
  keys="$(awk '/^variable "web_hosts"/{v=1} v&&/default = \{/{d=1;next} d&&/^  \}/{exit} d&&/^ *"[a-z0-9-]+" *=/{n++} END{print n+0}' "$vars_tf")"
  if [[ "$keys" == 1 ]]; then
    _report "T55 var.web_hosts holds exactly 1 key — host_creates may count hcloud_volume safely" ok
  else
    _report "T55 var.web_hosts holds exactly 1 key" fail \
      "found $keys keys. The host_creates HALT counts hcloud_volume creates, but its remediation text is written for hcloud_server only — with >1 web host, a job's OWN legitimate volume create now trips a HALT saying 'there is NO automated path'. RE-SCOPE the surviving host_creates HALTs (apply, deploy-pipeline-fix) to .type == \"hcloud_server\" before adding a web host."
  fi
}

t_apply_job_host_creates_halt_job_scoped() {
  local block code validation
  block="$(_job_block "$WORKFLOW_YML" "apply")"
  if [[ -z "$block" ]]; then
    _report "T54 apply block extracts non-empty" fail "empty block — extractor broken"
    return
  fi
  code="$(grep -vE '^[[:space:]]*#' <<<"$block" || true)"

  if grep -qE "host_creates=\\\$\\(echo \"\\\$counts\" \| jq -r '\.host_creates'" <<<"$code"; then
    _report "T54a apply parses host_creates from the .host_creates key (job-scoped)" ok
  else
    _report "T54a apply parses the .host_creates key" fail \
      "no exact \`jq -r '.host_creates'\` in the apply block — a renamed key would go undetected"
  fi

  validation="$(grep -E '\[\[ ! "\$[a-z_]+" =~ \^\[0-9\]\+\$ \]\]' <<<"$code" | head -1 || true)"
  if [[ -n "$validation" ]] && grep -qE '! "\$host_creates" =~' <<<"$validation"; then
    _report "T54b apply's ^[0-9]+\$ validation covers host_creates (job-scoped, fail-CLOSED)" ok
  else
    _report "T54b apply's validation covers host_creates" fail \
      "apply would fail OPEN. line='${validation}'"
  fi

  if grep -qF '[[ "$host_creates" -gt 0 ]]' <<<"$code"; then
    _report "T54c apply HALTs on host_creates > 0 (job-scoped)" ok
  else
    _report "T54c apply HALTs on host_creates > 0" fail "no -gt 0 comparison in the apply block"
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
t_hcloud_create_is_not_a_reboot
t_hcloud_reboot_ack_allows
t_host_create_halts
t_host_create_no_ack_bypass
t_host_replace_halts
t_host_creates_baseline_zero
t_host_creates_parse_failure_fails_closed
t_web2_retire_scoped_passes
t_web2_retire_retry_3of4_passes
t_web2_retire_retry_volume_only_passes
t_web2_retire_server_only_strands_volume_aborts
t_web2_retire_web1_touch_aborts
t_web2_retire_web1_volume_destroy_aborts
t_web2_retire_firewall_delete_aborts
t_web2_retire_proxy_tls_birth_aborts
t_web2_retire_noop_aborts
t_web2_retire_volume_forget_aborts
t_web2_retire_substring_collision_aborts
t_web2_retire_server_replace_aborts
t_apply_job_host_creates_halt_job_scoped
t_web_hosts_single_key_keeps_halt_scoped
t_deploy_pipeline_fix_carries_host_creates_halt

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
