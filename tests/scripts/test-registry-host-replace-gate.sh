#!/usr/bin/env bash
# Tests for tests/scripts/lib/registry-host-replace-gate.sh (sourced by the
# registry_host_replace job in .github/workflows/apply-web-platform-infra.yml,
# fix: registry-host-replace CI path + Better Stack ops@ recipient IaC).
#
# The gate reads a `terraform show -json <plan>` document and PASSes (rc=0) iff the plan
# is EXACTLY the scoped registry-host recreate: hcloud_server.registry + its 3 dependents
# (server_network + volume_attachment replaced, firewall_attachment update-in-place), the
# zot storage volume PRESERVED (a size-increasing in-place update OR no-op only), the new
# host positively re-attached to its private NIC + deny-all firewall, and no out-of-scope
# change. It has a LARGER allow-set (6 vs inngest's 3) and MORE positive assertions
# (nic_recreated / firewall_ok / volume-preserve) — do NOT simplify it to the inngest shape.
#
# Non-vacuity discipline (RED-verification for a gating primitive): each FAIL fixture
# differs from the PASS fixture by ONE mutation of the exact class the gate must catch,
# so a gate that ignored that class would wrongly pass. Deterministic; no network.
# All fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only) — seeded from the
# Phase 0.5 real scoped plan (server/network/volume_attachment=delete+create,
# firewall_attachment=update, volume=no-op/update). No captured real plan file.
#
# Run: bash tests/scripts/test-registry-host-replace-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/scripts/lib/registry-host-replace-gate.sh
source "${DIR}/lib/registry-host-replace-gate.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A resource_change object with the given address + actions array.
rc_obj() { printf '{"address":"%s","change":{"actions":[%s]}}' "$1" "$2"; }

# The scoped registry recreate, matching the Phase 0.5 real plan shape:
#   server + server_network + volume_attachment REPLACE (delete+create);
#   firewall_attachment UPDATE-in-place (server_ids re-point); volume size UPDATE (preserve).
SERVER_REPLACE="$(rc_obj 'hcloud_server.registry' '"delete","create"')"
NET_REPLACE="$(rc_obj 'hcloud_server_network.registry' '"delete","create"')"
VA_REPLACE="$(rc_obj 'hcloud_volume_attachment.registry' '"delete","create"')"
FW_UPDATE="$(rc_obj 'hcloud_firewall_attachment.registry' '"update"')"
VOL_UPDATE="$(rc_obj 'hcloud_volume.registry' '"update"')"
# #6244: the isolated Better Stack Logs token secret rides the SAME dispatch — a pure-create on
# first apply. The gate must PERMIT it (allow-set member), NOT count it as out_of_scope.
SECRET_CREATE="$(rc_obj 'doppler_secret.registry_betterstack_logs_token' '"create"')"

write_plan() { printf '{"resource_changes":[%s]}' "$1" > "$TMP/plan.json"; }

# --- Test 1: PASS — exact scoped recreate WITH the volume size ["update"] + the logs-token
# secret create (the REAL post-#6244 dispatch shape) preserved ---
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FW_UPDATE},${VOL_UPDATE},${SECRET_CREATE}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T1: exact scoped registry recreate (volume size-update + logs-token secret create) should PASS (rc=0)"
fi

# --- Test 2: FAIL — the zot store volume is DELETED (the preservation invariant) ---
VOL_DELETE="$(rc_obj 'hcloud_volume.registry' '"delete"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FW_UPDATE},${VOL_DELETE}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T2: a zot store volume delete must ABORT (rc=1)"
else
  pass
fi

# --- Test 3: FAIL — the zot store volume is REPLACED (delete+create — data lost) ---
VOL_REPLACE="$(rc_obj 'hcloud_volume.registry' '"delete","create"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FW_UPDATE},${VOL_REPLACE}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T3: a zot store volume replace (delete+create) must ABORT (rc=1)"
else
  pass
fi

# --- Test 4: FAIL — an out-of-scope resource change (a stray web host update) ---
WEB_UPDATE="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"update"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FW_UPDATE},${VOL_UPDATE},${WEB_UPDATE}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T4: an out-of-scope change must ABORT (rc=1)"
else
  pass
fi

# --- Test 5: FAIL — no-op plan (server not actually replaced) ---
SERVER_NOOP="$(rc_obj 'hcloud_server.registry' '"no-op"')"
write_plan "${SERVER_NOOP}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T5: a no-op plan (server_replaced==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 6: FAIL — server replaced but private NIC stripped (network only deleted) ---
# hcloud_server_network.registry shows ONLY delete (no create) → the new host boots with
# no private NIC (10.0.1.30), invisible to web-host pulls. nic_recreated==0 must ABORT.
NET_DELETE_ONLY="$(rc_obj 'hcloud_server_network.registry' '"delete"')"
write_plan "${SERVER_REPLACE},${NET_DELETE_ONLY},${VA_REPLACE},${FW_UPDATE},${VOL_UPDATE}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T6: a NIC-stripped plan (nic_recreated==0) must ABORT (rc=1)"
else
  pass
fi

# The following fixtures each isolate EXACTLY ONE failing clause (mutation reasoning:
# removing that clause from the PASS predicate would flip the fixture to PASS), so no
# assertion is vacuous. Additional building blocks:
FW_DELETE="$(rc_obj 'hcloud_firewall_attachment.registry' '"delete"')"
VOL_NOOP="$(rc_obj 'hcloud_volume.registry' '"no-op"')"
VOL_FORGET="$(rc_obj 'hcloud_volume.registry' '"forget"')"
SERVER_UPDATE="$(rc_obj 'hcloud_server.registry' '"update"')"
VA_DELETE_ONLY="$(rc_obj 'hcloud_volume_attachment.registry' '"delete"')"
DATA_READ="$(rc_obj 'data.hcloud_image.registry_os' '"read"')"
WEB_NOOP="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"no-op"')"

# --- Test 7 (a): FAIL — deny-all firewall stripped (firewall_attachment = ["delete"]) ---
# server replaced + NIC create + volume-attachment create + volume no-op, but the firewall
# attachment is deleted → the new host is naked on its public IP. ISOLATES firewall_ok==0
# (every other clause holds: oos=0, store=0, vol=ok, server=1, nic>=1, attachment>=1).
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FW_DELETE},${VOL_NOOP}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T7(a): a firewall-stripped plan (firewall_ok==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 8 (b): PASS — the REAL live state: volume already 30 GB → ["no-op"] ---
# The store volume is already resized, so a live scoped plan shows it as a no-op (not an
# update). The gate must PASS on this — no-op is a permitted, store-preserving action.
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FW_UPDATE},${VOL_NOOP}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T8(b): the live scoped recreate with volume ['no-op'] should PASS (rc=0)"
fi

# --- Test 9 (c): FAIL — the zot store volume is FORGOTTEN (removed from state) ---
# A `forget` drops the volume from state without destroying it — but the new host would
# then not manage/mount it. store_destroyed counts delete OR forget → must ABORT.
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FW_UPDATE},${VOL_FORGET}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T9(c): a zot store volume forget (store_destroyed) must ABORT (rc=1)"
else
  pass
fi

# --- Test 10 (d): FAIL — server updated in-place, NOT replaced (no fresh cloud-init) ---
# server = ["update"] (no delete+create) so cloud-init never re-runs. ISOLATES
# server_replaced==0 (oos=0 since update is in-allow-set; every other clause holds).
write_plan "${SERVER_UPDATE},${NET_REPLACE},${VA_REPLACE},${FW_UPDATE},${VOL_NOOP}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T10(d): an in-place server update (server_replaced==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 11 (e): PASS — a data-source ["read"] AND an out-of-allow-set ["no-op"] ---
# The positive-action out_of_scope filter must EXCLUDE both `read` (data source) and
# `no-op` (a stray in-graph resource): neither is a positive action, so the plan still
# PASSes. Proves the read/no-op exclusion is load-bearing (a "!= no-op" filter that failed
# to also exclude `read` would false-abort here).
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FW_UPDATE},${VOL_UPDATE},${DATA_READ},${WEB_NOOP}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T11(e): a plan with a data-source read + an out-of-scope no-op should still PASS (rc=0)"
fi

# --- Test 12 (f): FAIL — volume-attachment stripped (["delete"] only, no create) ---
# The store volume is preserved, NIC + firewall OK, server replaced — but the
# volume-attachment is not re-created, so the new host boots with /var/lib/zot UNMOUNTED
# (a broken store). ISOLATES attachment_recreated==0 (covers FIX 2; every other clause holds).
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_DELETE_ONLY},${FW_UPDATE},${VOL_NOOP}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T12(f): a volume-attachment-stripped plan (attachment_recreated==0) must ABORT (rc=1)"
else
  pass
fi

# --- Test 13 (#6244): FAIL — a DIFFERENT doppler secret create is out-of-scope (exact-match) ---
# The allow-set entry is the EXACT address doppler_secret.registry_betterstack_logs_token; a
# stray doppler_secret create (e.g. a mis-scoped soleur/prd secret) must still ABORT. Proves the
# allow-set entry is address-exact (IN(.address; allow[])), NOT a blanket doppler_secret permit.
STRAY_SECRET="$(rc_obj 'doppler_secret.some_other_prd' '"create"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FW_UPDATE},${VOL_UPDATE},${SECRET_CREATE},${STRAY_SECRET}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T13: a stray (non-allow-set) doppler secret create must ABORT (rc=1)"
else
  pass
fi

# --- Test 14 (#6244): FAIL — the logs-token secret create alone is not a host recreate ---
# server_replaced==0 (no host -replace) → ABORT even though the permitted secret is present.
write_plan "${SECRET_CREATE}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T14: the logs-token secret create alone (no server replace) must ABORT (rc=1)"
else
  pass
fi

echo ""
echo "=== test-registry-host-replace-gate.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
