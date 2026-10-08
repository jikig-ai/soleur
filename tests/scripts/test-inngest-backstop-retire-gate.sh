#!/usr/bin/env bash
# Tests for tests/scripts/lib/inngest-backstop-retire-gate.sh (sourced by the inngest_backstop_retire
# job in .github/workflows/apply-web-platform-infra.yml, #8285).
#
# THREE FUNCTIONS ARE GRADED, each the SAME bytes the workflow sources:
#   inngest_backstop_retire_gate        plan SHAPE per phase (Guard 2) -- detach | wipe | teardown | destroy
#   inngest_backstop_live_store_gate    the live-store chokepoint in front of EVERY phase (plan 2.0)
#   inngest_backstop_destroy_precondition   evidence-before-destroy (Guard 4), incl. the D4 alternative
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
  local flag=done active="$LIVEV" luks="$LUKS_OK" probe="$PROBE_OK" inflight=0 server="$SRVID" kv out rc=0
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

# ══ GUARD 4 -- evidence-before-destroy ════════════════════════════════════════════
NONCE="37900000001"
SIZE_BYTES=$((10 * 1073741824))
AFTER_EPOCH="$(date -u -d '2026-10-14T09:00:00Z' +%s)"
NOW4="$(date -u -d '2026-10-15T12:00:00Z' +%s)"
VOL_FILE="$FIX/v-retired.json"
printf '{"volume":{"id":%s,"name":"soleur-inngest-redis-store","server":null,"size":10}}\n' "$PIN" > "$VOL_FILE"
ev_row() { # <dt> <message-tail>  -> one Better Stack warehouse line (double-encoded raw)
  local msg="SOLEUR_INNGEST_BACKSTOP_WIPE $2"
  jq -cn --arg dt "$1" --arg m "$msg" '{dt:$dt, raw: ({message:$m} | tojson)}'
}
GOODTAIL="result=wiped nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES} readback=zero sig_after=none fs_uuid=abc last_write=2026-09-20"
EV="$FIX/ev.jsonl"
{ ev_row '2026-10-15 09:10:00' "result=started nonce=${NONCE} volume_id=${PIN} size_bytes=${SIZE_BYTES}"; ev_row '2026-10-15 09:20:00' "$GOODTAIL"; } > "$EV"

dpc() { # <name> <want_rc> <needle> [overrides: erasure= run= clo= clocode= rows= vol= after= now=]
  local name="$1" want="$2" needle="$3"; shift 3
  local erasure="" run="$NONCE" clo="" clocode="" rows="$EV" vol="$VOL_FILE" after="$AFTER_EPOCH" now="$NOW4" kv out rc=0
  for kv in "$@"; do
    case "$kv" in
      erasure=*) erasure="${kv#erasure=}" ;; run=*) run="${kv#run=}" ;; clo=*) clo="${kv#clo=}" ;; clocode=*) clocode="${kv#clocode=}" ;;
      rows=*) rows="${kv#rows=}" ;; vol=*) vol="${kv#vol=}" ;; after=*) after="${kv#after=}" ;; now=*) now="${kv#now=}" ;;
    esac
  done
  out="$(inngest_backstop_destroy_precondition --erasure "$erasure" --wipe-run-id "$run" --clo-attestation-ref "$clo" \
    --clo-ref-http-code "$clocode" --rows-file "$rows" --volume-file "$vol" --after-epoch "$after" --now "$now" 2>&1)" || rc=$?
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
# D4 alternative: provider-only needs the attestation reference, never a third way.
dpc "G4 D4: erasure=provider-only + a resolvable CLO ref + no wipe run => PASS" 0 "$DP_PASS" "erasure=provider-only" "run=" "clo=https://github.com/jikig-ai/soleur/issues/8285#issuecomment-1" "clocode=200"
dpc "G4 D4: provider-only with NO ref => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=" "clocode="
dpc "G4 D4: provider-only with a non-URL ref => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=trust-me" "clocode=200"
dpc "G4 D4: provider-only with an http (not https) ref => clo_ref_invalid" 1 "reason=clo_ref_invalid" "erasure=provider-only" "run=" "clo=http://example.test/x" "clocode=200"
dpc "G4 D4: provider-only whose ref does not resolve (404) => clo_ref_unresolvable" 1 "reason=clo_ref_unresolvable" "erasure=provider-only" "run=" "clo=https://github.com/x/y/issues/1" "clocode=404"
dpc "G4 D4: provider-only whose ref status is unreadable => clo_ref_unresolvable" 1 "reason=clo_ref_unresolvable" "erasure=provider-only" "run=" "clo=https://github.com/x/y/issues/1" "clocode="
dpc "G4 D4: provider-only AND a wipe run id => ambiguous_inputs" 1 "reason=ambiguous_inputs" "erasure=provider-only" "run=${NONCE}" "clo=https://github.com/x/y/issues/1" "clocode=200"
dpc "G4 D4: a CLO ref supplied without erasure=provider-only => ambiguous_inputs" 1 "reason=ambiguous_inputs" "clo=https://github.com/x/y/issues/1" "clocode=200"
dpc "G4 D4: an unknown erasure value => erasure_unknown" 1 "reason=erasure_unknown" "erasure=skip"
dpc "G4 D4: provider-only still needs the volume detached => still_attached" 1 "reason=still_attached" "erasure=provider-only" "run=" "clo=https://github.com/x/y/issues/1" "clocode=200" "vol=$FIX/vol-att.json"
dpc "G4 explicit erasure=wipe behaves as the default" 0 "$DP_PASS" "erasure=wipe"

# ── Usage and operand hygiene: an unknown option, a missing clock, direct evidence-gate misuse ──
for fn in inngest_backstop_live_store_gate inngest_backstop_destroy_precondition inngest_backstop_wipe_evidence_gate; do
  out="$("$fn" --bogus x 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 1 && "$out" == *"reason=usage"* ]] && one_line "$out"; then pass; else fail "usage: ${fn} must refuse an unknown option" "$rc" "$out"; fi
done
out="$(inngest_backstop_live_store_gate --cutover-flag done --active-id "$LIVEV" --luks-volume-file "$LUKS_OK" --probe-file "$PROBE_OK" --inflight-runs 0 --server-id "$SRVID" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 1 && "$out" == *"reason=probe_unusable"* ]]; then pass; else fail "LS: a missing --now (no clock) must fail closed" "$rc" "$out"; fi
out="$(inngest_backstop_live_store_gate --cutover-flag done --active-id "$LIVEV" --luks-volume-file "$LUKS_OK" --probe-file "$PROBE_OK" --now abc --inflight-runs 0 --server-id "$SRVID" 2>&1)" && rc=0 || rc=$?
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

# ── Row 5 / ordering and wiring, asserted against the workflow text ────────────────
WF="${REPO_ROOT}/.github/workflows/apply-web-platform-infra.yml"
wf_py() { python3 -I - "$WF" "$@" 2>&1; }
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

# ── H (suite edit): replace the sourced lib with an ALWAYS-PASS stub; THIS suite must fail ──
if [[ -z "${SOLEUR_IBRG_META:-}" ]]; then
  STUBLIB="$TMP/stub-lib.sh"
  cat > "$STUBLIB" <<'STUB'
inngest_backstop_retire_gate() { echo "inngest_backstop_retire_gate: PASS (stub)"; return 0; }
inngest_backstop_live_store_gate() { echo "inngest_backstop_live_store_gate: PASS (stub)"; return 0; }
inngest_backstop_destroy_precondition() { echo "inngest_backstop_destroy_precondition: PASS (stub)"; return 0; }
STUB
  if SOLEUR_IBRG_META=1 INNGEST_BACKSTOP_GATE_LIB="$STUBLIB" bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
    fail "H: with an always-pass stub lib this suite still exits 0 -- the must-RED rows are decorative"
  else pass; fi
fi

# ── Anti-vacuity: the must-PASS arms exist (counted from the file) and a floor on total assertions ──
_pass_arms="$(grep -cE '^(chk|lsg|dpc) "(PASS|LS PASS|G4 PASS|H[0-9]?:|G4 H:|Row 8[abc]|G4 D4: erasure=provider-only \+ a resolvable|G4 explicit)' "${BASH_SOURCE[0]}" || true)"
if [[ "$_pass_arms" =~ ^[0-9]+$ && "$_pass_arms" -ge 16 ]]; then pass; else fail "only ${_pass_arms} must-PASS arms found (floor 16) -- a guard stuck at 'reject everything' would go undetected"; fi
_ran=$((passes + fails))
if [[ "$_ran" -lt 226 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 226. Arms were deleted, skipped, or the suite exited early.\n' "$_ran" >&2
  printf 'inngest-backstop-retire-gate: %s passed, %s failed\n' "$passes" "$fails"
  exit 1
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 226)\n' "$_ran"
fi
echo ""
echo "inngest-backstop-retire-gate: ${passes} passed, ${fails} failed"
[[ "$fails" -eq 0 ]]
