#!/usr/bin/env bash
# Tests for tests/scripts/lib/inngest-backstop-retire-gate.sh (sourced by the inngest_backstop_retire
# job in .github/workflows/apply-web-platform-infra.yml, #8285).
#
# FIVE GATE FUNCTIONS AND ONE OUTPUT HELPER ARE GRADED, each the SAME bytes the workflow sources:
#   inngest_backstop_retire_gate        plan SHAPE per phase (Guard 2) -- detach | wipe | teardown | destroy
#   inngest_backstop_live_store_gate    the live-store chokepoint in front of phases detach | wipe | destroy (plan 2.0)
#   inngest_backstop_destroy_precondition   evidence-before-destroy (Guard 4), incl. the D4 two-person alternative
#   inngest_backstop_wipe_evidence_gate     the evidence funnel (the wipe poll and Guard 4 share it)
#   inngest_backstop_wipe_nonce_rows        the poll's refusal short-circuit (rows bearing the nonce)
#   inngest_backstop_clean                  the sanitizer every Better Stack-derived log string passes
# The workflow's run: bodies are graded too, from PyYAML-extracted text (the WIRING section at the end).
#
# WRITTEN FROM THE PLAN'S MUTATION MATRIX BEFORE THE LIB EXISTED (task 1.3: the Guard 2 rows first,
# RED, then the gate). Every row is labelled with its matrix number so a dropped row is visible.
#
# Non-vacuity discipline: each FAIL fixture differs from a PASS fixture by ONE mutation and asserts
# the gate's `reason=<token>`, not merely rc. All fixtures are SYNTHESIZED (cq-test-fixtures-
# synthesized-only). Deterministic; no network.
#
# Run: bash tests/scripts/test-inngest-backstop-retire-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${INNGEST_BACKSTOP_GATE_LIB:-${DIR}/lib/inngest-backstop-retire-gate.sh}"
PREAMBLE="${DIR}/lib/plan-gate-preamble.sh"
# shellcheck source=tests/scripts/lib/inngest-backstop-retire-gate.sh
source "$GATE"

passes=0
fails=0
mp=0   # must-PASS arms that actually EXECUTED and passed (a count of executed runs, never of source text)
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; [[ -n "${2:-}" ]] && echo "      rc=$2" >&2; [[ -n "${3:-}" ]] && echo "      out=$3" >&2; return 0; }

export TMPDIR="${TMPDIR:-/var/tmp}"
TMP="$(mktemp -d -t inngest-backstop-retire-gate.XXXXXXXX)" || { echo "FATAL: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# INSTRUMENT SELF-TEST: drive both counters once each; refuse to continue unless both moved.
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected -- proves fail() records)" >/dev/null 2>&1
if [[ "$passes" -ne $((_p0 + 1)) || "$fails" -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test did not move both counters\n' >&2
  exit 2
fi
passes=$_p0; fails=$_f0

# shellcheck source=tests/scripts/lib/gate-suite-harness.sh
source "${DIR}/lib/gate-suite-harness.sh"
if ! gate_harness_selftest; then fails=$((fails + 1)); fi

PIN="106261946"        # soleur-inngest-redis-store: the ONLY volume this retire may touch
LIVEV="106903269"      # soleur-inngest-redis-store-luks: the LIVE store
OTHER="105149570"      # some other physical volume
SRVID="169426216"

# ── Fixture builders ──────────────────────────────────────────────────────────────
ent() { # <address> <actions-json> [before-json] [after-json]
  printf '{"address":%s,"change":{"actions":%s,"before":%s,"after":%s}}' \
    "$(jq -Rn --arg a "$1" '$a')" "$2" "${3:-null}" "${4:-{\}}"
}
write_plan() { printf '{"format_version":"1.2","resource_changes":[%s]}' "$1" > "$TMP/plan.json"; }

ATT_DEL="$(ent 'hcloud_volume_attachment.inngest_redis' '["delete"]' "{\"id\":\"9001\",\"volume_id\":${PIN},\"server_id\":${SRVID}}" null)"
VOL_DEL="$(ent 'hcloud_volume.inngest_redis' '["delete"]' "{\"id\":\"${PIN}\",\"name\":\"soleur-inngest-redis-store\"}" null)"
WSRV_CREATE="$(ent 'hcloud_server.inngest_backstop_wipe[0]' '["create"]' null '{"name":"soleur-inngest-backstop-wipe"}')"
WATT_CREATE="$(ent 'hcloud_volume_attachment.inngest_backstop_wipe[0]' '["create"]' null "{\"volume_id\":${PIN},\"automount\":false}")"
WIPE_NAME="soleur-inngest-backstop-wipe"
WSRV_DEL="$(ent 'hcloud_server.inngest_backstop_wipe[0]' '["delete"]' "{\"id\":\"777\",\"name\":\"${WIPE_NAME}\"}" null)"
WATT_DEL="$(ent 'hcloud_volume_attachment.inngest_backstop_wipe[0]' '["delete"]' "{\"id\":\"778\",\"volume_id\":${PIN},\"server_id\":777}" null)"

SRV_NOOP="$(ent 'hcloud_server.inngest' '["no-op"]' "{\"id\":\"${SRVID}\"}" "{\"id\":\"${SRVID}\"}")"
LVOL_NOOP="$(ent 'hcloud_volume.inngest_redis_luks' '["no-op"]' "{\"id\":\"${LIVEV}\"}" "{\"id\":\"${LIVEV}\"}")"
LATT_NOOP="$(ent 'hcloud_volume_attachment.inngest_redis_luks' '["no-op"]' "{\"volume_id\":${LIVEV}}" "{\"volume_id\":${LIVEV}}")"
PW_NOOP="$(ent 'random_password.inngest_redis_luks' '["no-op"]')"
KEY_NOOP="$(ent 'doppler_secret.inngest_redis_luks_key' '["no-op"]')"
W1V_NOOP="$(ent 'hcloud_volume.workspaces["web-1"]' '["no-op"]')"
W1A_NOOP="$(ent 'hcloud_volume_attachment.workspaces["web-1"]' '["no-op"]')"
W1S_NOOP="$(ent 'hcloud_server.web["web-1"]' '["no-op"]')"
DATA_READ="$(ent 'data.hcloud_image.ubuntu' '["read"]')"
LIVE_SET="${SRV_NOOP},${LVOL_NOOP},${LATT_NOOP},${PW_NOOP},${KEY_NOOP},${W1V_NOOP},${W1A_NOOP},${W1S_NOOP}"

# chk <name> <want_rc> <needle> <phase> <pin> <mode>   (plan is $TMP/plan.json)
chk() {
  local name="$1" want="$2" needle="$3" phase="$4" pin="$5" mode="$6" out rc=0
  out="$(inngest_backstop_retire_gate "$TMP/plan.json" "$phase" "$pin" "$mode" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$want" && "$out" == *"$needle"* ]]; then pass; [[ "$want" -eq 0 ]] && mp=$((mp + 1)); else fail "$name (want rc=$want containing '$needle')" "$rc" "$out"; fi
}
PASS_TOK="inngest_backstop_retire_gate: PASS"
# A refusing live-store / precondition / evidence call prints EXACTLY ONE line. A guard neutered into an echo
# that falls through to a LATER guard prints two (the neutered one's reason, then the fallback's), and a
# needle-only check cannot see that: the needle is still there.
one_line() { [[ "$(printf '%s\n' "$1" | grep -c .)" -eq 1 ]]; }

# THE WRAPPER SELF-TEST: drive chk() in the direction that must FAIL, then roll back.
write_plan "${ATT_DEL},${LIVE_SET}"
_sp=$passes; _sf=$fails
chk "SELF-TEST (expected to fail): a PASS plan is not an abort" 1 "reason=live_volume_touched" detach "$PIN" targeted 2>/dev/null
if [[ "$fails" -eq $((_sf + 1)) && "$passes" -eq "$_sp" ]]; then passes=$_sp; fails=$_sf; pass
else passes=$_sp; fails=$_sf; fail "INSTRUMENT: chk() did not fail on a must-fail arm -- every assertion in this file is decorative"; fi

# ══ GUARD 2 -- plan shape per phase ═══════════════════════════════════════════════
# Canonical PASS, one per phase and mode.
write_plan "${ATT_DEL}"
chk "PASS detach/targeted: exactly one attachment delete, id-pinned" 0 "$PASS_TOK" detach "$PIN" targeted
write_plan "${ATT_DEL},${VOL_DEL},${LIVE_SET},${DATA_READ}"
chk "PASS detach/untargeted: attachment delete + the orphan volume delete + server and LUKS pair no-op" 0 "$PASS_TOK" detach "$PIN" untargeted
write_plan "${WSRV_CREATE},${WATT_CREATE}"
chk "PASS wipe/targeted: exactly two creates, attachment bound to the pinned id" 0 "$PASS_TOK" wipe "$PIN" targeted
write_plan "${VOL_DEL},${LIVE_SET}"
chk "PASS wipe/untargeted: only the orphan volume delete is pending" 0 "$PASS_TOK" wipe "$PIN" untargeted
write_plan "${WSRV_DEL},${WATT_DEL}"
chk "PASS teardown/targeted: both wipe addresses deleted" 0 "$PASS_TOK" teardown "$PIN" targeted
write_plan "${VOL_DEL},${LIVE_SET}"
chk "PASS teardown/untargeted: nothing to tear down, orphan volume delete pending" 0 "$PASS_TOK" teardown "$PIN" untargeted
write_plan "${VOL_DEL}"
chk "PASS destroy/targeted: exactly one volume delete" 0 "$PASS_TOK" destroy "$PIN" targeted
write_plan "${VOL_DEL},${LIVE_SET}"
chk "PASS destroy/untargeted: volume delete + live set as present no-ops" 0 "$PASS_TOK" destroy "$PIN" untargeted

# H (must-PASS, non-canonical): authorized change among unrelated no-ops in a different order, extra
# read-only data entries, a numeric AND a string id, plain (unindexed) wipe addresses.
write_plan "${DATA_READ},${LIVE_SET},$(ent 'doppler_secret.other' '["no-op"]'),${VOL_DEL}"
chk "H1: destroy, reordered with extra no-op and read entries" 0 "$PASS_TOK" destroy "$PIN" untargeted
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete"]' "{\"id\":${PIN}}" null)"
chk "H2: a NUMERIC before.id equal to the pin" 0 "$PASS_TOK" destroy "$PIN" targeted
write_plan "$(ent 'hcloud_server.inngest_backstop_wipe' '["create"]' null "{\"name\":\"${WIPE_NAME}\"}"),$(ent 'hcloud_volume_attachment.inngest_backstop_wipe' '["create"]' null "{\"volume_id\":\"${PIN}\"}")"
chk "H3: unindexed wipe addresses and a STRING volume_id" 0 "$PASS_TOK" wipe "$PIN" targeted

# ── Matrix row 1: a delete of the LIVE LUKS volume during destroy ──
write_plan "${VOL_DEL},$(ent 'hcloud_volume.inngest_redis_luks' '["delete"]' "{\"id\":\"${LIVEV}\"}" null)"
chk "Row 1: destroy plan also deletes the LUKS volume => live_volume_touched" 1 "reason=live_volume_touched" destroy "$PIN" targeted
write_plan "${VOL_DEL},$(ent 'hcloud_volume_attachment.inngest_redis_luks' '["delete","create"]' "{\"volume_id\":${LIVEV}}" "{}")"
chk "Row 1b: the LUKS ATTACHMENT replaced => live_volume_touched" 1 "reason=live_volume_touched" destroy "$PIN" targeted
# An unknown address that merely REFERENCES the live id is also the live store being acted on.
write_plan "${VOL_DEL},$(ent 'hcloud_volume.some_future_alias' '["delete"]' "{\"id\":\"${LIVEV}\"}" null)"
chk "Row 1c: ANY address whose before.id is the live volume => live_volume_touched" 1 "reason=live_volume_touched" destroy "$PIN" targeted
# The destroy target pointed at the live id: pin typed as the LUKS id, state agrees with the typo.
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete"]' "{\"id\":\"${LIVEV}\"}" null)"
chk "Row 1d: pin AND before.id both the live id => live_volume_touched" 1 "reason=live_volume_touched" destroy "$LIVEV" targeted

# ── Matrix row 2: phase unset or unknown ──
write_plan "${VOL_DEL}"
chk "Row 2a: phase unset => phase_unknown" 1 "reason=phase_unknown" "" "$PIN" targeted
chk "Row 2b: phase unknown => phase_unknown" 1 "reason=phase_unknown" "all" "$PIN" targeted
chk "Row 2c: phase is a prefix of a real one => phase_unknown" 1 "reason=phase_unknown" "dest" "$PIN" targeted
chk "Row 2d: phase with a glob => phase_unknown" 1 "reason=phase_unknown" "*" "$PIN" targeted
chk "Row 2e: mode unset => mode_unknown" 1 "reason=mode_unknown" destroy "$PIN" ""
chk "Row 2f: mode unknown => mode_unknown" 1 "reason=mode_unknown" destroy "$PIN" "partial"

# ── Matrix row 3: second delete after a compliant first (every member is checked) ──
write_plan "${VOL_DEL},${ATT_DEL}"
chk "Row 3a: destroy = authorized volume delete + a second delete (the attachment) => unauthorized_delete" 1 "reason=unauthorized_delete" destroy "$PIN" targeted
write_plan "${ATT_DEL},${VOL_DEL}"
chk "Row 3b: detach/targeted with the volume delete as the second member => unauthorized_delete" 1 "reason=unauthorized_delete" detach "$PIN" targeted
write_plan "${VOL_DEL},$(ent 'hcloud_volume.git_data' '["delete"]' '{"id":"5"}' null)"
chk "Row 3c: destroy + a delete of an un-enumerated volume => unauthorized_delete" 1 "reason=unauthorized_delete" destroy "$PIN" targeted
write_plan "${VOL_DEL},$(ent 'hcloud_volume.git_data' '["forget"]' '{"id":"5"}' null)"
chk "Row 3d: a FORGET of an un-enumerated address => unauthorized_delete" 1 "reason=unauthorized_delete" destroy "$PIN" targeted
write_plan "${VOL_DEL},${VOL_DEL}"
chk "Row 3e: the authorized delete listed twice => shape_extra" 1 "reason=shape_extra" destroy "$PIN" targeted
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete","create"]' "{\"id\":\"${PIN}\"}" "{}")"
chk "Row 3f: a REPLACE of the volume is not a delete => unauthorized_delete" 1 "reason=unauthorized_delete" destroy "$PIN" targeted
write_plan "${VOL_DEL},$(ent 'hcloud_volume.git_data' '["create"]' null)"
chk "Row 3g: a CREATE of an un-enumerated address => out_of_scope" 1 "reason=out_of_scope" destroy "$PIN" targeted
write_plan "${VOL_DEL},$(ent 'doppler_secret.something' '["update"]' '{"value":"a"}' '{"value":"b"}')"
chk "Row 3h: an UPDATE of an un-enumerated address => out_of_scope" 1 "reason=out_of_scope" destroy "$PIN" targeted

# ── Matrix row 4: the pin is omitted ──
write_plan "${VOL_DEL}"
chk "Row 4a: destroy with NO pin argument => id_pin_absent" 1 "reason=id_pin_absent" destroy "" targeted
write_plan "${ATT_DEL}"
chk "Row 4c: detach with an empty pin => id_pin_absent (the pin is required in EVERY phase)" 1 "reason=id_pin_absent" detach "" targeted
write_plan "${WSRV_CREATE},${WATT_CREATE}"
chk "Row 4d: wipe with an empty pin => id_pin_absent" 1 "reason=id_pin_absent" wipe "" targeted
write_plan "${VOL_DEL}"
chk "Row 4e: a pin that is not the retired id (typo) => pin_not_retired" 1 "reason=pin_not_retired" destroy "$OTHER" targeted

# ── Matrix row 5: state maps the address to a different physical id than the pin ──
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete"]' "{\"id\":\"${OTHER}\"}" null)"
chk "Row 5a: volume delete whose before.id is another volume => id_mismatch" 1 "reason=id_mismatch" destroy "$PIN" targeted
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete"]' "{\"id\":${OTHER}}" null)"
chk "Row 5b: the same with a NUMERIC id (ids compare as strings) => id_mismatch" 1 "reason=id_mismatch" destroy "$PIN" targeted
write_plan "$(ent 'hcloud_volume_attachment.inngest_redis' '["delete"]' "{\"volume_id\":${OTHER}}" null)"
chk "Row 5c: attachment delete whose before.volume_id is another volume => id_mismatch" 1 "reason=id_mismatch" detach "$PIN" targeted
write_plan "${VOL_DEL}"
chk "Row 5d: a PREFIX of the real id as the pin => pin_not_retired" 1 "reason=pin_not_retired" destroy "10626194" targeted
chk "Row 5e: a GLOB as the pin must not match" 1 "reason=pin_not_retired" destroy "*" targeted
chk "Row 5f: a REGEX as the pin must not match" 1 "reason=pin_not_retired" destroy ".*" targeted
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete"]' "{\"id\":\"${PIN}0\"}" null)"
chk "Row 5g: before.id that merely STARTS with the pin => id_mismatch" 1 "reason=id_mismatch" destroy "$PIN" targeted
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete"]' '{"id":null}' null)"
chk "Row 5h: before.id null => id_unverifiable" 1 "reason=id_unverifiable" destroy "$PIN" targeted
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete"]' '{}' null)"
chk "Row 5i: before without an id => id_unverifiable" 1 "reason=id_unverifiable" destroy "$PIN" targeted
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete"]' null null)"
chk "Row 5j: before null (state-drop) => id_unverifiable" 1 "reason=id_unverifiable" destroy "$PIN" targeted
write_plan "$(ent 'hcloud_volume_attachment.inngest_redis' '["delete"]' '{"volume_id":null}' null)"
chk "Row 5k: attachment before.volume_id null => id_unverifiable" 1 "reason=id_unverifiable" detach "$PIN" targeted

# ── Matrix row 6: the sole-scheduler host acted on ──
write_plan "${VOL_DEL},$(ent 'hcloud_server.inngest' '["update"]' "{\"id\":\"${SRVID}\"}" '{}')"
chk "Row 6a: server UPDATE => inngest_server_touched" 1 "reason=inngest_server_touched" destroy "$PIN" targeted
write_plan "${VOL_DEL},$(ent 'hcloud_server.inngest' '["delete","create"]' "{\"id\":\"${SRVID}\"}" '{}')"
chk "Row 6b: server REPLACE => inngest_server_touched" 1 "reason=inngest_server_touched" destroy "$PIN" targeted
write_plan "${ATT_DEL},$(ent 'hcloud_server.inngest' '["delete"]' "{\"id\":\"${SRVID}\"}" null)"
chk "Row 6c: server DELETE => inngest_server_touched" 1 "reason=inngest_server_touched" detach "$PIN" targeted
write_plan "${ATT_DEL},$(ent 'hcloud_server.inngest[0]' '["update"]' '{}' '{}')"
chk "Row 6d: an indexed alias of the server is the server too => inngest_server_touched" 1 "reason=inngest_server_touched" detach "$PIN" targeted
write_plan "${ATT_DEL},$(ent 'hcloud_volume.inngest_redis_luks' '["update"]' "{\"id\":\"${LIVEV}\"}" '{}')"
chk "Row 6e: the LUKS volume updated in place => live_volume_touched" 1 "reason=live_volume_touched" detach "$PIN" targeted
write_plan "${ATT_DEL},$(ent 'hcloud_server.web["web-1"]' '["update"]')"
chk "Row 6f: the web-1 server touched => named_live_touched" 1 "reason=named_live_touched" detach "$PIN" targeted
write_plan "${ATT_DEL},$(ent 'random_password.inngest_redis_luks' '["create"]')"
chk "Row 6g: even a FIRST create of the passphrase is refused here => named_live_touched" 1 "reason=named_live_touched" detach "$PIN" targeted

# ── Matrix row 7: wipe step A attaches the LIVE volume ──
write_plan "${WSRV_CREATE},$(ent 'hcloud_volume_attachment.inngest_backstop_wipe[0]' '["create"]' null "{\"volume_id\":${LIVEV}}")"
chk "Row 7a: wipe attachment after.volume_id = the LUKS volume => live_volume_touched" 1 "reason=live_volume_touched" wipe "$PIN" targeted
write_plan "${WSRV_CREATE},$(ent 'hcloud_volume_attachment.inngest_backstop_wipe[0]' '["create"]' null "{\"volume_id\":${OTHER}}")"
chk "Row 7b: wipe attachment bound to some OTHER volume => id_mismatch" 1 "reason=id_mismatch" wipe "$PIN" targeted
write_plan "${WSRV_CREATE},$(ent 'hcloud_volume_attachment.inngest_backstop_wipe[0]' '["create"]' null '{"volume_id":null}')"
chk "Row 7c: wipe attachment volume_id null => id_unverifiable" 1 "reason=id_unverifiable" wipe "$PIN" targeted
write_plan "${WSRV_CREATE},$(printf '{"address":"hcloud_volume_attachment.inngest_backstop_wipe[0]","change":{"actions":["create"],"before":null,"after":{"volume_id":null},"after_unknown":{"volume_id":true}}}')"
chk "Row 7d: wipe attachment volume_id UNKNOWN at plan time => id_unverifiable" 1 "reason=id_unverifiable" wipe "$PIN" targeted
write_plan "${WSRV_CREATE}"
chk "Row 7e: wipe with only the server create => shape_missing" 1 "reason=shape_missing" wipe "$PIN" targeted
write_plan "${WSRV_CREATE},${WATT_CREATE},$(ent 'hcloud_server.other_extra' '["create"]')"
chk "Row 7f: wipe plus a third create => out_of_scope" 1 "reason=out_of_scope" wipe "$PIN" targeted
write_plan "${WSRV_CREATE},${WATT_CREATE},${ATT_DEL}"
chk "Row 7g: wipe plus the attachment delete (detach is a different phase) => unauthorized_delete" 1 "reason=unauthorized_delete" wipe "$PIN" targeted
write_plan "${WSRV_CREATE},${WATT_CREATE},${VOL_DEL}"
chk "Row 7h: wipe/targeted must not also destroy the volume => unauthorized_delete" 1 "reason=unauthorized_delete" wipe "$PIN" targeted

# ── Matrix row 8: teardown accepts ANY subset of the two wipe deletes, nothing else ──
write_plan "${WSRV_DEL}"
chk "Row 8a: teardown with only the server delete (attachment never created) => PASS (subset rule)" 0 "$PASS_TOK" teardown "$PIN" targeted
write_plan "${WATT_DEL}"
chk "Row 8b: teardown with only the attachment delete => PASS" 0 "$PASS_TOK" teardown "$PIN" targeted
write_plan ""
chk "Row 8c: teardown with an EMPTY plan (nothing leaked) => PASS" 0 "$PASS_TOK" teardown "$PIN" targeted
write_plan "${WSRV_DEL},$(ent 'hcloud_volume.git_data' '["delete"]' '{"id":"5"}' null)"
chk "Row 8d: teardown subset + an unrelated delete => unauthorized_delete" 1 "reason=unauthorized_delete" teardown "$PIN" targeted
write_plan "${WSRV_DEL},${VOL_DEL}"
chk "Row 8e: teardown + the volume delete (destroy is a different phase) => unauthorized_delete" 1 "reason=unauthorized_delete" teardown "$PIN" targeted
write_plan "$(ent 'hcloud_server.inngest_backstop_wipe[0]' '["update"]' '{}' '{}')"
chk "Row 8f: teardown with an UPDATE of the wipe server => out_of_scope" 1 "reason=out_of_scope" teardown "$PIN" targeted
write_plan "${WSRV_DEL},$(ent 'hcloud_volume_attachment.inngest_backstop_wipe[0]' '["delete"]' "{\"volume_id\":${LIVEV}}" null)"
chk "Row 8g: teardown whose attachment delete was bound to the LIVE volume => live_volume_touched" 1 "reason=live_volume_touched" teardown "$PIN" targeted
write_plan "${WSRV_DEL},$(ent 'hcloud_volume_attachment.inngest_backstop_wipe[0]' '["delete"]' "{\"volume_id\":${OTHER}}" null)"
chk "Row 8h: teardown whose attachment delete was bound to another volume => id_mismatch" 1 "reason=id_mismatch" teardown "$PIN" targeted

# ── Matrix row 9: an UNTARGETED plan must carry the live set as present no-ops ──
write_plan "${VOL_DEL},${LVOL_NOOP},${LATT_NOOP},${PW_NOOP},${KEY_NOOP}"
chk "Row 9a: untargeted plan omits hcloud_server.inngest entirely => inngest_server_absent" 1 "reason=inngest_server_absent" destroy "$PIN" untargeted
write_plan "${VOL_DEL},$(ent 'hcloud_server.inngest' '["read"]'),${LVOL_NOOP},${LATT_NOOP}"
chk "Row 9b: server present only as a read => inngest_server_absent" 1 "reason=inngest_server_absent" destroy "$PIN" untargeted
write_plan "${VOL_DEL},${SRV_NOOP},${SRV_NOOP},${LVOL_NOOP},${LATT_NOOP}"
chk "Row 9c: server listed twice => inngest_server_absent (exactly one entry)" 1 "reason=inngest_server_absent" destroy "$PIN" untargeted
write_plan "${VOL_DEL},${SRV_NOOP},${LATT_NOOP}"
chk "Row 9d: untargeted plan omits the LUKS volume => luks_pair_absent" 1 "reason=luks_pair_absent" destroy "$PIN" untargeted
write_plan "${VOL_DEL},${SRV_NOOP},${LVOL_NOOP}"
chk "Row 9e: untargeted plan omits the LUKS attachment => luks_pair_absent" 1 "reason=luks_pair_absent" destroy "$PIN" untargeted
write_plan "${VOL_DEL}"
chk "Row 9f: the same plan is FINE when targeted (absence from a -target plan is not a finding)" 0 "$PASS_TOK" destroy "$PIN" targeted
write_plan "${ATT_DEL},${LIVE_SET},${WSRV_CREATE}"
chk "Row 9g: untargeted detach with a wipe create pending => out_of_scope (not this phase's set)" 1 "reason=out_of_scope" detach "$PIN" untargeted

# ── Matrix row 10 (D-C): the UNTARGETED plan is the D1 proof and must not block on UNRELATED drift ──
UNREL="$(ent 'hcloud_volume.git_data' '["create"]' null '{"name":"x"}'),$(ent 'doppler_secret.something' '["update"]' '{"value":"a"}' '{"value":"b"}'),$(ent 'hcloud_firewall.other' '["delete"]' '{"id":"5"}' null)"
write_plan "${VOL_DEL},${LIVE_SET},${UNREL}"
chk "Row 10a: untargeted destroy with UNRELATED create/update/delete pending => PASS (ignored, not out_of_scope)" 0 "$PASS_TOK" destroy "$PIN" untargeted
write_plan "${VOL_DEL},${LIVE_SET},${UNREL}"
chk "Row 10b: the SAME unrelated drift in the TARGETED plan is still refused => unauthorized_delete" 1 "reason=unauthorized_delete" destroy "$PIN" targeted
write_plan "${VOL_DEL},${LIVE_SET},$(ent 'hcloud_volume_attachment.unrelated' '["update"]' "{\"volume_id\":${LIVEV}}" '{}')"
chk "Row 10c: unrelated entry that carries the LIVE volume id is never ignored, even untargeted => live_volume_touched" 1 "reason=live_volume_touched" destroy "$PIN" untargeted
write_plan "${VOL_DEL},${LIVE_SET},$(ent 'hcloud_server.web["web-1"]' '["update"]')"
chk "Row 10d (E-4): the untargeted plan counts the web-1 server like the targeted one => named_live_touched" 1 "reason=named_live_touched" destroy "$PIN" untargeted
for nl in 'hcloud_volume.workspaces["web-1"]' 'hcloud_volume_attachment.workspaces["web-1"]' 'random_password.inngest_redis_luks' 'doppler_secret.inngest_redis_luks_key'; do
  write_plan "${VOL_DEL},${LIVE_SET},$(ent "$nl" '["update"]')"
  chk "Row 10d (E-4): untargeted, ${nl} updated => named_live_touched" 1 "reason=named_live_touched" destroy "$PIN" untargeted
done
write_plan "${VOL_DEL},${LIVE_SET},$(ent 'hcloud_server.web["web-2"]' '["update"]'),$(ent 'doppler_secret.other_key' '["update"]')"
chk "Row 10d (E-4 control): untargeted still ignores OTHER resources (web-2, an unrelated secret) => PASS" 0 "$PASS_TOK" destroy "$PIN" untargeted
write_plan "${VOL_DEL},${LIVE_SET},$(ent 'hcloud_server.inngest' '["update"]' "{\"id\":\"${SRVID}\"}" '{}')"
chk "Row 10e: untargeted plan that updates the host => inngest_server_touched (never ignored)" 1 "reason=inngest_server_touched" destroy "$PIN" untargeted
write_plan "${VOL_DEL},${LIVE_SET},${WSRV_CREATE}"
chk "Row 10f: untargeted destroy with a wipe create (a retire address outside the phase's set) => out_of_scope" 1 "reason=out_of_scope" destroy "$PIN" untargeted
write_plan "${WSRV_DEL},${WATT_DEL},${VOL_DEL},${LIVE_SET}"
chk "Row 10g: PASS teardown/untargeted with deletes of BOTH wipe addresses and the orphan volume delete" 0 "$PASS_TOK" teardown "$PIN" untargeted
write_plan "${WSRV_CREATE},${LIVE_SET}"
chk "Row 10h: wipe/untargeted with a wipe create (the targeted plan carries it, the whole-root plan must not) => out_of_scope" 1 "reason=out_of_scope" wipe "$PIN" untargeted
write_plan "${WSRV_CREATE},${WATT_CREATE},${LIVE_SET}"
chk "Row 10i: wipe/untargeted with BOTH wipe creates => out_of_scope" 1 "reason=out_of_scope" wipe "$PIN" untargeted
write_plan "${WSRV_DEL},${LIVE_SET},${VOL_DEL},${ATT_DEL}"
chk "Row 10j: teardown/untargeted with the retired attachment delete pending => unauthorized_delete" 1 "reason=unauthorized_delete" teardown "$PIN" untargeted

# ── Matrix row 11 (W7): the verb vocabulary is CLOSED ──
write_plan "${VOL_DEL},$(ent 'hcloud_server.inngest' '["move"]' "{\"id\":\"${SRVID}\"}" "{\"id\":\"${SRVID}\"}")"
chk "Row 11a: a verb outside the vocabulary on the host => unknown_verb (not read as inert)" 1 "reason=unknown_verb" destroy "$PIN" targeted
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete","wibble"]' "{\"id\":\"${PIN}\"}" null)"
chk "Row 11b: the authorized delete carrying an extra unknown verb => unknown_verb" 1 "reason=unknown_verb" destroy "$PIN" targeted
write_plan "${VOL_DEL},${LIVE_SET},$(ent 'hcloud_firewall.other' '["import"]' '{}' '{}')"
chk "Row 11c: an unknown verb on an UNRELATED address is still refused when untargeted" 1 "reason=unknown_verb" destroy "$PIN" untargeted
write_plan "${VOL_DEL},${LIVE_SET},${DATA_READ},$(ent 'hcloud_firewall.other' '["no-op"]' '{}' '{}')"
chk "Row 11d: every verb of the vocabulary (no-op, read, delete) is accepted => PASS" 0 "$PASS_TOK" destroy "$PIN" untargeted


# ── Matrix row 12 (E-4): the wipe addresses are graded on what they ARE (name, physical id), not on the address ──
LIVE_SRV_ID="169426216"
WSRV_DEL_N="$(ent 'hcloud_server.inngest_backstop_wipe[0]' '["delete"]' '{"id":"777","name":"soleur-inngest-backstop"}' null)"
WSRV_DEL_LIVE="$(ent 'hcloud_server.inngest_backstop_wipe[0]' '["delete"]' "{\"id\":\"${LIVE_SRV_ID}\",\"name\":\"${WIPE_NAME}\"}" null)"
WSRV_DEL_NUM="$(ent 'hcloud_server.inngest_backstop_wipe[0]' '["delete"]' "{\"id\":${LIVE_SRV_ID},\"name\":\"${WIPE_NAME}\"}" null)"
WSRV_DEL_NOID="$(ent 'hcloud_server.inngest_backstop_wipe[0]' '["delete"]' "{\"name\":\"${WIPE_NAME}\"}" null)"
WSRV_DEL_NONAME="$(ent 'hcloud_server.inngest_backstop_wipe[0]' '["delete"]' '{"id":"777"}' null)"
WSRV_CREATE_N="$(ent 'hcloud_server.inngest_backstop_wipe[0]' '["create"]' null '{"name":"soleur-inngest"}')"
WSRV_CREATE_NONAME="$(ent 'hcloud_server.inngest_backstop_wipe[0]' '["create"]' null)"
WATT_DEL_LIVE="$(ent 'hcloud_volume_attachment.inngest_backstop_wipe[0]' '["delete"]' "{\"id\":\"778\",\"volume_id\":${PIN},\"server_id\":${LIVE_SRV_ID}}" null)"
WATT_DEL_NOSRV="$(ent 'hcloud_volume_attachment.inngest_backstop_wipe[0]' '["delete"]' "{\"id\":\"778\",\"volume_id\":${PIN}}" null)"
write_plan "${WSRV_DEL_N},${WATT_DEL}"
chk "Row 12a: teardown, the server to delete is not named soleur-inngest-backstop-wipe => wipe_server_identity" 1 "reason=wipe_server_identity" teardown "$PIN" targeted
write_plan "${WSRV_DEL_LIVE},${WATT_DEL}"
chk "Row 12b: teardown, the 'wipe' server's physical id is the LIVE inngest server (string id) => wipe_server_identity" 1 "reason=wipe_server_identity" teardown "$PIN" targeted
write_plan "${WSRV_DEL_NUM},${WATT_DEL}"
chk "Row 12b2: ... the same with a NUMERIC id => wipe_server_identity" 1 "reason=wipe_server_identity" teardown "$PIN" targeted
write_plan "${WSRV_DEL_NOID}"
chk "Row 12c: teardown, the server delete carries no physical id => wipe_server_identity (fail closed)" 1 "reason=wipe_server_identity" teardown "$PIN" targeted
write_plan "${WSRV_DEL_NONAME}"
chk "Row 12d: teardown, the server delete carries no name => wipe_server_identity" 1 "reason=wipe_server_identity" teardown "$PIN" targeted
write_plan "${WSRV_DEL},${WATT_DEL_LIVE}"
chk "Row 12e: teardown, the attachment to delete is bound to the LIVE server => wipe_server_identity" 1 "reason=wipe_server_identity" teardown "$PIN" targeted
write_plan "${WATT_DEL_NOSRV}"
chk "Row 12f: teardown, the attachment delete carries no server_id => wipe_server_identity" 1 "reason=wipe_server_identity" teardown "$PIN" targeted
write_plan "${WSRV_CREATE_N},${WATT_CREATE}"
chk "Row 12g: wipe, the server to CREATE is named soleur-inngest (the live host) => wipe_server_identity" 1 "reason=wipe_server_identity" wipe "$PIN" targeted
write_plan "${WSRV_CREATE_NONAME},${WATT_CREATE}"
chk "Row 12h: wipe, the server create carries no name => wipe_server_identity" 1 "reason=wipe_server_identity" wipe "$PIN" targeted
write_plan "${WSRV_DEL_N},${WATT_DEL},${VOL_DEL},${LIVE_SET}"
chk "Row 12i: the same name mismatch is refused in the UNTARGETED teardown plan too => wipe_server_identity" 1 "reason=wipe_server_identity" teardown "$PIN" untargeted
write_plan "${WSRV_CREATE},${WATT_CREATE}"
chk "Row 12j (control): wipe/targeted with the real name => PASS" 0 "$PASS_TOK" wipe "$PIN" targeted
write_plan "${WSRV_DEL},${WATT_DEL}"
chk "Row 12k (control): teardown/targeted with the real name, a non-live id and a non-live attachment server => PASS" 0 "$PASS_TOK" teardown "$PIN" targeted

# ── Shape rows: each phase needs its own set ──
write_plan ""
chk "Shape 1: detach with an EMPTY plan => shape_missing" 1 "reason=shape_missing" detach "$PIN" targeted
write_plan "${LIVE_SET}"
chk "Shape 2: destroy with no volume delete => shape_missing" 1 "reason=shape_missing" destroy "$PIN" targeted
write_plan "${SRV_NOOP}"
chk "Shape 3: wipe with no creates => shape_missing" 1 "reason=shape_missing" wipe "$PIN" targeted
write_plan "${ATT_DEL},${VOL_DEL},${LIVE_SET}"
chk "Shape 4: destroy/untargeted with the attachment still pending (detach not done) => unauthorized_delete" 1 "reason=unauthorized_delete" destroy "$PIN" untargeted
write_plan "$(ent 'hcloud_volume_attachment.inngest_redis' '["update"]' "{\"volume_id\":${PIN}}" '{}')"
chk "Shape 5: attachment UPDATE in the detach phase => out_of_scope" 1 "reason=out_of_scope" detach "$PIN" targeted
write_plan "$(ent 'hcloud_volume_attachment.inngest_redis' '["delete","create"]' "{\"volume_id\":${PIN}}" '{}')"
chk "Shape 6: attachment REPLACE in the detach phase => unauthorized_delete" 1 "reason=unauthorized_delete" detach "$PIN" targeted
write_plan "$(ent 'hcloud_volume_attachment.inngest_redis' '["create"]' null '{}')"
chk "Shape 7: a CREATE of the retired attachment => out_of_scope" 1 "reason=out_of_scope" detach "$PIN" targeted

# ── Degraded plan documents: fail closed ──
chk "Degraded a: missing plan JSON" 1 "ABORT" detach "$PIN" targeted 2>/dev/null
cp "$TMP/plan.json" "$TMP/keep.json"
printf 'not json{{{' > "$TMP/plan.json"; chk "Degraded b: malformed plan JSON" 1 "unparseable" detach "$PIN" targeted
printf '{"format_version":"1.2"}' > "$TMP/plan.json"; chk "Degraded c: no resource_changes array" 1 "no resource_changes array" detach "$PIN" targeted
printf '{"resource_changes":null}' > "$TMP/plan.json"; chk "Degraded d: resource_changes null" 1 "no resource_changes array" destroy "$PIN" targeted
mk_plan "$TMP/pg-d5.json" "[$(rc_empty_actions 'hcloud_server.inngest' 'hcloud_server')]"
mk_plan "$TMP/pg-d6.json" "[$(rc_scalar_change 'hcloud_server.inngest' 'hcloud_server')]"
out="$(inngest_backstop_retire_gate "$TMP/pg-d5.json" destroy "$PIN" untargeted 2>&1 || true)"
if [[ "$out" == *"unclassifiable plan entry"* ]]; then pass; else fail "Degraded e: an EMPTY actions array hiding a server change must abort in the preamble" "" "$out"; fi
out="$(inngest_backstop_retire_gate "$TMP/pg-d6.json" destroy "$PIN" untargeted 2>&1 || true)"
if [[ "$out" == *"unclassifiable plan entry"* ]]; then pass; else fail "Degraded f: a SCALAR .change must abort in the preamble" "" "$out"; fi
out="$(inngest_backstop_retire_gate "$TMP" detach "$PIN" targeted 2>&1 || true)"
if [[ "$out" == *"ABORT"* ]]; then pass; else fail "Degraded g: a DIRECTORY as the plan path" "" "$out"; fi

# ── The gate's INVOKED-not-sourced preamble binding, and the numeric-counter assert ──
write_plan "${ATT_DEL}"
gate_mutate_layered "A4: classifiability call (invoked, not merely sourced)" \
  's/^  plan_gate_assert_classifiable .*/  :/' \
  "unclassifiable plan entry" "plan is NOT the exact destroy" \
  inngest_backstop_retire_gate "$TMP/pg-d5.json" destroy "$PIN" untargeted
_mut="$TMP/mutated-numeric.sh"
sed 's|^  lvt=\$(echo "\$counts".*|  lvt=""|' "$GATE" > "$_mut"
if cmp -s "$_mut" "$GATE"; then
  fail "Row N: the counter mutation matched NOTHING in the gate; the extraction shape drifted"
else
  _rc=0; _out="$(bash -c "source '$PREAMBLE'; source '$_mut'; inngest_backstop_retire_gate '$TMP/plan.json' detach '$PIN' targeted" 2>&1)" || _rc=$?
  if [[ "$_rc" -eq 1 && "$_out" == *"counter parse failed"* && "$_out" == *"live_volume_touched"* ]]; then pass
  else fail "Row N: an empty counter must ABORT naming that counter" "$_rc" "$_out"; fi
fi

# ── In-suite mutations: neuter ONE counter in a copy of the lib. SOLE-GUARD counters: the bad plan
#    must then be ACCEPTED. LAYERED counters (defence in depth by design): the plan must STILL be
#    refused, the counter's own reason must vanish and the named fallback appear. Each helper first
#    asserts the mutation landed (a byte-identical copy would report a vacuous pass). ──
mut() { # <label> <sed> <phase> <pin> <mode>  (plan = $TMP/plan.json)
  local label="$1" sedx="$2"; shift 2
  gate_mutate_and_check "$label" "$sedx" inngest_backstop_retire_gate "$TMP/plan.json" "$@"
}
lay() { # <label> <sed> <own> <fallback> <phase> <pin> <mode>
  local label="$1" sedx="$2" own="$3" fb="$4"; shift 4
  gate_mutate_layered "$label" "$sedx" "$own" "$fb" inngest_backstop_retire_gate "$TMP/plan.json" "$@"
}
ZERO() { printf 's|^  %s=\$(echo "\$counts".*|  %s=0|' "$1" "$1"; }
write_plan "${VOL_DEL},$(ent 'hcloud_volume.inngest_redis_luks' '["delete"]' "{\"id\":\"${LIVEV}\"}" null)"
lay "MUT live_volume_touched" "$(ZERO lvt)" "reason=live_volume_touched" "reason=unauthorized_delete" destroy "$PIN" targeted
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete"]' "{\"id\":\"${OTHER}\"}" null)"
mut "MUT id_mismatch" "$(ZERO idm)" destroy "$PIN" targeted
write_plan "${VOL_DEL},$(ent 'hcloud_server.inngest' '["update"]' "{\"id\":\"${SRVID}\"}" '{}')"
lay "MUT inngest_server_touched" "$(ZERO ist)" "reason=inngest_server_touched" "reason=out_of_scope" destroy "$PIN" targeted
write_plan "${ATT_DEL},$(ent 'hcloud_server.web["web-1"]' '["update"]')"
lay "MUT named_live_touched" "$(ZERO nlt)" "reason=named_live_touched" "reason=out_of_scope" detach "$PIN" targeted
write_plan "${VOL_DEL}"
mut "MUT id_pin_absent" "$(ZERO ipa)" destroy "" targeted
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete"]' "{\"id\":\"${OTHER}\"}" null)"
mut "MUT pin_not_retired" "$(ZERO pnr)" destroy "$OTHER" targeted
write_plan "${VOL_DEL},$(ent 'hcloud_server.inngest' '["move"]' "{\"id\":\"${SRVID}\"}" "{\"id\":\"${SRVID}\"}")"
mut "MUT unknown_verb" "$(ZERO uvb)" destroy "$PIN" targeted
write_plan "${VOL_DEL},${ATT_DEL}"
mut "MUT unauthorized_delete" "$(ZERO ud)" destroy "$PIN" targeted
write_plan "${WSRV_DEL_N},${WATT_DEL}"
mut "MUT wipe_server_identity (the counter itself)" "$(ZERO wsi)" teardown "$PIN" targeted
write_plan "${WSRV_DEL_LIVE},${WATT_DEL}"
mut "MUT wipe_server_identity: the server-id comparison dropped" 's/(bname != \$wname or bid == null or bid == \$lives)/(bname != $wname or bid == null)/' teardown "$PIN" targeted
write_plan "${WSRV_DEL_N},${WATT_DEL}"
mut "MUT wipe_server_identity: the server-name comparison dropped" 's/(bname != \$wname or bid == null or bid == \$lives)/(bid == null or bid == $lives)/' teardown "$PIN" targeted
write_plan "${WSRV_DEL},${WATT_DEL_LIVE}"
mut "MUT wipe_server_identity: the attachment's server comparison dropped" 's/(bsrv == null or bsrv == \$lives)/(bsrv == null)/' teardown "$PIN" targeted
write_plan "${WSRV_CREATE_N},${WATT_CREATE}"
mut "MUT wipe_server_identity: the create's name comparison dropped" 's/(aname != \$wname)/false/' wipe "$PIN" targeted
write_plan "${VOL_DEL},${LIVE_SET},$(ent 'hcloud_server.web["web-1"]' '["update"]')"
mut "MUT named_live_touched (untargeted, E-4)" "$(ZERO nlt)" destroy "$PIN" untargeted
write_plan "${VOL_DEL},$(ent 'hcloud_volume.git_data' '["create"]' null)"
mut "MUT out_of_scope" "$(ZERO oos)" destroy "$PIN" targeted
write_plan "${VOL_DEL},${LVOL_NOOP},${LATT_NOOP}"
mut "MUT inngest_server_absent" "$(ZERO sab)" destroy "$PIN" untargeted
write_plan "${VOL_DEL},${SRV_NOOP}"
mut "MUT luks_pair_absent" "$(ZERO lpa)" destroy "$PIN" untargeted
write_plan "$(ent 'hcloud_volume.inngest_redis' '["delete"]' '{"id":null}' null)"
mut "MUT id_unverifiable" "$(ZERO idu)" destroy "$PIN" targeted
write_plan "${LIVE_SET}"
mut "MUT shape_missing" "$(ZERO smi)" destroy "$PIN" targeted
write_plan "${VOL_DEL},${VOL_DEL}"
mut "MUT shape_extra" "$(ZERO sex)" destroy "$PIN" targeted

# ══ LIVE-STORE GATE (plan 2.0) -- the chokepoint in front of EVERY phase ══════════
NOW_EPOCH="$(date -u -d '2026-10-13T12:00:00Z' +%s)"
FIX="$TMP/fx"; mkdir -p "$FIX"
probe_row() { # <iso dt> <devid> <redis_active> -> TSV row as the workflow's selection emits it
  printf '%s\tSOLEUR_INNGEST_SERVER_PROBE host_role=dedicated data_mount_src=/dev/mapper/inngest-redis data_mount_devid=%s redis_active=%s redis_keys=3\n' "$1" "$2" "$3"
}
PROBE_OK="$FIX/probe.tsv"
probe_row '2026-10-13 11:10:00' "scsi-0HC_Volume_${LIVEV}" active > "$PROBE_OK"

lsg() { # <name> <want_rc> <needle> [overrides: flag= active= probe=]   (LSG_FN: the function under test; a seam for the reject-controls)
  local name="$1" want="$2" needle="$3"; shift 3
  local flag="done" active="$LIVEV" probe="$PROBE_OK" kv out rc=0
  for kv in "$@"; do
    case "$kv" in
      flag=*) flag="${kv#flag=}" ;; active=*) active="${kv#active=}" ;; probe=*) probe="${kv#probe=}" ;;
    esac
  done
  out="$("${LSG_FN:-inngest_backstop_live_store_gate}" --cutover-flag "$flag" --active-id "$active" --probe-file "$probe" --now "$NOW_EPOCH" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$want" && "$out" == *"$needle"* ]] && { [[ "$want" -eq 0 ]] || one_line "$out"; }; then pass; [[ "$want" -eq 0 ]] && mp=$((mp + 1)); else fail "$name (want rc=$want containing '$needle', one line)" "$rc" "$out"; fi
}
LS_PASS="inngest_backstop_live_store_gate: PASS"
lsg "LS PASS: flag done, pointer on the LUKS volume, fresh probe on it with redis active" 0 "$LS_PASS"
# Guard 4 row 7 -- the chokepoint guards detach/wipe too, so any non-`done` flag value is refused.
for v in rollback rolled-back armed copying "" "__UNREADABLE__" "DONE" "done " "done;x"; do
  lsg "LS flag '${v}' => flag_not_done (row 7)" 1 "reason=flag_not_done" "flag=${v}"
done
lsg "LS pointer on the RETIRED volume => active_id_mismatch" 1 "reason=active_id_mismatch" "active=${PIN}"
lsg "LS pointer empty => active_id_mismatch" 1 "reason=active_id_mismatch" "active="
lsg "LS pointer is a prefix => active_id_mismatch" 1 "reason=active_id_mismatch" "active=10690326"
# E-1: the in-flight-run count and the Hetzner LUKS-attached cross-check are GONE from the gate (the workflow
# group serializes runs; the probe row proves the mount): their options are now unknown options.
for opt in --inflight-runs --server-id --luks-volume-file; do
  out="$(inngest_backstop_live_store_gate --cutover-flag done --active-id "$LIVEV" --probe-file "$PROBE_OK" --now "$NOW_EPOCH" "$opt" 0 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 1 && "$out" == *"reason=usage"* ]] && one_line "$out"; then pass; else fail "E-1: the removed option ${opt} must now be refused as usage" "$rc" "$out"; fi
done
# Probe: freshness and identity.
probe_row '2026-10-13 08:30:00' "scsi-0HC_Volume_${LIVEV}" active > "$FIX/p1.tsv"; lsg "LS probe 3.5 h old => probe_stale (row 4)" 1 "reason=probe_stale" "probe=$FIX/p1.tsv"
probe_row '2026-10-13 11:10:00' "scsi-0HC_Volume_${PIN}" active > "$FIX/p2.tsv";  lsg "LS probe on the RETIRED volume => probe_devid_mismatch (row 4)" 1 "reason=probe_devid_mismatch" "probe=$FIX/p2.tsv"
probe_row '2026-10-13 11:10:00' "scsi-0HC_Volume_${LIVEV}0" active > "$FIX/p3.tsv"; lsg "LS probe devid that merely starts with the live id => probe_devid_mismatch" 1 "reason=probe_devid_mismatch" "probe=$FIX/p3.tsv"
probe_row '2026-10-13 11:10:00' "scsi-0HC_Volume_${LIVEV}" inactive > "$FIX/p4.tsv"; lsg "LS redis not active => probe_redis_down" 1 "reason=probe_redis_down" "probe=$FIX/p4.tsv"
probe_row '2026-10-13 12:30:00' "scsi-0HC_Volume_${LIVEV}" active > "$FIX/p5.tsv"; lsg "LS probe dated in the future => probe_future" 1 "reason=probe_future" "probe=$FIX/p5.tsv"
: > "$FIX/p6.tsv";                                                                lsg "LS empty probe file => probe_unusable" 1 "reason=probe_unusable" "probe=$FIX/p6.tsv"
printf 'garbage line without tab\n' > "$FIX/p7.tsv";                              lsg "LS malformed probe line => probe_unusable" 1 "reason=probe_unusable" "probe=$FIX/p7.tsv"
printf 'not-a-date\tSOLEUR_INNGEST_SERVER_PROBE data_mount_devid=scsi-0HC_Volume_%s redis_active=active\n' "$LIVEV" > "$FIX/p8.tsv"; lsg "LS unparseable dt => probe_unusable" 1 "reason=probe_unusable" "probe=$FIX/p8.tsv"
lsg "LS probe file missing => probe_unusable" 1 "reason=probe_unusable" "probe=$FIX/none.tsv"
# The NEWEST row decides: a stale-but-good row must not hide a newer bad one, and vice versa.
{ probe_row '2026-10-13 10:10:00' "scsi-0HC_Volume_${LIVEV}" active; probe_row '2026-10-13 11:10:00' "scsi-0HC_Volume_${PIN}" active; } > "$FIX/p9.tsv"
lsg "LS newest row off the live volume wins over an older good one => probe_devid_mismatch" 1 "reason=probe_devid_mismatch" "probe=$FIX/p9.tsv"
{ probe_row '2026-10-13 10:10:00' "scsi-0HC_Volume_${PIN}" active; probe_row '2026-10-13 11:10:00' "scsi-0HC_Volume_${LIVEV}" active; } > "$FIX/p10.tsv"
lsg "LS newest row good, older one bad => PASS (non-canonical order, extra fields)" 0 "$LS_PASS" "probe=$FIX/p10.tsv"
# Injected-clock boundaries (W6): the stale limit is 10800 s (inclusive), the future allowance 300 s (inclusive).
iso() { date -u -d "@$1" '+%Y-%m-%d %H:%M:%S'; }
probe_row "$(iso $((NOW_EPOCH - 10800)))" "scsi-0HC_Volume_${LIVEV}" active > "$FIX/b1.tsv";  lsg "LS boundary: probe EXACTLY 10800 s old => PASS" 0 "$LS_PASS" "probe=$FIX/b1.tsv"
probe_row "$(iso $((NOW_EPOCH - 10801)))" "scsi-0HC_Volume_${LIVEV}" active > "$FIX/b2.tsv";  lsg "LS boundary: probe 10801 s old => probe_stale" 1 "reason=probe_stale" "probe=$FIX/b2.tsv"
probe_row "$(iso $((NOW_EPOCH + 300)))" "scsi-0HC_Volume_${LIVEV}" active > "$FIX/b3.tsv";    lsg "LS boundary: probe 300 s in the future => PASS (clock skew allowance)" 0 "$LS_PASS" "probe=$FIX/b3.tsv"
probe_row "$(iso $((NOW_EPOCH + 301)))" "scsi-0HC_Volume_${LIVEV}" active > "$FIX/b4.tsv";    lsg "LS boundary: probe 301 s in the future => probe_future" 1 "reason=probe_future" "probe=$FIX/b4.tsv"
probe_row "$(date -u -d "@$((NOW_EPOCH - 60))" '+%Y-%m-%dT%H:%M:%SZ')" "scsi-0HC_Volume_${LIVEV}" active > "$FIX/b5.tsv"
lsg "LS: an ISO dt with T and Z (the Better Stack form) parses => PASS" 0 "$LS_PASS" "probe=$FIX/b5.tsv"
# Token parsing is FIRST-wins: a later duplicate cannot override the first.
printf '%s\tSOLEUR_INNGEST_SERVER_PROBE host_role=dedicated data_mount_devid=scsi-0HC_Volume_%s data_mount_devid=scsi-0HC_Volume_%s redis_active=active\n' "$(iso $((NOW_EPOCH - 60)))" "$PIN" "$LIVEV" > "$FIX/t1.tsv"
lsg "LS first-wins: devid on the retired volume FIRST, the live one later => probe_devid_mismatch" 1 "reason=probe_devid_mismatch" "probe=$FIX/t1.tsv"
printf '%s\tSOLEUR_INNGEST_SERVER_PROBE host_role=dedicated data_mount_devid=scsi-0HC_Volume_%s data_mount_devid=scsi-0HC_Volume_%s redis_active=active\n' "$(iso $((NOW_EPOCH - 60)))" "$LIVEV" "$PIN" > "$FIX/t2.tsv"
lsg "LS first-wins: live devid FIRST, a later duplicate on the retired one => PASS" 0 "$LS_PASS" "probe=$FIX/t2.tsv"
printf '%s\tSOLEUR_INNGEST_SERVER_PROBE host_role=dedicated data_mount_devid=scsi-0HC_Volume_%s redis_active=inactive redis_active=active\n' "$(iso $((NOW_EPOCH - 60)))" "$LIVEV" > "$FIX/t3.tsv"
lsg "LS first-wins: redis_active=inactive FIRST, active later => probe_redis_down" 1 "reason=probe_redis_down" "probe=$FIX/t3.tsv"

# ══ GUARD 4 -- evidence-before-destroy ════════════════════════════════════════════
NONCE="37900000001"
SIZE_BYTES=$((10 * 1073741824))
AFTER_EPOCH="$(date -u -d '2026-10-14T09:00:00Z' +%s)"
NOW4="$(date -u -d '2026-10-15T12:00:00Z' +%s)"
VOL_FILE="$FIX/v-retired.json"
printf '{"volume":{"id":%s,"name":"soleur-inngest-redis-store","server":null,"size":10}}\n' "$PIN" > "$VOL_FILE"
WIPE_HOST="soleur-inngest-backstop-wipe"; WIPE_SHIPPER="inngest-backstop-wipe"
ev_row_as() { # <host> <shipper> <dt> <message-tail> -> one Better Stack warehouse line (raw is the wipe host's payload, JSON-encoded as a string)
  local msg="SOLEUR_INNGEST_BACKSTOP_WIPE $4"
  jq -cn --arg dt "$3" --arg m "$msg" --arg h "$1" --arg sh "$2" '{dt:$dt, raw: ({message:$m, marker:"SOLEUR_INNGEST_BACKSTOP_WIPE", host:$h, dt:$dt, shipper:$sh} | tojson)}'
}
ev_row() { ev_row_as "$WIPE_HOST" "$WIPE_SHIPPER" "$1" "$2"; } # <dt> <message-tail>
GOODTAIL="result=wiped nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none fs_uuid=abc last_write=2026-09-20"
EV="$FIX/ev.jsonl"
{ ev_row '2026-10-15 09:10:00' "result=started nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES}"; ev_row '2026-10-15 09:20:00' "$GOODTAIL"; } > "$EV"

# Hetzner's action history for the retired volume (D-A): the wipe host's attach, then the detach, both
# after the wipe run's start, the attach to a server that is NOT the live one.
LIVE_SRV="$SRVID"; WIPE_SRV="777"
act() { # <command> <status> <finished-iso> <server-id-or-null>  -> one /v1/volumes/<id>/actions entry
  jq -cn --arg c "$1" --arg st "$2" --arg f "$3" --arg sv "$4" --argjson v "$PIN" \
    '{id: 1, command: $c, status: $st, started: $f, finished: (if $st == "running" then null else $f end),
      resources: ([{id: $v, type: "volume"}] + (if $sv == "none" then [] elif $sv == "null" then [{id: null, type: "server"}] else [{id: ($sv | tonumber), type: "server"}] end))}'
}
write_acts() { printf '{"actions":[%s],"meta":{"pagination":{"page":1,"next_page":null}}}\n' "$2" > "$1"; }
ACT_CREATE="$(act create_volume success 2025-03-01T10:00:00+00:00 none)"
ACT_LIVE_ATT="$(act attach_volume success 2025-03-01T10:01:00+00:00 "$LIVE_SRV")"
ACT_ATT="$(act attach_volume success 2026-10-15T09:05:00+00:00 "$WIPE_SRV")"
ACT_DET="$(act detach_volume success 2026-10-15T09:40:00+00:00 "$WIPE_SRV")"
ACTS_OK="$FIX/acts-ok.json"; write_acts "$ACTS_OK" "${ACT_DET},${ACT_ATT},${ACT_LIVE_ATT},${ACT_CREATE}"
# CLO attestation (D-B): the comment fetched through `gh api repos/<repo>/issues/comments/<id>`.
CLO_ID=4300000001
CLO_URL="https://github.com/jikig-ai/soleur/issues/8285#issuecomment-${CLO_ID}"
CLO_MARK="CLO-ATTESTATION erasure=provider-only volume=${PIN}"
ACTOR="dispatcher"
clo_file() { # <path> <author_association> <body> [id] [issue_url] [login] [user.type] [created_at] [updated_at]
  jq -cn --argjson id "${4:-$CLO_ID}" --arg a "$2" --arg b "$3" --arg iu "${5:-https://api.github.com/repos/jikig-ai/soleur/issues/8285}" \
    --arg lg "${6-clo-reviewer}" --arg ty "${7-User}" --arg c "${8-2026-10-15T10:00:00Z}" --arg u "${9-2026-10-15T10:00:00Z}" \
    '{id: $id, issue_url: $iu, author_association: $a, body: $b, user: {login: $lg, type: $ty}, created_at: $c, updated_at: $u}' > "$1"
}
clo_body() { printf '%s\n%s' "$CLO_MARK" "${1:-I attest that provider-only deletion of volume ${PIN} is accepted; no overwrite is evidenced.}"; }
CLO_OK="$FIX/clo-ok.json"; clo_file "$CLO_OK" OWNER "$(clo_body)"

dp_args() { # [overrides: erasure= run= clo= clofile= rows= vol= acts= livesrv= after= now=] -> DPA (the precondition's argv)
  local erasure="" run="$NONCE" clo="" clofile="" rows="$EV" vol="$VOL_FILE" acts="$ACTS_OK" livesrv="$LIVE_SRV" after="$AFTER_EPOCH" now="$NOW4" actor="$ACTOR" kv
  for kv in "$@"; do
    case "$kv" in
      erasure=*) erasure="${kv#erasure=}" ;; run=*) run="${kv#run=}" ;; clo=*) clo="${kv#clo=}" ;; clofile=*) clofile="${kv#clofile=}" ;;
      rows=*) rows="${kv#rows=}" ;; vol=*) vol="${kv#vol=}" ;; acts=*) acts="${kv#acts=}" ;; livesrv=*) livesrv="${kv#livesrv=}" ;;
      after=*) after="${kv#after=}" ;; now=*) now="${kv#now=}" ;; actor=*) actor="${kv#actor=}" ;;
    esac
  done
  DPA=(--erasure "$erasure" --wipe-run-id "$run" --clo-attestation-ref "$clo" --clo-comment-file "$clofile" --rows-file "$rows" --volume-file "$vol"
       --actions-file "$acts" --live-server-id "$livesrv" --after-epoch "$after" --now "$now" --actor "$actor")
}
dpc() { # <name> <want_rc> <needle> [overrides, see dp_args]   (DPC_FN: the function under test; a seam for the reject-controls)
  local name="$1" want="$2" needle="$3" out rc=0; shift 3
  dp_args "$@"
  out="$("${DPC_FN:-inngest_backstop_destroy_precondition}" "${DPA[@]}" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$want" && "$out" == *"$needle"* ]] && { [[ "$want" -eq 0 ]] || one_line "$out"; }; then pass; [[ "$want" -eq 0 ]] && mp=$((mp + 1)); else fail "$name (want rc=$want containing '$needle', one line)" "$rc" "$out"; fi
}
DP_PASS="inngest_backstop_destroy_precondition: PASS"
dpc "G4 PASS: a wiped row bound to this nonce, after the floor, matching id and size" 0 "$DP_PASS"
# Non-canonical: keys in another order, extra fields, a later refused row that must NOT hide the good one.
{ ev_row '2026-10-15 09:20:00' "fs_uuid=zz sig_after=none readback=zero size_bytes=${SIZE_BYTES} volume_id=${PIN} nonce=${NONCE} result=wiped extra=1 unknown=2"
  ev_row '2026-10-15 10:00:00' "result=refused nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES} guard=mounted"; } > "$FIX/ev-o.jsonl"
dpc "G4 H: reordered keys + extra fields + a LATER refused row => PASS (any qualifying row counts)" 0 "$DP_PASS" "rows=$FIX/ev-o.jsonl"
ev_row '2026-10-15 09:30:00' "result=wiped prior=blank nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none" > "$FIX/ev-b.jsonl"
dpc "G4 H: a prior=blank re-entry row is a wiped row => PASS" 0 "$DP_PASS" "rows=$FIX/ev-b.jsonl"
# Row 1: absent.
: > "$FIX/ev1.jsonl";                                              dpc "G4 row 1: evidence file EMPTY => evidence_absent" 1 "reason=evidence_absent" "rows=$FIX/ev1.jsonl"
dpc "G4 row 1b: evidence file missing => rows_unreadable" 1 "reason=rows_unreadable" "rows=$FIX/none.jsonl"
printf 'garbage\nmore garbage\n' > "$FIX/ev1c.jsonl";              dpc "G4 row 1c: nothing decodes => rows_unreadable" 1 "reason=rows_unreadable" "rows=$FIX/ev1c.jsonl"
jq -cn --arg dt '2026-10-15 09:20:00' --arg m "see SOLEUR_INNGEST_BACKSTOP_WIPE ${GOODTAIL}" '{dt:$dt, raw:({message:$m}|tojson)}' > "$FIX/ev1d.jsonl"
dpc "G4 row 1d: a row that merely QUOTES the marker mid-message is not evidence => evidence_absent" 1 "reason=evidence_absent" "rows=$FIX/ev1d.jsonl"
# Row 2: refused / nonzero.
ev_row '2026-10-15 09:20:00' "result=refused nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none" > "$FIX/ev2a.jsonl"
dpc "G4 row 2a: result=refused => not_wiped" 1 "reason=not_wiped" "rows=$FIX/ev2a.jsonl"
ev_row '2026-10-15 09:20:00' "result=wiped nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=nonzero sig_after=none" > "$FIX/ev2b.jsonl"
dpc "G4 row 2b: readback=nonzero => not_wiped" 1 "reason=not_wiped" "rows=$FIX/ev2b.jsonl"
ev_row '2026-10-15 09:20:00' "result=wiped nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=ext4" > "$FIX/ev2c.jsonl"
dpc "G4 row 2c: a signature survives (sig_after != none) => not_wiped" 1 "reason=not_wiped" "rows=$FIX/ev2c.jsonl"
ev_row '2026-10-15 09:20:00' "result=started nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES}" > "$FIX/ev2d.jsonl"
dpc "G4 row 2d: only a started row (crash after start) => not_wiped" 1 "reason=not_wiped" "rows=$FIX/ev2d.jsonl"
# Row 3: different volume id / size.
ev_row '2026-10-15 09:20:00' "result=wiped nonce=${NONCE} volume_id=${LIVEV} size_bytes=${SIZE_BYTES} readback=zero sig_after=none" > "$FIX/ev3a.jsonl"
dpc "G4 row 3a: evidence for a DIFFERENT volume id (the live one) => volume_mismatch" 1 "reason=volume_mismatch" "rows=$FIX/ev3a.jsonl"
ev_row '2026-10-15 09:20:00' "result=wiped nonce=${NONCE} volume_id=${PIN} size_bytes=$((SIZE_BYTES - 1)) readback=zero sig_after=none" > "$FIX/ev3b.jsonl"
dpc "G4 row 3b: size differs by one byte => volume_mismatch" 1 "reason=volume_mismatch" "rows=$FIX/ev3b.jsonl"
ev_row '2026-10-15 09:20:00' "result=wiped nonce=${NONCE} volume_id=${PIN}0 size_bytes=${SIZE_BYTES} readback=zero sig_after=none" > "$FIX/ev3c.jsonl"
dpc "G4 row 3c: volume_id that merely starts with the pin => volume_mismatch" 1 "reason=volume_mismatch" "rows=$FIX/ev3c.jsonl"
# Row 6: nonce / timestamp.
dpc "G4 row 6a: wipe_run_id differs from the row's nonce => nonce_mismatch" 1 "reason=nonce_mismatch" "run=37900000002"
dpc "G4 row 6b: wipe_run_id that is a PREFIX of the nonce => nonce_mismatch" 1 "reason=nonce_mismatch" "run=3790000000"
write_acts "$FIX/a-late.json" "$(act detach_volume success 2026-10-15T09:50:00+00:00 "$WIPE_SRV"),$(act attach_volume success 2026-10-15T09:35:00+00:00 "$WIPE_SRV")"
dpc "G4 row 6c: row older than the run floor => evidence_stale" 1 "reason=evidence_stale" "after=$(date -u -d '2026-10-15T09:30:00Z' +%s)" "acts=$FIX/a-late.json"
dpc "G4 row 6d: row dated in the future => evidence_stale" 1 "reason=evidence_stale" "now=$(date -u -d '2026-10-15T08:00:00Z' +%s)"
dpc "G4 row 6e: wipe_run_id empty without D4 inputs => run_id_invalid" 1 "reason=run_id_invalid" "run="
dpc "G4 row 6f: wipe_run_id not numeric => run_id_invalid" 1 "reason=run_id_invalid" "run=12ab"
dpc "G4 row 6g: after-epoch not numeric => evidence_stale" 1 "reason=evidence_stale" "after="
# The Hetzner-side re-check (outside the script's own diff).
printf '{"volume":{"id":%s,"server":%s,"size":10}}' "$PIN" "$SRVID" > "$FIX/vol-att.json"
dpc "G4 attached: volume still attached to a server => still_attached" 1 "reason=still_attached" "vol=$FIX/vol-att.json"
printf '{"volume":{"id":%s,"size":10}}' "$PIN" > "$FIX/vol-nokey.json"
dpc "G4 degraded: volume body without a server key => volume_unreadable" 1 "reason=volume_unreadable" "vol=$FIX/vol-nokey.json"
printf '{"volume":null}' > "$FIX/vol-null.json";                   dpc "G4 degraded: volume null => volume_unreadable" 1 "reason=volume_unreadable" "vol=$FIX/vol-null.json"
printf '{}' > "$FIX/vol-empty.json";                               dpc "G4 degraded: {} => volume_unreadable" 1 "reason=volume_unreadable" "vol=$FIX/vol-empty.json"
printf '{"volume":{"id":%s,"server":null,"size":"ten"}}' "$PIN" > "$FIX/vol-size.json"; dpc "G4 degraded: non-numeric size => volume_unreadable" 1 "reason=volume_unreadable" "vol=$FIX/vol-size.json"
printf '{"volume":{"id":%s,"server":null,"size":10}}' "$LIVEV" > "$FIX/vol-live.json"; dpc "G4 the volume answered is the LIVE one => volume_identity_mismatch" 1 "reason=volume_identity_mismatch" "vol=$FIX/vol-live.json"
printf '{"volume":{"id":%s,"server":null,"size":20}}' "$PIN" > "$FIX/vol-20.json";      dpc "G4 Hetzner size differs from the row's => volume_mismatch" 1 "reason=volume_mismatch" "vol=$FIX/vol-20.json"
dpc "G4 volume file missing => volume_unreadable" 1 "reason=volume_unreadable" "vol=$FIX/none.json"
# D4 alternative (D-B): provider-only needs a CLO attestation COMMENT on #8285, never a third way. The ref
# must be exactly https://github.com/jikig-ai/soleur/issues/8285#issuecomment-<digits>; the comment is
# fetched through the GitHub API (by id) and must be a TWO-PERSON attestation (E-2): first line exactly the
# marker, unedited, by a human OWNER|MEMBER whose login differs from the dispatching actor.
D4=("erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$CLO_OK")
dpc "G4 D4: erasure=provider-only + an attested comment + no wipe run => PASS" 0 "$DP_PASS" "${D4[@]}"
dpc "G4 D4: PASS needs no Hetzner action history (nothing was wiped)" 0 "$DP_PASS" "${D4[@]}" "acts=$FIX/none.json"
clo_file "$FIX/clo-MEMBER.json" MEMBER "$(clo_body)"
dpc "G4 D4: author_association MEMBER => PASS" 0 "$DP_PASS" "${D4[@]:0:3}" "clofile=$FIX/clo-MEMBER.json"
dpc "G4 (E-3d wording): the wipe-path PASS says what it does not prove" 0 "this corroborates that a host held the volume, not that the overwrite happened; erasure remains self-attested"
clo_file "$FIX/clo-crlf.json" OWNER "${CLO_MARK}"$'\r\n'"second line typed in the GitHub web editor"
dpc "G4 D4 (E-2a): the web editor's CRLF line ending after the marker is tolerated => PASS" 0 "$DP_PASS" "${D4[@]:0:3}" "clofile=$FIX/clo-crlf.json"
dpc "G4 D4 (E-2d): a different login (case-insensitively different from the actor) => PASS" 0 "$DP_PASS" "${D4[@]}" "actor=Somebody-Else"
dpc "G4 D4: provider-only with NO ref => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=" "clofile=$CLO_OK"
dpc "G4 D4: provider-only with a non-URL ref => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=trust-me" "clofile=$CLO_OK"
dpc "G4 D4: an http (not https) ref => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=http://github.com/jikig-ai/soleur/issues/8285#issuecomment-${CLO_ID}" "clofile=$CLO_OK"
dpc "G4 D4: an ARBITRARY HOST (any https URL that answers 200) is no longer accepted => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=https://example.test/x" "clofile=$CLO_OK"
dpc "G4 D4: a lookalike host => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=https://github.com.evil.test/jikig-ai/soleur/issues/8285#issuecomment-${CLO_ID}" "clofile=$CLO_OK"
dpc "G4 D4: another repo => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=https://github.com/x/y/issues/8285#issuecomment-${CLO_ID}" "clofile=$CLO_OK"
dpc "G4 D4: another issue number => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=https://github.com/jikig-ai/soleur/issues/8286#issuecomment-${CLO_ID}" "clofile=$CLO_OK"
dpc "G4 D4: the issue page itself (no comment anchor) => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=https://github.com/jikig-ai/soleur/issues/8285" "clofile=$CLO_OK"
dpc "G4 D4: a non-numeric comment id => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=https://github.com/jikig-ai/soleur/issues/8285#issuecomment-abc" "clofile=$CLO_OK"
dpc "G4 D4: trailing text after the id => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=${CLO_URL}x" "clofile=$CLO_OK"
dpc "G4 D4: a pull-request URL => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=https://github.com/jikig-ai/soleur/pull/8285#issuecomment-${CLO_ID}" "clofile=$CLO_OK"
dpc "G4 D4: comment file missing => clo_comment_unreadable" 1 "reason=clo_comment_unreadable" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/none.json"
: > "$FIX/clo-empty.json";   dpc "G4 D4: comment file EMPTY (the API read failed) => clo_comment_unreadable" 1 "reason=clo_comment_unreadable" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-empty.json"
printf 'not json' > "$FIX/clo-bad.json"; dpc "G4 D4: comment file not JSON => clo_comment_unreadable" 1 "reason=clo_comment_unreadable" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-bad.json"
printf '{"message":"Not Found"}' > "$FIX/clo-404.json"; dpc "G4 D4: an API error body => clo_comment_unreadable" 1 "reason=clo_comment_unreadable" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-404.json"
clo_file "$FIX/clo-id.json" OWNER "volume ${PIN}" 4300000002
dpc "G4 D4: the fetched comment is another comment than the ref names => clo_comment_unreadable" 1 "reason=clo_comment_unreadable" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-id.json"
clo_file "$FIX/clo-iss.json" OWNER "volume ${PIN}" "$CLO_ID" "https://api.github.com/repos/jikig-ai/soleur/issues/1"
dpc "G4 D4: the comment belongs to another issue => clo_comment_unreadable" 1 "reason=clo_comment_unreadable" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-iss.json"
for assoc in COLLABORATOR NONE CONTRIBUTOR FIRST_TIME_CONTRIBUTOR FIRST_TIMER MANNEQUIN owner ""; do
  clo_file "$FIX/clo-a.json" "$assoc" "$(clo_body)"
  dpc "G4 D4: author_association '${assoc}' => clo_author_not_privileged" 1 "reason=clo_author_not_privileged" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-a.json"
done
clo_file "$FIX/clo-b.json" OWNER "attested, no volume named"
dpc "G4 D4: the body does not name the volume => clo_body_missing_volume" 1 "reason=clo_body_missing_volume" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-b.json"
clo_file "$FIX/clo-c.json" OWNER "volume ${PIN}0 and 1${PIN}"
dpc "G4 D4: the id only as part of a longer number => clo_body_missing_volume" 1 "reason=clo_body_missing_volume" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-c.json"
# E-2: the two-person rule. Each refusal differs from the PASS fixture by ONE field.
clo_file "$FIX/clo-m1.json" OWNER "attested volume ${PIN}"$'\n'"${CLO_MARK}"
dpc "G4 D4 (E-2a): the marker only on the SECOND line => clo_marker_missing" 1 "reason=clo_marker_missing" "${D4[@]:0:3}" "clofile=$FIX/clo-m1.json"
for bad in "${CLO_MARK} " " ${CLO_MARK}" "${CLO_MARK}x" "clo-attestation erasure=provider-only volume=${PIN}" "CLO-ATTESTATION erasure=wipe volume=${PIN}" "CLO-ATTESTATION erasure=provider-only volume=${PIN}0" "CLO-ATTESTATION  erasure=provider-only volume=${PIN}"; do
  clo_file "$FIX/clo-m2.json" OWNER "${bad}"$'\n'"volume ${PIN}"
  dpc "G4 D4 (E-2a): first line '${bad}' is not EXACTLY the marker => clo_marker_missing" 1 "reason=clo_marker_missing" "${D4[@]:0:3}" "clofile=$FIX/clo-m2.json"
done
clo_file "$FIX/clo-e1.json" OWNER "$(clo_body)" "$CLO_ID" "" clo-reviewer User 2026-10-15T10:00:00Z 2026-10-15T10:00:01Z
dpc "G4 D4 (E-2b): the comment was edited one second after it was posted => clo_comment_edited" 1 "reason=clo_comment_edited" "${D4[@]:0:3}" "clofile=$FIX/clo-e1.json"
clo_file "$FIX/clo-e2.json" OWNER "$(clo_body)" "$CLO_ID" "" clo-reviewer User "" ""
dpc "G4 D4 (E-2b): no created_at/updated_at at all (empty equals empty) => clo_comment_edited" 1 "reason=clo_comment_edited" "${D4[@]:0:3}" "clofile=$FIX/clo-e2.json"
for ty in Bot Organization Mannequin user ""; do
  clo_file "$FIX/clo-u.json" OWNER "$(clo_body)" "$CLO_ID" "" clo-reviewer "$ty"
  dpc "G4 D4 (E-2c): user.type '${ty}' => clo_author_not_human" 1 "reason=clo_author_not_human" "${D4[@]:0:3}" "clofile=$FIX/clo-u.json"
done
jq -c 'del(.user)' "$CLO_OK" > "$FIX/clo-nouser.json"
dpc "G4 D4 (E-2c): no user object at all => clo_author_not_human" 1 "reason=clo_author_not_human" "${D4[@]:0:3}" "clofile=$FIX/clo-nouser.json"
dpc "G4 D4 (E-2d): the comment's author IS the dispatching actor => clo_same_actor" 1 "reason=clo_same_actor" "${D4[@]}" "actor=clo-reviewer"
dpc "G4 D4 (E-2d): ... compared case-insensitively => clo_same_actor" 1 "reason=clo_same_actor" "${D4[@]}" "actor=CLO-Reviewer"
dpc "G4 D4 (E-2d): an empty dispatching actor is refused (fail closed) => clo_same_actor" 1 "reason=clo_same_actor" "${D4[@]}" "actor="
clo_file "$FIX/clo-nolg.json" OWNER "$(clo_body)" "$CLO_ID" "" "" User
dpc "G4 D4 (E-2d): the comment carries no login => clo_same_actor" 1 "reason=clo_same_actor" "${D4[@]:0:3}" "clofile=$FIX/clo-nolg.json"
dpc "G4 D4: provider-only AND a wipe run id => ambiguous_inputs" 1 "reason=ambiguous_inputs" "erasure=provider-only" "run=${NONCE}" "clo=$CLO_URL" "clofile=$CLO_OK"
dpc "G4 D4: a CLO ref supplied without erasure=provider-only => ambiguous_inputs" 1 "reason=ambiguous_inputs" "clo=$CLO_URL" "clofile=$CLO_OK"
dpc "G4 D4: an unknown erasure value => erasure_unknown" 1 "reason=erasure_unknown" "erasure=skip"
dpc "G4 D4: provider-only still needs the volume detached => still_attached" 1 "reason=still_attached" "${D4[@]}" "vol=$FIX/vol-att.json"
dpc "G4 explicit erasure=wipe behaves as the default" 0 "$DP_PASS" "erasure=wipe"

# ── D-A: the evidence row is self-attested (a holder of the shared ingest token can forge one), so the
#    destroy ALSO needs Hetzner's own record: an attach by a server that is not the live one, after the
#    wipe run started, and a later detach. ──
write_acts "$FIX/a1.json" "${ACT_LIVE_ATT},${ACT_CREATE}"
dpc "G4 D-A: no wipe-host attach at all in Hetzner's history (a forged row alone) => no_wipe_attach" 1 "reason=no_wipe_attach" "acts=$FIX/a1.json"
write_acts "$FIX/a2.json" "${ACT_DET},$(act attach_volume success 2026-10-14T08:59:59+00:00 "$WIPE_SRV"),${ACT_LIVE_ATT}"
dpc "G4 D-A: the attach finished one second BEFORE the wipe run started => no_wipe_attach" 1 "reason=no_wipe_attach" "acts=$FIX/a2.json"
write_acts "$FIX/a2b.json" "${ACT_DET},$(act attach_volume success 2026-10-14T09:00:00+00:00 "$WIPE_SRV")"
dpc "G4 D-A: the attach finished AT the floor (>=) => PASS" 0 "$DP_PASS" "acts=$FIX/a2b.json"
write_acts "$FIX/a3.json" "${ACT_DET},$(act attach_volume success 2026-10-15T09:05:00+00:00 "$LIVE_SRV")"
dpc "G4 D-A: the post-floor attach was to the LIVE server => no_wipe_attach" 1 "reason=no_wipe_attach" "acts=$FIX/a3.json"
write_acts "$FIX/a4.json" "${ACT_DET},$(act attach_volume success 2026-10-15T09:05:00+00:00 null)"
dpc "G4 D-A: the attach references a null server id => no_wipe_attach" 1 "reason=no_wipe_attach" "acts=$FIX/a4.json"
write_acts "$FIX/a4b.json" "${ACT_DET},$(act attach_volume success 2026-10-15T09:05:00+00:00 none)"
dpc "G4 D-A: the attach references no server at all => no_wipe_attach" 1 "reason=no_wipe_attach" "acts=$FIX/a4b.json"
write_acts "$FIX/a5.json" "${ACT_DET},$(act attach_volume error 2026-10-15T09:05:00+00:00 "$WIPE_SRV"),$(act attach_volume running 2026-10-15T09:06:00+00:00 "$WIPE_SRV")"
dpc "G4 D-A: the post-floor attaches did not succeed (error, running) => no_wipe_attach" 1 "reason=no_wipe_attach" "acts=$FIX/a5.json"
write_acts "$FIX/a6.json" "${ACT_ATT}"
dpc "G4 D-A: attached, never detached => no_wipe_detach" 1 "reason=no_wipe_detach" "acts=$FIX/a6.json"
write_acts "$FIX/a7.json" "${ACT_ATT},$(act detach_volume success 2026-10-15T09:04:59+00:00 "$WIPE_SRV")"
dpc "G4 D-A: the only detach finished BEFORE the attach => no_wipe_detach" 1 "reason=no_wipe_detach" "acts=$FIX/a7.json"
write_acts "$FIX/a8.json" "${ACT_ATT},$(act detach_volume error 2026-10-15T09:40:00+00:00 "$WIPE_SRV")"
dpc "G4 D-A: the later detach did not succeed => no_wipe_detach" 1 "reason=no_wipe_detach" "acts=$FIX/a8.json"
write_acts "$FIX/a9.json" "${ACT_ATT},$(act detach_volume success 2026-10-15T09:05:00+00:00 "$WIPE_SRV")"
ev_row '2026-10-15 09:07:00' "$GOODTAIL" > "$FIX/ev-a9.jsonl"
dpc "G4 D-A: a detach finishing at the same second as the attach counts (>=) => PASS" 0 "$DP_PASS" "acts=$FIX/a9.json" "rows=$FIX/ev-a9.jsonl"
dpc "G4 D-A: actions file missing => actions_unreadable" 1 "reason=actions_unreadable" "acts=$FIX/none.json"
: > "$FIX/a10.json"; dpc "G4 D-A: actions file empty (the read failed) => actions_unreadable" 1 "reason=actions_unreadable" "acts=$FIX/a10.json"
printf '{}' > "$FIX/a11.json"; dpc "G4 D-A: actions body without an actions array => actions_unreadable" 1 "reason=actions_unreadable" "acts=$FIX/a11.json"
printf '{"actions":"x"}' > "$FIX/a12.json"; dpc "G4 D-A: actions not an array => actions_unreadable" 1 "reason=actions_unreadable" "acts=$FIX/a12.json"
printf '{"actions":[]}' > "$FIX/a13.json"; dpc "G4 D-A: an EMPTY history => no_wipe_attach" 1 "reason=no_wipe_attach" "acts=$FIX/a13.json"
dpc "G4 D-A: live server id empty => live_server_unreadable" 1 "reason=live_server_unreadable" "livesrv="
dpc "G4 D-A: live server id not numeric => live_server_unreadable" 1 "reason=live_server_unreadable" "livesrv=abc"
printf '{"actions":[{"command":"attach_volume","status":"success","finished":"garbage","resources":[{"id":777,"type":"server"}]},{"command":"detach_volume","status":"success","finished":"garbage"}]}' > "$FIX/a14.json"
dpc "G4 D-A: unparseable finished times never satisfy the floor => no_wipe_attach" 1 "reason=no_wipe_attach" "acts=$FIX/a14.json"
# D-A: the emitter is pinned (host + shipper the wipe host sends); a row from any other host is not evidence.
ev_row_as "attacker-box" "$WIPE_SHIPPER" '2026-10-15 09:20:00' "$GOODTAIL" > "$FIX/ev-h.jsonl"
dpc "G4 D-A: an otherwise-perfect row from host attacker-box (forged with the shared ingest token) => emitter_mismatch" 1 "reason=emitter_mismatch" "rows=$FIX/ev-h.jsonl"
ev_row_as "$WIPE_HOST" "vector" '2026-10-15 09:20:00' "$GOODTAIL" > "$FIX/ev-sh.jsonl"
dpc "G4 D-A: a perfect row from the right host but another shipper => emitter_mismatch" 1 "reason=emitter_mismatch" "rows=$FIX/ev-sh.jsonl"
ev_row_as "${WIPE_HOST}x" "$WIPE_SHIPPER" '2026-10-15 09:20:00' "$GOODTAIL" > "$FIX/ev-h2.jsonl"
dpc "G4 D-A: a host name that merely starts with the wipe host's => emitter_mismatch" 1 "reason=emitter_mismatch" "rows=$FIX/ev-h2.jsonl"
jq -cn --arg dt '2026-10-15 09:20:00' --arg m "SOLEUR_INNGEST_BACKSTOP_WIPE ${GOODTAIL}" '{dt:$dt, raw:({message:$m}|tojson)}' > "$FIX/ev-nohost.jsonl"
dpc "G4 D-A: a row with no host/shipper fields at all => emitter_mismatch" 1 "reason=emitter_mismatch" "rows=$FIX/ev-nohost.jsonl"
{ ev_row_as "attacker-box" "$WIPE_SHIPPER" '2026-10-15 09:21:00' "$GOODTAIL"; ev_row '2026-10-15 09:20:00' "$GOODTAIL"; } > "$FIX/ev-hmix.jsonl"
dpc "G4 D-A: a forged row does not hide a genuine one (any qualifying row counts) => PASS" 0 "$DP_PASS" "rows=$FIX/ev-hmix.jsonl"

# ── E-3: the corroboration is tightened. (a)+(b) the volume must not go back to the LIVE server after the wipe
#    host's attach; (c) the matched wiped row's INGEST time (the top-level dt column; the dt inside raw is
#    sender-supplied and never read) must lie between the attach and the first later detach, 300 s slack each side. ──
ACT_LIVE_RE="$(act attach_volume success 2026-10-15T09:50:00+00:00 "$LIVE_SRV")"
write_acts "$FIX/e1.json" "${ACT_LIVE_RE},${ACT_DET},${ACT_ATT},${ACT_LIVE_ATT},${ACT_CREATE}"
dpc "E-3a/b: the volume was attached to the LIVE server again after the wipe host's attach => live_reattached" 1 "reason=live_reattached" "acts=$FIX/e1.json"
write_acts "$FIX/e2.json" "$(act attach_volume success 2026-10-15T09:05:00+00:00 "$LIVE_SRV"),${ACT_DET},${ACT_ATT},${ACT_CREATE}"
dpc "E-3a/b: a live attach finishing in the SAME second as the wipe attach is not 'after' => PASS" 0 "$DP_PASS" "acts=$FIX/e2.json"
write_acts "$FIX/e3.json" "$(act attach_volume success 2026-10-14T08:00:00+00:00 "$LIVE_SRV"),${ACT_DET},${ACT_ATT},${ACT_CREATE}"
dpc "E-3a: a live attach from BEFORE the wipe run started does not matter => PASS" 0 "$DP_PASS" "acts=$FIX/e3.json"
write_acts "$FIX/e4.json" "$(act attach_volume running 2026-10-15T09:50:00+00:00 "$LIVE_SRV"),${ACT_DET},${ACT_ATT},${ACT_CREATE}"
dpc "E-3a: a live attach that did not succeed is ignored => PASS" 0 "$DP_PASS" "acts=$FIX/e4.json"
ev_row_dts() { # <top-level (ingest) dt> <dt inside raw (sender-supplied)> <message tail>
  jq -cn --arg dt "$1" --arg rdt "$2" --arg m "SOLEUR_INNGEST_BACKSTOP_WIPE $3" --arg h "$WIPE_HOST" --arg sh "$WIPE_SHIPPER" \
    '{dt:$dt, raw: ({message:$m, marker:"SOLEUR_INNGEST_BACKSTOP_WIPE", host:$h, dt:$rdt, shipper:$sh} | tojson)}'
}
win_row() { ev_row_dts "$1" "$1" "$GOODTAIL" > "$FIX/ev-win.jsonl"; }
win_row '2026-10-15 09:00:00'; dpc "E-3c: the row exactly 300 s before the attach (inclusive) => PASS" 0 "$DP_PASS" "rows=$FIX/ev-win.jsonl"
win_row '2026-10-15 08:59:59'; dpc "E-3c: the row 301 s before the attach => row_outside_attach_window" 1 "reason=row_outside_attach_window" "rows=$FIX/ev-win.jsonl"
win_row '2026-10-15 09:45:00'; dpc "E-3c: the row exactly 300 s after the detach (inclusive) => PASS" 0 "$DP_PASS" "rows=$FIX/ev-win.jsonl"
win_row '2026-10-15 09:45:01'; dpc "E-3c: the row 301 s after the detach => row_outside_attach_window" 1 "reason=row_outside_attach_window" "rows=$FIX/ev-win.jsonl"
win_row '2026-10-15T09:20:00Z'; dpc "E-3c: an ISO T...Z ingest dt inside the window => PASS" 0 "$DP_PASS" "rows=$FIX/ev-win.jsonl"
ev_row_dts '2026-10-15 09:45:01' '2026-10-15 09:45:01' "$GOODTAIL" > "$FIX/ev-win-late.jsonl"
ev_row_dts '2026-10-15 08:59:59' '2026-10-15 08:59:59' "$GOODTAIL" > "$FIX/ev-win-early.jsonl"
ev_row_dts '2026-10-15 07:00:00' '2026-10-15 09:20:00' "$GOODTAIL" > "$FIX/ev-win-a.jsonl"
dpc "E-3c: the ingest dt is OUTSIDE the window although the sender-supplied dt in raw is inside => row_outside_attach_window" 1 "reason=row_outside_attach_window" "rows=$FIX/ev-win-a.jsonl"
ev_row_dts '2026-10-15 09:20:00' '2020-01-01 00:00:00' "$GOODTAIL" > "$FIX/ev-win-b.jsonl"
dpc "E-3c: the ingest dt is inside the window although the dt in raw is years out => PASS (only the ingest column is read)" 0 "$DP_PASS" "rows=$FIX/ev-win-b.jsonl"
{ ev_row '2026-10-15 07:00:00' "$GOODTAIL"; ev_row '2026-10-15 09:20:00' "$GOODTAIL"; } > "$FIX/ev-win-c.jsonl"
dpc "E-3c: one qualifying row outside the window and one inside => PASS (any qualifying row counts)" 0 "$DP_PASS" "rows=$FIX/ev-win-c.jsonl"
ev_row '2026-10-15 09:20:00' "result=wiped nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=ext4" > "$FIX/ev-win-d.jsonl"
dpc "E-3c: the window does not mask an earlier funnel reason (not_wiped is reported first)" 1 "reason=not_wiped" "rows=$FIX/ev-win-d.jsonl"
out="$(inngest_backstop_wipe_evidence_gate --rows-file "$EV" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now "$NOW4" --attach-epoch "$(date -u -d '2026-10-15T09:05:00Z' +%s)" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 1 && "$out" == *"reason=window_invalid"* ]] && one_line "$out"; then pass; else fail "E-3c: an attach epoch without a detach epoch => window_invalid" "$rc" "$out"; fi

# ── Usage and operand hygiene: an unknown option, a missing clock, direct evidence-gate misuse ──
for fn in inngest_backstop_live_store_gate inngest_backstop_destroy_precondition inngest_backstop_wipe_evidence_gate; do
  out="$("$fn" --bogus x 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 1 && "$out" == *"reason=usage"* ]] && one_line "$out"; then pass; else fail "usage: ${fn} must refuse an unknown option" "$rc" "$out"; fi
done
out="$(inngest_backstop_live_store_gate --cutover-flag "done" --active-id "$LIVEV" --probe-file "$PROBE_OK" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 1 && "$out" == *"reason=probe_unusable"* ]]; then pass; else fail "LS: a missing --now (no clock) must fail closed" "$rc" "$out"; fi
out="$(inngest_backstop_live_store_gate --cutover-flag "done" --active-id "$LIVEV" --probe-file "$PROBE_OK" --now abc 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 1 && "$out" == *"reason=probe_unusable"* ]]; then pass; else fail "LS: a non-numeric --now must fail closed" "$rc" "$out"; fi
evg() { # <name> <want-needle> then evidence-gate args
  local name="$1" needle="$2"; shift 2; local out rc=0
  out="$("${EVG_FN:-inngest_backstop_wipe_evidence_gate}" "$@" 2>&1)" || rc=$?
  if [[ "$rc" -eq 1 && "$out" == *"$needle"* ]] && one_line "$out"; then pass; else fail "$name (want rc=1 containing '$needle', one line)" "$rc" "$out"; fi
}
evg "EV: non-numeric nonce" "reason=run_id_invalid" --rows-file "$EV" --nonce abc --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now "$NOW4"
evg "EV: a volume id other than the retired one" "reason=volume_mismatch" --rows-file "$EV" --nonce "$NONCE" --volume-id "$LIVEV" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now "$NOW4"
evg "EV: a zero or missing size" "reason=volume_mismatch" --rows-file "$EV" --nonce "$NONCE" --volume-id "$PIN" --size-bytes 0 --after-epoch "$AFTER_EPOCH" --now "$NOW4"
evg "EV: a non-numeric clock" "reason=evidence_stale" --rows-file "$EV" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now x
evg "EV: rows file not given" "reason=rows_unreadable" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now "$NOW4"
out="$(inngest_backstop_wipe_evidence_gate --rows-file "$EV" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now "$NOW4" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"inngest_backstop_wipe_evidence_gate: PASS"* ]]; then pass; else fail "EV (must-PASS): the evidence gate accepts the canonical wiped row directly (the wipe phase's poll form)" "$rc" "$out"; fi
evok() { # <name> <rows-file> <now> <after>   must-PASS direction of the funnel (boundary rows)
  local name="$1" rf="$2" nw="$3" af="$4" o r=0
  o="$("${EVG_FN:-inngest_backstop_wipe_evidence_gate}" --rows-file "$rf" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$af" --now "$nw" 2>&1)" || r=$?
  if [[ "$r" -eq 0 && "$o" == *"evidence_gate: PASS"* ]]; then pass; mp=$((mp + 1)); else fail "$name" "$r" "$o"; fi
}
ROW_EPOCH="$(date -u -d '2026-10-15T09:20:00Z' +%s)"
evok "EV boundary: now = row - 300 s (the future allowance, inclusive) => PASS" "$EV" $((ROW_EPOCH - 300)) "$AFTER_EPOCH"
evg "EV boundary: now = row - 301 s => evidence_stale" "reason=evidence_stale" --rows-file "$EV" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now $((ROW_EPOCH - 301))
evok "EV boundary: floor = the row's own second (>=) => PASS" "$EV" "$NOW4" "$ROW_EPOCH"
evg "EV boundary: floor = row + 1 s => evidence_stale" "reason=evidence_stale" --rows-file "$EV" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch $((ROW_EPOCH + 1)) --now "$NOW4"
ev_row_as "$WIPE_HOST" "$WIPE_SHIPPER" '2026-10-15T09:20:00Z' "$GOODTAIL" > "$FIX/ev-iso.jsonl"
evok "EV: a row dt in the ISO T...Z form parses => PASS" "$FIX/ev-iso.jsonl" "$NOW4" "$AFTER_EPOCH"
# Token parsing is FIRST-wins here too: a later duplicate key cannot flip a verdict either way.
ev_row '2026-10-15 09:20:00' "result=refused nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none result=wiped" > "$FIX/ev-fw1.jsonl"
evg "EV first-wins: result=refused FIRST, wiped later => not_wiped" "reason=not_wiped" --rows-file "$FIX/ev-fw1.jsonl" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now "$NOW4"
ev_row '2026-10-15 09:20:00' "result=wiped nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none result=refused nonce=1" > "$FIX/ev-fw2.jsonl"
evok "EV first-wins: wiped FIRST, a later result=refused / nonce=1 duplicate is ignored => PASS" "$FIX/ev-fw2.jsonl" "$NOW4" "$AFTER_EPOCH"
ev_row '2026-10-15 09:20:00' "result=wiped nonce=1 nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none" > "$FIX/ev-fw3.jsonl"
evg "EV first-wins: a foreign nonce FIRST, ours later => nonce_mismatch" "reason=nonce_mismatch" --rows-file "$FIX/ev-fw3.jsonl" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now "$NOW4"

# ── The poll's refusal short-circuit: inngest_backstop_wipe_nonce_rows prints the message of every marker
#    row bearing THIS nonce (and only those), so a refusal's reason= is readable without a Better Stack session.
NR="$FIX/nr.jsonl"
{ ev_row '2026-10-15 09:10:00' "result=started nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES}"
  ev_row '2026-10-15 09:11:00' "result=refused reason=has_holders nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES}"
  ev_row '2026-10-15 09:12:00' "result=refused reason=mounted nonce=999 volume_id=${PIN} size_bytes=${SIZE_BYTES}"
  jq -cn '{dt:"2026-10-15 09:13:00", raw: ({message:"unrelated line"} | tojson)}'; } > "$NR"
nr_out="$(inngest_backstop_wipe_nonce_rows --rows-file "$NR" --nonce "$NONCE" 2>&1)" && nr_rc=0 || nr_rc=$?
if [[ "$nr_rc" -eq 0 && "$nr_out" == *"result=started nonce=${NONCE}"* && "$nr_out" == *"reason=has_holders"* && "$nr_out" != *"reason=mounted"* && "$nr_out" != *"unrelated"* && "$(printf '%s\n' "$nr_out" | grep -c .)" -eq 2 ]]; then pass
else fail "NR: prints exactly this nonce's marker rows (started + refused/has_holders), not another nonce's nor an unrelated line" "$nr_rc" "$nr_out"; fi
: > "$FIX/nr-empty.jsonl"
nr_out="$(inngest_backstop_wipe_nonce_rows --rows-file "$FIX/nr-empty.jsonl" --nonce "$NONCE" 2>&1)" && nr_rc=0 || nr_rc=$?
if [[ "$nr_rc" -eq 0 && -z "$nr_out" ]]; then pass; else fail "NR: no rows => prints nothing, rc 0" "$nr_rc" "$nr_out"; fi
nr_out="$(inngest_backstop_wipe_nonce_rows --rows-file "$NR" --nonce abc 2>&1)" && nr_rc=0 || nr_rc=$?
if [[ "$nr_rc" -eq 1 && "$nr_out" == *"reason=run_id_invalid"* ]]; then pass; else fail "NR: a non-numeric nonce is refused" "$nr_rc" "$nr_out"; fi
nr_out="$(inngest_backstop_wipe_nonce_rows --rows-file "$FIX/none.jsonl" --nonce "$NONCE" 2>&1)" && nr_rc=0 || nr_rc=$?
if [[ "$nr_rc" -eq 1 && "$nr_out" == *"reason=rows_unreadable"* ]]; then pass; else fail "NR: a missing rows file is refused (not 'no refusal')" "$nr_rc" "$nr_out"; fi
nr_out="$(inngest_backstop_wipe_nonce_rows --bogus x 2>&1)" && nr_rc=0 || nr_rc=$?
if [[ "$nr_rc" -eq 1 && "$nr_out" == *"reason=usage"* ]]; then pass; else fail "NR: an unknown option is refused" "$nr_rc" "$nr_out"; fi

# ── In-suite mutations of the destroy precondition's NEW guards (D-A, D-B): neuter ONE guard in a copy of the
#    lib; the input that the guard exists to refuse must then be ACCEPTED (sole guard) or fall to the named
#    fallback (layered). Each helper first asserts the mutation LANDED. ──
dmut() { # <label> <sed> [dp_args overrides]
  local label="$1" sedx="$2"; shift 2; dp_args "$@"
  gate_mutate_and_check "$label" "$sedx" inngest_backstop_destroy_precondition "${DPA[@]}"
}
dlay() { # <label> <sed> <own> <fallback> [dp_args overrides]
  local label="$1" sedx="$2" own="$3" fb="$4"; shift 4; dp_args "$@"
  gate_mutate_layered "$label" "$sedx" "$own" "$fb" inngest_backstop_destroy_precondition "${DPA[@]}"
}
dmut "MUT emitter pin: a forged row from another host passes" 's/map(select(\.h == \$eh and \.sh == \$es))/map(select(true))/' "rows=$FIX/ev-h.jsonl"
dmut "MUT emitter pin (shipper half): a wrong shipper passes" 's/\.h == \$eh and \.sh == \$es/.h == $eh/' "rows=$FIX/ev-sh.jsonl"
dmut "MUT Hetzner corroboration: a history with no wipe-host attach passes" 's/^    no_wipe_attach) echo .*; return 1 ;;/    no_wipe_attach) ;;/' "acts=$FIX/a1.json"
dmut "MUT live-server exclusion: an attach to the LIVE server passes" 's/(\.s | any(\. != \$live))/(.s | any(true))/' "acts=$FIX/a3.json"
dmut "MUT attach floor: an attach from before the wipe run started passes" 's/\.c == "attach_volume" and \.f >= \$after and/.c == "attach_volume" and/' "acts=$FIX/a2.json"
dmut "MUT attach status: attaches that did not succeed pass" 's/select(\.status == "success")/select(true)/' "acts=$FIX/a5.json"
dlay "MUT detach requirement: attached-never-detached is then caught only by the unparseable-window check" 's/ == 0 then "no_wipe_detach"/ == -1 then "no_wipe_detach"/' "reason=no_wipe_detach" "reason=actions_unreadable" "acts=$FIX/a6.json"
dlay "MUT detach ordering: a detach from BEFORE the attach is then caught only by the attach..detach window" 's/\.c == "detach_volume" and \.f >= \$af/.c == "detach_volume"/' "reason=no_wipe_detach" "reason=row_outside_attach_window" "acts=$FIX/a7.json"
dmut "MUT E-3a/b: a re-attach to the LIVE server after the wipe attach passes" 's|select(\.f >= (\$ln // 0))|select(true)|' "acts=$FIX/e1.json"
dmut "MUT E-3c: the attach..detach window is not applied" 's/\$win == 0 or (\.e >= (\$att - 300) and \.e <= (\$det + 300))/true/' "rows=$FIX/ev-win-a.jsonl"
dmut "MUT E-3c: the row time is read from the sender-supplied dt inside raw" 's/e: (\$o | epoch)/e: ($r | epoch)/' "rows=$FIX/ev-win-a.jsonl"
dmut "MUT E-3c: the window's upper bound is dropped" 's/ and \.e <= (\$det + 300)//' "rows=$FIX/ev-win-late.jsonl"
dmut "MUT E-3c: the window's lower bound is dropped" 's/(\.e >= (\$att - 300) and /(/' "rows=$FIX/ev-win-early.jsonl"
clo_file "$FIX/clo-a.json" NONE "$(clo_body)"
dmut "MUT CLO author (NONE fixture): author_association NONE passes" 's/IN("OWNER", "MEMBER")/IN("OWNER", "MEMBER", "NONE")/' "${D4[@]:0:3}" "clofile=$FIX/clo-a.json"
dlay "MUT CLO body: a comment that does not name the volume is then refused only by the marker" 's/test("(^|\[^0-9\])" + \$v + "(\[^0-9\]|\$)")/test("")/' "reason=clo_body_missing_volume" "reason=clo_marker_missing" "${D4[@]:0:3}" "clofile=$FIX/clo-b.json"
dmut "MUT E-2a: the marker line is not required" '/reason=clo_marker_missing/s/return 1; }/:; }/' "${D4[@]:0:3}" "clofile=$FIX/clo-m1.json"
dmut "MUT E-2b: an edited comment is accepted" '/reason=clo_comment_edited/s/return 1; }/:; }/' "${D4[@]:0:3}" "clofile=$FIX/clo-e1.json"
clo_file "$FIX/clo-bot.json" OWNER "$(clo_body)" "$CLO_ID" "" clo-reviewer Bot
dmut "MUT E-2c: a Bot author is accepted" '/reason=clo_author_not_human/s/return 1; }/:; }/' "${D4[@]:0:3}" "clofile=$FIX/clo-bot.json"
dmut "MUT E-2d: the comment's author may be the dispatching actor" '/reason=clo_same_actor/s/return 1$/:/' "${D4[@]}" "actor=clo-reviewer"
dmut "MUT E-2d: the actor comparison is case-sensitive" 's/(\.user\.login | ascii_downcase) != (\$actor | ascii_downcase)/.user.login != $actor/' "${D4[@]}" "actor=CLO-Reviewer"
dlay "MUT CLO ref pattern: an arbitrary host is then refused only by the comment-id binding" 's|^    if \[\[ ! "\$clo" =~ .*|    if false; then|' "reason=clo_ref_invalid" "reason=clo_comment_unreadable" "${D4[@]:0:3}" "clo=https://example.test/x" "clofile=$CLO_OK"

# the always-pass stub-lib meta-run (the meta-run) stops HERE when SOLEUR_IBRG_META is set: everything above is graded by the lib under test, everything below is helper-only (its reject-controls would FATAL against a stub that passes everything)
if [[ -n "${SOLEUR_IBRG_META:-}" ]]; then
  printf 'inngest-backstop-retire-gate: %s passed, %s failed\n' "$passes" "$fails"
  [[ "$fails" -eq 0 ]]; exit $?
fi

# ── Row 5 / ordering and wiring, asserted against the workflow text ────────────────
WF="${REPO_ROOT}/.github/workflows/apply-web-platform-infra.yml"
# W2-14: the 489 KB workflow is parsed ONCE (CSafeLoader when libyaml exists, else the pure-Python SafeLoader), by the
# extractor below; it writes the facts, one file per step `run:` (byte for byte, no escape processing) and the pin
# results. Every later row reads those files; nothing re-parses the YAML.
XD="$TMP/xd"; mkdir -p "$XD"
assert_fixture_dir "$XD"
EXTRACT_PY="$TMP/wf-extract.py"
cat > "$EXTRACT_PY" <<'EXTRACTPY'
import sys, re, json, os
import yaml

def load(text):
    return yaml.load(text, Loader=getattr(yaml, "CSafeLoader", yaml.SafeLoader))

# ---- the exact `if:` of EVERY step of the job, in order (label = name, or the pinned action for an unnamed step)
IF_TABLE = [
    ("actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5", None),
    ("hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85", None),
    ("Load infra credentials (tiered)", None),
    ("Validate inputs (typo-guards, NOT the authorization)", None),
    ("Assert the inngest-cutover reviewer set is NON-EMPTY (layer 1 is the authorization)", None),
    ("Live-store gate (plan 2.0, in front of detach, wipe and destroy; NOT teardown)", "env.RETIRE_PHASE != 'teardown'"),
    ("Prepare terraform (ephemeral ssh key, R2 backend credentials, init)", None),
    ("Convergence read (idempotent per phase; Hetzner first)", None),
    ("Destroy precondition (Guard 4, before any plan)", "env.RETIRE_PHASE == 'destroy' && steps.conv.outputs.skip != 'true'"),
    ("Read-only untargeted plan (host and LUKS pair must be present no-ops)", "steps.conv.outputs.skip != 'true' && env.RETIRE_PHASE != 'teardown'"),
    ("Terraform plan (phase) + plan-shape gate + stock preflight", "steps.conv.outputs.skip != 'true' && env.RETIRE_PHASE != 'teardown'"),
    ("Terraform apply (phase)", "steps.conv.outputs.skip != 'true' && env.RETIRE_PHASE != 'teardown'"),
    ("Wipe evidence (bounded poll for this run's nonce)", "env.RETIRE_PHASE == 'wipe' && steps.conv.outputs.skip != 'true'"),
    ("Teardown of the wipe host (if always; also phase=teardown)", "always() && steps.conv.outcome == 'success' && steps.conv.outputs.skip != 'true' && (env.RETIRE_PHASE == 'wipe' || env.RETIRE_PHASE == 'teardown')"),
    ("Read-back (hard exit criterion for the phase)", "always() && steps.conv.outcome == 'success' && (steps.conv.outputs.skip != 'true' || env.RETIRE_PHASE == 'destroy')"),
    ("Progress comment on #8285 (success or failure)", "always()"),
    ("Dispatch summary", "always()"),
]
JOB_KEYS = {"if", "runs-on", "timeout-minutes", "environment", "concurrency", "permissions", "env", "steps"}
SHORT = {"Live-store gate": "LIVE", "Convergence read": "CONV", "Destroy precondition": "PRE", "Read-only untargeted plan": "UNT",
         "Terraform plan (phase)": "PLAN", "Terraform apply (phase)": "APPLY", "Wipe evidence": "POLL", "Teardown of the wipe host": "TEAR",
         "Read-back": "RB", "Progress comment": "PROG", "Dispatch summary": "SUM"}
# which of the gated steps RUN, per phase and per skip flag, when every earlier step succeeded (conv succeeded)
ALWAYS = {"PROG", "SUM"}
EXPECT_OK = {
    ("detach", "false"): {"LIVE", "CONV", "UNT", "PLAN", "APPLY", "RB"} | ALWAYS,
    ("detach", "true"): {"LIVE", "CONV"} | ALWAYS,
    ("wipe", "false"): {"LIVE", "CONV", "UNT", "PLAN", "APPLY", "POLL", "TEAR", "RB"} | ALWAYS,
    ("wipe", "true"): {"LIVE", "CONV"} | ALWAYS,
    ("teardown", "false"): {"CONV", "TEAR", "RB"} | ALWAYS,
    ("teardown", "true"): {"CONV"} | ALWAYS,
    ("destroy", "false"): {"LIVE", "CONV", "PRE", "UNT", "PLAN", "APPLY", "RB"} | ALWAYS,
    ("destroy", "true"): {"LIVE", "CONV", "RB"} | ALWAYS,
}
# after ANY failed earlier step only the always() steps may run
EXPECT_FAIL = {
    ("detach", "false"): {"RB"} | ALWAYS, ("detach", "true"): ALWAYS,
    ("wipe", "false"): {"TEAR", "RB"} | ALWAYS, ("wipe", "true"): ALWAYS,
    ("teardown", "false"): {"TEAR", "RB"} | ALWAYS, ("teardown", "true"): ALWAYS,
    ("destroy", "false"): {"RB"} | ALWAYS, ("destroy", "true"): {"RB"} | ALWAYS,
}

def eval_if(expr, phase, skip, conv, prev_ok):
    """Evaluate a step `if:` the way Actions does for the tiny grammar this job uses."""
    if expr is None:
        return prev_ok
    e = expr
    if not re.fullmatch(r"[\w\s'=!()&|.]+", e):
        raise ValueError("unsupported if grammar: " + expr)
    always = "always()" in e
    e = e.replace("&&", " and ").replace("||", " or ").replace("always()", "True")
    e = e.replace("env.RETIRE_PHASE", repr(phase)).replace("steps.conv.outputs.skip", repr(skip)).replace("steps.conv.outcome", repr(conv))
    val = bool(eval(e, {"__builtins__": {}}, {}))
    return val if always else (prev_ok and val)

def matrix(job):
    bad = []
    steps = job["steps"]
    for (phase, skip), want in EXPECT_OK.items():
        for ok, table in ((True, EXPECT_OK), (False, EXPECT_FAIL)):
            want = table[(phase, skip)]
            got = set()
            for s in steps:
                nm = s.get("name", "")
                k = next((v for f, v in SHORT.items() if f in nm), None)
                if k is None:
                    continue
                if k == "CONV" and not ok:
                    continue
                conv = "success"
                if eval_if(s.get("if"), phase, skip, conv, ok):
                    got.add(k)
            if got != want:
                bad.append("%s/skip=%s/%s: got %s want %s" % (phase, skip, "ok" if ok else "failed", sorted(got), sorted(want)))
    return bad

def pins(wf):
    """Return the ids of every pin that FAILS for this parsed workflow."""
    bad = []
    def pin(pid, ok):
        if not ok:
            bad.append(pid)
    job = wf["jobs"]["inngest_backstop_retire"]
    steps = job["steps"]
    def find(frag):
        m = [s for s in steps if frag in s.get("name", "")]
        return m[0] if len(m) == 1 else {"name": frag, "run": "", "_missing": True}
    def lines(step):
        out = []
        for l in str(step.get("run", "")).split("\n"):
            t = l.strip()
            if t and not t.startswith("#"):
                out.append(t)
        return out
    live, conv, pre = find("Live-store gate"), find("Convergence read"), find("Destroy precondition")
    unt, plan, apply_, poll = find("Read-only untargeted plan"), find("Terraform plan (phase)"), find("Terraform apply (phase)"), find("Wipe evidence")
    tear, back, valid = find("Teardown of the wipe host"), find("Read-back"), find("Validate inputs")
    prog = find("Progress comment")
    for s in (live, conv, pre, unt, plan, apply_, poll, tear, back, valid, prog):
        pin("steps_present", not s.get("_missing"))
    L = {k: lines(v) for k, v in dict(live=live, conv=conv, pre=pre, unt=unt, plan=plan, apply_=apply_, poll=poll, tear=tear, back=back, valid=valid, prog=prog).items()}
    # --- the exact `if:` table for ALL steps, the job-level key allow-list, and the run matrix
    got = [((s.get("name") or s.get("uses")), s.get("if")) for s in steps]
    pin("if_table", got == IF_TABLE)
    pin("job_keys", set(job.keys()) <= JOB_KEYS and job.get("runs-on") == "ubuntu-24.04" and job.get("timeout-minutes") == 45
        and job.get("if") == "github.event_name == 'workflow_dispatch' && inputs.apply_target == 'inngest-backstop-retire'"
        and set(job.get("env", {}).keys()) == {"RETIRE_PHASE", "EXPECTED_INNGEST_VOLUME_ID", "WIPE_RUN_ID", "RETIRE_ERASURE", "CLO_REF", "GH_TOKEN"})
    try:
        mx = matrix(job)
    except Exception as e:  # an unevaluable `if:` is itself a finding
        mx = [str(e)]
    pin("if_matrix", not mx)
    # --- exact `if:` strings (each one also named so a mutation reports its own pin)
    pin("if_destroy_precondition", pre.get("if") == "env.RETIRE_PHASE == 'destroy' && steps.conv.outputs.skip != 'true'")
    pin("if_live_store_not_teardown", live.get("if") == "env.RETIRE_PHASE != 'teardown'")
    pin("if_readback_always", back.get("if") == "always() && steps.conv.outcome == 'success' && (steps.conv.outputs.skip != 'true' || env.RETIRE_PHASE == 'destroy')")
    pin("if_teardown_always", str(tear.get("if", "")).startswith("always() && steps.conv.outcome == 'success' && steps.conv.outputs.skip != 'true'"))
    pin("if_poll_wipe_only", poll.get("if") == "env.RETIRE_PHASE == 'wipe' && steps.conv.outputs.skip != 'true'")
    pin("if_unt_plan_skip", unt.get("if") == "steps.conv.outputs.skip != 'true' && env.RETIRE_PHASE != 'teardown'")
    pin("if_apply_not_teardown", apply_.get("if") == "steps.conv.outputs.skip != 'true' && env.RETIRE_PHASE != 'teardown'")
    pin("apply_has_id", apply_.get("id") == "apply" and back.get("env", {}).get("APPLY") == "${{ steps.apply.outcome }}")
    # --- no continue-on-error anywhere except the advisory progress comment
    for s in steps:
        if "continue-on-error" in s and "Progress comment" not in s.get("name", ""):
            pin("no_continue_on_error", False)
    pin("progress_comment_advisory", prog.get("continue-on-error") is True)
    # --- every gate call site is a non-suppressing `if !` whose block exits 1 before `fi`
    sites = [("live", "inngest_backstop_live_store_gate"), ("pre", "inngest_backstop_destroy_precondition"),
             ("unt", "inngest_backstop_retire_gate"), ("plan", "inngest_backstop_retire_gate"), ("tear", "inngest_backstop_retire_gate")]
    for key, fn in sites:
        ls = L[key]
        idx = [i for i, l in enumerate(ls) if l.startswith("if ! " + fn + " ")]
        ok = len(idx) == 1
        if ok:
            blk = []
            for l in ls[idx[0]:]:
                blk.append(l)
                if l == "fi":
                    break
            ok = blk[-1] == "fi" and any(re.search(r"(^|[;\s])exit 1\b", b) for b in blk[1:-1]) and not any("|| true" in b or "exit 0" in b for b in blk)
        pin("gate_site_exits_%s_%s" % (key, fn), ok)
    # --- live-store gate (E-1: no in-flight count, no Hetzner read; the probe query error is printed)
    lv = L["live"]
    ljoin = " ".join(lv)
    pin("live_gate_call_exact", 'if ! inngest_backstop_live_store_gate --cutover-flag "$FLAG" --active-id "$ACT" --probe-file "${RUNNER_TEMP}/probe.tsv" --now "$(date -u +%s)"; then' in lv)
    pin("live_no_inflight_no_hetzner", not any(w in ljoin for w in ("inflight", "in_progress", "--server-id", "--luks-volume-file", "hz ", "hz.sh", "HCLOUD_TOKEN")))
    pin("live_probe_error_printed", any("probe-row query failed rc=$?" in l and "inngest_backstop_clean" in l for l in lv))
    # --- the poll
    pl = L["poll"]
    pjoin = " ".join(pl)
    pin("poll_ok_required", any(l.startswith('[[ "$OK" == 1 ]] || {') and "exit 1" in l for l in pl))
    pin("poll_deadline", 'DEADLINE=$(( $(date -u +%s) + 1200 )); (( DEADLINE <= JOB_START + 1800 )) || DEADLINE=$(( JOB_START + 1800 ))' in pl
        and 'while (( $(date -u +%s) < DEADLINE )); do' in pl)
    pin("poll_no_archive_hot_only", any("betterstack-query.sh" in l and "--no-archive" in l and "--since 1h" in l for l in pl))
    pin("poll_breaks_on_refusal", "grep -qF ' result=refused ' <<<\"$MSGS\" && break" in pl)
    pin("poll_query_error_printed", any("poll query failed rc=$?" in l for l in pl))
    pin("poll_gate_inputs", any(l.startswith('if EV="$(inngest_backstop_wipe_evidence_gate ') and '--nonce "$GITHUB_RUN_ID"' in l and '--rows-file "$NR"' in l
                                and '--after-epoch "$JOB_START"' in l and l.endswith("then OK=1; break; fi") for l in pl))
    pin("poll_nonce_rows_raw", any(l.startswith("inngest_backstop_wipe_nonce_rows ") and "--raw" in l and '> "$NR"' in l for l in pl))
    pin("poll_classifies", '[[ "$EV" == *reason=evidence_absent* || "$EV" == *reason=rows_unreadable* || "$EV" == *reason=not_wiped* ]] || break' in pl)
    pin("poll_output_sanitized", 'inngest_backstop_clean <<<"${MSGS:-none}"' in pjoin and 'inngest_backstop_clean 300 <<<"$EV"' in pjoin
        and '| inngest_backstop_clean 300)' in pjoin and 'inngest_backstop_clean 60 <<<' in pjoin)
    pin("poll_partial_zero_text", "PARTIALLY ZEROED" in pjoin and "zero_failed, readback_nonzero, sig_survived" in pjoin and "no started row, so nothing was written" in pjoin)
    pin("poll_hetzner_codes", "(HTTP ${HV})" in pjoin and "(HTTP ${HW})" in pjoin)
    # --- convergence
    cv = L["conv"]
    pin("conv_wipe_requires_detached", any(l.startswith('[[ "$VS" == null ]] || fail') for l in cv))
    wi = [i for i, l in enumerate(cv) if l == "wipe)"]; te = [i for i, l in enumerate(cv) if l == "teardown)"]
    gi = [i for i, l in enumerate(cv) if l.startswith('[[ "$VS" == null ]] || fail')]
    ni = [i for i, l in enumerate(cv) if l.startswith('[[ "$NWS" == 0 ]] || fail "a wipe host already exists')]
    pin("conv_wipe_guard_in_wipe_arm", bool(wi and te and gi and wi[0] < gi[0] < te[0]))
    pin("conv_wipe_host_before_detached", bool(wi and gi and ni and wi[0] < ni[0] < gi[0]))
    pin("conv_reads_the_pinned_volume", any(l.startswith('VC="$(hz "volumes/${EXPECTED_INNGEST_VOLUME_ID}" ') for l in cv))
    pin("conv_reconcile_exact_delta", '[[ ( "$DEL" == "$a" || "$DEL" == "$ALLOW" ) && -z "$ADD" ]] || fail "the refresh of ${a} changed state beyond it: dropped=\'${DEL}\' added=\'${ADD}\'"' in cv
        and any(l.startswith('DEL="$(comm -23 ') and "ADD=\"$(comm -13 " in l for l in cv))
    pin("conv_gone_queues_volume", '[[ "$VS" == gone ]] && has hcloud_volume.inngest_redis && RM+=(hcloud_volume.inngest_redis)' in cv
        and any(l.startswith('ALLOW="$a"; [[ "$VS" == gone && "$a" == hcloud_volume_attachment.inngest_redis ]]') for l in cv))
    pin("conv_detach_reads_live_server", any("hz 'servers?name=soleur-inngest'" in l for l in cv))
    pin("conv_state_list_in_variable", not any("terraform state list" in l and "|" in l.replace("||", "") for l in cv))
    pin("conv_orphan_host_message", any(l.startswith('if [[ "$NWS" != 0 ]] && ! has "$WSA"; then') for l in cv))
    pin("conv_reconcile_targets_literal", all(any(t in l for l in cv) for t in ("T=-target=hcloud_volume_attachment.inngest_redis ", "T=-target=hcloud_volume.inngest_redis ", "T=-target=hcloud_server.inngest_backstop_wipe ", "T=-target=hcloud_volume_attachment.inngest_backstop_wipe ")))
    pin("conv_destroy_attached_message", any("is still attached (server ${VS})" in l for l in cv))
    # --- destroy precondition
    pr = L["pre"]
    pin("pre_provenance", any(l.startswith("if jq -e '") and '.path == ".github/workflows/apply-web-platform-infra.yml"' in l and '.head_branch == "main"' in l
                              and '.event == "workflow_dispatch"' in l and '.status == "completed"' in l for l in pr))
    pin("pre_archive_kept", any("betterstack-query.sh" in l and "--since 14d" in l and "--no-archive" not in l for l in pr))
    pin("pre_hetzner_actions_read", any('/actions?per_page=50&sort=id%3Adesc"' in l for l in pr))
    pin("pre_call_inputs", all(any(a in l for l in pr) for a in ("--clo-comment-file", "--actions-file", "--live-server-id", "--after-epoch")))
    pin("pre_actor_arg", any(l.startswith("if ! inngest_backstop_destroy_precondition ") and '--actor "$GITHUB_ACTOR"' in l for l in pr))
    pin("pre_clo_strict_pattern", any("https://github\\.com/jikig-ai/soleur/issues/8285#issuecomment-([0-9]+)$" in l for l in pr) and any("issues/comments/${BASH_REMATCH[1]}" in l for l in pr))
    pin("pre_no_http_code_path", not any("clo-ref-http-code" in l or "%{http_code}" in l for l in pr))
    pin("pre_query_errors_visible", any(l.startswith("rd() {") and 'answered ${c}' in l for l in pr)
        and any("Better Stack query failed rc=$?" in l and "inngest_backstop_clean" in l for l in pr)
        and any("could not be read, or is not a completed workflow_dispatch run" in l for l in pr))
    # --- plan / apply
    pp = L["plan"]
    pin("plan_nonce_is_run_id", any('-var="inngest_backstop_wipe_nonce=${GITHUB_RUN_ID}"' in l and "-var='inngest_backstop_wipe_enabled=true'" in l for l in pp))
    pin("plan_exact_targets_wipe", any("-target=hcloud_server.inngest_backstop_wipe -target=hcloud_volume_attachment.inngest_backstop_wipe" in l for l in pp))
    ap = L["apply_"]
    pin("apply_touched_zero", any(l.startswith('[[ "$TOUCHED" == "0" ]] || {') and "exit 1" in l for l in ap) and any(l.startswith("for ADDR in ") for l in ap)
        and any('any(. == "create" or . == "update" or . == "delete" or . == "forget")' in l for l in ap))
    pin("apply_exact_command", 'if ! doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -no-color -input=false tfplan; then' in ap)
    pin("apply_touched_exact", """TOUCHED=$(jq --arg a "$ADDR" '[.resource_changes[]? | select(.address == $a) | select(.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"))] | length' tfplan.json)""" in ap
        and '[[ "$TOUCHED" == "0" ]] || { echo "::error::${ADDR} shows ${TOUCHED} action(s) in the applied plan; the host and live store must be untouched. Failing hard."; exit 1; }' in ap)
    # --- teardown
    td = L["tear"]
    pin("teardown_detailed_exitcode", any("terraform plan" in l and "-detailed-exitcode" in l for l in td))
    pin("teardown_rc_zero_is_noop", '[[ $rc -ne 0 ]] || { echo "no wipe host or attachment exists; nothing to tear down."; exit 0; }' in td)
    pin("teardown_rc_two_only", any(l.startswith("[[ $rc -eq 2 ]] || {") and "exit 1" in l for l in td))
    pin("teardown_gate_enabled_false", any("-var='inngest_backstop_wipe_enabled=false'" in l for l in td))
    pin("teardown_apply_exact", '"${D[@]}" terraform apply -no-color -input=false tfplan-td || { echo "::error::teardown apply failed; re-dispatch phase=teardown."; exit 1; }' in td)
    # --- read-back and progress comment
    bk = L["back"]
    pin("rb_destroy_not_applied", any(l.startswith('if [[ "$VC" != 404 && "$APPLY" == skipped ]]; then note "destroy not applied') and l.endswith("exit 0; fi") for l in bk))
    pg = L["prog"]
    pin("prog_d4_conditional", any(l.startswith('D4=""; [[ "$RETIRE_PHASE" == detach || ( "$RETIRE_PHASE" == wipe && "$JOB_STATUS" != success ) ]] && D4=') for l in pg)
        and any('EXP="OVERDUE by ' in l for l in pg))
    # --- secrets / hygiene
    v = " ".join(L["valid"])
    pin("hz_token_on_stdin", "curl -q -K - " in v and "-H " not in v)
    pin("hz_default_000", '|| true)"; echo "${c:-000}"; }' in v)
    pin("doppler_token_not_on_argv", any(l.startswith('dget() { DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get') and "--token" not in l for l in lv))
    ui = [i for i, l in enumerate(lv) if l.startswith("unset INNGEST_PROBE_ROW_JQ ") and "INNGEST_PROBE_ROW_LIB" in l.split()]
    ai = [i for i, l in enumerate(lv) if l.startswith("_ipr_lib=")]
    pin("probe_lib_not_overridable", len(ui) == 1 and len(ai) == 1 and ui[0] < ai[0])
    allbody = "\n".join("\n".join(v2) for v2 in L.values())
    pin("retired_id_literal_once", sum(1 for l in allbody.split("\n") if "106261946" in l) == 1 and any(l.startswith('[[ "$EXPECTED_INNGEST_VOLUME_ID" == "106261946" ]]') for l in L["valid"]))
    pin("live_id_literal_absent", "106903269" not in allbody)
    return bad

def mutations():
    # (label, old, new, expected pin id)
    return [
        ("destroy-precondition if: inverted", "if: env.RETIRE_PHASE == 'destroy' && steps.conv.outputs.skip != 'true'", "if: env.RETIRE_PHASE != 'destroy' && steps.conv.outputs.skip != 'true'", "if_destroy_precondition"),
        ("destroy-precondition if: dropped", "        if: env.RETIRE_PHASE == 'destroy' && steps.conv.outputs.skip != 'true'\n", "", "if_destroy_precondition"),
        ("live-store gate also runs for teardown", "if: env.RETIRE_PHASE != 'teardown'\n        env:\n          BETTERSTACK_QUERY_HOST", "if: always()\n        env:\n          BETTERSTACK_QUERY_HOST", "if_live_store_not_teardown"),
        ("read-back lost always()", "if: always() && steps.conv.outcome == 'success' && (steps.conv.outputs.skip != 'true' || env.RETIRE_PHASE == 'destroy')", "if: steps.conv.outcome == 'success' && (steps.conv.outputs.skip != 'true' || env.RETIRE_PHASE == 'destroy')", "if_readback_always"),
        ("read-back no longer runs on the destroy 404 shortcut", "(steps.conv.outputs.skip != 'true' || env.RETIRE_PHASE == 'destroy')", "steps.conv.outputs.skip != 'true'", "if_matrix"),
        ("untargeted plan runs for teardown again", "      - name: Read-only untargeted plan (host and LUKS pair must be present no-ops)\n        if: steps.conv.outputs.skip != 'true' && env.RETIRE_PHASE != 'teardown'", "      - name: Read-only untargeted plan (host and LUKS pair must be present no-ops)\n        if: steps.conv.outputs.skip != 'true'", "if_unt_plan_skip"),
        ("apply runs for teardown", "      - name: Terraform apply (phase)\n        id: apply\n        if: steps.conv.outputs.skip != 'true' && env.RETIRE_PHASE != 'teardown'", "      - name: Terraform apply (phase)\n        id: apply\n        if: steps.conv.outputs.skip != 'true'", "if_apply_not_teardown"),
        ("teardown lost always()", "if: always() && steps.conv.outcome == 'success' && steps.conv.outputs.skip != 'true' && (env.RETIRE_PHASE == 'wipe'", "if: steps.conv.outcome == 'success' && steps.conv.outputs.skip != 'true' && (env.RETIRE_PHASE == 'wipe'", "if_teardown_always"),
        ("poll runs for another phase", "if: env.RETIRE_PHASE == 'wipe' && steps.conv.outputs.skip != 'true'", "if: env.RETIRE_PHASE != 'destroy' && steps.conv.outputs.skip != 'true'", "if_poll_wipe_only"),
        ("progress comment no longer always()", "      - name: \"Progress comment on #8285 (success or failure)\"\n        if: always()", "      - name: \"Progress comment on #8285 (success or failure)\"\n        if: success()", "if_table"),
        ("job-level continue-on-error", "    runs-on: ubuntu-24.04\n    timeout-minutes: 45\n    environment: inngest-cutover\n", "    runs-on: ubuntu-24.04\n    timeout-minutes: 45\n    continue-on-error: true\n    environment: inngest-cutover\n", "job_keys"),
        ("job-level env gains a key", "      GH_TOKEN: ${{ github.token }}\n    steps:\n      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1\n\n      - uses: hashicorp/setup-terraform", "      GH_TOKEN: ${{ github.token }}\n      EXTRA: x\n    steps:\n      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1\n\n      - uses: hashicorp/setup-terraform", "job_keys"),
        ("apply step loses its id", "      - name: Terraform apply (phase)\n        id: apply\n", "      - name: Terraform apply (phase)\n", "apply_has_id"),
        ("continue-on-error on the destroy precondition", "      - name: Destroy precondition (Guard 4, before any plan)\n", "      - name: Destroy precondition (Guard 4, before any plan)\n        continue-on-error: true\n", "no_continue_on_error"),
        ("continue-on-error on the live-store gate", "      - name: Live-store gate (plan 2.0, in front of detach, wipe and destroy; NOT teardown)\n", "      - name: Live-store gate (plan 2.0, in front of detach, wipe and destroy; NOT teardown)\n        continue-on-error: true\n", "no_continue_on_error"),
        ("destroy precondition: exit 1 dropped", "(D4); read reason=.\"; exit 1", "(D4); read reason=.\"", "gate_site_exits_pre_inngest_backstop_destroy_precondition"),
        ("destroy precondition: call without the negation", "          if ! inngest_backstop_destroy_precondition ", "          if inngest_backstop_destroy_precondition ", "gate_site_exits_pre_inngest_backstop_destroy_precondition"),
        ("destroy precondition: actor dropped", " --actor \"$GITHUB_ACTOR\"", "", "pre_actor_arg"),
        ("live-store gate: exit 1 dropped", "not provably serving.\"; exit 1", "not provably serving.\"", "gate_site_exits_live_inngest_backstop_live_store_gate"),
        ("live-store gate: the in-flight count is back", "--probe-file \"${RUNNER_TEMP}/probe.tsv\" --now \"$(date -u +%s)\"; then", "--probe-file \"${RUNNER_TEMP}/probe.tsv\" --now \"$(date -u +%s)\" --inflight-runs 0; then", "live_gate_call_exact"),
        ("live-store gate: the probe query error swallowed", "2> \"${RUNNER_TEMP}/probe.err\" \\\n            || { echo \"::error::probe-row query failed rc=$?: $(head -c 300 \"${RUNNER_TEMP}/probe.err\" | inngest_backstop_clean 300)\"; exit 1; }", "2>/dev/null \\\n            || { echo \"::error::probe-row query failed.\"; exit 1; }", "live_probe_error_printed"),
        ("targeted gate: exit 1 replaced by exit 0", "NO [ack-destroy] bypass.\"\n            grep -E 'will be (created|destroyed|updated)|must be replaced|Plan:' tfplan.txt | head -30 >&2\n            exit 1", "NO [ack-destroy] bypass.\"\n            grep -E 'will be (created|destroyed|updated)|must be replaced|Plan:' tfplan.txt | head -30 >&2\n            exit 0", "gate_site_exits_plan_inngest_backstop_retire_gate"),
        ("untargeted gate: exit 1 dropped", "head -30 >&2\n            exit 1\n          fi\n\n      - name: Terraform plan (phase)", "head -30 >&2\n          fi\n\n      - name: Terraform plan (phase)", "gate_site_exits_unt_inngest_backstop_retire_gate"),
        ("teardown gate: exit 1 dropped", "(only deletes of the two wipe addresses are legal).\"; exit 1", "(only deletes of the two wipe addresses are legal).\"", "gate_site_exits_tear_inngest_backstop_retire_gate"),
        ("poll: the OK==1 requirement removed", "[[ \"$OK\" == 1 ]] || { echo \"::error::no wiped row", "[[ \"$OK\" == 1 ]] || true; { echo \"::error::no wiped row", "poll_ok_required"),
        ("poll: back to a fixed 24-iteration loop", "while (( $(date -u +%s) < DEADLINE )); do", "for _ in $(seq 1 24); do", "poll_deadline"),
        ("poll: the job-timeout cap dropped", "(( DEADLINE <= JOB_START + 1800 )) || DEADLINE=$(( JOB_START + 1800 ))", ":", "poll_deadline"),
        ("poll: archive query again", "--since 1h --no-archive --grep SOLEUR_INNGEST_BACKSTOP_WIPE", "--since 2h --grep SOLEUR_INNGEST_BACKSTOP_WIPE", "poll_no_archive_hot_only"),
        ("poll: refusal no longer ends it", "grep -qF ' result=refused ' <<<\"$MSGS\" && break", "grep -qF ' result=refused ' <<<\"$MSGS\" || true", "poll_breaks_on_refusal"),
        ("poll: query errors swallowed again", "|| { echo \"poll query failed rc=$?: $(head -c 300 \"$ERR\" | inngest_backstop_clean 300)\"; : > \"$ROWS\"; }", "|| : > \"$ROWS\"", "poll_query_error_printed"),
        ("poll: a genuine rejection no longer ends it", "[[ \"$EV\" == *reason=evidence_absent* || \"$EV\" == *reason=rows_unreadable* || \"$EV\" == *reason=not_wiped* ]] || break", ":", "poll_classifies"),
        ("poll: the funnel reads the pinned rows only", " --raw > \"$NR\"", " > \"$NR\"", "poll_nonce_rows_raw"),
        ("poll: rows printed unsanitized", "$(inngest_backstop_clean <<<\"${MSGS:-none}\")", "${MSGS:-none}", "poll_output_sanitized"),
        ("poll: the partial-zero warning removed", "the device may be PARTIALLY ZEROED", "the device is fine", "poll_partial_zero_text"),
        ("poll: the Hetzner HTTP codes dropped", " (HTTP ${HV}) wipe hosts", " wipe hosts", "poll_hetzner_codes"),
        ("conv: wipe no longer requires a detached volume", "[[ \"$VS\" == null ]] || fail \"volume ${EXPECTED_INNGEST_VOLUME_ID} must be detached", "[[ \"$VS\" == null ]] || true; : \"volume ${EXPECTED_INNGEST_VOLUME_ID} must be detached", "conv_wipe_requires_detached"),
        ("conv: the volume-attached check runs before the leaked-host check", "              [[ \"$NWS\" == 0 ]] || fail \"a wipe host already exists: dispatch phase=teardown first\"\n              [[ \"$VS\" == null ]] || fail \"volume ${EXPECTED_INNGEST_VOLUME_ID} must be detached (server null; state=${VS}) -- run phase=detach first\"\n", "              [[ \"$VS\" == null ]] || fail \"volume ${EXPECTED_INNGEST_VOLUME_ID} must be detached (server null; state=${VS}) -- run phase=detach first\"\n              [[ \"$NWS\" == 0 ]] || fail \"a wipe host already exists: dispatch phase=teardown first\"\n", "conv_wipe_host_before_detached"),
        ("conv: reads another volume", "VC=\"$(hz \"volumes/${EXPECTED_INNGEST_VOLUME_ID}\" \"${RUNNER_TEMP}/vol.json\")\"", "VC=\"$(hz \"volumes/106903269\" \"${RUNNER_TEMP}/vol.json\")\"", "conv_reads_the_pinned_volume"),
        ("conv: refresh delta no longer exact", "[[ ( \"$DEL\" == \"$a\" || \"$DEL\" == \"$ALLOW\" ) && -z \"$ADD\" ]] || fail", "[[ \"$DEL\" == \"$a\" ]] || fail", "conv_reconcile_exact_delta"),
        ("conv: the gone volume is no longer queued", "[[ \"$VS\" == gone ]] && has hcloud_volume.inngest_redis && RM+=(hcloud_volume.inngest_redis)", ":", "conv_gone_queues_volume"),
        ("conv: detach no longer reads the live server", "SC=\"$(hz 'servers?name=soleur-inngest' \"${RUNNER_TEMP}/srv.json\")\"", "SC=200", "conv_detach_reads_live_server"),
        ("conv: state list piped into grep -q (SIGPIPE fail-open)", "            ST1=\"$(terraform state list 2>/dev/null)\" || fail \"cannot list terraform state after the refresh\"", "            terraform state list 2>/dev/null | grep -qFx -- \"$a\" && fail \"still in state\"\n            ST1=\"$(terraform state list 2>/dev/null)\" || fail \"cannot list terraform state after the refresh\"", "conv_state_list_in_variable"),
        ("conv: leaked-host recovery message removed", "if [[ \"$NWS\" != 0 ]] && ! has \"$WSA\"; then", "if false; then", "conv_orphan_host_message"),
        ("conv: a reconcile target made non-literal", "T=-target=hcloud_volume.inngest_redis ;;", "T=-target=$a ;;", "conv_reconcile_targets_literal"),
        ("pre: .head_branch == \"main\" dropped", "and .head_branch == \"main\" and .event", "and .event", "pre_provenance"),
        ("pre: archive dropped from the destroy query", "--since 14d --grep SOLEUR_INNGEST_BACKSTOP_WIPE --limit 2000", "--since 14d --no-archive --grep SOLEUR_INNGEST_BACKSTOP_WIPE --limit 2000", "pre_archive_kept"),
        ("pre: Hetzner action history not read", "/actions?per_page=50&sort=id%3Adesc\"", "/actions\"", "pre_hetzner_actions_read"),
        ("pre: actions file not handed to the gate", "--actions-file \"$P/acts.json\" ", "", "pre_call_inputs"),
        ("pre: CLO ref accepts any https URL again", "https://github\\.com/jikig-ai/soleur/issues/8285#issuecomment-([0-9]+)$", "https://[^[:space:]]+$", "pre_clo_strict_pattern"),
        ("pre: the Hetzner HTTP code no longer printed", "echo \"Hetzner GET $1 answered ${c}\"; ", "", "pre_query_errors_visible"),
        ("plan: nonce no longer the run id", "-var=\"inngest_backstop_wipe_nonce=${GITHUB_RUN_ID}\"", "-var=\"inngest_backstop_wipe_nonce=1\"", "plan_nonce_is_run_id"),
        ("apply: TOUCHED==0 check removed", "[[ \"$TOUCHED\" == \"0\" ]] || {", "[[ \"$TOUCHED\" == \"0\" ]] || true; {", "apply_touched_zero"),
        ("apply: a verb dropped from the TOUCHED filter", "any(. == \"create\" or . == \"update\" or . == \"delete\" or . == \"forget\")", "any(. == \"create\" or . == \"delete\")", "apply_touched_zero"),
        ("apply: the TOUCHED jq reads another file", "| length' tfplan.json)", "| length' tfplan-all.json)", "apply_touched_exact"),
        ("apply: applies without the saved plan", "terraform apply -no-color -input=false tfplan; then", "terraform apply -no-color -input=false; then", "apply_exact_command"),
        ("teardown: applies without the saved plan", "terraform apply -no-color -input=false tfplan-td ||", "terraform apply -no-color -input=false ||", "teardown_apply_exact"),
        ("teardown: rc 0 no longer a no-op", "nothing to tear down.\"; exit 0; }", "nothing to tear down.\"; exit 1; }", "teardown_rc_zero_is_noop"),
        ("teardown: rc other than 2 no longer fatal", "[[ $rc -eq 2 ]] || { echo \"::error::teardown plan failed", "[[ $rc -eq 2 ]] || true; { echo \"::error::teardown plan failed", "teardown_rc_two_only"),
        ("teardown: -detailed-exitcode dropped", "-detailed-exitcode -out=tfplan-td", "-out=tfplan-td", "teardown_detailed_exitcode"),
        ("read-back: a refused destroy is reported as a failed one again", "if [[ \"$VC\" != 404 && \"$APPLY\" == skipped ]]; then note", "if false; then note", "rb_destroy_not_applied"),
        ("progress: the D4 sentence unconditional", "D4=\"\"; [[ \"$RETIRE_PHASE\" == detach ||", "D4=\"x\"; [[ \"$RETIRE_PHASE\" == detach ||", "prog_d4_conditional"),
        ("hz: token on argv again", "hz() { local c; c=\"$(printf 'header = \"Authorization: Bearer %s\"\\n' \"$HCLOUD_TOKEN\" | curl -q -K - -sS --max-time 20", "hz() { local c; c=\"$(curl -sS --max-time 20 -H \"Authorization: Bearer ${HCLOUD_TOKEN}\"", "hz_token_on_stdin"),
        ("hz: the empty answer is no longer 000", "echo \"${c:-000}\"; }", "echo \"$c\"; }", "hz_default_000"),
        ("dget: Doppler token on argv again", "dget() { DOPPLER_TOKEN=\"$DOPPLER_TOKEN_INNGEST_ARM\" doppler secrets get \"$1\" --project soleur-inngest --config prd --plain 2>/dev/null", "dget() { doppler secrets get \"$1\" --project soleur-inngest --config prd --plain --token \"$DOPPLER_TOKEN_INNGEST_ARM\" 2>/dev/null", "doppler_token_not_on_argv"),
        ("probe lib overridable again", "unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_ROW_LIB INNGEST_PROBE_EMITTER", "unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_EMITTER", "probe_lib_not_overridable"),
        ("a second retired-id literal reappears", "VC=\"$(hz \"volumes/${EXPECTED_INNGEST_VOLUME_ID}\" \"${RUNNER_TEMP}/vol-rb.json\")\"", "VC=\"$(hz \"volumes/106261946\" \"${RUNNER_TEMP}/vol-rb.json\")\"", "retired_id_literal_once"),
        ("the live-id literal reappears", "note \"server volumes == [${_IBRG_LIVE_ID}]\"", "note \"server volumes == [106903269]\"", "live_id_literal_absent"),
    ]

def main():
    path, libpath, xd = sys.argv[1:4]
    text = open(path).read()
    wf = load(text)
    job = wf["jobs"].get("inngest_backstop_retire")
    out = {"job": bool(job)}
    os.makedirs(os.path.join(xd, "s"), exist_ok=True)
    if job:
        steps = job["steps"]
        out["names"] = [s.get("name", "") for s in steps]
        out["env"] = job.get("environment")
        out["conc"] = job.get("concurrency")
        out["if"] = job.get("if")
        out["wfconc"] = wf.get("concurrency")
        out["perm"] = job.get("permissions")
        out["bodies"] = {s.get("name", ""): s.get("run", "") for s in steps}
        out["ifs"] = {s.get("name", ""): s.get("if", "") for s in steps}
        on = wf[True] if True in wf else wf["on"]
        inp = on["workflow_dispatch"]["inputs"]
        out["opts"] = inp["apply_target"]["options"]
        out["inputs"] = sorted(inp.keys())
        out["clo_desc"] = inp["clo_attestation_ref"]["description"]
        with open(os.path.join(xd, "names.tsv"), "w") as f:
            for i, s in enumerate(steps):
                f.write("%d\t%s\n" % (i, s.get("name", "")))
                if "run" in s:
                    with open(os.path.join(xd, "s", "%d.sh" % i), "w") as g:
                        g.write(s["run"])
    out["old_job_present"] = "inngest_volume_recut" in wf["jobs"]
    json.dump(out, open(os.path.join(xd, "facts.json"), "w"))
    # the post-apply untouched loop == the gate's never-acted-on set
    lib = open(libpath).read()
    body = [s for s in wf["jobs"]["inngest_backstop_retire"]["steps"] if s.get("name") == "Terraform apply (phase)"][0]["run"]
    addrs = set(re.findall(r"'([^']+)'", re.search(r"for ADDR in (.*?); do", body).group(1)))
    def lst(name):
        m = re.search(r"def " + name + r":\s*\[(.*?)\];", lib, re.S)
        return set(x.replace('\\"', '"') for x in re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)))
    want = lst("live_addr") | lst("named_live") | {"hcloud_server.inngest"}
    print("LOOP SAME %d" % len(want) if addrs == want else "LOOP DIFF only-in-workflow=%s only-in-lib=%s" % (sorted(addrs - want), sorted(want - addrs)))
    base = pins(wf)
    print("CONTROL " + ("ok" if not base else "FAIL " + ",".join(base)))
    if base and "if_matrix" in base:
        for m in matrix(wf["jobs"]["inngest_backstop_retire"]):
            print("MATRIX " + m)
    muts = mutations()
    print("MUTCOUNT %d" % len(muts))
    a = text.index("\n  inngest_backstop_retire:\n"); b = text.index("\n  registry_host_replace:\n")
    jobtext = text[a:b]
    for label, old, new, want_pin in muts:
        n = jobtext.count(old)
        if n != 1:
            print("MUT NOLAND [%s] occurrences=%d" % (label, n))
            continue
        got = pins(load("jobs:" + jobtext.replace(old, new)))
        print("MUT %s [%s] -> %s" % ("ok" if want_pin in got else "NOTRED", label, ",".join(got) or "none"))

if __name__ == "__main__":
    main()
EXTRACTPY
EXOUT="$(python3 -I "$EXTRACT_PY" "$WF" "$GATE" "$XD" 2>&1)"
WF_FACTS="$(cat "$XD/facts.json" 2>/dev/null)"
if ! printf '%s' "$WF_FACTS" | jq -e . >/dev/null 2>&1; then
  fail "workflow YAML facts could not be extracted" "" "$WF_FACTS"
  WF_FACTS='{"job":false}'
fi
wf() { printf '%s' "$WF_FACTS" | jq -r "$1" 2>/dev/null; }
if [[ "$(wf '.job')" == "true" ]]; then pass; else fail "Wiring: job inngest_backstop_retire is missing from the workflow"; fi
if [[ "$(wf '.old_job_present')" == "false" ]]; then pass; else fail "Wiring: the old inngest_volume_recut job survives"; fi
if [[ "$(wf '.opts | index("inngest-backstop-retire") != null and index("inngest-volume-recut") == null')" == "true" ]]; then pass; else fail "Wiring: apply_target options must list inngest-backstop-retire and not inngest-volume-recut"; fi
if [[ "$(wf '.if | contains("inngest-backstop-retire")')" == "true" ]]; then pass; else fail "Wiring: the job's if: does not select apply_target == inngest-backstop-retire"; fi
if [[ "$(wf '.env')" == "inngest-cutover" ]]; then pass; else fail "Wiring: environment must stay the reviewer-gated inngest-cutover" "" "$(wf '.env')"; fi
if [[ "$(wf '.conc.group')" == "deploy-inngest-restart" && "$(wf '.conc["cancel-in-progress"]')" == "false" ]]; then pass; else fail "Wiring: job concurrency must be deploy-inngest-restart, not cancelling"; fi
# The root's serializer: the state backend has use_lockfile=false. A workflow-level group is the ONLY
# thing serializing against the merge apply; a job cannot carry two groups, so assert the workflow's.
if [[ "$(wf '.wfconc.group')" == "terraform-apply-web-platform-host" && "$(wf '.wfconc["cancel-in-progress"]')" == "false" ]]; then pass; else fail "Wiring: the workflow-level group terraform-apply-web-platform-host must govern this job and not cancel in progress"; fi
if [[ "$(wf '.perm.issues')" == "write" ]]; then pass; else fail "Wiring: the #8285 progress comment needs the job to carry permissions.issues: write"; fi
idx() { printf '%s' "$WF_FACTS" | jq -r --arg p "$1" '[.names | to_entries[] | select(.value | test($p)) | .key] | first // -1'; }
I_LIVE="$(idx 'Live-store gate')"; I_CONV="$(idx 'Convergence')"; I_PRE="$(idx 'Destroy precondition')"; I_UNT="$(idx 'untargeted')"
I_PLAN="$(idx 'Terraform plan \(phase')"; I_APPLY="$(idx 'Terraform apply \(phase')"; I_ASSERT="$(idx 'reviewer set')"; I_VALID="$(idx 'Validate')"
I_WIPE="$(idx 'Wipe evidence')"; I_TEAR="$(idx 'Teardown')"; I_COMMENT="$(idx '#8285')"
for n in I_LIVE I_CONV I_PRE I_UNT I_PLAN I_APPLY I_ASSERT I_VALID I_WIPE I_TEAR I_COMMENT; do
  [[ "${!n}" =~ ^[0-9]+$ && "${!n}" -ge 0 ]] && pass || fail "Wiring: step for ${n} not found in the job"
done
# Guard 4 row 5: the precondition runs BEFORE any plan or apply; the live-store gate runs before everything that reads terraform.
if [[ "$I_PRE" -ge 0 && "$I_PRE" -lt "$I_UNT" && "$I_UNT" -lt "$I_PLAN" && "$I_PLAN" -lt "$I_APPLY" ]]; then pass; else fail "Wiring (G4 row 5): order must be destroy precondition < untargeted plan < targeted plan < apply" "" "pre=$I_PRE unt=$I_UNT plan=$I_PLAN apply=$I_APPLY"; fi
if [[ "$I_ASSERT" -ge 0 && "$I_ASSERT" -lt "$I_LIVE" && "$I_VALID" -lt "$I_LIVE" && "$I_LIVE" -lt "$I_CONV" && "$I_CONV" -le "$I_PRE" ]]; then pass; else fail "Wiring: order must be validate, reviewer assert < live-store gate < convergence read <= destroy precondition" "" "valid=$I_VALID assert=$I_ASSERT live=$I_LIVE conv=$I_CONV pre=$I_PRE"; fi
if [[ "$I_WIPE" -gt "$I_APPLY" && "$I_TEAR" -gt "$I_WIPE" ]]; then pass; else fail "Wiring: wipe evidence poll follows the apply and the teardown follows the poll"; fi
if [[ "$(wf '.ifs["'"$(wf '.names['"$I_TEAR"']')"'"] | contains("always()")')" == "true" ]]; then pass; else fail "Wiring: the teardown step must run under if: always()"; fi
if [[ "$(wf '.ifs["'"$(wf '.names['"$I_COMMENT"']')"'"] | contains("always()")')" == "true" ]]; then pass; else fail "Wiring: the #8285 progress comment must run under if: always()"; fi
if [[ "$(wf '.ifs["'"$(wf '.names['"$I_PRE"']')"'"] | contains("destroy")')" == "true" ]]; then pass; else fail "Wiring: the destroy precondition must be conditioned on phase == destroy"; fi
# Every gate call is non-suppressing and the pin reaches it (a pin that never arrives disables the id check in production).
BODIES="$(wf '.bodies | to_entries[] | .value')"
n_calls="$(grep -cE '^[[:space:]]*if ! inngest_backstop_retire_gate ' <<<"$BODIES" || true)"
if [[ "$n_calls" -ge 3 ]]; then pass; else fail "Wiring: expected >=3 'if ! inngest_backstop_retire_gate' calls (untargeted, targeted, teardown); found ${n_calls}"; fi
if grep -E '^[[:space:]]*if ! inngest_backstop_retire_gate ' <<<"$BODIES" | grep -vqE '"\$\{?EXPECTED_INNGEST_VOLUME_ID'; then fail "Wiring: a gate call does not pass EXPECTED_INNGEST_VOLUME_ID as the pin"; else pass; fi
for fn in inngest_backstop_live_store_gate inngest_backstop_destroy_precondition; do
  if grep -qE "^[[:space:]]*if ! ${fn} " <<<"$BODIES"; then pass; else fail "Wiring: ${fn} is not called under a non-suppressing 'if !'"; fi
done
if grep -qF 'tests/scripts/lib/inngest-backstop-retire-gate.sh' <<<"$BODIES"; then pass; else fail "Wiring: the workflow does not source the gate lib"; fi
# No -destroy flag and no closing keyword in the new job's text; no shell-injection of inputs into run bodies.
if grep -qE '(^|[[:space:]])-destroy([[:space:]=]|$)' <<<"$BODIES"; then fail "Wiring: a -destroy flag is present (orphans are destroyed by -target only)"; else pass; fi
if grep -qiE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#(8285|6894)' <<<"$BODIES"; then fail "Wiring: a closing keyword next to #8285/#6894"; else pass; fi
if grep -q '\${{' <<<"$BODIES"; then fail "Wiring: a \${{ }} expression sits inside a run: body (route inputs through env:)"; else pass; fi
# The retired addresses leave the other two dispatch jobs' target sets.
for j in inngest_host inngest_host_replace; do
  if awk -v j="$j" '$0 ~ "^  "j":" {on=1; next} on && /^  [a-z_]+:$/ {on=0} on' "$WF" | grep -qE "(-target|-replace)='hcloud_volume(_attachment)?\.inngest_redis'"; then
    fail "Wiring: ${j} still targets a retired address"
  else pass; fi
done

# ══ THE WORKFLOW'S run: BODIES (W3, D-A..D-E, W2-13) ═══════════════════════════════
# Each step's `run:` is pinned as ANCHORED, comment-stripped lines, and every step's `if:` as ONE exact table (plus an
# allow-list of job-level keys and an evaluated run matrix: which steps run per phase, with and without skip, with and
# without an earlier failure). The extractor ALSO carries a mutation table: every pin is mutated out of a copy of the
# real job and must go RED (a pin that its mutation does not trip is decorative). CONTROL is the real workflow.
if [[ "$(grep -m1 '^CONTROL' <<<"$EXOUT")" == "CONTROL ok" ]]; then pass; else fail "Pins: the real workflow trips a pin" "" "$(grep -E '^(CONTROL|MATRIX|Traceback)|Error' <<<"$EXOUT" | head -6)"; fi
n_mut=0; n_ok=0
while IFS= read -r l; do
  [[ "$l" == MUT\ * ]] || continue
  n_mut=$((n_mut + 1))
  if [[ "$l" == "MUT ok "* ]]; then n_ok=$((n_ok + 1)); pass; else fail "Pins: a mutation was not caught (${l%% ->*})" "" "$l"; fi
done <<<"$EXOUT"
MUTCOUNT="$(sed -n 's/^MUTCOUNT \([0-9]*\)$/\1/p' <<<"$EXOUT")"
if [[ "$MUTCOUNT" =~ ^[0-9]+$ && "$n_mut" -eq "$MUTCOUNT" && "$MUTCOUNT" -eq 67 ]]; then pass; else fail "Pins: ${n_mut} mutation rows ran, the table holds '${MUTCOUNT}', expected exactly 67 (a row was deleted, or one did not land)"; fi

# Replicated literals and lists agree across the lib, the workflow and the Terraform (W8).
TF="${REPO_ROOT}/apps/web-platform/infra/inngest-backstop-wipe.tf"
YML="${REPO_ROOT}/apps/web-platform/infra/cloud-init-inngest-backstop-wipe.yml"
tf_name="$(sed -n 's/^  name  *= "\(soleur-inngest-backstop-wipe\)"$/\1/p' "$TF")"
tf_role="$(sed -n 's/^    role  *= "\(inngest-backstop-wipe\)"$/\1/p' "$TF")"
if [[ "$tf_name" == "$_IBRG_WIPE_HOST" ]]; then pass; else fail "Parity: the Terraform server name ('${tf_name}') != the funnel's pinned emitter host ('${_IBRG_WIPE_HOST}')"; fi
sel_all="$(sed -n '/^  inngest_backstop_retire:/,/^  registry_host_replace:/p' "$WF" | grep -o "label_selector=role%3D[A-Za-z0-9-]*" | sort -u)"
sel_n="$(sed -n '/^  inngest_backstop_retire:/,/^  registry_host_replace:/p' "$WF" | grep -c "label_selector=role%3D" || true)"
if [[ -n "$tf_role" && "$sel_all" == "label_selector=role%3D${tf_role}" ]]; then pass; else fail "Parity: the job's Hetzner label selector(s) (${sel_all//$'\n'/ }) != the Terraform label role=${tf_role}"; fi
if [[ "$sel_n" -ge 3 ]]; then pass; else fail "Parity: expected >=3 label-selector reads in the workflow, found ${sel_n}"; fi
if grep -qF "\\\"shipper\\\":\\\"${_IBRG_WIPE_SHIPPER}\\\"" "$YML"; then pass; else fail "Parity: the cloud-init payload's shipper literal != the funnel's pinned shipper ${_IBRG_WIPE_SHIPPER}"; fi
if [[ "$(wf '.bodies["Validate inputs (typo-guards, NOT the authorization)"]')" == *"== \"${_IBRG_RETIRED_ID}\" ]]"* ]]; then pass; else fail "Parity: the workflow's id-pin literal != the lib's retired id ${_IBRG_RETIRED_ID}"; fi
LOOP_CMP="$(sed -n 's/^LOOP //p' <<<"$EXOUT")"
if [[ "$LOOP_CMP" == SAME\ * ]]; then pass; else fail "Parity: the post-apply untouched loop != the gate's never-acted-on set" "" "$LOOP_CMP"; fi

# The REAL wipe script's evidence row (W8): the script's own san/log/post/emit are extracted from the cloud-init,
# the happy-path `emit wiped ...` line is run with a curl stub that captures the POST body, and that body is wrapped
# the way Better Stack stores it (dt + raw as a JSON string). The funnel must PASS it, and a refused row must not.
WIPE_SCRIPT="$TMP/wipe-script.sh"; WIPE_DEFS="$TMP/wipe-defs.sh"
awk '/^  - path: \/usr\/local\/sbin\/inngest-backstop-wipe\.sh$/{f=1;next} f&&(/^  - path: /||/^[a-z]/){f=0} f' "$YML" \
  | sed -e '/^    content: |$/d' -e '/^    owner:/d' -e '/^    permissions:/d' -e 's/^      //' > "$WIPE_SCRIPT"
# the four functions plus the script's top-level constants (the retry budget is one: a rename must not break this row)
awk '/^[A-Z][A-Z_0-9]*=[^ ]*$/{print; next} /^(san|log|post|emit)\(\) \{/{ if ($0 ~ /\}[[:space:]]*$/) { print; next } f=1 } f{print} f&&/^\}$/{f=0}' "$WIPE_SCRIPT" > "$WIPE_DEFS"
if [[ -s "$WIPE_SCRIPT" && "$(grep -cE '^(san|log|post|emit)\(\) \{' "$WIPE_DEFS")" -eq 4 ]]; then pass; else fail "REAL ROW: san/log/post/emit could not be extracted from the cloud-init script (the extraction shape drifted)"; fi
real_row() { # <command...>  -> a Better Stack line on stdout (rc 1 when nothing was POSTed)
  rm -f "$TMP/wipe-payload.json"
  (
    export LC_ALL=C; _nonce="$NONCE"
    # shellcheck source=/dev/null
    source "$WIPE_DEFS"
    export NONCE="$_nonce" VOLUME_ID="$PIN" ROW_SIZE="$SIZE_BYTES" FS_UUID=abc LAST_WRITE=2026-09-20
    export LOG_FILE="$TMP/wipe.log" TOKEN_OK=1 TOKEN=synthtoken INGEST_URL=https://ingest.invalid/
    hostname() { printf '%s\n' "$tf_name"; }
    sleep() { :; }
    curl() { cat >/dev/null; while [[ $# -gt 0 ]]; do if [[ "$1" == -d ]]; then printf '%s' "$2" > "$TMP/wipe-payload.json"; fi; shift; done; return 0; }
    "$@"
  ) >/dev/null 2>&1
  [[ -s "$TMP/wipe-payload.json" ]] || return 1
  jq -cn --arg dt "2026-10-15 09:20:00" --arg p "$(cat "$TMP/wipe-payload.json")" '{dt:$dt, raw:$p}'
}
HAPPY="$(grep -E '^emit wiped readback=zero ' "$WIPE_SCRIPT" | tail -1 | sed 's/ || exit 1$//')"
if [[ -n "$HAPPY" ]]; then pass; else fail "REAL ROW: could not find the script's happy-path 'emit wiped readback=zero' line"; fi
if real_row eval "$HAPPY" > "$FIX/real-wiped.jsonl"; then pass; else fail "REAL ROW: running the script's own san/post/emit produced no POST body"; : > "$FIX/real-wiped.jsonl"; fi
dpc "REAL ROW: the wipe script's own happy-path row passes the destroy precondition (shape, emitter, nonce, size)" 0 "$DP_PASS" "rows=$FIX/real-wiped.jsonl"
if jq -e '.raw | fromjson | .shipper == "inngest-backstop-wipe" and .marker == "SOLEUR_INNGEST_BACKSTOP_WIPE" and (.message | startswith("SOLEUR_INNGEST_BACKSTOP_WIPE result=wiped "))' "$FIX/real-wiped.jsonl" >/dev/null 2>&1; then pass; else fail "REAL ROW: the posted payload does not carry the expected marker/shipper/message shape" "" "$(cat "$FIX/real-wiped.jsonl")"; fi
if real_row emit refused reason=mounted > "$FIX/real-refused.jsonl"; then pass; else fail "REAL ROW: the script's own refused row could not be produced"; : > "$FIX/real-refused.jsonl"; fi
dpc "REAL ROW: the script's own REFUSED row is not evidence => not_wiped" 1 "reason=not_wiped" "rows=$FIX/real-refused.jsonl"
nr_out="$(inngest_backstop_wipe_nonce_rows --rows-file "$FIX/real-refused.jsonl" --nonce "$NONCE" 2>&1)"
if [[ "$nr_out" == *" result=refused "* && "$nr_out" == *"reason=mounted"* ]]; then pass; else fail "REAL ROW: the poll's refusal short-circuit does not see the script's own refused row" "" "$nr_out"; fi

# ══ BEHAVIOUR: the job's run: bodies EXECUTED against refuse-by-default stubs ═════════════════════
# Each step's `run:` is extracted with PyYAML and run exactly as the runner runs it -- `bash --noprofile --norc
# -eo pipefail` on the unmodified text, under `env -i` -- with terraform, doppler, gh, the Hetzner helper hz() and
# the Better Stack query script replaced by stubs that answer ONLY what the scenario provides and exit 64 (or print
# UNEXPECTED on stderr, which fails the row) on any other argv. Static pins above prove the text; these rows prove
# what the text DOES.
SB="$TMP/sb"; mkdir -p "$SB/bin" "$SB/ws/scripts/lib" "$SB/ws/tests/scripts" "$SB/rt" "$SB/hz" "$SB/cwd" "$SB/dop"
assert_fixture_dir "$SB"
ln -s "${REPO_ROOT}/tests/scripts/lib" "$SB/ws/tests/scripts/lib"
ln -s "${REPO_ROOT}/scripts/lib/inngest-probe-row.sh" "$SB/ws/scripts/lib/inngest-probe-row.sh"
cat > "$SB/bin/terraform" <<'STUB'
#!/usr/bin/env bash
echo "terraform $*" >> "$TF_LOG"
case "$1 $2" in
  "state list") cat "$TF_STATE" ;;
  "apply -refresh-only")
    t=""; for a in "$@"; do case "$a" in -target=*) t="${a#-target=}" ;; esac; done
    drops="$(awk -F'\t' -v t="$t" '$1 == t {print $2}' "$TF_REFRESH")"; adds="$(awk -F'\t' -v t="$t" '$1 == t {print $3}' "$TF_REFRESH")"
    [[ -n "$drops" ]] || { echo "UNEXPECTED refresh target '$t'" >&2; exit 64; }
    IFS=, read -r -a d <<<"$drops"; for a in "${d[@]}"; do grep -vFx -- "$a" "$TF_STATE" > "$TF_STATE.new"; mv "$TF_STATE.new" "$TF_STATE"; done
    [[ -z "$adds" ]] || { IFS=, read -r -a ad <<<"$adds"; printf '%s\n' "${ad[@]}" >> "$TF_STATE"; } ;;
  "plan -no-color") exit "${TF_PLAN_RC:-64}" ;;
  "show -json") cat "$TF_SHOW" ;;
  "apply -no-color") exit "${TF_APPLY_RC:-64}" ;;
  *) echo "UNEXPECTED terraform $*" >&2; exit 64 ;;
esac
STUB
cat > "$SB/bin/doppler" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == run ]]; then shift; while [[ $# -gt 0 && "$1" != -- ]]; do shift; done; shift; exec "$@"; fi
if [[ "$1 $2" == "secrets get" ]]; then
  [[ -n "${DOPPLER_TOKEN:-}" ]] || { echo "UNEXPECTED doppler secrets get without DOPPLER_TOKEN in the environment" >&2; exit 64; }
  for a in "$@"; do [[ "$a" == --token || "$a" == "$DOPPLER_TOKEN" ]] && { echo "UNEXPECTED doppler token on argv" >&2; exit 64; }; done
  [[ -f "$DOP_DIR/$3" ]] && { cat "$DOP_DIR/$3"; exit 0; }
  exit 1
fi
echo "UNEXPECTED doppler $*" >&2; exit 64
STUB
cat > "$SB/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  api) shift; for a in "$@"; do case "$a" in
      repos/*/actions/runs/*) [[ -f "$GH_RUN" ]] && { cat "$GH_RUN"; exit 0; }; exit 1 ;;
      repos/*/issues/comments/*) echo "comment-fetch $a" >> "$GH_LOG"; [[ -f "$GH_COMMENT" ]] && { cat "$GH_COMMENT"; exit 0; }; exit 1 ;;
    esac; done ;;
  issue) cat > "$GH_ISSUE_OUT"; exit 0 ;;
esac
echo "UNEXPECTED gh $*" >&2; exit 64
STUB
cat > "$SB/bin/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$SB/bin/date" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == "-u +%s" && -n "${SB_CLOCK:-}" ]]; then n=$(( $(cat "$SB_CLOCK") + 60 )); echo "$n" > "$SB_CLOCK"; echo "$n"; else exec /usr/bin/date "$@"; fi
STUB
cat > "$SB/ws/scripts/betterstack-query.sh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$BS_LOG"
if [[ "${BS_RC:-0}" != 0 ]]; then printf '%s\n' "${BS_ERRTXT:-boom: simulated query failure}" >&2; exit "$BS_RC"; fi
[[ -f "$BS_ROWS" ]] && cat "$BS_ROWS"
exit 0
STUB
cat > "$SB/rt/hz.sh" <<'STUB'
hz() {
  local f; f="$HZ_FIX/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"
  if [[ -f "$f.code" ]]; then if [[ -f "$f.body" ]]; then cp "$f.body" "$2"; else : > "$2"; fi; cat "$f.code"
  else echo "UNEXPECTED hz $1" >&2; echo 599; fi
}
STUB
chmod +x "$SB"/bin/* "$SB/ws/scripts/betterstack-query.sh"

hzset() { # <hetzner path> <code> [body]
  local k; k="$SB/hz/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"
  printf '%s' "$2" > "$k.code"; if [[ -n "${3:-}" ]]; then printf '%s' "$3" > "$k.body"; else rm -f "$k.body"; fi
}
hzreset() { rm -f "$SB"/hz/* "$SB"/rt/srv.json "$SB"/out "$SB"/gh-* "$SB"/bs-*; : > "$SB/tf.log"; : > "$SB/gh.log"; : > "$SB/bs.log"; : > "$SB/out"; }
HZ_VOL="volumes/${PIN}"; HZ_WS='servers?label_selector=role%3Dinngest-backstop-wipe'; HZ_SRV='servers?name=soleur-inngest'
vol_json() { printf '{"volume":{"id":%s,"server":%s,"size":10}}' "$PIN" "$1"; }
state_set() { printf '%s\n' "$@" > "$SB/tf.state"; [[ $# -gt 0 ]] || : > "$SB/tf.state"; }
step_body() { # <step-name fragment> -> $SB/step.sh (the run: text, byte for byte, from the one-time extraction)
  local m
  m="$(awk -F'\t' -v f="$1" 'index($2, f) {print $1}' "$XD/names.tsv")"
  [[ "$(grep -c . <<<"$m")" -eq 1 && -f "$XD/s/$m.sh" ]] || return 3
  if [[ -n "${STEP_MUT_OLD:-}" ]]; then   # a behavioural mutation: replace ONE literal in this copy of the body
    local body; body="$(cat "$XD/s/$m.sh"; printf x)"; body="${body%x}"
    [[ "$body" == *"$STEP_MUT_OLD"* ]] || return 4
    printf '%s' "${body/"$STEP_MUT_OLD"/"$STEP_MUT_NEW"}" > "$SB/step.sh"
  else cp "$XD/s/$m.sh" "$SB/step.sh"; fi
}
run_step() { # <step-name fragment> [VAR=val ...] -> SOUT (stdout+stderr), SRC (exit code)
  local frag="$1"; shift
  step_body "$frag" || { SOUT="step '$frag' not found, or the behavioural mutation did not land"; SRC=99; return; }
  SRC=0
  SOUT="$(cd "$SB/cwd" && env -i PATH="$SB/bin:/usr/bin:/bin" HOME="$SB" LC_ALL=C RUNNER_TEMP="$SB/rt" GITHUB_WORKSPACE="$SB/ws" GITHUB_OUTPUT="$SB/out" \
    GITHUB_REPOSITORY=jikig-ai/soleur GITHUB_RUN_ID=555 GITHUB_ACTOR=dispatcher APPLY=success DOP_DIR="$SB/dop" CI_SSH_PUB=/x EXPECTED_INNGEST_VOLUME_ID="$PIN" HZ_FIX="$SB/hz" TF_STATE="$SB/tf.state" TF_REFRESH="$SB/tf.refresh" \
    TF_LOG="$SB/tf.log" TF_SHOW="$SB/tf.show" GH_RUN="$SB/gh-run.json" GH_COMMENT="$SB/gh-comment.json" GH_LOG="$SB/gh.log" GH_ISSUE_OUT="$SB/gh-issue.txt" \
    BS_LOG="$SB/bs.log" BS_ROWS="$SB/bs-rows.jsonl" "$@" bash --noprofile --norc -eo pipefail "$SB/step.sh" 2>&1)" || SRC=$?
}
beh() { # <name> <want-rc> <needle> [<absent-needle>]  (uses SOUT/SRC from the last run_step)
  local name="$1" want="$2" needle="$3" absent="${4:-}"
  if [[ "$SRC" -eq "$want" && "$SOUT" == *"$needle"* && "$SOUT" != *"UNEXPECTED"* && ( -z "$absent" || "$SOUT" != *"$absent"* ) ]]; then pass; [[ "$want" -eq 0 ]] && mp=$((mp + 1)); else fail "BEHAVIOUR: $name (want rc=$want containing '$needle')" "$SRC" "$SOUT"; fi
}
out_has() { grep -qxF -- "$1" "$SB/out"; }
SRV_LIVE='{"servers":[{"id":169426216}]}'
conv() { # <phase> -> runs the convergence step
  run_step "Convergence read" RETIRE_PHASE="$1"
}
conv_base() { # <vol-code> <vol-body> <ws-body>
  hzreset; hzset "$HZ_VOL" "$1" "$2"; hzset "$HZ_WS" 200 "$3"; hzset "$HZ_SRV" 200 "$SRV_LIVE"
}
WSA='hcloud_server.inngest_backstop_wipe[0]'; WAA='hcloud_volume_attachment.inngest_backstop_wipe[0]'
printf 'hcloud_volume_attachment.inngest_redis\thcloud_volume_attachment.inngest_redis\nhcloud_volume.inngest_redis\thcloud_volume.inngest_redis\nhcloud_server.inngest_backstop_wipe\t%s\nhcloud_volume_attachment.inngest_backstop_wipe\t%s\n' "$WSA" "$WAA" > "$SB/tf.refresh"

# ---- convergence read: every phase's arms (D-E, W13) ----
conv_base 200 "$(vol_json 169426216)" '{"servers":[]}'; state_set hcloud_volume_attachment.inngest_redis hcloud_server.inngest; conv detach
beh "detach, volume on the live host, nothing to reconcile => proceeds (skip=false)" 0 "" ; out_has "skip=false" && pass || fail "BEHAVIOUR: detach proceed did not write skip=false" "" "$(cat "$SB/out")"
conv_base 200 "$(vol_json null)" '{"servers":[]}'; state_set hcloud_volume_attachment.inngest_redis hcloud_server.inngest; conv detach
beh "detach, already detached with a stale attachment in state => reconciled, skip=true" 0 "state-only reconcile: hcloud_volume_attachment.inngest_redis dropped"
out_has "skip=true" && pass || fail "BEHAVIOUR: detach reconcile did not write skip=true" "" "$(cat "$SB/out")"
if ! grep -qxF hcloud_volume_attachment.inngest_redis "$SB/tf.state" && grep -qxF hcloud_server.inngest "$SB/tf.state"; then pass; else fail "BEHAVIOUR: the reconcile must drop exactly the attachment from state" "" "$(cat "$SB/tf.state")"; fi
conv_base 200 "$(vol_json null)" '{"servers":[]}'; state_set hcloud_volume_attachment.inngest_redis hcloud_server.inngest
printf 'hcloud_volume_attachment.inngest_redis\thcloud_volume_attachment.inngest_redis,hcloud_server.inngest\n' > "$SB/tf.refresh.x"; cp "$SB/tf.refresh" "$SB/tf.refresh.keep"; cp "$SB/tf.refresh.x" "$SB/tf.refresh"
conv detach
beh "D-E: a refresh that drops MORE than the one address (the host too) => refused" 1 "changed state beyond it: dropped='hcloud_server.inngest"
printf 'hcloud_volume_attachment.inngest_redis\thcloud_volume_attachment.inngest_redis\thcloud_server.surprise\n' > "$SB/tf.refresh"
conv_base 200 "$(vol_json null)" '{"servers":[]}'; state_set hcloud_volume_attachment.inngest_redis hcloud_server.inngest; conv detach
beh "D-E: a refresh that ADDS an address to state => refused" 1 "added='hcloud_server.surprise'"
cp "$SB/tf.refresh.keep" "$SB/tf.refresh"
# W2-10: the volume is already GONE (404): the attachment and the volume address are both queued, and a refresh of the
# attachment may drop the volume with it ({attachment, volume} is legal ONLY in this case)
G_ATT=hcloud_volume_attachment.inngest_redis; G_VOL=hcloud_volume.inngest_redis
conv_base 404 '{"error":{"code":"not_found"}}' '{"servers":[]}'; state_set "$G_ATT" "$G_VOL" hcloud_server.inngest
printf '%s\t%s,%s\t\n%s\t%s\t\n' "$G_ATT" "$G_ATT" "$G_VOL" "$G_VOL" "$G_VOL" > "$SB/tf.refresh"; conv detach
beh "W2-10: detach with the volume gone (404): the attachment refresh drops {attachment, volume} together => accepted" 0 "state-only reconcile: hcloud_volume.inngest_redis + hcloud_volume_attachment.inngest_redis dropped"
out_has "skip=true" && pass || fail "BEHAVIOUR: detach/gone did not write skip=true"
if [[ "$(cat "$SB/tf.state")" == "hcloud_server.inngest" && "$(grep -c 'apply -refresh-only' "$SB/tf.log")" -eq 1 ]]; then pass; else fail "BEHAVIOUR: the {attachment, volume} refresh must leave only the host in state after exactly one refresh" "" "$(cat "$SB/tf.state") / $(cat "$SB/tf.log")"; fi
cp "$SB/tf.refresh.keep" "$SB/tf.refresh"
conv_base 404 '{"error":{"code":"not_found"}}' '{"servers":[]}'; state_set "$G_ATT" "$G_VOL" hcloud_server.inngest; conv detach
beh "W2-10: detach with the volume gone, the attachment refresh drops only itself => the volume address is refreshed next" 0 "state-only reconcile: hcloud_volume.inngest_redis dropped"
if [[ "$(cat "$SB/tf.state")" == "hcloud_server.inngest" && "$(grep -c 'apply -refresh-only' "$SB/tf.log")" -eq 2 ]]; then pass; else fail "BEHAVIOUR: attachment then volume must be two refreshes" "" "$(cat "$SB/tf.state") / $(cat "$SB/tf.log")"; fi
conv_base 404 '{"error":{"code":"not_found"}}' '{"servers":[]}'; state_set "$G_VOL" hcloud_server.inngest; conv detach
beh "W2-10: detach with the volume gone and only the volume in state => the volume is reconciled" 0 "state-only reconcile: hcloud_volume.inngest_redis dropped"
conv_base 404 '{"error":{"code":"not_found"}}' '{"servers":[]}'; state_set "$G_ATT" "$G_VOL" hcloud_server.inngest
printf '%s\t%s,%s,hcloud_server.inngest\t\n' "$G_ATT" "$G_ATT" "$G_VOL" > "$SB/tf.refresh"; conv detach
beh "W2-10: ... but a refresh that also drops the HOST is refused" 1 "changed state beyond it"
conv_base 200 "$(vol_json null)" '{"servers":[]}'; state_set "$G_ATT" "$G_VOL" hcloud_server.inngest
printf '%s\t%s,%s\t\n' "$G_ATT" "$G_ATT" "$G_VOL" > "$SB/tf.refresh"; conv detach
beh "W2-10: {attachment, volume} is NOT legal when the volume still answers 200 (detached) => refused" 1 "changed state beyond it"
cp "$SB/tf.refresh.keep" "$SB/tf.refresh"
conv_base 200 "$(vol_json 169426216)" '{"servers":[]}'; hzset "$HZ_SRV" 500; state_set "$G_ATT" hcloud_server.inngest; conv detach
beh "W2-10: detach, the live-server read answers 500 => refused, naming the code" 1 "server read 500"
conv_base 200 "$(vol_json 777)" '{"servers":[{"id":777,"status":"running"}]}'; state_set "$WSA" "$WAA"; conv wipe
beh "W2-10: wipe while a wipe host holds the volume => the LEAKED HOST is named first, not 'must be detached'" 1 "a wipe host already exists: dispatch phase=teardown first" "must be detached"
conv_base 200 "$(vol_json 169426216)" '{"servers":[{"id":777,"status":"running"}]}'; state_set "$WSA" "$WAA"; conv detach
beh "detach with a wipe host present => teardown first" 1 "a wipe host exists: dispatch phase=teardown first"
conv_base 200 "$(vol_json 4242)" '{"servers":[]}'; state_set hcloud_volume_attachment.inngest_redis; conv detach
beh "detach, the volume is attached to some OTHER server => refused" 1 "not the live inngest host"
conv_base 200 "$(vol_json 169426216)" '{"servers":[]}'; state_set; conv wipe
beh "wipe while the volume is still attached => refused" 1 "must be detached"
conv_base 200 "$(vol_json null)" '{"servers":[]}'; state_set; conv wipe
beh "wipe, detached, no host, nothing in state => proceeds" 0 ""; out_has "skip=false" && pass || fail "BEHAVIOUR: wipe proceed did not write skip=false"
conv_base 200 "$(vol_json null)" '{"servers":[{"id":777,"status":"running"}]}'; state_set; conv wipe
beh "W13: a wipe host in Hetzner but ABSENT from state names its id and the manual recovery" 1 "wipe host id(s) 777 exist in Hetzner but not in state"
conv_base 200 "$(vol_json null)" '{"servers":[{"id":777}]}'; state_set "$WSA" "$WAA"; conv wipe
beh "wipe with a wipe host already present (in state) => teardown first" 1 "a wipe host already exists: dispatch phase=teardown first"
conv_base 200 "$(vol_json null)" '{"servers":[]}'; state_set "$WSA"; conv wipe
beh "wipe with a stale wipe address in state => teardown first" 1 "wipe addresses already in state"
conv_base 200 "$(vol_json null)" '{"servers":[]}'; state_set "$WSA" "$WAA" hcloud_server.inngest; conv teardown
beh "teardown, host already gone, both wipe addresses stale in state => both reconciled" 0 "state-only reconcile: hcloud_volume_attachment.inngest_backstop_wipe[0] dropped"
out_has "skip=true" && pass || fail "BEHAVIOUR: teardown reconcile did not write skip=true"
if [[ "$(grep -n 'apply -refresh-only' "$SB/tf.log" | sed -n 's/.*-target=\(hcloud_[a-z_.]*\).*/\1/p' | tr '\n' ' ')" == "hcloud_server.inngest_backstop_wipe hcloud_volume_attachment.inngest_backstop_wipe " ]]; then pass; else fail "BEHAVIOUR: the wipe SERVER must be reconciled before its attachment (refreshing the attachment also drops a vanished server)" "" "$(cat "$SB/tf.log")"; fi
if [[ "$(cat "$SB/tf.state")" == "hcloud_server.inngest" ]]; then pass; else fail "BEHAVIOUR: teardown reconcile left unexpected state" "" "$(cat "$SB/tf.state")"; fi
conv_base 200 "$(vol_json 169426216)" '{"servers":[{"id":777}]}'; state_set "$WSA" "$WAA"; conv teardown
beh "teardown with a wipe host present => proceeds to the plan (skip=false)" 0 ""; out_has "skip=false" && pass || fail "BEHAVIOUR: teardown proceed did not write skip=false"
conv_base 200 "$(vol_json 169426216)" '{"servers":[{"id":777}]}'; state_set hcloud_server.inngest; conv teardown
beh "W13: teardown cannot find the leaked host in state => explicit recovery, not 'nothing to tear down'" 1 "exist in Hetzner but not in state"
conv_base 200 "$(vol_json 169426216)" '{"servers":[]}'; state_set; conv destroy
beh "destroy with the volume still attached => detach first" 1 "is still attached (server 169426216): dispatch phase=detach"
conv_base 200 "$(vol_json null)" '{"servers":[]}'; state_set hcloud_volume_attachment.inngest_redis; conv destroy
beh "W13: destroy with a stale orphan attachment in state => re-dispatch detach, not a generic abort" 1 "re-dispatch phase=detach first"
conv_base 200 "$(vol_json null)" '{"servers":[]}'; state_set; conv destroy
beh "destroy, detached, state clean => proceeds" 0 ""; out_has "skip=false" && pass || fail "BEHAVIOUR: destroy proceed did not write skip=false"
conv_base 404 '{"error":{"code":"not_found"}}' '{"servers":[]}'; state_set hcloud_volume.inngest_redis; conv destroy
beh "destroy when Hetzner already answers 404 for the volume => state reconciled, skip=true" 0 "state-only reconcile: hcloud_volume.inngest_redis dropped"
out_has "skip=true" && pass || fail "BEHAVIOUR: destroy 404 did not write skip=true"
conv_base 500 '' '{"servers":[]}'; state_set; conv destroy
beh "a Hetzner 500 for the volume decides NOTHING" 1 "Hetzner answered 500"
conv_base 200 "$(vol_json null)" '{"servers":[]}'; state_set hcloud_volume_attachment.inngest_redis; : > "$SB/tf.refresh"; conv detach
if [[ "$SRC" -eq 1 && "$SOUT" == *"refresh-only reconcile of hcloud_volume_attachment.inngest_redis failed"* ]]; then pass; else fail "BEHAVIOUR: a failing refresh-only apply must fail the step, not skip" "$SRC" "$SOUT"; fi
cp "$SB/tf.refresh.keep" "$SB/tf.refresh"

# ---- the wipe evidence poll (W2, W2-1..W2-5, W2-11) ----
WCLOCK="$SB/clock"; echo 1760000000 > "$WCLOCK"
poll() { echo 1760000000 > "$WCLOCK"; run_step "Wipe evidence" SB_CLOCK="$WCLOCK" JOB_START=1759999000 RETIRE_PHASE=wipe BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x "$@"; }
poll_base() { hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 200 '{"servers":[]}'; }
POLL_GOOD="result=wiped nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none fs_uuid=abc last_write=x"
POLL_STARTED="result=started nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES}"
poll_base; ev_row '2025-10-09 08:55:00' "$POLL_GOOD" > "$SB/bs-rows.jsonl"; poll
beh "poll: a wiped row for this run's nonce => success, with the Hetzner HTTP codes beside the end-of-poll values (W2-11)" 0 "Hetzner at poll end: volume.server=null (HTTP 200) wipe hosts= (HTTP 200)"
poll_base; { ev_row '2025-10-09 08:54:00' "$POLL_STARTED"; ev_row '2025-10-09 08:55:00' "result=refused reason=has_holders nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES}"; ev_row '2025-10-09 08:55:30' "result=refused reason=mounted nonce=999 volume_id=${PIN} size_bytes=${SIZE_BYTES}"; } > "$SB/bs-rows.jsonl"; poll
beh "poll: a refusal for this nonce ends the poll at once and names the host's reason" 1 "host refusal: has_holders" "reason=mounted"
if [[ "$(grep -c . "$SB/bs.log")" -le 2 ]]; then pass; else fail "BEHAVIOUR: the poll kept querying after a refusal" "" "$(cat "$SB/bs.log")"; fi
if [[ "$SOUT" == *"result=started nonce=555"* && "$SOUT" != *"nonce=999"* ]]; then pass; else fail "BEHAVIOUR: the poll must print only THIS nonce's rows" "" "$SOUT"; fi
beh "W2-4: a started row and no wiped row => 'may be PARTIALLY ZEROED; rollback is gone', naming the post-write guards, never 'stays intact'" 1 "the device may be PARTIALLY ZEROED" "volume stays intact"
if [[ "$SOUT" == *"zero_failed, readback_nonzero, sig_survived"* && "$SOUT" == *"re-dispatch phase=wipe (the wipe re-enters)"* && "$SOUT" == *"rollback is gone"* ]]; then pass; else fail "BEHAVIOUR: the partial-zero message must cite the post-write guards and the re-entry" "" "$SOUT"; fi
poll_base; ev_row '2025-10-09 08:55:00' "result=refused reason=has_holders nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES}" > "$SB/bs-rows.jsonl"; poll
beh "W2-4: a pre-write refusal with NO started row => 'nothing was written: the volume stays intact'" 1 "no started row, so nothing was written: the volume stays intact" "PARTIALLY"
for g in zero_failed readback_nonzero sig_survived; do
  poll_base; ev_row '2025-10-09 08:55:00' "result=refused reason=${g} nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES}" > "$SB/bs-rows.jsonl"; poll
  beh "W2-4: the post-write guard ${g} alone (no started row seen) still says PARTIALLY ZEROED" 1 "the device may be PARTIALLY ZEROED" "stays intact"
done
poll_base; : > "$SB/bs-rows.jsonl"; poll
beh "poll: no rows => bounded by the wall-clock deadline, says none seen" 1 "host refusal: none seen" "PARTIALLY"
n_q="$(grep -c . "$SB/bs.log")"
if [[ "$n_q" -ge 3 && "$n_q" -le 25 ]]; then pass; else fail "BEHAVIOUR: expected the 20-minute wall-clock deadline to bound the poll to a handful of queries, saw ${n_q}" "" ""; fi
if [[ "$(grep -vc -e '--no-archive' -e '^$' "$SB/bs.log")" -eq 0 && "$(grep -c -e '--since 1h' "$SB/bs.log")" -eq "$n_q" ]]; then pass; else fail "BEHAVIOUR: every poll query must be the hot-window form (--since 1h --no-archive)" "" "$(cat "$SB/bs.log")"; fi
poll_base; : > "$SB/bs-rows.jsonl"; poll JOB_START=1759998000
if [[ "$SRC" -eq 1 && ! -s "$SB/bs.log" ]]; then pass; else fail "W2-5: a deadline capped at JOB_START+1800 (already past) must run no query" "$SRC" "$(cat "$SB/bs.log")"; fi
poll_base; : > "$SB/bs-rows.jsonl"; poll JOB_START=1759998600
n_cap="$(grep -c . "$SB/bs.log")"
if [[ "$n_cap" -ge 1 && "$n_cap" -lt "$n_q" ]]; then pass; else fail "W2-5: a later JOB_START must cap the poll tighter than 20 minutes (${n_cap} queries vs ${n_q})" "" ""; fi
poll_base; poll BS_RC=7
beh "poll: a failing query is printed (rc and stderr), not swallowed" 1 "poll query failed rc=7: boom: simulated query failure"
poll_base; ev_row_as attacker-box "$WIPE_SHIPPER" '2025-10-09 08:55:00' "$POLL_GOOD" > "$SB/bs-rows.jsonl"; poll
beh "W2-3: a perfect row from the wrong host is not evidence; it ends the poll at once as emitter_mismatch, printing the observed host and shipper" 1 "reason=emitter_mismatch"
if [[ "$SOUT" == *"observed host=attacker-box shipper=inngest-backstop-wipe"* && "$SOUT" == *"no wiped row for nonce 555"* && "$(grep -c . "$SB/bs.log")" -eq 1 ]]; then pass; else fail "W2-3: emitter_mismatch must print the observed values and not wait out the deadline" "" "$SOUT"; fi
poll_base; ev_row_as "$(printf 'h%.0s' $(seq 1 200))" "$WIPE_SHIPPER" '2025-10-09 08:55:00' "$POLL_GOOD" > "$SB/bs-rows.jsonl"; poll
if [[ "$SOUT" == *"observed host=hhhhhhhh"* && "$SOUT" != *"$(printf 'h%.0s' $(seq 1 81))"* ]]; then pass; else fail "W2-3: the observed host is cut to 80 characters" "" "$SOUT"; fi
poll_base; ev_row '2025-10-09 08:55:00' "result=wiped nonce=555 volume_id=${PIN} size_bytes=$((SIZE_BYTES - 1)) readback=zero sig_after=none" > "$SB/bs-rows.jsonl"; poll
beh "W2-3: a wiped row for the wrong size ends the poll at once with the funnel's own reason" 1 "reason=volume_mismatch"
poll_base; ev_row '2025-10-09 08:55:00' "$POLL_STARTED" > "$SB/bs-rows.jsonl"; poll
n_st="$(grep -c . "$SB/bs.log")"
if [[ "$SRC" -eq 1 && "$n_st" -ge 3 ]]; then pass; else fail "W2-3: a started-only row is not a rejection: the poll keeps waiting for the wiped row (${n_st} queries)" "$SRC" "$SOUT"; fi
poll_base; { ev_row_as attacker-box "$WIPE_SHIPPER" '2025-10-09 08:54:00' "result=refused reason=mounted nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES}"; ev_row '2025-10-09 08:55:00' "$POLL_GOOD"; } > "$SB/bs-rows.jsonl"; poll
beh "W2-2: a REFUSED row from another emitter bearing this nonce does not abort the poll when the genuine wiped row is there" 0 "Hetzner at poll end"
# W2-1: nothing Better Stack-derived can open a workflow command. The row's message carries an embedded newline followed
# by ::stop-commands:: and ::error:: lines, an ESC and a CR; the failing query's stderr does the same.
inj_row() { jq -cn --arg dt '2025-10-09 08:55:00' --arg m "$1" --arg h "$WIPE_HOST" --arg sh "$WIPE_SHIPPER" \
  '{dt:$dt, raw: ({message:$m, marker:"SOLEUR_INNGEST_BACKSTOP_WIPE", host:$h, dt:$dt, shipper:$sh} | tojson)}'; }
no_cmd_lines() { # SOUT: no line opens a workflow command except the poll's OWN error annotation
  ! grep -E '^[[:space:]]*::' <<<"$SOUT" | grep -vE '^::error::no wiped row for nonce 555' | grep -q . && [[ "$SOUT" != *$'\e'* && "$SOUT" != *$'\r'* ]]
}
poll_base; inj_row "SOLEUR_INNGEST_BACKSTOP_WIPE result=refused reason=x"$'\n::stop-commands::x\n::error::injected\e[31m\rtail'" nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES}" > "$SB/bs-rows.jsonl"; poll
if [[ "$SRC" -eq 1 && "$SOUT" == *"stop-commands::x"* && "$SOUT" == *"error::injected"* ]] && no_cmd_lines; then pass; else fail "W2-1: an embedded newline + ::stop-commands:: / ::error:: in a row must not open a command line in the poll output" "$SRC" "$SOUT"; fi
poll_base; poll BS_RC=7 BS_ERRTXT=$'first\n::stop-commands::y\n   ::error::pwn'
if [[ "$SOUT" == *"poll query failed rc=7: first"* ]] && no_cmd_lines; then pass; else fail "W2-1: the failing query's stderr is sanitized too" "$SRC" "$SOUT"; fi
poll_base; inj_row "SOLEUR_INNGEST_BACKSTOP_WIPE result=refused reason=$(printf 'z%.0s' $(seq 1 3000)) nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES}" > "$SB/bs-rows.jsonl"; poll
if [[ "$(grep -m1 '^rows for nonce' <<<"$SOUT" | wc -c)" -le 640 ]]; then pass; else fail "W2-1: the printed rows are capped at 600 bytes" "" "$(grep -m1 '^rows for nonce' <<<"$SOUT" | wc -c)"; fi
hzreset; hzset "$HZ_VOL" 404; poll
beh "poll: an unreadable volume stops it before any query" 1 "cannot read volume"

# ---- the destroy precondition (D-A, D-B), end to end through the real step ----
# the behavioural history lives on the step's own (2025-10-09) timeline: run started 08:50, wipe host attached 08:52, row
# ingested 08:55, detached 08:58 -- the row sits inside the attach..detach window, as the gate now demands
ACTS_BEH="$SB/acts-beh.json"; write_acts "$ACTS_BEH" "$(act detach_volume success 2025-10-09T08:58:00+00:00 "$WIPE_SRV"),$(act attach_volume success 2025-10-09T08:52:00+00:00 "$WIPE_SRV"),${ACT_LIVE_ATT},${ACT_CREATE}"
pre_base() {
  hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "${HZ_VOL}/actions?per_page=50&sort=id%3Adesc" 200 "$(cat "$ACTS_BEH")"; hzset "$HZ_SRV" 200 "$SRV_LIVE"
  printf '{"path":".github/workflows/apply-web-platform-infra.yml","head_branch":"main","event":"workflow_dispatch","status":"completed","run_started_at":"2025-10-09T08:50:00Z"}' > "$SB/gh-run.json"
  ev_row_as "$WIPE_HOST" "$WIPE_SHIPPER" '2025-10-09 08:55:00' "result=wiped nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none fs_uuid=abc last_write=x" > "$SB/bs-rows.jsonl"
}
pre() { run_step "Destroy precondition" RETIRE_PHASE=destroy BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x "$@"; }
pre_base; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: a wiped row + the wipe host's attach/detach in Hetzner's history => PASS" 0 "destroy_precondition: PASS"
pre_base; printf '{"path":".github/workflows/apply-web-platform-infra.yml","head_branch":"feature","event":"workflow_dispatch","status":"completed","run_started_at":"2025-10-09T08:50:00Z"}' > "$SB/gh-run.json"; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: a wipe run from a non-main branch => refused (no floor), with its own explanatory line (W2-6)" 1 "reason=evidence_stale"
if [[ "$SOUT" == *"run 555 could not be read, or is not a completed workflow_dispatch run of this workflow on main: no time floor"* ]]; then pass; else fail "W2-6: a non-main/unreadable wipe run must print its own line, not surface only as an unreadable floor" "" "$SOUT"; fi
pre_base; rm -f "$SB/gh-run.json"; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: the wipe run cannot be read => refused" 1 "reason=evidence_stale"
pre_base; printf '{"path":".github/workflows/other.yml","head_branch":"main","event":"workflow_dispatch","status":"completed","run_started_at":"2025-10-09T08:50:00Z"}' > "$SB/gh-run.json"; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: a run of another workflow => refused" 1 "reason=evidence_stale"
pre_base; printf '{"path":".github/workflows/apply-web-platform-infra.yml","head_branch":"main","event":"workflow_dispatch","status":"in_progress","run_started_at":"2025-10-09T08:50:00Z"}' > "$SB/gh-run.json"; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: a wipe run that has not completed => refused" 1 "reason=evidence_stale"
pre_base; hzset "${HZ_VOL}/actions?per_page=50&sort=id%3Adesc" 500; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: Hetzner's action history unreadable (500) => refused, the HTTP code printed (W2-6)" 1 "reason=actions_unreadable"
if [[ "$SOUT" == *"Hetzner GET volumes/106261946/actions?per_page=50&sort=id%3Adesc answered 500"* ]]; then pass; else fail "W2-6: rd must print the Hetzner HTTP code" "" "$SOUT"; fi
pre_base; hzset "$HZ_SRV" 500; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: the live server id unreadable => refused" 1 "reason=live_server_unreadable"
pre_base; hzset "$HZ_VOL" 200 "$(vol_json 777)"; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: the volume still attached => refused" 1 "reason=still_attached"
pre_base; ev_row_as attacker-box "$WIPE_SHIPPER" '2025-10-09 08:55:00' "result=wiped nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none" > "$SB/bs-rows.jsonl"; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: D-A forged row from another host => refused" 1 "reason=emitter_mismatch"
if [[ "$(grep -c 'no-archive' "$SB/bs.log")" -eq 0 && "$(grep -c -e '--since 14d' "$SB/bs.log")" -ge 1 ]]; then pass; else fail "BEHAVIOUR: the destroy precondition must keep the archive (--since 14d, no --no-archive)" "" "$(cat "$SB/bs.log")"; fi
CLO_GOOD_REF="https://github.com/jikig-ai/soleur/issues/8285#issuecomment-4300000001"
pre_base; cp "$CLO_OK" "$SB/gh-comment.json"; pre WIPE_RUN_ID= RETIRE_ERASURE=provider-only CLO_REF="$CLO_GOOD_REF"
beh "precondition D4: an attestation comment from an OWNER naming the volume => PASS" 0 "destroy_precondition: PASS"
if grep -q 'comment-fetch repos/jikig-ai/soleur/issues/comments/4300000001' "$SB/gh.log"; then pass; else fail "BEHAVIOUR: the comment must be fetched by id through the API" "" "$(cat "$SB/gh.log")"; fi
pre_base; clo_file "$SB/gh-comment.json" NONE "$(clo_body)"; pre WIPE_RUN_ID= RETIRE_ERASURE=provider-only CLO_REF="$CLO_GOOD_REF"
beh "precondition D4: the same comment from an author with NONE association => refused" 1 "reason=clo_author_not_privileged"
pre_base; cp "$CLO_OK" "$SB/gh-comment.json"; pre WIPE_RUN_ID= RETIRE_ERASURE=provider-only CLO_REF="https://example.test/attestation"
beh "precondition D4: an arbitrary https URL is refused before any fetch" 1 "reason=clo_ref_invalid"
if [[ ! -s "$SB/gh.log" ]]; then pass; else fail "BEHAVIOUR: an invalid ref must not trigger an API fetch" "" "$(cat "$SB/gh.log")"; fi
pre_base; pre WIPE_RUN_ID= RETIRE_ERASURE=provider-only CLO_REF="$CLO_GOOD_REF"
beh "precondition D4: the comment cannot be fetched => refused, with its own line (W2-6)" 1 "reason=clo_comment_unreadable"
if [[ "$SOUT" == *"GitHub API could not return comment 4300000001"* ]]; then pass; else fail "W2-6: a failed comment fetch must print its own line" "" "$SOUT"; fi
pre_base; cp "$CLO_OK" "$SB/gh-comment.json"; pre WIPE_RUN_ID= RETIRE_ERASURE=provider-only CLO_REF="$CLO_GOOD_REF" GITHUB_ACTOR=clo-reviewer
beh "precondition D4 (E-2d): the dispatching GITHUB_ACTOR is the comment's author => refused (the step passes the actor)" 1 "reason=clo_same_actor"
pre_base; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF= BS_RC=7
beh "precondition: a failing Better Stack query is printed with rc and stderr (W2-6), then the empty rows are refused" 1 "Better Stack query failed rc=7: boom: simulated query failure"
beh "precondition: ... and the gate then reports the rows as absent, not as a pass" 1 "reason=evidence_absent"
pre_base; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF= BS_RC=7 BS_ERRTXT=$'x\n::stop-commands::z'
if ! grep -qE '^[[:space:]]*::stop-commands' <<<"$SOUT"; then pass; else fail "W2-1: the destroy precondition's query stderr is sanitized" "" "$SOUT"; fi
pre_base; hzset "$HZ_VOL" 500; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: the volume read answers 500 => 'Hetzner GET volumes/106261946 answered 500' and a refusal" 1 "Hetzner GET volumes/106261946 answered 500"

# ---- behavioural mutations: ONE literal of the extracted body is replaced, the bad scenario is re-run ----
# mutrow_accept: the scenario was shown RED unmutated; under the mutation it must go GREEN (rc 0) -- the guard is load-bearing.
# mutrow_red:    the scenario was shown GREEN unmutated; under the mutation it must go RED (rc != 0 or an UNEXPECTED stub call).
mutrow_accept() { # <label> <step fragment> <old> <new> [VAR=val ...]
  local label="$1" frag="$2"; STEP_MUT_OLD="$3"; STEP_MUT_NEW="$4"; shift 4
  run_step "$frag" "$@"; STEP_MUT_OLD=""
  if [[ "$SRC" -eq 0 && "$SOUT" != *UNEXPECTED* ]]; then pass; else fail "MUTATION: $label -- the mutated step still refused (rc=$SRC); the guard is not load-bearing" "$SRC" "$SOUT"; fi
}
mutrow_red() { # <label> <step fragment> <old> <new> [VAR=val ...]
  local label="$1" frag="$2"; STEP_MUT_OLD="$3"; STEP_MUT_NEW="$4"; shift 4
  run_step "$frag" "$@"; STEP_MUT_OLD=""
  if [[ "$SRC" -ne 0 && "$SRC" -ne 99 ]] || [[ "$SOUT" == *UNEXPECTED* ]]; then pass; else fail "MUTATION: $label -- the mutated step still passed (rc=$SRC); the pin on it is decorative" "$SRC" "$SOUT"; fi
}

# ---- the live-store gate step (E-1, W2-6, W2-13 P2-2): stubbed doppler/Better Stack, the REAL probe-row lib ----
LS_ENV=(RETIRE_PHASE=detach BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x DOPPLER_TOKEN_INNGEST_ARM=armtok)
probe_bs_row() { # <host> <host_name> <host_role> <emitter> <epoch-ago-seconds>
  jq -cn --arg dt "$(date -u -d "@$(( $(date -u +%s) - $5 ))" '+%Y-%m-%d %H:%M:%S')" --arg h "$1" --arg hn "$2" --arg e "$4" \
    --arg m "SOLEUR_INNGEST_SERVER_PROBE host_role=$3 data_mount_src=/dev/mapper/inngest-redis data_mount_devid=scsi-0HC_Volume_${LIVEV} redis_active=active redis_keys=3" \
    '{dt:$dt, raw: ({SYSLOG_IDENTIFIER:$e, host:$h, host_name:$hn, message:$m} | tojson)}'
}
ls_base() { hzreset; rm -f "$SB"/dop/*; printf 'done' > "$SB/dop/INNGEST_LUKS_CUTOVER"; printf '%s' "$LIVEV" > "$SB/dop/INNGEST_LUKS_ACTIVE_VOLUME_ID"
  probe_bs_row soleur-inngest soleur-inngest-prd dedicated inngest-server-probe 600 > "$SB/bs-rows.jsonl"; }
lsrun() { run_step "Live-store gate" "${LS_ENV[@]}" "$@"; }
ls_base; lsrun
beh "live-store step: flag done, pointer on the LUKS volume, a fresh dedicated probe row from the REAL selector => PASS (producer and consumer meet)" 0 "live_store_gate: PASS"
if [[ "$(cat "$SB/bs.log")" == *"--grep SOLEUR_INNGEST_SERVER_PROBE"* && "$(cat "$SB/bs.log")" == *"--since 6h"* ]]; then pass; else fail "live-store step: the probe query must be the 6 h window on the REAL marker" "" "$(cat "$SB/bs.log")"; fi
ls_base; rm -f "$SB"/dop/*; lsrun
beh "live-store step: Doppler returns nothing (failure) => __UNREADABLE__ => flag_not_done, fail-closed" 1 "reason=flag_not_done"
ls_base; printf 'rollback' > "$SB/dop/INNGEST_LUKS_CUTOVER"; lsrun
beh "live-store step: a rollback flag => refused" 1 "reason=flag_not_done"
ls_base; printf '%s' "$PIN" > "$SB/dop/INNGEST_LUKS_ACTIVE_VOLUME_ID"; lsrun
beh "live-store step: the pointer on the retired volume => refused" 1 "reason=active_id_mismatch"
ls_base; probe_bs_row attacker-box soleur-inngest-prd dedicated inngest-server-probe 600 > "$SB/bs-rows.jsonl"; lsrun
beh "live-store step: a probe row from ANOTHER host is not a probe row => probe_unusable" 1 "reason=probe_unusable"
ls_base; probe_bs_row soleur-inngest other-name dedicated inngest-server-probe 600 > "$SB/bs-rows.jsonl"; lsrun
beh "live-store step: ... nor from another host_name" 1 "reason=probe_unusable"
ls_base; probe_bs_row soleur-inngest soleur-inngest-prd shared inngest-server-probe 600 > "$SB/bs-rows.jsonl"; lsrun
beh "live-store step: the dedicated-role filter: a host_role=shared row is not the live store's => probe_unusable" 1 "reason=probe_unusable"
ls_base; probe_bs_row soleur-inngest soleur-inngest-prd dedicated doppler 600 > "$SB/bs-rows.jsonl"; lsrun
beh "live-store step: the shared predicate: a row from another emitter quoting the marker is not a probe row" 1 "reason=probe_unusable"
ls_base; probe_bs_row soleur-inngest soleur-inngest-prd dedicated inngest-server-probe 12600 > "$SB/bs-rows.jsonl"; lsrun
beh "live-store step: a 3.5 h old probe row => probe_stale" 1 "reason=probe_stale"
ls_base; lsrun BETTERSTACK_QUERY_PASSWORD=
beh "live-store step: a missing read credential fails closed before anything is read" 1 "a read credential is missing"
ls_base; lsrun BS_RC=7
beh "live-store step: a failing probe query prints its rc and stderr (W2-6)" 1 "probe-row query failed rc=7: boom: simulated query failure"
ls_base; lsrun BS_RC=7 BS_ERRTXT=$'e\n::stop-commands::q'
if ! grep -qE '^[[:space:]]*::stop-commands' <<<"$SOUT"; then pass; else fail "W2-1: the probe query's stderr is sanitized" "" "$SOUT"; fi
ls_base; lsrun
if [[ "$SOUT" != *"inflight"* && "$SOUT" != *"in_progress"* && ! -s "$SB/gh.log" ]] && ! grep -q 'hz' "$SB/step.sh"; then pass; else fail "E-1: the live-store step must neither count in-flight runs nor read Hetzner" "" "$SOUT"; fi
# mutations (each re-runs the scenario that proves the line)
ls_base; mutrow_red "G15: the @tsv join becomes join(\" \") (producer and consumer no longer meet)" "Live-store gate" "@tsv'" 'join(" ")'"'" "${LS_ENV[@]}"
ls_base; probe_bs_row soleur-inngest soleur-inngest-prd shared inngest-server-probe 600 > "$SB/bs-rows.jsonl"
mutrow_accept "G3: the dedicated-role filter dropped" "Live-store gate" '| select(((capture("(?:^| )host_role=(?<r>[^ ]*)")? // {r: ""}).r) == "dedicated")' '' "${LS_ENV[@]}"
ls_base; probe_bs_row attacker-box soleur-inngest-prd dedicated inngest-server-probe 600 > "$SB/bs-rows.jsonl"
mutrow_accept "G3b: the host/host_name isolation dropped" "Live-store gate" '| select(.host == $h and .host_name == $hn)' '' "${LS_ENV[@]}"
ls_base; probe_bs_row soleur-inngest soleur-inngest-prd dedicated doppler 600 > "$SB/bs-rows.jsonl"
mutrow_accept "G12c: the shared probe-row predicate dropped" "Live-store gate" '| select(inngest_probe_row)' '' "${LS_ENV[@]}"
ls_base; mutrow_red "the Doppler token on argv again (the stub refuses it)" "Live-store gate" '--plain 2>/dev/null' '--plain --token "$DOPPLER_TOKEN_INNGEST_ARM" 2>/dev/null' "${LS_ENV[@]}"
ls_base; printf 'rollback' > "$SB/dop/INNGEST_LUKS_CUTOVER"
mutrow_accept "the gate call's refusal arm neutered (exit 1 dropped)" "Live-store gate" 'not provably serving."; exit 1' 'not provably serving."' "${LS_ENV[@]}"

# ---- the apply step (W2-13 P2-1): argv, the untouched loop, the failure arm ----
AP_ENV=(RETIRE_PHASE=detach)
ap_plan() { printf '{"resource_changes":[%s]}' "$1" > "$SB/cwd/tfplan.json"; }
ap_ent() { printf '{"address":%s,"change":{"actions":%s}}' "$(jq -Rn --arg a "$1" '$a')" "$2"; }
apply_tail_ok() { [[ "$(grep '^terraform apply' "$SB/tf.log" | tail -1)" == "terraform apply -no-color -input=false tfplan" ]]; }
APPLY_ADDRS=('hcloud_server.inngest' 'hcloud_volume.inngest_redis_luks' 'hcloud_volume_attachment.inngest_redis_luks' 'random_password.inngest_redis_luks' 'doppler_secret.inngest_redis_luks_key' 'hcloud_volume.workspaces["web-1"]' 'hcloud_volume_attachment.workspaces["web-1"]' 'hcloud_server.web["web-1"]')
ap_clean() { local a e=""; for a in "${APPLY_ADDRS[@]}"; do e+="$(ap_ent "$a" '["no-op"]'),"; done; e+="$(ap_ent hcloud_volume_attachment.inngest_redis '["delete"]')"; printf '%s' "$e"; }
hzreset; ap_plan "$(ap_clean)"; run_step "Terraform apply (phase)" "${AP_ENV[@]}" TF_APPLY_RC=0
beh "apply: a clean plan => applies and reports the host and live store untouched" 0 "host and live encrypted store untouched"
if apply_tail_ok; then pass; else fail "apply: the terraform apply argv must END in exactly 'tfplan' (the saved, gated plan)" "" "$(cat "$SB/tf.log")"; fi
if ! grep -q 'tfplan-all\|-target\|-auto-approve' "$SB/tf.log"; then pass; else fail "apply: no other plan file, -target or -auto-approve" "" "$(cat "$SB/tf.log")"; fi
: > "$SB/tf.log"; run_step "Terraform apply (phase)" "${AP_ENV[@]}" TF_APPLY_RC=1
beh "apply: terraform apply fails => fails, says re-dispatch the SAME phase" 1 "terraform apply (detach) failed. Re-dispatch the SAME phase"
for a in "${APPLY_ADDRS[@]}"; do
  ap_plan "$(ap_ent "$a" '["update"]')"; run_step "Terraform apply (phase)" "${AP_ENV[@]}" TF_APPLY_RC=0
  beh "apply: ${a} showing an update in the applied plan => fails hard, names it" 1 "${a} shows 1 action(s) in the applied plan"
done
for v in '"create"' '"delete"' '"forget"' '"delete","create"'; do
  ap_plan "$(ap_ent hcloud_server.inngest "[$v]")"; run_step "Terraform apply (phase)" "${AP_ENV[@]}" TF_APPLY_RC=0
  beh "apply: the host with the verb(s) ${v//\"/} => fails hard" 1 "hcloud_server.inngest shows 1 action(s)"
done
ap_plan "$(ap_ent hcloud_server.inngest '["read"]'),$(ap_ent hcloud_server.web '["update"]')"; run_step "Terraform apply (phase)" "${AP_ENV[@]}" TF_APPLY_RC=0
beh "apply: a read of the host and an update of an UNLISTED address are not touches (control) => rc 0" 0 "untouched"
ap_plan "$(ap_ent hcloud_server.inngest '["update"]')"
mutrow_accept "G4: the untouched loop's verb filter loses 'update'" "Terraform apply (phase)" 'any(. == "create" or . == "update" or . == "delete" or . == "forget")' 'any(. == "create")' "${AP_ENV[@]}" TF_APPLY_RC=0
mutrow_accept "G4b: the TOUCHED comparison neutered" "Terraform apply (phase)" '[[ "$TOUCHED" == "0" ]] || {' '[[ "$TOUCHED" == "0" ]] || [[ 1 ]] || {' "${AP_ENV[@]}" TF_APPLY_RC=0
mutrow_accept "G4c: the loop reads another plan file's content (an empty list)" "Terraform apply (phase)" "| length' tfplan.json)" "| length' <<<'{\"resource_changes\":[]}')" "${AP_ENV[@]}" TF_APPLY_RC=0
ap_plan "$(ap_clean)"; : > "$SB/tf.log"
STEP_MUT_OLD='-input=false tfplan; then' STEP_MUT_NEW='-input=false; then' run_step "Terraform apply (phase)" "${AP_ENV[@]}" TF_APPLY_RC=0
if ! apply_tail_ok; then pass; else fail "MUTATION G10: an apply without the saved plan must trip the argv pin" "" "$(cat "$SB/tf.log")"; fi
: > "$SB/tf.log"; STEP_MUT_OLD='tfplan; then' STEP_MUT_NEW='tfplan-all; then' run_step "Terraform apply (phase)" "${AP_ENV[@]}" TF_APPLY_RC=0
if ! apply_tail_ok; then pass; else fail "MUTATION G10b: an apply of another plan file must trip the argv pin" "" "$(cat "$SB/tf.log")"; fi
STEP_MUT_OLD=""

# ---- the teardown step: rc 0 / 1 / 2 (W3), the exact argv, the E-4 identity pin ----
TD_ENV=(RETIRE_PHASE=wipe)
td() { run_step "Teardown of the wipe host" "${TD_ENV[@]}" "$@"; }
write_plan "${WSRV_DEL},${WATT_DEL}"; cp "$TMP/plan.json" "$SB/tf.show.ok"
write_plan "${WSRV_DEL},${VOL_DEL}"; cp "$TMP/plan.json" "$SB/tf.show.bad"
write_plan "${WSRV_DEL_N},${WATT_DEL}"; cp "$TMP/plan.json" "$SB/tf.show.name"
write_plan "${WSRV_DEL_LIVE},${WATT_DEL}"; cp "$TMP/plan.json" "$SB/tf.show.live"
hzreset; : > "$SB/tf.state"; cp "$SB/tf.show.ok" "$SB/tf.show"
td TF_PLAN_RC=0 TF_APPLY_RC=64
beh "teardown: plan rc 0 (nothing exists) => exits 0 without applying" 0 "nothing to tear down"
if ! grep -q 'apply -no-color' "$SB/tf.log"; then pass; else fail "BEHAVIOUR: teardown must not apply when the plan is empty" "" "$(cat "$SB/tf.log")"; fi
: > "$SB/tf.log"; td TF_PLAN_RC=1 TF_APPLY_RC=64
beh "teardown: plan rc 1 (error) => fails, names the leak" 1 "teardown plan failed (exit 1)"
: > "$SB/tf.log"; td TF_PLAN_RC=2 TF_APPLY_RC=0
beh "teardown: plan rc 2 + a legal deletes-only plan => applies" 0 ""
if [[ "$(grep '^terraform apply' "$SB/tf.log")" == "terraform apply -no-color -input=false tfplan-td" ]]; then pass; else fail "BEHAVIOUR: the teardown apply must be exactly the saved teardown plan (tfplan-td)" "" "$(cat "$SB/tf.log")"; fi
if [[ "$(grep '^terraform plan' "$SB/tf.log")" == "terraform plan -no-color -input=false -detailed-exitcode -out=tfplan-td -var=ssh_key_path=/x -var=inngest_backstop_wipe_enabled=false -target=hcloud_server.inngest_backstop_wipe -target=hcloud_volume_attachment.inngest_backstop_wipe" ]]; then pass; else fail "BEHAVIOUR: the teardown plan must be enabled=false, -detailed-exitcode and exactly the two wipe targets" "" "$(cat "$SB/tf.log")"; fi
: > "$SB/tf.log"; td TF_PLAN_RC=2 TF_APPLY_RC=1
beh "teardown: the apply fails => fails, says re-dispatch" 1 "teardown apply failed; re-dispatch phase=teardown"
cp "$SB/tf.show.bad" "$SB/tf.show"; : > "$SB/tf.log"; td TF_PLAN_RC=2 TF_APPLY_RC=0
beh "teardown: a plan that also deletes the retired volume is REFUSED by the gate, never applied" 1 "teardown plan REFUSED by the gate"
if ! grep -q 'apply -no-color' "$SB/tf.log"; then pass; else fail "BEHAVIOUR: a refused teardown plan must not be applied" "" "$(cat "$SB/tf.log")"; fi
for v in name live; do
  cp "$SB/tf.show.$v" "$SB/tf.show"; : > "$SB/tf.log"; td TF_PLAN_RC=2 TF_APPLY_RC=0
  beh "teardown (E-4): the 'wipe' server fails the identity pin (${v}) => refused by the gate with wipe_server_identity, never applied" 1 "reason=wipe_server_identity"
  if ! grep -q 'apply -no-color' "$SB/tf.log"; then pass; else fail "BEHAVIOUR: an identity-refused teardown plan must not be applied" "" "$(cat "$SB/tf.log")"; fi
done
cp "$SB/tf.show.ok" "$SB/tf.show"
TD_ENV=(RETIRE_PHASE=teardown); : > "$SB/tf.log"; td TF_PLAN_RC=2 TF_APPLY_RC=0
beh "teardown phase: the same step applies the legal plan (phase=teardown)" 0 ""
TD_ENV=(RETIRE_PHASE=wipe)
cp "$SB/tf.show.bad" "$SB/tf.show"
mutrow_accept "G10c: the teardown gate call's refusal neutered" "Teardown of the wipe host" '(only deletes of the two wipe addresses are legal)."; exit 1' '(only deletes of the two wipe addresses are legal)."' RETIRE_PHASE=wipe TF_PLAN_RC=2 TF_APPLY_RC=0

# ---- the read-back and the progress comment (W1, W9, W2-8, W2-11) ----
rb() { run_step "Read-back" "$@"; }
hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 200 '{"servers":[]}'; rb RETIRE_PHASE=detach
beh "read-back detach: detached => records the rollback boundary" 0 "detached; rollback ends here"
hzreset; hzset "$HZ_VOL" 200 "$(vol_json 169426216)"; hzset "$HZ_WS" 200 '{"servers":[]}'; rb RETIRE_PHASE=detach
beh "read-back detach: still attached => fails and records it" 1 "is still attached"
if grep -q 'READ-BACK FAILED' "$SB/rt/readback.txt"; then pass; else fail "BEHAVIOUR: a failed read-back must be recorded for the progress comment" "" "$(cat "$SB/rt/readback.txt" 2>/dev/null)"; fi
hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 500; rb RETIRE_PHASE=detach
beh "read-back: the wipe-server listing answers 500 => fails, naming the code" 1 "wipe-server listing answered 500"
hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 200 '{"servers":[{"id":777}]}'; rb RETIRE_PHASE=wipe
beh "read-back wipe: a wipe host still exists => fails" 1 "a wipe host still exists"
hzreset; hzset "$HZ_VOL" 200 "$(vol_json 777)"; hzset "$HZ_WS" 200 '{"servers":[]}'; rb RETIRE_PHASE=wipe
beh "read-back wipe: the volume is attached to a server again after the wipe => fails" 1 "is not detached again"
hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 200 '{"servers":[]}'; rb RETIRE_PHASE=wipe
beh "read-back wipe: host gone, volume detached again => PASS" 0 "wipe host and attachment gone"
hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 200 '{"servers":[{"id":777}]}'; rb RETIRE_PHASE=teardown
beh "read-back teardown: a wipe host still exists => fails" 1 "a wipe host still exists"
printf '{"resource_changes":[]}' > "$SB/tf.show"
hzreset; hzset "$HZ_VOL" 404; hzset "$HZ_WS" 200 '{"servers":[]}'; hzset "$HZ_SRV" 200 "{\"servers\":[{\"id\":169426216,\"volumes\":[${LIVEV}]}]}"; rb RETIRE_PHASE=destroy TF_PLAN_RC=0 APPLY=skipped
beh "read-back destroy on the 404 shortcut (apply skipped): 404, the host holds only the live volume, no retired address => PASS" 0 "untargeted plan lists neither retired address"
hzreset; hzset "$HZ_VOL" 404; hzset "$HZ_WS" 200 '{"servers":[]}'; hzset "$HZ_SRV" 200 "{\"servers\":[{\"id\":169426216,\"volumes\":[${LIVEV},${PIN}]}]}"; rb RETIRE_PHASE=destroy TF_PLAN_RC=0
beh "read-back destroy: the host also lists the retired volume => fails" 1 "inngest server volumes"
hzreset; hzset "$HZ_VOL" 404; hzset "$HZ_WS" 200 '{"servers":[]}'; hzset "$HZ_SRV" 200 "{\"servers\":[{\"id\":169426216,\"volumes\":[${LIVEV}]}]}"; rb RETIRE_PHASE=destroy TF_PLAN_RC=1
beh "read-back destroy: the read-only untargeted plan fails => fails" 1 "read-only untargeted plan failed"
printf '{"resource_changes":[{"address":"hcloud_volume.inngest_redis","change":{"actions":["delete"]}}]}' > "$SB/tf.show"
hzreset; hzset "$HZ_VOL" 404; hzset "$HZ_WS" 200 '{"servers":[]}'; hzset "$HZ_SRV" 200 "{\"servers\":[{\"id\":169426216,\"volumes\":[${LIVEV}]}]}"; rb RETIRE_PHASE=destroy TF_PLAN_RC=0
beh "read-back destroy: a retired address is still in the plan => fails" 1 "a retired address is still in the plan"
hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 200 '{"servers":[]}'; rb RETIRE_PHASE=destroy TF_PLAN_RC=0
beh "read-back destroy: the volume still answers 200 after an apply => fails" 1 "expected 404"
hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 200 '{"servers":[]}'; rb RETIRE_PHASE=destroy TF_PLAN_RC=0 APPLY=skipped
beh "W2-8: the destroy apply never ran (a gate refused) => 'destroy not applied', not a failed destroy" 0 "destroy not applied" "READ-BACK FAILED"
if ! grep -q 'READ-BACK FAILED' "$SB/rt/readback.txt"; then pass; else fail "W2-8: a refused destroy must not leave READ-BACK FAILED in the progress comment's record" "" "$(cat "$SB/rt/readback.txt")"; fi
prog() { rm -f "$SB/gh-issue.txt"; echo "$1" > "$SB/clock"; run_step "Progress comment" SB_CLOCK="$SB/clock" RETIRE_PHASE="$2" JOB_STATUS="$3" RUN_URL=u "${@:4}"; }
mkdir -p "$SB/rt"; printf 'volume x detached' > "$SB/rt/readback.txt"
# the clock is a SEAM (SB_CLOCK): the date stub answers `date -u +%s` from it (+60 per call), so no row reads the real clock
EXP_EP="$(date -u -d 2026-10-22 +%s)"
gh_issue() { cat "$SB/gh-issue.txt" 2>/dev/null; }
prog 1760000000 wipe failure
if [[ "$SRC" -eq 0 && "$(gh_issue)" == *"D4 decision point (wipe not yet succeeded): 2026-10-17."* && "$(gh_issue)" == *"Read-back: volume x detached"* ]]; then pass; else fail "BEHAVIOUR: a FAILED wipe's progress comment carries the D4 point and the read-back" "$SRC" "$(gh_issue) $SOUT"; fi
prog 1760000000 wipe success
if [[ "$SRC" -eq 0 && "$(gh_issue)" != *"D4 decision"* ]]; then pass; else fail "W2-11: a SUCCESSFUL wipe drops the D4 sentence" "$SRC" "$(gh_issue)"; fi
prog 1760000000 detach success
if [[ "$SRC" -eq 0 && "$(gh_issue)" == *"D4 decision point"* ]]; then pass; else fail "W2-11: phase=detach (the wipe is still to come) carries the D4 sentence" "$SRC" "$(gh_issue)"; fi
for ph in teardown destroy; do
  prog 1760000000 "$ph" failure
  if [[ "$SRC" -eq 0 && "$(gh_issue)" != *"D4 decision"* && "$(gh_issue)" == *"day(s) to the non-extendable 2026-10-22"* ]]; then pass; else fail "W2-11: phase=${ph} never carries the D4 sentence" "$SRC" "$(gh_issue)"; fi
done
prog $((EXP_EP - 3 * 86400 - 70)) wipe success
if [[ "$SRC" -eq 0 && "$(gh_issue)" == *$'\n\n3 day(s) to the non-extendable 2026-10-22 ledger expiry.'* ]]; then pass; else fail "BEHAVIOUR: 3 days and 10 s left prints 3 day(s)" "$SRC" "$(gh_issue)"; fi
prog $((EXP_EP - 60)) wipe success
if [[ "$SRC" -eq 0 && "$(gh_issue)" == *$'\n\n0 day(s) to the non-extendable'* ]]; then pass; else fail "BEHAVIOUR: exactly at the expiry instant is 0 day(s), not OVERDUE" "$SRC" "$(gh_issue)"; fi
prog $((EXP_EP - 59)) wipe success
if [[ "$SRC" -eq 0 && "$(gh_issue)" == *"OVERDUE by 1 day(s)"* ]]; then pass; else fail "W2-11: one second past the expiry is OVERDUE by 1 day(s)" "$SRC" "$(gh_issue)"; fi
prog 1800000000 wipe success
if [[ "$SRC" -eq 0 && "$(gh_issue)" == *"OVERDUE by 86 day(s)"* && "$(gh_issue)" != *"-"[0-9]*"day(s)"* ]]; then pass; else fail "W2-11: a past expiry (pinned clock 1800000000 = 2027-01-15) prints OVERDUE by 86 day(s), never a negative number" "$SRC" "$(gh_issue)"; fi
prog $((EXP_EP + 2 * 86400 - 60)) wipe success
if [[ "$SRC" -eq 0 && "$(gh_issue)" == *"OVERDUE by 2 day(s)"* ]]; then pass; else fail "W2-11: exactly two days past is OVERDUE by 2 day(s)" "$SRC" "$(gh_issue)"; fi

# ── REJECT-CONTROLS for the verdict helpers lsg / dpc / evg (W5): drive each in a direction that MUST
#    fail (a good call asserted to refuse, a refusing call asserted to pass, a wrong reason) and require
#    exactly one recorded failure, then unwind. Reported with printf + exit, never through the helper
#    it back-stops: a helper that cannot fail would otherwise make every row in this file decorative. ──
reject_control() { # <label> <helper> <args...>
  local label="$1" p0=$passes f0=$fails; shift
  "$@" >/dev/null 2>&1
  if [[ "$fails" -ne $((f0 + 1)) || "$passes" -ne "$p0" ]]; then
    printf 'FATAL: reject-control "%s": the helper did not fail exactly once on a must-fail arm (passes %s->%s, fails %s->%s)\n' "$label" "$p0" "$passes" "$f0" "$fails" >&2
    exit 2
  fi
  passes=$p0; fails=$f0; pass
}
reject_control "lsg: a good call asserted as a refusal" lsg "x" 1 "reason=flag_not_done"
reject_control "lsg: a refusing call asserted as a PASS" lsg "x" 0 "$LS_PASS" "flag=rollback"
reject_control "lsg: a refusing call asserted with the wrong reason" lsg "x" 1 "reason=probe_stale" "flag=rollback"
reject_control "dpc: a good call asserted as a refusal" dpc "x" 1 "reason=not_wiped"
reject_control "dpc: a refusing call asserted as a PASS" dpc "x" 0 "$DP_PASS" "run=12ab"
reject_control "dpc: a refusing call asserted with the wrong reason" dpc "x" 1 "reason=still_attached" "run=12ab"
reject_control "evg: a good call asserted as a refusal" evg "x" "reason=not_wiped" --rows-file "$EV" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now "$NOW4"
reject_control "evg: a refusing call asserted with the wrong reason" evg "x" "reason=not_wiped" --rows-file "$EV" --nonce abc --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now "$NOW4"
reject_control "evok: a refusing call asserted as a PASS" evok "x" "$EV" "$NOW4" $((ROW_EPOCH + 1))
# the rc conjunct and the one_line conjunct of each helper, varied ONE AT A TIME against a function that satisfies the rest
two_line_refuse() { echo "stub reason=flag_not_done"; echo "a second line"; return 1; }
pass_rc1() { echo "stub PASS inngest_backstop_live_store_gate: PASS inngest_backstop_destroy_precondition: PASS evidence_gate: PASS"; return 1; }
lsg_two() { LSG_FN=two_line_refuse lsg "$@"; }
dpc_two() { DPC_FN=two_line_refuse dpc "$@"; }
evg_two() { EVG_FN=two_line_refuse evg "$@"; }
lsg_rc() { LSG_FN=pass_rc1 lsg "$@"; }
dpc_rc() { DPC_FN=pass_rc1 dpc "$@"; }
evok_rc() { EVG_FN=pass_rc1 evok "$@"; }
reject_control "lsg rc conjunct: a PASS-text output with rc 1 asserted as a PASS" lsg_rc "x" 0 "$LS_PASS"
reject_control "lsg one_line conjunct: two lines asserted as one refusal" lsg_two "x" 1 "reason=flag_not_done"
reject_control "dpc rc conjunct: a PASS-text output with rc 1 asserted as a PASS" dpc_rc "x" 0 "$DP_PASS"
reject_control "dpc one_line conjunct: two lines asserted as one refusal" dpc_two "x" 1 "reason=flag_not_done"
reject_control "evg one_line conjunct: two lines asserted as one refusal" evg_two "x" "reason=flag_not_done" --rows-file "$EV"
reject_control "evg rc conjunct: a refusing call asserted... the good call (rc 0) with a matching needle" evg "x" "evidence_gate: PASS" --rows-file "$EV" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$AFTER_EPOCH" --now "$NOW4"
reject_control "evok rc conjunct: a PASS-text output with rc 1 asserted as a PASS" evok_rc "x" "$EV" "$NOW4" "$AFTER_EPOCH"
# ── reject-controls for `beh` (it reads SOUT/SRC): drop the rc conjunct, the UNEXPECTED check, the absent-needle check ──
SOUT="has needle"; SRC=1;  reject_control "beh rc conjunct: rc 1 asserted as rc 0" beh "x" 0 "has needle"
SOUT="has needle UNEXPECTED hz foo"; SRC=0; reject_control "beh UNEXPECTED conjunct: a stub that saw an unexpected call" beh "x" 0 "has needle"
SOUT="has needle and BADTHING"; SRC=0; reject_control "beh absent-needle conjunct: the forbidden text is present" beh "x" 0 "has needle" "BADTHING"
SOUT="no match"; SRC=0; reject_control "beh needle conjunct: the needle is absent" beh "x" 0 "has needle"
# the run_step mutation helpers must be able to fail too
SRC=0; SOUT="fine"
reject_control "mutrow_red: a mutation that leaves the step green" mutrow_red "x" "Dispatch summary" "GITHUB_STEP_SUMMARY" "GITHUB_STEP_SUMMARY" RETIRE_PHASE=detach GITHUB_STEP_SUMMARY="$SB/summary.md" JOB_STATUS=success RUN_URL=u
reject_control "mutrow_accept: a mutation that still refuses (or does not land)" mutrow_accept "x" "Dispatch summary" "THIS-LITERAL-IS-NOT-IN-THE-BODY" "y"
STEP_MUT_OLD=""

# ── H (suite edit): replace the sourced lib with an ALWAYS-PASS stub; THIS suite must fail, loudly ──
# rc must be exactly 1 (a FATAL 2 or a crash would also be "non-zero") and the stub must trip at least META_MIN rows.
META_MIN=150
if [[ -z "${SOLEUR_IBRG_META:-}" ]]; then
  STUBLIB="$TMP/stub-lib.sh"
  cat > "$STUBLIB" <<'STUB'
inngest_backstop_retire_gate() { echo "inngest_backstop_retire_gate: PASS (stub)"; return 0; }
inngest_backstop_live_store_gate() { echo "inngest_backstop_live_store_gate: PASS (stub)"; return 0; }
inngest_backstop_destroy_precondition() { echo "inngest_backstop_destroy_precondition: PASS (stub)"; return 0; }
inngest_backstop_wipe_evidence_gate() { echo "inngest_backstop_wipe_evidence_gate: PASS (stub)"; return 0; }
inngest_backstop_wipe_nonce_rows() { return 0; }
STUB
  meta_rc=0; meta_out="$(SOLEUR_IBRG_META=1 INNGEST_BACKSTOP_GATE_LIB="$STUBLIB" bash "${BASH_SOURCE[0]}" 2>/dev/null)" || meta_rc=$?
  meta_f="$(sed -n 's/^inngest-backstop-retire-gate: [0-9]* passed, \([0-9]*\) failed$/\1/p' <<<"$meta_out" | tail -1)"
  if [[ "$meta_rc" -eq 1 && "$meta_f" =~ ^[0-9]+$ && "$meta_f" -ge "$META_MIN" ]]; then pass; else fail "H: with an always-pass stub lib this suite must exit EXACTLY 1 with >= ${META_MIN} failed rows -- the must-RED rows are decorative (rc=${meta_rc}, failed='${meta_f}')"; fi
fi

# ── Anti-vacuity: EXACT floors. The assertion total and the executed must-PASS arms are pinned to the numbers this suite
#    produces; adding or deleting a row means raising or lowering them in the SAME edit. ──
EXPECTED_TOTAL=660
EXPECTED_MP=77
_ran=$((passes + fails))
if [[ "$mp" -ne "$EXPECTED_MP" ]]; then fails=$((fails + 1)); printf '  FAIL ANTI-VACUITY: %s must-PASS arms executed and passed, expected exactly %s (a guard stuck at "reject everything" would hide in the gap)\n' "$mp" "$EXPECTED_MP" >&2
else printf '  ok   must-PASS arms executed: %s\n' "$mp"; fi
_ran=$((passes + fails))
if [[ "$_ran" -ne "$EXPECTED_TOTAL" ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: %s assertions ran, expected exactly %s. Arms were deleted, skipped, added without raising the floor, or the suite exited early.\n' "$_ran" "$EXPECTED_TOTAL" >&2
else
  printf '  ok   anti-vacuity: exactly %s assertions ran\n' "$_ran"
fi
echo ""
echo "inngest-backstop-retire-gate: ${passes} passed, ${fails} failed"
[[ "$fails" -eq 0 ]]
