#!/usr/bin/env bash
# Tests for tests/scripts/lib/workspaces-luks-recut-gate.sh (sourced by the workspaces_luks_recut
# job in .github/workflows/apply-web-platform-infra.yml, #6855 / #6812).
#
# The gate reads a `terraform show -json <plan>` document and PASSes (rc=0) iff the plan is EXACTLY
# the scoped workspaces-luks RECUT: hcloud_volume.workspaces_luks REPLACED (actions include BOTH
# "delete" AND "create") OR the RECOVERY bare create (["create"] with before==null), plus
# hcloud_volume_attachment.workspaces_luks re-CREATED, with the LIVE plaintext /mnt/data volume + its
# attachment + the web-1 server PRESERVED (untouched), the passphrase + its doppler_secret REUSED
# (untouched — NOT re-minted), the replaced-volume id matching the operator-supplied expected id
# (when provided), and nothing else out of scope.
#
# Non-vacuity discipline (RED-verification for a gating primitive): each FAIL fixture differs from
# the PASS fixture by ONE mutation of the exact class the gate must catch. Deterministic; no network.
# All fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only) — modeled on the -replace plan
# shape; no captured real plan.
#
# Run: bash tests/scripts/test-workspaces-luks-recut-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/scripts/lib/workspaces-luks-recut-gate.sh
source "${DIR}/lib/workspaces-luks-recut-gate.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ORPHAN_ID="106406962"   # the orphaned LUKS volume the operator authorizes destroying
LIVE_ID="105149570"     # the LIVE plaintext /mnt/data volume — must never be the destroy target

# A resource_change object with the given address + actions array (no `before`).
rc_obj() { printf '{"address":"%s","change":{"actions":[%s]}}' "$1" "$2"; }
# A resource_change object carrying a `before.id` (the physical volume being acted on).
rc_obj_id() { printf '{"address":"%s","change":{"actions":[%s],"before":{"id":"%s"}}}' "$1" "$2" "$3"; }
write_plan() { printf '{"resource_changes":[%s]}' "$1" > "$TMP/plan.json"; }

# The scoped recut: the LUKS volume shows a REPLACE (["delete","create"]) carrying the orphaned id;
# its attachment shows a REPLACE too.
VOL_REPLACE_ID="$(rc_obj_id 'hcloud_volume.workspaces_luks' '"delete","create"' "$ORPHAN_ID")"
ATT_REPLACE="$(rc_obj 'hcloud_volume_attachment.workspaces_luks' '"delete","create"')"
# The live plaintext volume/attachment + web-1 server appear as no-op (untargeted deps in the plan).
OLDVOL_NOOP="$(rc_obj 'hcloud_volume.workspaces[\"web-1\"]' '"no-op"')"
OLDATT_NOOP="$(rc_obj 'hcloud_volume_attachment.workspaces[\"web-1\"]' '"no-op"')"
WEB1_NOOP="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"no-op"')"
# The passphrase + its doppler_secret are untouched (no-op) — the recut reuses the existing key.
PW_NOOP="$(rc_obj 'random_password.workspaces_luks' '"no-op"')"
SECRET_NOOP="$(rc_obj 'doppler_secret.workspaces_luks_key' '"no-op"')"

# The canonical PASS fixture.
PASS_SET="${VOL_REPLACE_ID},${ATT_REPLACE},${OLDVOL_NOOP},${OLDATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"

# --- Test 1: PASS — exact scoped recut, id-pinned to the orphaned volume ---
write_plan "${PASS_SET}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then pass; else fail "Test 1: exact scoped recut (id-pinned) should PASS"; fi

# --- Test 2 (recovery arm): bare volume create with before==null + expected id ⇒ PASS ---
# A stranded destroy-before-create partial apply leaves the volume absent; a re-dispatch plans a
# bare create. The gate ACCEPTS it (fresh empty volume, no live data touched); the id-pin is a no-op
# because there is no before.id to destroy.
write_plan "$(rc_obj 'hcloud_volume.workspaces_luks' '"create"'),$(rc_obj 'hcloud_volume_attachment.workspaces_luks' '"create"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then pass; else fail "Test 2: recovery bare create (before null) should PASS"; fi

# --- Test 3: volume shows only ["delete"]/["forget"] (no recreate) ⇒ ABORT ---
write_plan "$(rc_obj_id 'hcloud_volume.workspaces_luks' '"delete"' "$ORPHAN_ID"),${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 3a: bare volume delete should ABORT"; else pass; fi
write_plan "$(rc_obj_id 'hcloud_volume.workspaces_luks' '"forget"' "$ORPHAN_ID"),${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 3b: bare volume forget should ABORT"; else pass; fi

# --- Test 4: live plaintext volume hcloud_volume.workspaces["web-1"] touched ⇒ ABORT ---
write_plan "${VOL_REPLACE_ID},${ATT_REPLACE},$(rc_obj 'hcloud_volume.workspaces[\"web-1\"]' '"delete","create"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 4: touching the live plaintext volume should ABORT"; else pass; fi

# --- Test 5: live plaintext attachment touched ⇒ ABORT ---
write_plan "${VOL_REPLACE_ID},${ATT_REPLACE},$(rc_obj 'hcloud_volume_attachment.workspaces[\"web-1\"]' '"delete"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 5: touching the live plaintext attachment should ABORT"; else pass; fi

# --- Test 6: web-1 server touched ⇒ ABORT (cx33 unrebuildable) ---
write_plan "${VOL_REPLACE_ID},${ATT_REPLACE},$(rc_obj 'hcloud_server.web[\"web-1\"]' '"delete","create"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 6: replacing the web-1 server should ABORT"; else pass; fi

# --- Test 7: passphrase re-minted (create/update) ⇒ ABORT (F4 header loss; create INCLUDED) ---
write_plan "${VOL_REPLACE_ID},${ATT_REPLACE},$(rc_obj 'random_password.workspaces_luks' '"create"'),${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 7a: passphrase create/re-mint should ABORT"; else pass; fi
write_plan "${VOL_REPLACE_ID},${ATT_REPLACE},$(rc_obj 'random_password.workspaces_luks' '"update"'),${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 7b: passphrase update should ABORT"; else pass; fi

# --- Test 8: doppler_secret.workspaces_luks_key touched ⇒ ABORT ---
write_plan "${VOL_REPLACE_ID},${ATT_REPLACE},${PW_NOOP},$(rc_obj 'doppler_secret.workspaces_luks_key' '"update"')"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 8: touching the doppler_secret should ABORT"; else pass; fi

# --- Test 9: doppler_service_token.workspaces_luks touched ⇒ ABORT (out_of_scope) ---
write_plan "${VOL_REPLACE_ID},${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP},$(rc_obj 'doppler_service_token.workspaces_luks' '"update"')"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 9: touching the service token should ABORT (out_of_scope)"; else pass; fi

# --- Test 10: any un-enumerated address with a positive action ⇒ ABORT ---
write_plan "${VOL_REPLACE_ID},${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP},$(rc_obj 'hcloud_server.inngest' '"delete","create"')"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 10: an out-of-scope resource action should ABORT"; else pass; fi

# --- Test 11: a delete/forget of an out-of-scope resource ⇒ ABORT (resource_deletes) ---
write_plan "${VOL_REPLACE_ID},${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP},$(rc_obj 'hcloud_volume.registry' '"delete"')"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 11: an out-of-scope delete should ABORT (resource_deletes)"; else pass; fi

# --- Test 12: attachment missing its create ⇒ ABORT (new volume unmounted) ---
write_plan "${VOL_REPLACE_ID},$(rc_obj 'hcloud_volume_attachment.workspaces_luks' '"delete"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 12: attachment without a create should ABORT"; else pass; fi

# --- Test 13: malformed / missing plan JSON ⇒ fail-closed (rc=1) ---
if workspaces_luks_recut_gate "$TMP/does-not-exist.json" "$ORPHAN_ID" >/dev/null; then fail "Test 13a: missing plan JSON should fail-closed"; else pass; fi
printf 'not json{{{' > "$TMP/bad.json"
if workspaces_luks_recut_gate "$TMP/bad.json" "$ORPHAN_ID" >/dev/null; then fail "Test 13b: malformed plan JSON should fail-closed"; else pass; fi

# --- Test 14: PASS survives create_before_destroy ordering (["create","delete"]) ---
write_plan "$(rc_obj_id 'hcloud_volume.workspaces_luks' '"create","delete"' "$ORPHAN_ID"),${ATT_REPLACE},${OLDVOL_NOOP},${OLDATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then pass; else fail "Test 14: create_before_destroy replace ordering should PASS"; fi

# --- Test 15 (ID-PIN): replace whose before.id is the LIVE volume id ⇒ ABORT ---
# The address-drift catastrophe: state maps hcloud_volume.workspaces_luks → the live volume's
# physical id. The id-pin catches it even though every address-based counter reads 0.
write_plan "$(rc_obj_id 'hcloud_volume.workspaces_luks' '"delete","create"' "$LIVE_ID"),${ATT_REPLACE},${OLDVOL_NOOP},${OLDATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 15: replace of the WRONG physical id (live volume) should ABORT (id-pin)"; else pass; fi

# --- Test 16 (ID-PIN skipped): same wrong-id replace but NO expected id ⇒ PASS (backward compat) ---
# When the caller passes no expected id, the id-pin is skipped and only the address model applies.
write_plan "$(rc_obj_id 'hcloud_volume.workspaces_luks' '"delete","create"' "$LIVE_ID"),${ATT_REPLACE},${OLDVOL_NOOP},${OLDATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then pass; else fail "Test 16: replace with no expected id should PASS (id-pin skipped, address model only)"; fi

# --- Test 17: volume update-in-place (no replace, no recovery create) ⇒ ABORT ---
write_plan "$(rc_obj_id 'hcloud_volume.workspaces_luks' '"update"' "$ORPHAN_ID"),${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 17: volume update-in-place should ABORT"; else pass; fi

# --- Test 18 (recovery arm, no expected id): bare create with before null ⇒ PASS ---
write_plan "$(rc_obj 'hcloud_volume.workspaces_luks' '"create"'),$(rc_obj 'hcloud_volume_attachment.workspaces_luks' '"create"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then pass; else fail "Test 18: recovery bare create (no expected id) should PASS"; fi

echo ""
echo "workspaces-luks-recut-gate: ${passes} passed, ${fails} failed"
[[ "$fails" -eq 0 ]]
