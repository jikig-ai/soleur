#!/usr/bin/env bash
# Test suite for tests/scripts/lib/registry-luks-recut-gate.sh (#6929).
#
# Mechanics mirror test-workspaces-luks-recut-gate.sh: `set -uo pipefail` (NOT -e — the suite
# accumulates failures and exits on the tally), mktemp -d + trap, printf-based fixture builders
# (no heredocs), synthesized fixtures only (cq-test-fixtures-synthesized-only), passes/fails
# tally, `[[ "$fails" -eq 0 ]]` as the exit expression.
#
# EVERY case asserts the NAMED COUNTER in stdout, not just rc. The gate's counter line is the
# contract (§Observability designates it the machine-readable ABORT reason), so asserting it
# makes each case self-proving DURABLY IN CI rather than resting on a hand-run mutation matrix
# that runs once and never re-runs.
#
# Assertions use bash pattern-matching (`[[ "$out" == *needle* ]]`), never `printf | grep -q`:
# under `pipefail` an early `grep -q` match closes the pipe, the producer takes SIGPIPE (141),
# and the pipeline reports failure even though the pattern MATCHED — which fails OPEN on every
# negative assertion. See 2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source the SAME BYTES the workflow sources — no re-derived inline copy to drift.
# shellcheck source=tests/scripts/lib/registry-luks-recut-gate.sh
source "${DIR}/lib/registry-luks-recut-gate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0

pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"
  printf '       rc=%s\n' "${2:-?}"
  printf '       out=%s\n' "${3:-}"
}

# The volume id the operator authorizes in every fixture below unless a case overrides it.
ID="4242424242"

# ---------------------------------------------------------------------------
# Fixture builders. printf-based; each emits one resource_changes element.
# ---------------------------------------------------------------------------

# rc <address> <actions-csv> [before_id]
#   before_id: omitted or "" => "before": null. "-" => before object with a null id.
rc() {
  local addr="$1" actions="$2" before_id="${3-}"
  local acts_json before_json a
  # Escape the double quotes in indexed addresses (hcloud_server.web["web-1"]) — unescaped they
  # terminate the JSON string early and the whole fixture becomes unparseable, which the gate
  # correctly reports as "jq evaluation failed". That is a FIXTURE bug masquerading as a gate
  # result: the case would "abort" for the wrong reason and prove nothing about out_of_scope.
  addr="${addr//\"/\\\"}"
  acts_json=""
  for a in ${actions//,/ }; do
    acts_json="${acts_json:+${acts_json},}\"${a}\""
  done
  if [[ -z "$before_id" ]]; then
    before_json="null"
  elif [[ "$before_id" == "-" ]]; then
    before_json='{"id":null}'
  else
    before_json="{\"id\":${before_id}}"
  fi
  printf '{"address":"%s","change":{"actions":[%s],"before":%s}}' \
    "$addr" "$acts_json" "$before_json"
}

# rc_str <address> <actions-csv> <before_id>  — before.id as a JSON *string* (tostring path).
rc_str() {
  local addr="$1" actions="$2" before_id="$3"
  local acts_json="" a
  for a in ${actions//,/ }; do
    acts_json="${acts_json:+${acts_json},}\"${a}\""
  done
  printf '{"address":"%s","change":{"actions":[%s],"before":{"id":"%s"}}}' \
    "${addr//\"/\\\"}" "$acts_json" "$before_id"
}

# plan <file> <element> [element...]  — wrap elements into a terraform-show-json plan.
plan() {
  local f="$1"; shift
  local body="" e
  for e in "$@"; do
    body="${body:+${body},}${e}"
  done
  printf '{"format_version":"1.2","resource_changes":[%s]}' "$body" > "$f"
}

# The canonical recut plan: volume + attachment + server all replaced together, NIC recreated
# transitively (server_id is ForceNew), firewall attachment re-attached, logs secret untouched.
canonical_recut() {
  plan "$1" \
    "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
    "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
    "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
    "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
    "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)"
}

# ---------------------------------------------------------------------------
# check <name> <expected-rc> <expected-substring> <plan-file> [expected_id] [probe]
# ---------------------------------------------------------------------------
check() {
  local name="$1" want_rc="$2" needle="$3" f="$4"
  local eid="${5-$ID}" probe="${6-}"
  local out rc
  if [[ -n "$probe" ]]; then
    out="$(registry_luks_recut_gate "$f" "$eid" "$probe" 2>&1)"; rc=$?
  else
    out="$(registry_luks_recut_gate "$f" "$eid" 2>&1)"; rc=$?
  fi
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

printf '\n=== registry-luks-recut-gate ===\n\n'

# --- Recut arm: the happy path -------------------------------------------------------------
canonical_recut "$TMP/canonical.json"
check "canonical recut PASS" 0 "registry_luks_recut_gate: PASS" "$TMP/canonical.json"

# --- THE case that proves this issue's purpose --------------------------------------------
# registry-host-replace PRESERVES the volume. Against a still-plaintext volume that boots
# cloud-init into the blkid `*)` FATAL arm and DARKS the registry. The gate must ABORT.
# NOTE the attachment/NIC shape: this fixture must be a FAITHFUL registry-host-replace plan,
# because the cross-gate divergence block below asserts the host-replace gate PASSES it. In a
# real host replace the SERVER is replaced, which forces its volume-attachment and private NIC
# to be re-created; only the VOLUME is preserved (`no-op`). A fixture with the attachment
# no-op'd would abort under BOTH gates and the divergence assertion would prove nothing.
plan "$TMP/vol-noop.json" \
  "$(rc 'hcloud_volume.registry' 'no-op' "$ID")" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)"
check "volume no-op (the registry-host-replace footgun) ABORT" 1 "volume_provisioned=0" "$TMP/vol-noop.json"

# --- Recut arm: missing pieces --------------------------------------------------------------
plan "$TMP/srv-noop.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'no-op' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)"
check "server no-op in recut arm ABORT" 1 "server_provisioned=0" "$TMP/srv-noop.json"

plan "$TMP/no-att.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)"
check "attachment create missing ABORT" 1 "attachment_created=0" "$TMP/no-att.json"

plan "$TMP/no-nic.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)"
check "NIC create missing ABORT" 1 "nic_created=0" "$TMP/no-nic.json"

# --- firewall_ok: create OR update pass; delete aborts ---------------------------------------
plan "$TMP/fw-create.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'create')"
check "firewall attachment create PASS" 0 "firewall_ok=1" "$TMP/fw-create.json"

plan "$TMP/fw-delete.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'delete' 33)"
check "firewall attachment delete (host left naked) ABORT" 1 "firewall_ok=0" "$TMP/fw-delete.json"

# --- Id-pin (D9): per-CHANGE, never per-invocation -------------------------------------------
plan "$TMP/id-mismatch.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' 999999)" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)"
check "id mismatch (address resolves to a DIFFERENT physical volume) ABORT" 1 "volume_id_mismatch=1" "$TMP/id-mismatch.json"

# An ABSENT before.id in the recut arm is a FAIL, never a skip. The sibling gate's
# skip-on-empty idiom must NOT be inherited here.
plan "$TMP/id-absent.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' '-')" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)"
check "before.id ABSENT in recut arm ABORT" 1 "volume_id_mismatch=1" "$TMP/id-absent.json"

# tostring normalization: a JSON *string* before.id against a numeric operator input.
# ONE resource_change carrying both actions — the shape terraform actually emits for a replace.
plan "$TMP/id-string.json" \
  "$(rc_str 'hcloud_volume.registry' 'delete,create' "$ID")" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)"
check "before.id as JSON string vs numeric input PASS (tostring)" 0 "volume_id_mismatch=0" "$TMP/id-string.json"

# --- The lib fail-closes on its OWN argument (D9) ---------------------------------------------
check "empty \$expected ABORT (fail-closed on own arg)" 1 "expected_registry_store_volume_id" "$TMP/canonical.json" ""
check "non-numeric \$expected ABORT (fail-closed on own arg)" 1 "expected_registry_store_volume_id" "$TMP/canonical.json" "not-a-number"

# --- Named-live addresses: the logs secret and the LUKS key ------------------------------------
plan "$TMP/logs-del.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)" \
  "$(rc 'doppler_secret.registry_betterstack_logs_token' 'delete' 12)"
check "logs-token secret delete (fresh host would brick) ABORT" 1 "logs_secret_destroyed=1" "$TMP/logs-del.json"

for verb in create update delete forget; do
  plan "$TMP/luks-$verb.json" \
    "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
    "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
    "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
    "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
    "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)" \
    "$(rc 'doppler_secret.registry_luks_key' "$verb" 21)"
  check "registry_luks_key [$verb] ABORT (D6 full 4-verb)" 1 "luks_key_touched=1" "$TMP/luks-$verb.json"
done

plan "$TMP/pw-forget.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)" \
  "$(rc 'random_password.registry_luks' 'forget' 22)"
check "random_password.registry_luks [forget] ABORT" 1 "luks_key_touched=1" "$TMP/pw-forget.json"

# --- out_of_scope: the shared, lock-less state's other tenants ----------------------------------
plan "$TMP/oos-web.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)" \
  "$(rc 'hcloud_server.web["web-1"]' 'delete,create' 5)"
check "out-of-scope on hcloud_server.web[web-1] ABORT" 1 "out_of_scope=1" "$TMP/oos-web.json"

plan "$TMP/oos-ws.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)" \
  "$(rc 'hcloud_volume.workspaces["web-1"]' 'delete' 6)"
check "out-of-scope on hcloud_volume.workspaces[web-1] (sole /mnt/data) ABORT" 1 "out_of_scope=1" "$TMP/oos-ws.json"

# From-empty birth: the closure creates 13-14 out-of-scope resources. out_of_scope is the
# SOLE rejecter of this shape — nothing else in the gate sees it.
plan "$TMP/birth.json" \
  "$(rc 'hcloud_volume.registry' 'create')" \
  "$(rc 'hcloud_volume_attachment.registry' 'create')" \
  "$(rc 'hcloud_server.registry' 'create')" \
  "$(rc 'hcloud_server_network.registry' 'create')" \
  "$(rc 'hcloud_firewall_attachment.registry' 'create')" \
  "$(rc 'hcloud_firewall.registry' 'create')" \
  "$(rc 'hcloud_network.private' 'create')" \
  "$(rc 'hcloud_network_subnet.private' 'create')" \
  "$(rc 'hcloud_ssh_key.default' 'create')" \
  "$(rc 'doppler_project.registry' 'create')" \
  "$(rc 'betteruptime_heartbeat.registry_prd' 'create')"
check "from-empty birth shape ABORT (out_of_scope is the sole rejecter)" 1 "out_of_scope=6" "$TMP/birth.json" "$ID" "absent"

# --- Fail-closed on the plan JSON itself ---------------------------------------------------------
check "plan JSON missing ABORT" 1 "plan JSON not found" "$TMP/does-not-exist.json"

printf 'not json at all {{{' > "$TMP/malformed.json"
check "malformed plan JSON ABORT (fail-loud, never a silent 0)" 1 "jq evaluation failed" "$TMP/malformed.json"

# --- A data.* read and unrelated no-ops must NOT false-abort --------------------------------------
plan "$TMP/reads.json" \
  "$(rc 'hcloud_volume.registry' 'delete,create' "$ID")" \
  "$(rc 'hcloud_volume_attachment.registry' 'delete,create' 91)" \
  "$(rc 'hcloud_server.registry' 'delete,create' 77)" \
  "$(rc 'hcloud_server_network.registry' 'delete,create' 55)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)" \
  "$(rc 'data.hcloud_server_type.registry' 'read')" \
  "$(rc 'hcloud_server.web["web-1"]' 'no-op' 5)" \
  "$(rc 'hcloud_volume.workspaces["web-1"]' 'no-op' 6)"
check "data.* read + unrelated no-ops PASS" 0 "out_of_scope=0" "$TMP/reads.json"

# ---------------------------------------------------------------------------
# Resume arm — one case per mid-apply failure window (D3/D4).
# Admitted ONLY by the live Hetzner existence probe, never by an operator flag.
# ---------------------------------------------------------------------------
printf '\n--- resume arm (mid-apply recovery windows) ---\n\n'

# (a) both volume + server bare create (apply died after both destroys)
plan "$TMP/resume-a.json" \
  "$(rc 'hcloud_volume.registry' 'create')" \
  "$(rc 'hcloud_volume_attachment.registry' 'create')" \
  "$(rc 'hcloud_server.registry' 'create')" \
  "$(rc 'hcloud_server_network.registry' 'create')" \
  "$(rc 'hcloud_firewall_attachment.registry' 'create')"
check "resume (a) both bare create PASS" 0 "registry_luks_recut_gate: PASS" "$TMP/resume-a.json" "$ID" "absent"

# (b) volume already recreated (no-op) + server still to create
plan "$TMP/resume-b.json" \
  "$(rc 'hcloud_volume.registry' 'no-op' 777)" \
  "$(rc 'hcloud_volume_attachment.registry' 'create')" \
  "$(rc 'hcloud_server.registry' 'create')" \
  "$(rc 'hcloud_server_network.registry' 'create')" \
  "$(rc 'hcloud_firewall_attachment.registry' 'create')"
check "resume (b) volume no-op + server create PASS" 0 "registry_luks_recut_gate: PASS" "$TMP/resume-b.json" "$ID" "absent"

# (c) volume + server both already landed; only the attachment remains
plan "$TMP/resume-c.json" \
  "$(rc 'hcloud_volume.registry' 'no-op' 777)" \
  "$(rc 'hcloud_volume_attachment.registry' 'create')" \
  "$(rc 'hcloud_server.registry' 'no-op' 888)" \
  "$(rc 'hcloud_server_network.registry' 'no-op' 999)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)"
check "resume (c) volume+server no-op, attachment create PASS" 0 "completion_progress=1" "$TMP/resume-c.json" "$ID" "absent"

# (d) the resume shape is REFUSED unless the live probe says the pinned volume is gone.
check "resume shape with probe != absent ABORT" 1 "probe" "$TMP/resume-a.json" "$ID" "present"
check "resume shape with NO probe argument ABORT" 1 "probe" "$TMP/resume-a.json"

# (e) a resume plan that creates nothing is not a recovery.
plan "$TMP/resume-e.json" \
  "$(rc 'hcloud_volume.registry' 'no-op' 777)" \
  "$(rc 'hcloud_volume_attachment.registry' 'no-op' 91)" \
  "$(rc 'hcloud_server.registry' 'no-op' 888)" \
  "$(rc 'hcloud_server_network.registry' 'no-op' 999)" \
  "$(rc 'hcloud_firewall_attachment.registry' 'update' 33)"
check "resume with zero creates ABORT (not a recovery)" 1 "completion_progress=0" "$TMP/resume-e.json" "$ID" "absent"

# ---------------------------------------------------------------------------
# Cross-gate divergence — the mechanical enforcement of preserve-vs-replace.
#
# The failure this catches is NOT "someone writes a wrong new gate". It is "someone
# HARMONISES the two registry gates", which silently re-arms the exact footgun #6929
# exists to remove. No other case in this suite would go red for it.
# ---------------------------------------------------------------------------
printf '\n--- cross-gate divergence (recut vs host-replace) ---\n\n'

# shellcheck source=tests/scripts/lib/registry-host-replace-gate.sh
source "${DIR}/lib/registry-host-replace-gate.sh"

hr_out="$(registry_host_replace_gate "$TMP/canonical.json" 2>&1)"; hr_rc=$?
if [[ "$hr_rc" -ne 0 ]]; then
  pass "canonical recut is ABORTed by the host-replace gate (it preserves the store)"
else
  fail "canonical recut MUST abort under registry_host_replace_gate — the two gates have been harmonised" "$hr_rc" "$hr_out"
fi

hr_out="$(registry_host_replace_gate "$TMP/vol-noop.json" 2>&1)"; hr_rc=$?
if [[ "$hr_rc" -eq 0 ]]; then
  pass "volume-no-op plan is PASSed by the host-replace gate (its correct domain)"
else
  fail "volume-no-op MUST pass under registry_host_replace_gate — the two gates have been harmonised" "$hr_rc" "$hr_out"
fi

# ---------------------------------------------------------------------------
printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
