#!/usr/bin/env bash
# Tests for tests/scripts/lib/git-data-host-replace-gate.sh (sourced by the
# git_data_host_replace job in .github/workflows/apply-web-platform-infra.yml, #6242).
#
# The gate reads a `terraform show -json <plan>` document and PASSes (rc=0) iff the plan
# is EXACTLY the scoped git-data-host recreate: hcloud_server.git_data + its 4 dependents
# (server_network + BOTH volume_attachments replaced, firewall_attachment update-in-place),
# with BOTH data volumes (hcloud_volume.git_data + hcloud_volume.git_data_luks) and the LUKS
# passphrase (random_password.git_data_luks + doppler_secret.git_data_luks_key) PRESERVED BY
# OMISSION (not in the -target set, so any positive action on them is out_of_scope), the new
# host positively re-attached to its private NIC + both stores + deny-all firewall, and no
# out-of-scope change. It has a 5-member allow-set with SEPARATE plaintext/LUKS attachment
# counters (a LUKS-specific store the registry gate has no analog for) — do NOT simplify it to
# the registry or inngest shape.
#
# Non-vacuity discipline (RED-verification for a gating primitive): each FAIL fixture
# differs from the PASS fixture by ONE mutation of the exact class the gate must catch,
# so a gate that ignored that class would wrongly pass. Deterministic; no network.
# All fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only) — modeled on the scoped
# -replace plan shape (server/network/both-attachments=delete+create,
# firewall_attachment=update, volumes/passphrase=no-op/absent). No captured real plan file.
#
# Run: bash tests/scripts/test-git-data-host-replace-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/scripts/lib/git-data-host-replace-gate.sh
source "${DIR}/lib/git-data-host-replace-gate.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A resource_change object with the given address + actions array.
rc_obj() { printf '{"address":"%s","change":{"actions":[%s]}}' "$1" "$2"; }

# The scoped git-data recreate: server + server_network + BOTH volume_attachments REPLACE
# (delete+create); firewall_attachment UPDATE-in-place (server_ids re-point). The two data
# volumes + the LUKS passphrase are UNTARGETED → they do not appear in resource_changes at all
# (preserved by omission). Test 8 exercises the explicit-no-op variant.
SERVER_REPLACE="$(rc_obj 'hcloud_server.git_data' '"delete","create"')"
NET_REPLACE="$(rc_obj 'hcloud_server_network.git_data' '"delete","create"')"
VA_REPLACE="$(rc_obj 'hcloud_volume_attachment.git_data' '"delete","create"')"
VA_LUKS_REPLACE="$(rc_obj 'hcloud_volume_attachment.git_data_luks' '"delete","create"')"
FW_UPDATE="$(rc_obj 'hcloud_firewall_attachment.git_data' '"update"')"

write_plan() { printf '{"resource_changes":[%s]}' "$1" > "$TMP/plan.json"; }

# The canonical PASS fixture (referenced by later single-mutation tests).
PASS_SET="${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${VA_LUKS_REPLACE},${FW_UPDATE}"

# --- Test 1: PASS — exact scoped recreate; both volumes + passphrase preserved by omission ---
write_plan "${PASS_SET}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T1: exact scoped git-data recreate (both stores + LUKS passphrase omitted) should PASS (rc=0)"
fi

# --- Test 2: FAIL — the plaintext bare-repo volume is DELETED (a user's git history) ---
GVOL_DELETE="$(rc_obj 'hcloud_volume.git_data' '"delete"')"
write_plan "${PASS_SET},${GVOL_DELETE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T2: a git-data volume delete must ABORT (rc=1)"
else
  pass
fi

# --- Test 3: FAIL — the LUKS at-rest volume is DELETED (Art.17 store + rollback backstop) ---
LVOL_DELETE="$(rc_obj 'hcloud_volume.git_data_luks' '"delete"')"
write_plan "${PASS_SET},${LVOL_DELETE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T3: a LUKS volume delete must ABORT (rc=1)"
else
  pass
fi

# --- Test 4: FAIL — the LUKS at-rest volume is REPLACED (delete+create — data lost) ---
LVOL_REPLACE="$(rc_obj 'hcloud_volume.git_data_luks' '"delete","create"')"
write_plan "${PASS_SET},${LVOL_REPLACE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T4: a LUKS volume replace (delete+create) must ABORT (rc=1)"
else
  pass
fi

# --- Test 5: FAIL — the LUKS passphrase is ROTATED (random_password update) ---
# A rotated passphrase luksOpens a NEW header on fresh boot, stranding the existing at-rest
# data. random_password.git_data_luks is out of the allow-set → out_of_scope AND the named
# luks_passphrase_touched backstop both fire.
LUKS_PW_UPDATE="$(rc_obj 'random_password.git_data_luks' '"delete","create"')"
write_plan "${PASS_SET},${LUKS_PW_UPDATE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T5: a LUKS passphrase rotation (random_password replace) must ABORT (rc=1)"
else
  pass
fi

# --- Test 6: FAIL — the LUKS key doppler_secret is UPDATED (passphrase-carrier drift) ---
LUKS_SECRET_UPDATE="$(rc_obj 'doppler_secret.git_data_luks_key' '"update"')"
write_plan "${PASS_SET},${LUKS_SECRET_UPDATE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T6: a LUKS key doppler_secret update (luks_passphrase_touched) must ABORT (rc=1)"
else
  pass
fi

# --- Test 7: FAIL — an out-of-scope resource change (a stray web host update) ---
WEB_UPDATE="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"update"')"
write_plan "${PASS_SET},${WEB_UPDATE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T7: an out-of-scope change must ABORT (rc=1)"
else
  pass
fi

# --- Test 8: PASS — the volumes/passphrase appear as explicit ["no-op"] (still preserved) ---
# A live scoped plan may list the untargeted resources as no-ops rather than omitting them; the
# positive-action out_of_scope filter must EXCLUDE no-op, so the plan still PASSes.
GVOL_NOOP="$(rc_obj 'hcloud_volume.git_data' '"no-op"')"
LVOL_NOOP="$(rc_obj 'hcloud_volume.git_data_luks' '"no-op"')"
LUKS_PW_NOOP="$(rc_obj 'random_password.git_data_luks' '"no-op"')"
LUKS_SECRET_NOOP="$(rc_obj 'doppler_secret.git_data_luks_key' '"no-op"')"
write_plan "${PASS_SET},${GVOL_NOOP},${LVOL_NOOP},${LUKS_PW_NOOP},${LUKS_SECRET_NOOP}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T8: the scoped recreate with volumes/passphrase as explicit no-op should PASS (rc=0)"
fi

# --- Test 9: FAIL — no-op plan (server not actually replaced) ---
SERVER_NOOP="$(rc_obj 'hcloud_server.git_data' '"no-op"')"
write_plan "${SERVER_NOOP}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T9: a no-op plan (server_replaced==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 10: FAIL — server replaced but private NIC stripped (network only deleted) ---
# hcloud_server_network.git_data shows ONLY delete (no create) → the new host boots with no
# private NIC (10.0.1.20), no transport path for web-host push/pull. nic_recreated==0 must ABORT.
NET_DELETE_ONLY="$(rc_obj 'hcloud_server_network.git_data' '"delete"')"
write_plan "${SERVER_REPLACE},${NET_DELETE_ONLY},${VA_REPLACE},${VA_LUKS_REPLACE},${FW_UPDATE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T10: a NIC-stripped plan (nic_recreated==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 11: FAIL — plaintext bare-repo attachment stripped (delete only, no create) ---
# ISOLATES plaintext_attachment_recreated==0: the new host boots with /mnt/git-data UNMOUNTED
# (the plaintext store) while the LUKS attachment, NIC, firewall all pass.
VA_DELETE_ONLY="$(rc_obj 'hcloud_volume_attachment.git_data' '"delete"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_DELETE_ONLY},${VA_LUKS_REPLACE},${FW_UPDATE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T11: a plaintext-store-attachment-stripped plan (plaintext_attachment_recreated==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 12: FAIL — LUKS attachment stripped (delete only, no create) ---
# ISOLATES luks_attachment_recreated==0: the new host boots with /mnt/git-data-luks UNMOUNTED
# (the at-rest store) while the plaintext attachment, NIC, firewall all pass. This is the
# SEPARATE second store counter with no registry analog.
VA_LUKS_DELETE_ONLY="$(rc_obj 'hcloud_volume_attachment.git_data_luks' '"delete"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${VA_LUKS_DELETE_ONLY},${FW_UPDATE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T12: a LUKS-store-attachment-stripped plan (luks_attachment_recreated==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 13: FAIL — deny-all firewall stripped (firewall_attachment = ["delete"]) ---
# ISOLATES firewall_ok==0: the new host is naked on its public IP. Every other clause holds.
FW_DELETE="$(rc_obj 'hcloud_firewall_attachment.git_data' '"delete"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${VA_LUKS_REPLACE},${FW_DELETE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T13: a firewall-stripped plan (firewall_ok==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 14: FAIL — server updated in-place, NOT replaced (no fresh cloud-init) ---
# server = ["update"] (no delete+create) so cloud-init never re-runs. ISOLATES
# server_replaced==0 (oos=0 since update is in-allow-set; every other clause holds).
SERVER_UPDATE="$(rc_obj 'hcloud_server.git_data' '"update"')"
write_plan "${SERVER_UPDATE},${NET_REPLACE},${VA_REPLACE},${VA_LUKS_REPLACE},${FW_UPDATE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T14: an in-place server update (server_replaced==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 15: PASS — a data-source ["read"] AND an out-of-allow-set ["no-op"] ---
# The positive-action out_of_scope filter must EXCLUDE both `read` (data source) and `no-op`
# (a stray in-graph resource): neither is a positive action, so the plan still PASSes.
DATA_READ="$(rc_obj 'data.hcloud_image.git_data_os' '"read"')"
WEB_NOOP="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"no-op"')"
write_plan "${PASS_SET},${DATA_READ},${WEB_NOOP}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T15: a plan with a data-source read + an out-of-scope no-op should still PASS (rc=0)"
fi

# --- Test 16: FAIL — the plaintext bare-repo volume is FORGOTTEN (removed from state) ---
# A `forget` drops the volume from state without destroying it — but the new host would then not
# manage/mount it. git_data_volume_destroyed counts delete OR forget → must ABORT.
GVOL_FORGET="$(rc_obj 'hcloud_volume.git_data' '"forget"')"
write_plan "${PASS_SET},${GVOL_FORGET}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T16: a git-data volume forget (git_data_volume_destroyed) must ABORT (rc=1)"
else
  pass
fi

echo ""
echo "=== test-git-data-host-replace-gate.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
