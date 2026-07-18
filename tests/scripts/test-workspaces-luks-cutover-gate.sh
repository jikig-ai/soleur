#!/usr/bin/env bash
# Tests for tests/scripts/lib/workspaces-luks-cutover-gate.sh (sourced by the
# workspaces_luks_cutover job in .github/workflows/apply-web-platform-infra.yml, #6604).
#
# The gate reads a `terraform show -json <plan>` document and PASSes (rc=0) iff the plan is
# EXACTLY the scoped workspaces-luks FIRST PROVISION: a pure `+create` of the five #6593-authored
# resources (random_password.workspaces_luks, doppler_secret.workspaces_luks_key,
# doppler_service_token.workspaces_luks, hcloud_volume.workspaces_luks,
# hcloud_volume_attachment.workspaces_luks), with the LIVE plaintext /mnt/data volume + its
# attachment + the web-1 server PRESERVED (untouched — the old volume has NO prevent_destroy,
# #6593 deliberately omitted it), no passphrase re-mint, no destroy, and nothing out of scope.
#
# ⚠️ DP-1 non-vacuity note: this is a first provision, NOT a host -replace. The passphrase +
# doppler_secret + service_token do not yet exist in state, so the create plan is a `+create` of
# ALL FIVE. luks_passphrase_touched counts update/delete/forget ONLY (a FIRST create is legal); a
# gate that counted the create (as the git-data host-*replace* gate legitimately does) would
# ABORT this provision. Test 1 (pure create) proves the gate PERMITS the five creates.
#
# Non-vacuity discipline (RED-verification for a gating primitive): each FAIL fixture differs
# from the PASS fixture by ONE mutation of the exact class the gate must catch, so a gate that
# ignored that class would wrongly pass. Deterministic; no network. All fixtures are SYNTHESIZED
# (cq-test-fixtures-synthesized-only) — modeled on the +create plan shape; no captured real plan.
#
# Run: bash tests/scripts/test-workspaces-luks-cutover-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/scripts/lib/workspaces-luks-cutover-gate.sh
source "${DIR}/lib/workspaces-luks-cutover-gate.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A resource_change object with the given address + actions array.
rc_obj() { printf '{"address":"%s","change":{"actions":[%s]}}' "$1" "$2"; }

# The scoped first provision: all five workspaces_luks resources show a pure ["create"].
PW_CREATE="$(rc_obj 'random_password.workspaces_luks' '"create"')"
SECRET_CREATE="$(rc_obj 'doppler_secret.workspaces_luks_key' '"create"')"
TOKEN_CREATE="$(rc_obj 'doppler_service_token.workspaces_luks' '"create"')"
VOL_CREATE="$(rc_obj 'hcloud_volume.workspaces_luks' '"create"')"
ATT_CREATE="$(rc_obj 'hcloud_volume_attachment.workspaces_luks' '"create"')"

write_plan() { printf '{"resource_changes":[%s]}' "$1" > "$TMP/plan.json"; }

# The canonical PASS fixture (referenced by later single-mutation tests).
PASS_SET="${PW_CREATE},${SECRET_CREATE},${TOKEN_CREATE},${VOL_CREATE},${ATT_CREATE}"

# --- Test 1: PASS — the exact scoped first provision (all five +create) ---
# DP-1 proof: the gate PERMITS the passphrase/secret/token first-creates.
write_plan "${PASS_SET}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T1: the exact scoped workspaces-luks first provision (five +create) should PASS (rc=0)"
fi

# --- Test 2: FAIL — the LIVE plaintext /mnt/data volume is TOUCHED (any verb) ---
# hcloud_volume.workspaces["web-1"] update → old_volume_touched (AC20's STOP) + out_of_scope.
OLD_VOL_TOUCH="$(rc_obj 'hcloud_volume.workspaces[\"web-1\"]' '"update"')"
write_plan "${PASS_SET},${OLD_VOL_TOUCH}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T2: a touch on the live plaintext volume (old_volume_touched) must ABORT (rc=1)"
else
  pass
fi

# --- Test 3: FAIL — the LIVE /mnt/data attachment is TOUCHED (detach strands sole-copy data) ---
OLD_ATT_TOUCH="$(rc_obj 'hcloud_volume_attachment.workspaces[\"web-1\"]' '"update"')"
write_plan "${PASS_SET},${OLD_ATT_TOUCH}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T3: a touch on the live plaintext attachment (old_attachment_touched) must ABORT (rc=1)"
else
  pass
fi

# --- Test 4: FAIL — the web-1 server is TOUCHED (cx33 unrebuildable → product-gone) ---
WEB1_TOUCH="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"update"')"
write_plan "${PASS_SET},${WEB1_TOUCH}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T4: a touch on the web-1 server (web1_server_touched) must ABORT (rc=1)"
else
  pass
fi

# --- Test 5: FAIL — the LUKS volume is REPLACED (delete+create — data lost) ---
# ISOLATES luks_volume_destroyed: the create counter still holds (create present), but the
# delete fires luks_volume_destroyed + resource_deletes. A gate missing those clauses would pass.
VOL_REPLACE="$(rc_obj 'hcloud_volume.workspaces_luks' '"delete","create"')"
write_plan "${PW_CREATE},${SECRET_CREATE},${TOKEN_CREATE},${VOL_REPLACE},${ATT_CREATE}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T5: a LUKS volume replace (delete+create → luks_volume_destroyed) must ABORT (rc=1)"
else
  pass
fi

# --- Test 6: FAIL — the passphrase is RE-MINTED (random_password update — NOT a first create) ---
# ISOLATES luks_passphrase_touched: update fires it; create is not a required counter for the
# passphrase, so ONLY the passphrase clause fires. Proves the DP-1 split (create legal, re-mint not).
PW_REMINT="$(rc_obj 'random_password.workspaces_luks' '"update"')"
write_plan "${PW_REMINT},${SECRET_CREATE},${TOKEN_CREATE},${VOL_CREATE},${ATT_CREATE}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T6: a passphrase re-mint (random_password update → luks_passphrase_touched) must ABORT (rc=1)"
else
  pass
fi

# --- Test 7: FAIL — the doppler_secret carrier is RE-MINTED (delete+create) ---
# ISOLATES luks_passphrase_touched via the doppler_secret carrier: the create keeps
# luks_secret_created>=1, but the delete fires luks_passphrase_touched (+ resource_deletes).
SECRET_REMINT="$(rc_obj 'doppler_secret.workspaces_luks_key' '"delete","create"')"
write_plan "${PW_CREATE},${SECRET_REMINT},${TOKEN_CREATE},${VOL_CREATE},${ATT_CREATE}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T7: a doppler_secret re-mint (delete+create → luks_passphrase_touched) must ABORT (rc=1)"
else
  pass
fi

# --- Test 8: FAIL — an out-of-scope positive action (a stray web-2 host update) ---
# ISOLATES out_of_scope: web-2 is NOT web-1, so web1_server_touched stays 0; only out_of_scope fires.
WEB2_UPDATE="$(rc_obj 'hcloud_server.web[\"web-2\"]' '"update"')"
write_plan "${PASS_SET},${WEB2_UPDATE}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T8: an out-of-scope positive action (out_of_scope) must ABORT (rc=1)"
else
  pass
fi

# --- Test 9: FAIL — an in-allow-set resource is FORGOTTEN (state rm without destroy) ---
# ISOLATES resource_deletes: forget of doppler_service_token is in-allow-set (NOT out_of_scope)
# and is NOT a passphrase carrier, so ONLY resource_deletes fires. A `removed{}`/`state rm`
# manifests as `forget`, which a pure +create provision must never contain.
TOKEN_FORGET="$(rc_obj 'doppler_service_token.workspaces_luks' '"forget"')"
write_plan "${PW_CREATE},${SECRET_CREATE},${TOKEN_FORGET},${VOL_CREATE},${ATT_CREATE}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T9: a forget of an in-set resource (resource_deletes) must ABORT (rc=1)"
else
  pass
fi

# --- Test 10: FAIL — the LUKS volume create is MISSING (anti-no-op / anti-vacuity) ---
# The volume shows an explicit ["no-op"] → luks_volume_created==0. A gate that only checked the
# "must-not-touch" backstops (and forgot the positive anti-no-op floor) would wrongly pass a plan
# that provisions nothing.
VOL_NOOP="$(rc_obj 'hcloud_volume.workspaces_luks' '"no-op"')"
write_plan "${PW_CREATE},${SECRET_CREATE},${TOKEN_CREATE},${VOL_NOOP},${ATT_CREATE}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T10: a missing LUKS volume create (luks_volume_created==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 11: FAIL — the attachment create is MISSING (volume created but never attached) ---
# ISOLATES luks_attachment_created==0: the volume exists but /mnt/data would never see it.
ATT_NOOP="$(rc_obj 'hcloud_volume_attachment.workspaces_luks' '"no-op"')"
write_plan "${PW_CREATE},${SECRET_CREATE},${TOKEN_CREATE},${VOL_CREATE},${ATT_NOOP}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T11: a missing attachment create (luks_attachment_created==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 12: FAIL — the doppler_secret create is MISSING (escrow would have no key to read) ---
# ISOLATES luks_secret_created==0: without WORKSPACES_LUKS_KEY the host cannot unlock the mapper.
SECRET_NOOP="$(rc_obj 'doppler_secret.workspaces_luks_key' '"no-op"')"
write_plan "${PW_CREATE},${SECRET_NOOP},${TOKEN_CREATE},${VOL_CREATE},${ATT_CREATE}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T12: a missing doppler_secret create (luks_secret_created==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 13: FAIL — a no-op plan (nothing provisioned at all) ---
ALL_NOOP="$(rc_obj 'hcloud_volume.workspaces_luks' '"no-op"')"
write_plan "${ALL_NOOP}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T13: a no-op plan (luks_volume_created==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 14: PASS — the untargeted old volume/attachment appear as explicit ["no-op"] ---
# A live scoped plan may LIST the untargeted live resources as no-ops rather than omitting them;
# the positive-action filter must EXCLUDE no-op, so the provision still PASSes.
OLD_VOL_NOOP="$(rc_obj 'hcloud_volume.workspaces[\"web-1\"]' '"no-op"')"
OLD_ATT_NOOP="$(rc_obj 'hcloud_volume_attachment.workspaces[\"web-1\"]' '"no-op"')"
WEB1_NOOP="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"no-op"')"
write_plan "${PASS_SET},${OLD_VOL_NOOP},${OLD_ATT_NOOP},${WEB1_NOOP}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T14: the first provision with the live resources as explicit no-op should PASS (rc=0)"
fi

# --- Test 15: PASS — a data-source ["read"] AND an out-of-allow-set ["no-op"] ---
# The positive-action filter must EXCLUDE both `read` (data source) and `no-op` (a stray in-graph
# resource): neither is a positive action, so the plan still PASSes.
DATA_READ="$(rc_obj 'data.hcloud_image.workspaces_os' '"read"')"
WEB2_NOOP="$(rc_obj 'hcloud_server.web[\"web-2\"]' '"no-op"')"
write_plan "${PASS_SET},${DATA_READ},${WEB2_NOOP}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T15: a plan with a data-source read + an out-of-scope no-op should still PASS (rc=0)"
fi

# --- Test 16: FAIL — the LUKS volume is FORGOTTEN (dropped from state, not managed) ---
# A `forget` of the just-created volume: luks_volume_destroyed (delete OR forget) + resource_deletes
# fire while luks_volume_created==0 too — a compound abort, but the class the gate must catch.
VOL_FORGET="$(rc_obj 'hcloud_volume.workspaces_luks' '"forget"')"
write_plan "${PW_CREATE},${SECRET_CREATE},${TOKEN_CREATE},${VOL_FORGET},${ATT_CREATE}"
if workspaces_luks_cutover_gate "$TMP/plan.json" >/dev/null; then
  fail "T16: a LUKS volume forget (luks_volume_destroyed) must ABORT (rc=1)"
else
  pass
fi

echo ""
echo "=== test-workspaces-luks-cutover-gate.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
