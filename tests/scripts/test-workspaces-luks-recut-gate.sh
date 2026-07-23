#!/usr/bin/env bash
# Tests for tests/scripts/lib/workspaces-luks-recut-gate.sh (sourced by the workspaces_luks_recut
# job in .github/workflows/apply-web-platform-infra.yml, #6855 / #6812).
#
# The gate reads a `terraform show -json <plan>` document and PASSes (rc=0) iff the plan is EXACTLY
# the scoped workspaces-luks RECUT: hcloud_volume.workspaces_luks REPLACED (actions include BOTH
# "delete" AND "create") + hcloud_volume_attachment.workspaces_luks re-CREATED, with the LIVE
# plaintext /mnt/data volume + its attachment + the web-1 server PRESERVED (untouched), the
# passphrase + its doppler_secret REUSED (untouched — NOT re-minted), and nothing else out of scope.
#
# Non-vacuity discipline (RED-verification for a gating primitive): each FAIL fixture differs from
# the PASS fixture by ONE mutation of the exact class the gate must catch, so a gate that ignored
# that class would wrongly pass. Deterministic; no network. All fixtures are SYNTHESIZED
# (cq-test-fixtures-synthesized-only) — modeled on the -replace plan shape; no captured real plan.
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

# A resource_change object with the given address + actions array.
rc_obj() { printf '{"address":"%s","change":{"actions":[%s]}}' "$1" "$2"; }
write_plan() { printf '{"resource_changes":[%s]}' "$1" > "$TMP/plan.json"; }

# The scoped recut: the LUKS volume + its attachment show a REPLACE (["delete","create"]).
VOL_REPLACE="$(rc_obj 'hcloud_volume.workspaces_luks' '"delete","create"')"
ATT_REPLACE="$(rc_obj 'hcloud_volume_attachment.workspaces_luks' '"delete","create"')"
# The live plaintext volume/attachment + web-1 server appear as no-op (untargeted deps in the plan).
OLDVOL_NOOP="$(rc_obj 'hcloud_volume.workspaces[\"web-1\"]' '"no-op"')"
OLDATT_NOOP="$(rc_obj 'hcloud_volume_attachment.workspaces[\"web-1\"]' '"no-op"')"
WEB1_NOOP="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"no-op"')"
# The passphrase + its doppler_secret are untouched (no-op) — the recut reuses the existing key.
PW_NOOP="$(rc_obj 'random_password.workspaces_luks' '"no-op"')"
SECRET_NOOP="$(rc_obj 'doppler_secret.workspaces_luks_key' '"no-op"')"

# The canonical PASS fixture.
PASS_SET="${VOL_REPLACE},${ATT_REPLACE},${OLDVOL_NOOP},${OLDATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"

# --- Test 1: PASS — the exact scoped recut (volume + attachment replace, everything else preserved) ---
write_plan "${PASS_SET}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then pass; else fail "Test 1: exact scoped recut should PASS"; fi

# --- Test 2 (mutation a): volume shows only ["create"] (not a replace) ⇒ ABORT ---
# Proves the gate REQUIRES a genuine replace, not a bare create (which would mean the orphaned
# volume was never in state — the recut would then not be discarding the stale window).
write_plan "$(rc_obj 'hcloud_volume.workspaces_luks' '"create"'),${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 2: bare volume create (no replace) should ABORT"; else pass; fi

# --- Test 3 (mutation b): volume shows only ["delete"]/["forget"] (no recreate) ⇒ ABORT ---
write_plan "$(rc_obj 'hcloud_volume.workspaces_luks' '"delete"'),${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 3a: bare volume delete should ABORT"; else pass; fi
write_plan "$(rc_obj 'hcloud_volume.workspaces_luks' '"forget"'),${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 3b: bare volume forget should ABORT"; else pass; fi

# --- Test 4 (mutation c): live plaintext volume hcloud_volume.workspaces[\"web-1\"] touched ⇒ ABORT ---
# The AC20 STOP — the sole-copy /mnt/data must be untouched.
write_plan "${VOL_REPLACE},${ATT_REPLACE},$(rc_obj 'hcloud_volume.workspaces[\"web-1\"]' '"delete","create"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 4: touching the live plaintext volume should ABORT"; else pass; fi

# --- Test 5 (mutation d): live plaintext attachment touched ⇒ ABORT ---
write_plan "${VOL_REPLACE},${ATT_REPLACE},$(rc_obj 'hcloud_volume_attachment.workspaces[\"web-1\"]' '"delete"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 5: touching the live plaintext attachment should ABORT"; else pass; fi

# --- Test 6 (mutation e): web-1 server touched ⇒ ABORT ---
# cx33 unrebuildable — a replaced web-1 is "the product is gone".
write_plan "${VOL_REPLACE},${ATT_REPLACE},$(rc_obj 'hcloud_server.web[\"web-1\"]' '"delete","create"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 6: replacing the web-1 server should ABORT"; else pass; fi

# --- Test 7 (mutation f): passphrase re-minted (create/update) ⇒ ABORT ---
# The recut REUSES the existing key. Any touch (create INCLUDED — the inversion vs the cutover gate)
# opens a new header and strands the at-rest data (F4).
write_plan "${VOL_REPLACE},${ATT_REPLACE},$(rc_obj 'random_password.workspaces_luks' '"create"'),${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 7a: passphrase create/re-mint should ABORT"; else pass; fi
write_plan "${VOL_REPLACE},${ATT_REPLACE},$(rc_obj 'random_password.workspaces_luks' '"update"'),${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 7b: passphrase update should ABORT"; else pass; fi

# --- Test 8 (mutation g): doppler_secret.workspaces_luks_key touched ⇒ ABORT ---
write_plan "${VOL_REPLACE},${ATT_REPLACE},${PW_NOOP},$(rc_obj 'doppler_secret.workspaces_luks_key' '"update"')"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 8: touching the doppler_secret should ABORT"; else pass; fi

# --- Test 9 (mutation h): doppler_service_token.workspaces_luks touched ⇒ ABORT (out_of_scope) ---
# The token is deliberately NOT named-live, so a touch fires out_of_scope.
write_plan "${VOL_REPLACE},${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP},$(rc_obj 'doppler_service_token.workspaces_luks' '"update"')"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 9: touching the service token should ABORT (out_of_scope)"; else pass; fi

# --- Test 10 (mutation i): any un-enumerated address with a positive action ⇒ ABORT ---
write_plan "${VOL_REPLACE},${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP},$(rc_obj 'hcloud_server.inngest' '"delete","create"')"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 10: an out-of-scope resource action should ABORT"; else pass; fi

# --- Test 11 (mutation): a delete/forget of an out-of-scope resource ⇒ ABORT (resource_deletes) ---
write_plan "${VOL_REPLACE},${ATT_REPLACE},${PW_NOOP},${SECRET_NOOP},$(rc_obj 'hcloud_volume.registry' '"delete"')"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 11: an out-of-scope delete should ABORT (resource_deletes)"; else pass; fi

# --- Test 12 (mutation): attachment missing its create ⇒ ABORT (new volume unmounted) ---
write_plan "${VOL_REPLACE},$(rc_obj 'hcloud_volume_attachment.workspaces_luks' '"delete"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then fail "Test 12: attachment without a create should ABORT"; else pass; fi

# --- Test 13 (mutation j): malformed / missing plan JSON ⇒ fail-closed (rc=1) ---
if workspaces_luks_recut_gate "$TMP/does-not-exist.json" >/dev/null; then fail "Test 13a: missing plan JSON should fail-closed"; else pass; fi
printf 'not json{{{' > "$TMP/bad.json"
if workspaces_luks_recut_gate "$TMP/bad.json" >/dev/null; then fail "Test 13b: malformed plan JSON should fail-closed"; else pass; fi

# --- Test 14: PASS survives create_before_destroy ordering (["create","delete"]) ---
# The replace check is order-independent — a create_before_destroy lifecycle qualifies too.
write_plan "$(rc_obj 'hcloud_volume.workspaces_luks' '"create","delete"'),${ATT_REPLACE},${OLDVOL_NOOP},${OLDATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" >/dev/null; then pass; else fail "Test 14: create_before_destroy replace ordering should PASS"; fi

echo ""
echo "workspaces-luks-recut-gate: ${passes} passed, ${fails} failed"
[[ "$fails" -eq 0 ]]
