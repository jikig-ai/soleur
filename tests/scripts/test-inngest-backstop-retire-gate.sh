#!/usr/bin/env bash
# Tests for tests/scripts/lib/inngest-backstop-retire-gate.sh (sourced by the inngest_backstop_retire
# job in .github/workflows/apply-web-platform-infra.yml, #8285).
#
# FIVE FUNCTIONS ARE GRADED, each the SAME bytes the workflow sources:
#   inngest_backstop_retire_gate        plan SHAPE per phase (Guard 2) -- detach | wipe | teardown | destroy
#   inngest_backstop_live_store_gate    the live-store chokepoint in front of phases detach | wipe | destroy (plan 2.0)
#   inngest_backstop_destroy_precondition   evidence-before-destroy (Guard 4), incl. the D4 alternative
#   inngest_backstop_wipe_evidence_gate     the evidence funnel (the wipe poll and Guard 4 share it)
#   inngest_backstop_wipe_nonce_rows        the poll's refusal short-circuit (rows bearing the nonce)
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
WSRV_DEL="$(ent 'hcloud_server.inngest_backstop_wipe[0]' '["delete"]' '{"id":"777"}' null)"
WATT_DEL="$(ent 'hcloud_volume_attachment.inngest_backstop_wipe[0]' '["delete"]' "{\"id\":\"778\",\"volume_id\":${PIN}}" null)"

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
  if [[ "$rc" -eq "$want" && "$out" == *"$needle"* ]]; then pass; else fail "$name (want rc=$want containing '$needle')" "$rc" "$out"; fi
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
write_plan "$(ent 'hcloud_server.inngest_backstop_wipe' '["create"]' null),$(ent 'hcloud_volume_attachment.inngest_backstop_wipe' '["create"]' null "{\"volume_id\":\"${PIN}\"}")"
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
chk "Row 10d: untargeted ignores other resources' updates (the web-1 set is graded by the TARGETED gate and the post-apply loop)" 0 "$PASS_TOK" destroy "$PIN" untargeted
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
LUKS_OK="$FIX/luks.json"
printf '{"volume":{"id":%s,"name":"soleur-inngest-redis-store-luks","server":%s,"size":10}}\n' "$LIVEV" "$SRVID" > "$LUKS_OK"
probe_row() { # <iso dt> <devid> <redis_active> -> TSV row as the workflow's selection emits it
  printf '%s\tSOLEUR_INNGEST_SERVER_PROBE host_role=dedicated data_mount_src=/dev/mapper/inngest-redis data_mount_devid=%s redis_active=%s redis_keys=3\n' "$1" "$2" "$3"
}
PROBE_OK="$FIX/probe.tsv"
probe_row '2026-10-13 11:10:00' "scsi-0HC_Volume_${LIVEV}" active > "$PROBE_OK"

lsg() { # <name> <want_rc> <needle> [overrides: flag= active= luks= probe= inflight= server=]
  local name="$1" want="$2" needle="$3"; shift 3
  local flag="done" active="$LIVEV" luks="$LUKS_OK" probe="$PROBE_OK" inflight=0 server="$SRVID" kv out rc=0
  for kv in "$@"; do
    case "$kv" in
      flag=*) flag="${kv#flag=}" ;; active=*) active="${kv#active=}" ;; luks=*) luks="${kv#luks=}" ;;
      probe=*) probe="${kv#probe=}" ;; inflight=*) inflight="${kv#inflight=}" ;; server=*) server="${kv#server=}" ;;
    esac
  done
  out="$(inngest_backstop_live_store_gate --cutover-flag "$flag" --active-id "$active" --luks-volume-file "$luks" \
    --probe-file "$probe" --now "$NOW_EPOCH" --inflight-runs "$inflight" --server-id "$server" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$want" && "$out" == *"$needle"* ]] && { [[ "$want" -eq 0 ]] || one_line "$out"; }; then pass; else fail "$name (want rc=$want containing '$needle', one line)" "$rc" "$out"; fi
}
LS_PASS="inngest_backstop_live_store_gate: PASS"
lsg "LS PASS: flag done, pointer on the LUKS volume, attached, fresh probe on it, no run in flight" 0 "$LS_PASS"
# Guard 4 row 7 -- the chokepoint guards detach/wipe too, so any non-`done` flag value is refused.
for v in rollback rolled-back armed copying "" "__UNREADABLE__" "DONE" "done " "done;x"; do
  lsg "LS flag '${v}' => flag_not_done (row 7)" 1 "reason=flag_not_done" "flag=${v}"
done
lsg "LS pointer on the RETIRED volume => active_id_mismatch" 1 "reason=active_id_mismatch" "active=${PIN}"
lsg "LS pointer empty => active_id_mismatch" 1 "reason=active_id_mismatch" "active="
lsg "LS pointer is a prefix => active_id_mismatch" 1 "reason=active_id_mismatch" "active=10690326"
# Hetzner reads are ADVERSARIAL: a 200 with a degraded body must fail closed.
printf 'not json' > "$FIX/l1.json";                              lsg "LS luks body not JSON => luks_volume_unreadable" 1 "reason=luks_volume_unreadable" "luks=$FIX/l1.json"
printf '{}' > "$FIX/l2.json";                                    lsg "LS luks body {} => luks_volume_unreadable" 1 "reason=luks_volume_unreadable" "luks=$FIX/l2.json"
printf '{"volume":null}' > "$FIX/l3.json";                       lsg "LS luks volume null => luks_volume_unreadable" 1 "reason=luks_volume_unreadable" "luks=$FIX/l3.json"
printf '{"volume":{"id":%s}}' "$LIVEV" > "$FIX/l4.json";         lsg "LS luks volume without a server key => luks_volume_unreadable" 1 "reason=luks_volume_unreadable" "luks=$FIX/l4.json"
printf '{"volume":{"id":%s,"server":null}}' "$LIVEV" > "$FIX/l5.json"; lsg "LS luks volume DETACHED (server null) => luks_not_attached" 1 "reason=luks_not_attached" "luks=$FIX/l5.json"
printf '{"volume":{"id":%s,"server":999}}' "$LIVEV" > "$FIX/l6.json";   lsg "LS luks volume attached to ANOTHER server => luks_not_attached" 1 "reason=luks_not_attached" "luks=$FIX/l6.json"
printf '{"volume":{"id":%s,"server":%s}}' "$PIN" "$SRVID" > "$FIX/l7.json"; lsg "LS the volume answered is not the LUKS volume => luks_identity_mismatch" 1 "reason=luks_identity_mismatch" "luks=$FIX/l7.json"
printf '{"volume":{"id":"%s","server":"%s"}}' "$LIVEV" "$SRVID" > "$FIX/l8.json"; lsg "LS string ids compare equal to the numeric pin => PASS" 0 "$LS_PASS" "luks=$FIX/l8.json"
lsg "LS luks file missing => luks_volume_unreadable" 1 "reason=luks_volume_unreadable" "luks=$FIX/none.json"
lsg "LS server id empty => luks_not_attached" 1 "reason=luks_not_attached" "server="
lsg "LS server id not numeric => luks_not_attached" 1 "reason=luks_not_attached" "server=abc"
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
# In-flight apply.
lsg "LS another apply in flight => inflight_apply" 1 "reason=inflight_apply" "inflight=1"
lsg "LS in-flight count unreadable => inflight_apply" 1 "reason=inflight_apply" "inflight=__UNREADABLE__"
lsg "LS in-flight count empty => inflight_apply" 1 "reason=inflight_apply" "inflight="
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
clo_file() { # <path> <author_association> <body>  [id] [issue_url]
  jq -cn --argjson id "${4:-$CLO_ID}" --arg a "$2" --arg b "$3" --arg iu "${5:-https://api.github.com/repos/jikig-ai/soleur/issues/8285}" \
    '{id: $id, issue_url: $iu, author_association: $a, body: $b}' > "$1"
}
CLO_OK="$FIX/clo-ok.json"; clo_file "$CLO_OK" OWNER "CLO attestation: provider-only deletion of volume ${PIN} accepted; no overwrite is evidenced."

dp_args() { # [overrides: erasure= run= clo= clofile= rows= vol= acts= livesrv= after= now=] -> DPA (the precondition's argv)
  local erasure="" run="$NONCE" clo="" clofile="" rows="$EV" vol="$VOL_FILE" acts="$ACTS_OK" livesrv="$LIVE_SRV" after="$AFTER_EPOCH" now="$NOW4" kv
  for kv in "$@"; do
    case "$kv" in
      erasure=*) erasure="${kv#erasure=}" ;; run=*) run="${kv#run=}" ;; clo=*) clo="${kv#clo=}" ;; clofile=*) clofile="${kv#clofile=}" ;;
      rows=*) rows="${kv#rows=}" ;; vol=*) vol="${kv#vol=}" ;; acts=*) acts="${kv#acts=}" ;; livesrv=*) livesrv="${kv#livesrv=}" ;;
      after=*) after="${kv#after=}" ;; now=*) now="${kv#now=}" ;;
    esac
  done
  DPA=(--erasure "$erasure" --wipe-run-id "$run" --clo-attestation-ref "$clo" --clo-comment-file "$clofile" --rows-file "$rows" --volume-file "$vol"
       --actions-file "$acts" --live-server-id "$livesrv" --after-epoch "$after" --now "$now")
}
dpc() { # <name> <want_rc> <needle> [overrides, see dp_args]
  local name="$1" want="$2" needle="$3" out rc=0; shift 3
  dp_args "$@"
  out="$(inngest_backstop_destroy_precondition "${DPA[@]}" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$want" && "$out" == *"$needle"* ]] && { [[ "$want" -eq 0 ]] || one_line "$out"; }; then pass; else fail "$name (want rc=$want containing '$needle', one line)" "$rc" "$out"; fi
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
dpc "G4 row 6c: row older than the detach/run floor => evidence_stale" 1 "reason=evidence_stale" "after=$(date -u -d '2026-10-15T09:30:00Z' +%s)"
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
# fetched through the GitHub API (by id) and must come from OWNER|MEMBER|COLLABORATOR and name the volume.
D4=("erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$CLO_OK")
dpc "G4 D4: erasure=provider-only + an attested comment + no wipe run => PASS" 0 "$DP_PASS" "${D4[@]}"
dpc "G4 D4: PASS needs no Hetzner action history (nothing was wiped)" 0 "$DP_PASS" "${D4[@]}" "acts=$FIX/none.json"
for assoc in MEMBER COLLABORATOR; do
  clo_file "$FIX/clo-$assoc.json" "$assoc" "attested: volume ${PIN}"
  dpc "G4 D4: author_association ${assoc} => PASS" 0 "$DP_PASS" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-$assoc.json"
done
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
for assoc in NONE CONTRIBUTOR FIRST_TIME_CONTRIBUTOR FIRST_TIMER MANNEQUIN owner ""; do
  clo_file "$FIX/clo-a.json" "$assoc" "attested: volume ${PIN}"
  dpc "G4 D4: author_association '${assoc}' => clo_author_not_privileged" 1 "reason=clo_author_not_privileged" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-a.json"
done
clo_file "$FIX/clo-b.json" OWNER "attested, no volume named"
dpc "G4 D4: the body does not name the volume => clo_body_missing_volume" 1 "reason=clo_body_missing_volume" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-b.json"
clo_file "$FIX/clo-c.json" OWNER "volume ${PIN}0 and 1${PIN}"
dpc "G4 D4: the id only as part of a longer number => clo_body_missing_volume" 1 "reason=clo_body_missing_volume" "erasure=provider-only" "run=" "clo=$CLO_URL" "clofile=$FIX/clo-c.json"
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
dpc "G4 D-A: a detach finishing at the same second as the attach counts (>=) => PASS" 0 "$DP_PASS" "acts=$FIX/a9.json"
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

# ── Usage and operand hygiene: an unknown option, a missing clock, direct evidence-gate misuse ──
for fn in inngest_backstop_live_store_gate inngest_backstop_destroy_precondition inngest_backstop_wipe_evidence_gate; do
  out="$("$fn" --bogus x 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 1 && "$out" == *"reason=usage"* ]] && one_line "$out"; then pass; else fail "usage: ${fn} must refuse an unknown option" "$rc" "$out"; fi
done
out="$(inngest_backstop_live_store_gate --cutover-flag "done" --active-id "$LIVEV" --luks-volume-file "$LUKS_OK" --probe-file "$PROBE_OK" --inflight-runs 0 --server-id "$SRVID" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 1 && "$out" == *"reason=probe_unusable"* ]]; then pass; else fail "LS: a missing --now (no clock) must fail closed" "$rc" "$out"; fi
out="$(inngest_backstop_live_store_gate --cutover-flag "done" --active-id "$LIVEV" --luks-volume-file "$LUKS_OK" --probe-file "$PROBE_OK" --now abc --inflight-runs 0 --server-id "$SRVID" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 1 && "$out" == *"reason=probe_unusable"* ]]; then pass; else fail "LS: a non-numeric --now must fail closed" "$rc" "$out"; fi
evg() { # <name> <want-needle> then evidence-gate args
  local name="$1" needle="$2"; shift 2; local out rc=0
  out="$(inngest_backstop_wipe_evidence_gate "$@" 2>&1)" || rc=$?
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
  o="$(inngest_backstop_wipe_evidence_gate --rows-file "$rf" --nonce "$NONCE" --volume-id "$PIN" --size-bytes "$SIZE_BYTES" --after-epoch "$af" --now "$nw" 2>&1)" || r=$?
  if [[ "$r" -eq 0 && "$o" == *"evidence_gate: PASS"* ]]; then pass; else fail "$name" "$r" "$o"; fi
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
dmut "MUT Hetzner corroboration: a history with no wipe-host attach passes" 's/^  case "\$hres" in/  case "ok" in/' "acts=$FIX/a1.json"
dmut "MUT live-server exclusion: an attach to the LIVE server passes" 's/(\.s | any(\. != \$live))/(.s | any(true))/' "acts=$FIX/a3.json"
dmut "MUT attach floor: an attach from before the wipe run started passes" 's/\.c == "attach_volume" and \.f >= \$after and/.c == "attach_volume" and/' "acts=$FIX/a2.json"
dmut "MUT attach status: attaches that did not succeed pass" 's/select(\.status == "success")/select(true)/' "acts=$FIX/a5.json"
dmut "MUT detach requirement: attached-never-detached passes" 's/ == 0 then "no_wipe_detach"/ == -1 then "no_wipe_detach"/' "acts=$FIX/a6.json"
dmut "MUT detach ordering: a detach from BEFORE the attach passes" 's/\.c == "detach_volume" and \.f >= (\$att | map(\.f) | min)/.c == "detach_volume"/' "acts=$FIX/a7.json"
clo_file "$FIX/clo-a.json" NONE "attested: volume ${PIN}"
dmut "MUT CLO author (NONE fixture): author_association NONE passes" 's/IN("OWNER", "MEMBER", "COLLABORATOR")/IN("OWNER", "MEMBER", "COLLABORATOR", "NONE")/' "${D4[@]:0:3}" "clofile=$FIX/clo-a.json"
dmut "MUT CLO body: a comment that does not name the volume passes" 's/test("(^|\[^0-9\])" + \$v + "(\[^0-9\]|\$)")/test("")/' "${D4[@]:0:3}" "clofile=$FIX/clo-b.json"
dlay "MUT CLO ref pattern: an arbitrary host is then refused only by the comment-id binding" 's|^    if \[\[ ! "\$clo" =~ .*|    if false; then|' "reason=clo_ref_invalid" "reason=clo_comment_unreadable" "${D4[@]:0:3}" "clo=https://example.test/x" "clofile=$CLO_OK"

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

# ── Row 5 / ordering and wiring, asserted against the workflow text ────────────────
WF="${REPO_ROOT}/.github/workflows/apply-web-platform-infra.yml"
wf_py() { python3 -I - "$WF" 2>&1; }
WF_FACTS="$(wf_py <<'PY'
import sys, yaml, json
wf = yaml.safe_load(open(sys.argv[1]))
job = wf["jobs"].get("inngest_backstop_retire")
out = {"job": bool(job)}
if job:
    steps = job["steps"]
    names = [s.get("name", "") for s in steps]
    out["names"] = names
    out["env"] = job.get("environment")
    out["conc"] = job.get("concurrency")
    out["if"] = job.get("if")
    out["wfconc"] = wf.get("concurrency")
    out["perm"] = job.get("permissions")
    out["bodies"] = {s.get("name", ""): s.get("run", "") for s in steps}
    out["ifs"] = {s.get("name", ""): s.get("if", "") for s in steps}
    out["uses"] = [s.get("uses", "") for s in steps]
    out["opts"] = wf[True]["workflow_dispatch"]["inputs"]["apply_target"]["options"] if True in wf else wf["on"]["workflow_dispatch"]["inputs"]["apply_target"]["options"]
    inp = wf[True]["workflow_dispatch"]["inputs"] if True in wf else wf["on"]["workflow_dispatch"]["inputs"]
    out["inputs"] = sorted(inp.keys())
out["old_job_present"] = "inngest_volume_recut" in wf["jobs"]
print(json.dumps(out))
PY
)"
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

# ══ THE WORKFLOW'S run: BODIES (W3, D-A..D-E) ═══════════════════════════════════════
# Each step's `run:` is extracted with PyYAML (no escape processing, exactly what bash receives) and the
# decisions that make the gates bite are pinned as ANCHORED, comment-stripped lines or exact `if:` strings:
# the destroy precondition's condition, no continue-on-error on any gate step, `exit 1` before `fi` at each of the
# five gate call sites, the poll's `[[ "$OK" == 1 ]] ||`, the wipe-phase detach guard, the convergence read of the
# pinned volume, the provenance clause, the nonce, the post-apply untouched loop, the teardown rc handling.
# The pin program ALSO carries a mutation table: every pin is mutated out of a copy of the real workflow and must
# go RED (a pin that its mutation does not trip is decorative). The first line is the CONTROL on the real workflow.
PINS_PY="$TMP/wf-pins.py"
assert_fixture_dir "$TMP"
cat > "$PINS_PY" <<'PINS'
import sys, re, json
import yaml

def load(text):
    return yaml.load(text, Loader=getattr(yaml, "CSafeLoader", yaml.SafeLoader))

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
    L = {k: lines(v) for k, v in dict(live=live, conv=conv, pre=pre, unt=unt, plan=plan, apply_=apply_, poll=poll, tear=tear, back=back, valid=valid).items()}
    # --- exact `if:` strings
    pin("if_destroy_precondition", pre.get("if") == "env.RETIRE_PHASE == 'destroy' && steps.conv.outputs.skip != 'true'")
    pin("if_live_store_not_teardown", live.get("if") == "env.RETIRE_PHASE != 'teardown'")
    pin("if_readback_always", back.get("if") == "always() && steps.conv.outcome == 'success' && steps.conv.outputs.skip != 'true'")
    pin("if_teardown_always", str(tear.get("if", "")).startswith("always() && steps.conv.outcome == 'success' && steps.conv.outputs.skip != 'true'"))
    pin("if_poll_wipe_only", poll.get("if") == "env.RETIRE_PHASE == 'wipe' && steps.conv.outputs.skip != 'true'")
    pin("if_unt_plan_skip", unt.get("if") == "steps.conv.outputs.skip != 'true'")
    pin("if_apply_not_teardown", apply_.get("if") == "steps.conv.outputs.skip != 'true' && env.RETIRE_PHASE != 'teardown'")
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
    # --- the poll
    pl = L["poll"]
    pin("poll_ok_required", any(l.startswith('[[ "$OK" == 1 ]] || {') and "exit 1" in l for l in pl))
    pin("poll_deadline", 'DEADLINE=$(( $(date -u +%s) + 1200 ))' in " ".join(pl) and 'while (( $(date -u +%s) < DEADLINE )); do' in pl)
    pin("poll_no_archive_hot_only", any("betterstack-query.sh" in l and "--no-archive" in l and "--since 1h" in l for l in pl))
    pin("poll_breaks_on_refusal", "grep -qF ' result=refused ' <<<\"$MSGS\" && break" in pl)
    pin("poll_query_error_printed", any("poll query failed rc=$?" in l for l in pl))
    pin("poll_gate_inputs", any(l.startswith("if inngest_backstop_wipe_evidence_gate ") and '--nonce "$GITHUB_RUN_ID"' in l and '--after-epoch "$JOB_START"' in l and "OK=1; break" in l for l in pl))
    # --- convergence
    cv = L["conv"]
    pin("conv_wipe_requires_detached", any(l.startswith('[[ "$VS" == null ]] || fail') for l in cv))
    wi = [i for i, l in enumerate(cv) if l == "wipe)"]; te = [i for i, l in enumerate(cv) if l == "teardown)"]
    gi = [i for i, l in enumerate(cv) if l.startswith('[[ "$VS" == null ]] || fail')]
    pin("conv_wipe_guard_in_wipe_arm", bool(wi and te and gi and wi[0] < gi[0] < te[0]))
    pin("conv_reads_the_pinned_volume", any(l.startswith('VC="$(hz "volumes/${EXPECTED_INNGEST_VOLUME_ID}" ') for l in cv))
    pin("conv_reconcile_exact_delta", '[[ "$DEL" == "$a" && -z "$ADD" ]] || fail "the refresh of ${a} changed state beyond it: dropped=\'${DEL}\' added=\'${ADD}\'"' in cv
        and any(l.startswith('DEL="$(comm -23 ') and "ADD=\"$(comm -13 " in l for l in cv))
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
    pin("pre_clo_strict_pattern", any("https://github\\.com/jikig-ai/soleur/issues/8285#issuecomment-([0-9]+)$" in l for l in pr) and any("issues/comments/${BASH_REMATCH[1]}" in l for l in pr))
    pin("pre_no_http_code_path", not any("clo-ref-http-code" in l or "%{http_code}" in l for l in pr))
    # --- plan / apply
    pp = L["plan"]
    pin("plan_nonce_is_run_id", any('-var="inngest_backstop_wipe_nonce=${GITHUB_RUN_ID}"' in l and "-var='inngest_backstop_wipe_enabled=true'" in l for l in pp))
    pin("plan_exact_targets_wipe", any("-target=hcloud_server.inngest_backstop_wipe -target=hcloud_volume_attachment.inngest_backstop_wipe" in l for l in pp))
    ap = L["apply_"]
    pin("apply_touched_zero", any(l.startswith('[[ "$TOUCHED" == "0" ]] || {') and "exit 1" in l for l in ap) and any(l.startswith("for ADDR in ") for l in ap)
        and any('any(. == "create" or . == "update" or . == "delete" or . == "forget")' in l for l in ap))
    # --- teardown
    td = L["tear"]
    pin("teardown_detailed_exitcode", any("terraform plan" in l and "-detailed-exitcode" in l for l in td))
    pin("teardown_rc_zero_is_noop", '[[ $rc -ne 0 ]] || { echo "no wipe host or attachment exists; nothing to tear down."; exit 0; }' in td)
    pin("teardown_rc_two_only", any(l.startswith("[[ $rc -eq 2 ]] || {") and "exit 1" in l for l in td))
    pin("teardown_gate_enabled_false", any("-var='inngest_backstop_wipe_enabled=false'" in l for l in td))
    # --- secrets / hygiene
    v = " ".join(L["valid"])
    pin("hz_token_on_stdin", "curl -q -K - " in v and "-H " not in v)
    lv = L["live"]
    pin("doppler_token_not_on_argv", any(l.startswith('dget() { DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get') and "--token" not in l for l in lv))
    # The probe-row census (scripts/lib/inngest-probe-row.test.sh) requires the `unset INNGEST_PROBE_ROW_JQ`
    # and `INNGEST_PROBE_ROW_LIB:-` literals, so the override stays spelled in the default; it is safe only
    # because the SAME step unsets INNGEST_PROBE_ROW_LIB on a line before the `_ipr_lib=` assignment.
    ui = [i for i, l in enumerate(lv) if l.startswith("unset INNGEST_PROBE_ROW_JQ ") and "INNGEST_PROBE_ROW_LIB" in l.split()]
    ai = [i for i, l in enumerate(lv) if l.startswith("_ipr_lib=")]
    pin("probe_lib_not_overridable", len(ui) == 1 and len(ai) == 1 and ui[0] < ai[0])
    # --- literal hygiene: the pinned ids appear once (the validation) and the live id never
    allbody = "\n".join("\n".join(v) for v in L.values())
    pin("retired_id_literal_once", sum(1 for l in allbody.split("\n") if "106261946" in l) == 1 and any(l.startswith('[[ "$EXPECTED_INNGEST_VOLUME_ID" == "106261946" ]]') for l in L["valid"]))
    pin("live_id_literal_absent", "106903269" not in allbody)
    return bad

def mutations():
    # (label, old, new, expected pin id)
    PRE_HEAD = "env:\n          BETTERSTACK_QUERY_HOST: ${{ secrets.BETTERSTACK_QUERY_HOST }}\n          BETTERSTACK_QUERY_USERNAME: ${{ secrets.BETTERSTACK_QUERY_USERNAME }}\n          BETTERSTACK_QUERY_PASSWORD: ${{ secrets.BETTERSTACK_QUERY_PASSWORD }}\n        run: |\n          set -uo pipefail\n          source \"${GITHUB_WORKSPACE}/tests/scripts/lib/inngest-backstop-retire-gate.sh\"\n          source \"${RUNNER_TEMP}/hz.sh\"\n          P="
    DP_IF = "if: env.RETIRE_PHASE == 'destroy' && steps.conv.outputs.skip != 'true'\n        "
    RB_IF = "if: always() && steps.conv.outcome == 'success' && steps.conv.outputs.skip != 'true'\n        working-directory: ${{ env.INFRA_DIR }}\n        env:\n          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}\n        run: |\n          set -uo pipefail\n          source \"${GITHUB_WORKSPACE}/tests/scripts/lib/inngest-backstop-retire-gate.sh\"\n          source \"${RUNNER_TEMP}/hz.sh\"\n          OUT="
    return [
        ("destroy-precondition if: inverted", "if: env.RETIRE_PHASE == 'destroy' && steps.conv.outputs.skip != 'true'", "if: env.RETIRE_PHASE != 'destroy' && steps.conv.outputs.skip != 'true'", "if_destroy_precondition"),
        ("destroy-precondition if: dropped", DP_IF + PRE_HEAD, PRE_HEAD, "if_destroy_precondition"),
        ("live-store gate also runs for teardown", "if: env.RETIRE_PHASE != 'teardown'\n        env:\n          BETTERSTACK_QUERY_HOST", "if: always()\n        env:\n          BETTERSTACK_QUERY_HOST", "if_live_store_not_teardown"),
        ("read-back lost always()", RB_IF, RB_IF.replace("if: always() && steps.conv.outcome == 'success' && ", "if: "), "if_readback_always"),
        ("continue-on-error on the destroy precondition", "      - name: Destroy precondition (Guard 4, before any plan)\n", "      - name: Destroy precondition (Guard 4, before any plan)\n        continue-on-error: true\n", "no_continue_on_error"),
        ("continue-on-error on the live-store gate", "      - name: Live-store gate (plan 2.0, in front of detach, wipe and destroy; NOT teardown)\n", "      - name: Live-store gate (plan 2.0, in front of detach, wipe and destroy; NOT teardown)\n        continue-on-error: true\n", "no_continue_on_error"),
        ("destroy precondition: exit 1 dropped", "(D4); read reason=.\"; exit 1", "(D4); read reason=.\"", "gate_site_exits_pre_inngest_backstop_destroy_precondition"),
        ("destroy precondition: call without the negation", "          if ! inngest_backstop_destroy_precondition ", "          if inngest_backstop_destroy_precondition ", "gate_site_exits_pre_inngest_backstop_destroy_precondition"),
        ("live-store gate: exit 1 dropped", "not provably serving.\"; exit 1", "not provably serving.\"", "gate_site_exits_live_inngest_backstop_live_store_gate"),
        ("targeted gate: exit 1 replaced by exit 0", "NO [ack-destroy] bypass.\"\n            grep -E 'will be (created|destroyed|updated)|must be replaced|Plan:' tfplan.txt | head -30 >&2\n            exit 1", "NO [ack-destroy] bypass.\"\n            grep -E 'will be (created|destroyed|updated)|must be replaced|Plan:' tfplan.txt | head -30 >&2\n            exit 0", "gate_site_exits_plan_inngest_backstop_retire_gate"),
        ("untargeted gate: exit 1 dropped", "head -30 >&2\n            exit 1\n          fi\n\n      - name: Terraform plan (phase)", "head -30 >&2\n          fi\n\n      - name: Terraform plan (phase)", "gate_site_exits_unt_inngest_backstop_retire_gate"),
        ("teardown gate: exit 1 dropped", "(only deletes of the two wipe addresses are legal).\"; exit 1", "(only deletes of the two wipe addresses are legal).\"", "gate_site_exits_tear_inngest_backstop_retire_gate"),
        ("poll: the OK==1 requirement removed", "[[ \"$OK\" == 1 ]] || { echo \"::error::no wiped row", "[[ \"$OK\" == 1 ]] || true; { echo \"::error::no wiped row", "poll_ok_required"),
        ("poll: back to a fixed 24-iteration loop", "while (( $(date -u +%s) < DEADLINE )); do", "for _ in $(seq 1 24); do", "poll_deadline"),
        ("poll: archive query again", "--since 1h --no-archive --grep SOLEUR_INNGEST_BACKSTOP_WIPE", "--since 2h --grep SOLEUR_INNGEST_BACKSTOP_WIPE", "poll_no_archive_hot_only"),
        ("poll: refusal no longer ends it", "grep -qF ' result=refused ' <<<\"$MSGS\" && break", "grep -qF ' result=refused ' <<<\"$MSGS\" || true", "poll_breaks_on_refusal"),
        ("poll: query errors swallowed again", "|| { echo \"poll query failed rc=$?: $(head -c 300 \"$ERR\")\"; : > \"$ROWS\"; }", "|| : > \"$ROWS\"", "poll_query_error_printed"),
        ("conv: wipe no longer requires a detached volume", "[[ \"$VS\" == null ]] || fail \"volume ${EXPECTED_INNGEST_VOLUME_ID} must be detached", "[[ \"$VS\" == null ]] || true; : \"volume ${EXPECTED_INNGEST_VOLUME_ID} must be detached", "conv_wipe_requires_detached"),
        ("conv: reads another volume", "VC=\"$(hz \"volumes/${EXPECTED_INNGEST_VOLUME_ID}\" \"${RUNNER_TEMP}/vol.json\")\"", "VC=\"$(hz \"volumes/106903269\" \"${RUNNER_TEMP}/vol.json\")\"", "conv_reads_the_pinned_volume"),
        ("conv: refresh delta no longer exact", "[[ \"$DEL\" == \"$a\" && -z \"$ADD\" ]] || fail", "[[ \"$DEL\" == \"$a\" ]] || fail", "conv_reconcile_exact_delta"),
        ("conv: state list piped into grep -q (SIGPIPE fail-open)", "            ST1=\"$(terraform state list 2>/dev/null)\" || fail \"cannot list terraform state after the refresh\"", "            terraform state list 2>/dev/null | grep -qFx -- \"$a\" && fail \"still in state\"\n            ST1=\"$(terraform state list 2>/dev/null)\" || fail \"cannot list terraform state after the refresh\"", "conv_state_list_in_variable"),
        ("conv: leaked-host recovery message removed", "if [[ \"$NWS\" != 0 ]] && ! has \"$WSA\"; then", "if false; then", "conv_orphan_host_message"),
        ("conv: a reconcile target made non-literal", "T=-target=hcloud_volume.inngest_redis ;;", "T=-target=$a ;;", "conv_reconcile_targets_literal"),
        ("pre: .head_branch == \"main\" dropped", "and .head_branch == \"main\" and .event", "and .event", "pre_provenance"),
        ("pre: archive dropped from the destroy query", "--since 14d --grep SOLEUR_INNGEST_BACKSTOP_WIPE --limit 2000", "--since 14d --no-archive --grep SOLEUR_INNGEST_BACKSTOP_WIPE --limit 2000", "pre_archive_kept"),
        ("pre: Hetzner action history not read", "/actions?per_page=50&sort=id%3Adesc\"", "/actions\"", "pre_hetzner_actions_read"),
        ("pre: actions file not handed to the gate", "--actions-file \"$P/acts.json\" ", "", "pre_call_inputs"),
        ("pre: CLO ref accepts any https URL again", "https://github\\.com/jikig-ai/soleur/issues/8285#issuecomment-([0-9]+)$", "https://[^[:space:]]+$", "pre_clo_strict_pattern"),
        ("plan: nonce no longer the run id", "-var=\"inngest_backstop_wipe_nonce=${GITHUB_RUN_ID}\"", "-var=\"inngest_backstop_wipe_nonce=1\"", "plan_nonce_is_run_id"),
        ("apply: TOUCHED==0 check removed", "[[ \"$TOUCHED\" == \"0\" ]] || {", "[[ \"$TOUCHED\" == \"0\" ]] || true; {", "apply_touched_zero"),
        ("apply: a verb dropped from the TOUCHED filter", "any(. == \"create\" or . == \"update\" or . == \"delete\" or . == \"forget\")", "any(. == \"create\" or . == \"delete\")", "apply_touched_zero"),
        ("teardown: rc 0 no longer a no-op", "nothing to tear down.\"; exit 0; }", "nothing to tear down.\"; exit 1; }", "teardown_rc_zero_is_noop"),
        ("teardown: rc other than 2 no longer fatal", "[[ $rc -eq 2 ]] || { echo \"::error::teardown plan failed", "[[ $rc -eq 2 ]] || true; { echo \"::error::teardown plan failed", "teardown_rc_two_only"),
        ("teardown: -detailed-exitcode dropped", "-detailed-exitcode -out=tfplan-td", "-out=tfplan-td", "teardown_detailed_exitcode"),
        ("hz: token on argv again", "hz() { printf 'header = \"Authorization: Bearer %s\"\\n' \"$HCLOUD_TOKEN\" | curl -q -K - -sS --max-time 20", "hz() { curl -sS --max-time 20 -H \"Authorization: Bearer ${HCLOUD_TOKEN}\"", "hz_token_on_stdin"),
        ("dget: Doppler token on argv again", "dget() { DOPPLER_TOKEN=\"$DOPPLER_TOKEN_INNGEST_ARM\" doppler secrets get \"$1\" --project soleur-inngest --config prd --plain 2>/dev/null", "dget() { doppler secrets get \"$1\" --project soleur-inngest --config prd --plain --token \"$DOPPLER_TOKEN_INNGEST_ARM\" 2>/dev/null", "doppler_token_not_on_argv"),
        ("probe lib overridable again", "unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_ROW_LIB INNGEST_PROBE_EMITTER", "unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_EMITTER", "probe_lib_not_overridable"),
        ("a second retired-id literal reappears", "VC=\"$(hz \"volumes/${EXPECTED_INNGEST_VOLUME_ID}\" \"${RUNNER_TEMP}/vol-rb.json\")\"", "VC=\"$(hz \"volumes/106261946\" \"${RUNNER_TEMP}/vol-rb.json\")\"", "retired_id_literal_once"),
        ("the live-id literal reappears", "[[ \"$(hz \"volumes/${_IBRG_LIVE_ID}\" \"${RUNNER_TEMP}/luks.json\")\" == 200 ]]", "[[ \"$(hz \"volumes/106903269\" \"${RUNNER_TEMP}/luks.json\")\" == 200 ]]", "live_id_literal_absent"),
    ]

def main():
    path = sys.argv[1]
    text = open(path).read()
    base = pins(load(text))
    print("CONTROL " + ("ok" if not base else "FAIL " + ",".join(base)))
    a = text.index("\n  inngest_backstop_retire:\n"); b = text.index("\n  registry_host_replace:\n")
    pre, job, post = text[:a], text[a:b], text[b:]
    for label, old, new, want in mutations():
        n = job.count(old)
        if n != 1:
            print("MUT NOLAND [%s] occurrences=%d" % (label, n))
            continue
        got = pins(load("jobs:" + job.replace(old, new)))  # only the job under test is parsed: a mutation run stays cheap
        print("MUT %s [%s] -> %s" % ("ok" if want in got else "NOTRED", label, ",".join(got) or "none"))

if __name__ == "__main__":
    main()
PINS
PIN_OUT="$(python3 -I "$PINS_PY" "$WF" 2>&1)"
if [[ "$(head -1 <<<"$PIN_OUT")" == "CONTROL ok" ]]; then pass; else fail "Pins: the real workflow trips a pin" "" "$(head -3 <<<"$PIN_OUT")"; fi
n_mut=0
while IFS= read -r l; do
  [[ "$l" == MUT\ * ]] || continue
  n_mut=$((n_mut + 1))
  if [[ "$l" == "MUT ok "* ]]; then pass; else fail "Pins: a mutation was not caught (${l%% ->*})" "" "$l"; fi
done <<<"$PIN_OUT"
if [[ "$n_mut" -ge 38 ]]; then pass; else fail "Pins: only ${n_mut} workflow mutations ran (floor 38)"; fi

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
LOOP_CMP="$(python3 -I - "$WF" "$GATE" <<'LOOPPY' 2>&1
import re, sys, yaml
wf = yaml.safe_load(open(sys.argv[1])); lib = open(sys.argv[2]).read()
body = [s for s in wf["jobs"]["inngest_backstop_retire"]["steps"] if s.get("name") == "Terraform apply (phase)"][0]["run"]
addrs = set(re.findall(r"'([^']+)'", re.search(r"for ADDR in (.*?); do", body).group(1)))
def lst(name):
    m = re.search(r"def " + name + r":\s*\[(.*?)\];", lib, re.S)
    return set(x.replace('\\"', '"') for x in re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)))
want = lst("live_addr") | lst("named_live") | {"hcloud_server.inngest"}
print("SAME %d" % len(want) if addrs == want else "DIFF only-in-workflow=%s only-in-lib=%s" % (sorted(addrs - want), sorted(want - addrs)))
LOOPPY
)"
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
SB="$TMP/sb"; mkdir -p "$SB/bin" "$SB/ws/scripts" "$SB/ws/tests/scripts" "$SB/rt" "$SB/hz" "$SB/cwd"
assert_fixture_dir "$SB"
ln -s "${REPO_ROOT}/tests/scripts/lib" "$SB/ws/tests/scripts/lib"
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
if [[ "${BS_RC:-0}" != 0 ]]; then echo "boom: simulated query failure" >&2; exit "$BS_RC"; fi
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
step_body() { # <step-name fragment> -> $SB/step.sh (the run: text, byte for byte)
  python3 -I - "$WF" "$1" > "$SB/step.sh" <<'EXTRACT'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
m = [s for s in wf["jobs"]["inngest_backstop_retire"]["steps"] if sys.argv[2] in s.get("name", "")]
if len(m) != 1: sys.exit(3)
sys.stdout.write(m[0]["run"])
EXTRACT
}
run_step() { # <step-name fragment> [VAR=val ...] -> SOUT (stdout+stderr), SRC (exit code)
  local frag="$1"; shift
  step_body "$frag" || { SOUT="step '$frag' not found"; SRC=99; return; }
  SRC=0
  SOUT="$(cd "$SB/cwd" && env -i PATH="$SB/bin:/usr/bin:/bin" HOME="$SB" LC_ALL=C RUNNER_TEMP="$SB/rt" GITHUB_WORKSPACE="$SB/ws" GITHUB_OUTPUT="$SB/out" \
    GITHUB_REPOSITORY=jikig-ai/soleur GITHUB_RUN_ID=555 CI_SSH_PUB=/x EXPECTED_INNGEST_VOLUME_ID="$PIN" HZ_FIX="$SB/hz" TF_STATE="$SB/tf.state" TF_REFRESH="$SB/tf.refresh" \
    TF_LOG="$SB/tf.log" TF_SHOW="$SB/tf.show" GH_RUN="$SB/gh-run.json" GH_COMMENT="$SB/gh-comment.json" GH_LOG="$SB/gh.log" GH_ISSUE_OUT="$SB/gh-issue.txt" \
    BS_LOG="$SB/bs.log" BS_ROWS="$SB/bs-rows.jsonl" "$@" bash --noprofile --norc -eo pipefail "$SB/step.sh" 2>&1)" || SRC=$?
}
beh() { # <name> <want-rc> <needle> [<absent-needle>]  (uses SOUT/SRC from the last run_step)
  local name="$1" want="$2" needle="$3" absent="${4:-}"
  if [[ "$SRC" -eq "$want" && "$SOUT" == *"$needle"* && "$SOUT" != *"UNEXPECTED"* && ( -z "$absent" || "$SOUT" != *"$absent"* ) ]]; then pass; else fail "BEHAVIOUR: $name (want rc=$want containing '$needle')" "$SRC" "$SOUT"; fi
}
out_has() { grep -qxF -- "$1" "$SB/out"; }
SRV_LIVE='{"servers":[{"id":169426216}]}'
conv() { # <phase> -> runs the convergence step
  run_step "Convergence read" RETIRE_PHASE="$1"
}
conv_base() { # <vol-code> <vol-body> <ws-body>
  hzreset; hzset "$HZ_VOL" "$1" "$2"; hzset "$HZ_WS" 200 "$3"; printf '%s' "$SRV_LIVE" > "$SB/rt/srv.json"
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

# ---- the wipe evidence poll (W2) ----
WCLOCK="$SB/clock"; echo 1760000000 > "$WCLOCK"
poll() { echo 1760000000 > "$WCLOCK"; run_step "Wipe evidence" SB_CLOCK="$WCLOCK" JOB_START=1759999000 RETIRE_PHASE=wipe BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x "$@"; }
poll_base() { hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 200 '{"servers":[]}'; }
POLL_GOOD="result=wiped nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none fs_uuid=abc last_write=x"
poll_base; ev_row '2025-10-09 08:55:00' "$POLL_GOOD" > "$SB/bs-rows.jsonl"; poll
beh "poll: a wiped row for this run's nonce => success" 0 "Hetzner at poll end: volume.server=null wipe hosts="
poll_base; { ev_row '2025-10-09 08:54:00' "result=started nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES}"; ev_row '2025-10-09 08:55:00' "result=refused reason=has_holders nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES}"; ev_row '2025-10-09 08:55:30' "result=refused reason=mounted nonce=999 volume_id=${PIN} size_bytes=${SIZE_BYTES}"; } > "$SB/bs-rows.jsonl"; poll
beh "poll: a refusal for this nonce ends the poll at once and names the host's reason" 1 "host refusal: has_holders" "reason=mounted"
if [[ "$(grep -c . "$SB/bs.log")" -le 2 ]]; then pass; else fail "BEHAVIOUR: the poll kept querying after a refusal" "" "$(cat "$SB/bs.log")"; fi
if [[ "$SOUT" == *"result=started nonce=555"* && "$SOUT" != *"nonce=999"* ]]; then pass; else fail "BEHAVIOUR: the poll must print only THIS nonce's rows" "" "$SOUT"; fi
poll_base; : > "$SB/bs-rows.jsonl"; poll
beh "poll: no rows => bounded by the wall-clock deadline, says none seen" 1 "host refusal: none seen"
n_q="$(grep -c . "$SB/bs.log")"
if [[ "$n_q" -ge 3 && "$n_q" -le 25 ]]; then pass; else fail "BEHAVIOUR: expected the 20-minute wall-clock deadline to bound the poll to a handful of queries, saw ${n_q}" "" ""; fi
if [[ "$(grep -vc -e '--no-archive' -e '^$' "$SB/bs.log")" -eq 0 && "$(grep -c -e '--since 1h' "$SB/bs.log")" -eq "$n_q" ]]; then pass; else fail "BEHAVIOUR: every poll query must be the hot-window form (--since 1h --no-archive)" "" "$(cat "$SB/bs.log")"; fi
poll_base; poll BS_RC=7
beh "poll: a failing query is printed (rc and stderr), not swallowed" 1 "poll query failed rc=7: boom: simulated query failure"
poll_base; ev_row_as attacker-box "$WIPE_SHIPPER" '2025-10-09 08:55:00' "$POLL_GOOD" > "$SB/bs-rows.jsonl"; poll
beh "poll: a perfect row from the wrong host is not evidence" 1 "no wiped row for nonce 555"
hzreset; hzset "$HZ_VOL" 404; poll
beh "poll: an unreadable volume stops it before any query" 1 "cannot read volume"

# ---- the destroy precondition (D-A, D-B), end to end through the real step ----
pre_base() {
  hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "${HZ_VOL}/actions?per_page=50&sort=id%3Adesc" 200 "$(cat "$ACTS_OK")"; hzset "$HZ_SRV" 200 "$SRV_LIVE"
  printf '{"path":".github/workflows/apply-web-platform-infra.yml","head_branch":"main","event":"workflow_dispatch","status":"completed","run_started_at":"2025-10-09T08:50:00Z"}' > "$SB/gh-run.json"
  ev_row_as "$WIPE_HOST" "$WIPE_SHIPPER" '2025-10-09 08:55:00' "result=wiped nonce=555 volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none fs_uuid=abc last_write=x" > "$SB/bs-rows.jsonl"
}
pre() { run_step "Destroy precondition" RETIRE_PHASE=destroy BETTERSTACK_QUERY_HOST=x BETTERSTACK_QUERY_USERNAME=x BETTERSTACK_QUERY_PASSWORD=x "$@"; }
pre_base; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: a wiped row + the wipe host's attach/detach in Hetzner's history => PASS" 0 "destroy_precondition: PASS"
pre_base; printf '{"path":".github/workflows/apply-web-platform-infra.yml","head_branch":"feature","event":"workflow_dispatch","status":"completed","run_started_at":"2025-10-09T08:50:00Z"}' > "$SB/gh-run.json"; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: a wipe run from a non-main branch => refused (no floor)" 1 "reason=evidence_stale"
pre_base; rm -f "$SB/gh-run.json"; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: the wipe run cannot be read => refused" 1 "reason=evidence_stale"
pre_base; printf '{"path":".github/workflows/other.yml","head_branch":"main","event":"workflow_dispatch","status":"completed","run_started_at":"2025-10-09T08:50:00Z"}' > "$SB/gh-run.json"; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: a run of another workflow => refused" 1 "reason=evidence_stale"
pre_base; printf '{"path":".github/workflows/apply-web-platform-infra.yml","head_branch":"main","event":"workflow_dispatch","status":"in_progress","run_started_at":"2025-10-09T08:50:00Z"}' > "$SB/gh-run.json"; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: a wipe run that has not completed => refused" 1 "reason=evidence_stale"
pre_base; hzset "${HZ_VOL}/actions?per_page=50&sort=id%3Adesc" 500; pre WIPE_RUN_ID=555 RETIRE_ERASURE= CLO_REF=
beh "precondition: Hetzner's action history unreadable (500) => refused" 1 "reason=actions_unreadable"
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
pre_base; clo_file "$SB/gh-comment.json" NONE "volume ${PIN}"; pre WIPE_RUN_ID= RETIRE_ERASURE=provider-only CLO_REF="$CLO_GOOD_REF"
beh "precondition D4: the same comment from an author with NONE association => refused" 1 "reason=clo_author_not_privileged"
pre_base; cp "$CLO_OK" "$SB/gh-comment.json"; pre WIPE_RUN_ID= RETIRE_ERASURE=provider-only CLO_REF="https://example.test/attestation"
beh "precondition D4: an arbitrary https URL is refused before any fetch" 1 "reason=clo_ref_invalid"
if [[ ! -s "$SB/gh.log" ]]; then pass; else fail "BEHAVIOUR: an invalid ref must not trigger an API fetch" "" "$(cat "$SB/gh.log")"; fi
pre_base; pre WIPE_RUN_ID= RETIRE_ERASURE=provider-only CLO_REF="$CLO_GOOD_REF"
beh "precondition D4: the comment cannot be fetched => refused" 1 "reason=clo_comment_unreadable"

# ---- the teardown step: rc 0 / 1 / 2 (W3) ----
TD_ENV=(RETIRE_PHASE=wipe)
td() { run_step "Teardown of the wipe host" "${TD_ENV[@]}" "$@"; }
write_plan "${WSRV_DEL},${WATT_DEL}"; cp "$TMP/plan.json" "$SB/tf.show.ok"
write_plan "${WSRV_DEL},${VOL_DEL}"; cp "$TMP/plan.json" "$SB/tf.show.bad"
hzreset; : > "$SB/tf.state"; cp "$SB/tf.show.ok" "$SB/tf.show"
td TF_PLAN_RC=0 TF_APPLY_RC=64
beh "teardown: plan rc 0 (nothing exists) => exits 0 without applying" 0 "nothing to tear down"
if ! grep -q 'apply -no-color' "$SB/tf.log"; then pass; else fail "BEHAVIOUR: teardown must not apply when the plan is empty" "" "$(cat "$SB/tf.log")"; fi
: > "$SB/tf.log"; td TF_PLAN_RC=1 TF_APPLY_RC=64
beh "teardown: plan rc 1 (error) => fails, names the leak" 1 "teardown plan failed (exit 1)"
: > "$SB/tf.log"; td TF_PLAN_RC=2 TF_APPLY_RC=0
beh "teardown: plan rc 2 + a legal deletes-only plan => applies" 0 ""
if grep -q 'apply -no-color' "$SB/tf.log"; then pass; else fail "BEHAVIOUR: teardown must apply a legal plan" "" "$(cat "$SB/tf.log")"; fi
: > "$SB/tf.log"; td TF_PLAN_RC=2 TF_APPLY_RC=1
beh "teardown: the apply fails => fails, says re-dispatch" 1 "teardown apply failed; re-dispatch phase=teardown"
cp "$SB/tf.show.bad" "$SB/tf.show"; : > "$SB/tf.log"; td TF_PLAN_RC=2 TF_APPLY_RC=0
beh "teardown: a plan that also deletes the retired volume is REFUSED by the gate, never applied" 1 "teardown plan REFUSED by the gate"
if ! grep -q 'apply -no-color' "$SB/tf.log"; then pass; else fail "BEHAVIOUR: a refused teardown plan must not be applied" "" "$(cat "$SB/tf.log")"; fi

# ---- the read-back and the progress comment (W1, W9) ----
rb() { run_step "Read-back" "$@"; }
hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 200 '{"servers":[]}'; rb RETIRE_PHASE=detach
beh "read-back detach: detached => records the rollback boundary" 0 "detached; rollback ends here"
hzreset; hzset "$HZ_VOL" 200 "$(vol_json 169426216)"; hzset "$HZ_WS" 200 '{"servers":[]}'; rb RETIRE_PHASE=detach
beh "read-back detach: still attached => fails and records it" 1 "is still attached"
if grep -q 'READ-BACK FAILED' "$SB/rt/readback.txt"; then pass; else fail "BEHAVIOUR: a failed read-back must be recorded for the progress comment" "" "$(cat "$SB/rt/readback.txt" 2>/dev/null)"; fi
hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 200 '{"servers":[{"id":777}]}'; rb RETIRE_PHASE=wipe
beh "read-back wipe: a wipe host still exists => fails" 1 "a wipe host still exists"
printf '{"resource_changes":[]}' > "$SB/tf.show"
hzreset; hzset "$HZ_VOL" 404; hzset "$HZ_WS" 200 '{"servers":[]}'; hzset "$HZ_SRV" 200 "{\"servers\":[{\"id\":169426216,\"volumes\":[${LIVEV}]}]}"; rb RETIRE_PHASE=destroy TF_PLAN_RC=0
beh "read-back destroy: 404, the host holds only the live volume, no retired address in the plan => PASS" 0 "untargeted plan lists neither retired address"
hzreset; hzset "$HZ_VOL" 404; hzset "$HZ_WS" 200 '{"servers":[]}'; hzset "$HZ_SRV" 200 "{\"servers\":[{\"id\":169426216,\"volumes\":[${LIVEV},${PIN}]}]}"; rb RETIRE_PHASE=destroy TF_PLAN_RC=0
beh "read-back destroy: the host also lists the retired volume => fails" 1 "inngest server volumes"
hzreset; hzset "$HZ_VOL" 200 "$(vol_json null)"; hzset "$HZ_WS" 200 '{"servers":[]}'; rb RETIRE_PHASE=destroy TF_PLAN_RC=0
beh "read-back destroy: the volume still answers 200 => fails" 1 "expected 404"
prog() { rm -f "$SB/gh-issue.txt"; echo "$1" > "$SB/clock"; run_step "Progress comment" SB_CLOCK="$SB/clock" RETIRE_PHASE="$2" JOB_STATUS="$3" RUN_URL=u "${@:4}"; }
mkdir -p "$SB/rt"; printf 'volume x detached' > "$SB/rt/readback.txt"
prog 1760000000 wipe failure
if [[ "$SRC" -eq 0 && "$(cat "$SB/gh-issue.txt")" == *"D4 decision point (wipe not yet succeeded): 2026-10-17."* && "$(cat "$SB/gh-issue.txt")" == *"Read-back: volume x detached"* ]]; then pass; else fail "BEHAVIOUR: the progress comment before destroy carries the D4 point and the read-back" "$SRC" "$(cat "$SB/gh-issue.txt" 2>/dev/null) $SOUT"; fi
prog 1760000000 destroy success
if [[ "$SRC" -eq 0 && "$(cat "$SB/gh-issue.txt")" != *"D4 decision"* && "$(cat "$SB/gh-issue.txt")" == *"day(s) to the non-extendable 2026-10-22"* ]]; then pass; else fail "BEHAVIOUR: the D4 sentence must go once destroy has succeeded" "$SRC" "$(cat "$SB/gh-issue.txt" 2>/dev/null)"; fi
prog 1800000000 wipe success
if [[ "$SRC" -eq 0 && "$(cat "$SB/gh-issue.txt")" == *$'\n\n0 day(s) to the non-extendable'* ]]; then pass; else fail "BEHAVIOUR: a past expiry must clamp to 0 day(s), never print a negative number" "$SRC" "$(cat "$SB/gh-issue.txt" 2>/dev/null)"; fi

# ── H (suite edit): replace the sourced lib with an ALWAYS-PASS stub; THIS suite must fail ──
if [[ -z "${SOLEUR_IBRG_META:-}" ]]; then
  STUBLIB="$TMP/stub-lib.sh"
  cat > "$STUBLIB" <<'STUB'
inngest_backstop_retire_gate() { echo "inngest_backstop_retire_gate: PASS (stub)"; return 0; }
inngest_backstop_live_store_gate() { echo "inngest_backstop_live_store_gate: PASS (stub)"; return 0; }
inngest_backstop_destroy_precondition() { echo "inngest_backstop_destroy_precondition: PASS (stub)"; return 0; }
inngest_backstop_wipe_evidence_gate() { echo "inngest_backstop_wipe_evidence_gate: PASS (stub)"; return 0; }
inngest_backstop_wipe_nonce_rows() { return 0; }
STUB
  if SOLEUR_IBRG_META=1 INNGEST_BACKSTOP_GATE_LIB="$STUBLIB" bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
    fail "H: with an always-pass stub lib this suite still exits 0 -- the must-RED rows are decorative"
  else pass; fi
fi

# ── Anti-vacuity: the must-PASS arms exist (counted from the file) and a floor on total assertions ──
_pass_arms="$(grep -cE '^(chk|lsg|dpc|evok) "(PASS|LS PASS|G4 PASS|H[0-9]?:|G4 H:|Row 8[abc]|Row 10[adg]|Row 11d|G4 D4: erasure=provider-only \+|G4 D4: PASS|G4 explicit|G4 D-A: the attach finished AT|REAL ROW: the wipe script|EV boundary: (now|floor))' "${BASH_SOURCE[0]}" || true)"
if [[ "$_pass_arms" =~ ^[0-9]+$ && "$_pass_arms" -ge 24 ]]; then pass; else fail "only ${_pass_arms} must-PASS arms found (floor 24) -- a guard stuck at 'reject everything' would go undetected"; fi
_ran=$((passes + fails))
if [[ "$_ran" -lt 460 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 460. Arms were deleted, skipped, or the suite exited early.\n' "$_ran" >&2
  printf 'inngest-backstop-retire-gate: %s passed, %s failed\n' "$passes" "$fails"
  exit 1
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 460)\n' "$_ran"
fi
echo ""
echo "inngest-backstop-retire-gate: ${passes} passed, ${fails} failed"
[[ "$fails" -eq 0 ]]
