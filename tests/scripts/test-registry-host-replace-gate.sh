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
# change. It has a LARGER allow-set (5 vs inngest's 3) and MORE positive assertions
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

write_plan() { printf '{"resource_changes":[%s]}' "$1" > "$TMP/plan.json"; }

# --- Test 1: PASS — exact scoped recreate WITH the volume size ["update"] preserved ---
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FW_UPDATE},${VOL_UPDATE}"
if registry_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T1: exact scoped registry recreate (volume size-update preserved) should PASS (rc=0)"
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

echo ""
echo "=== test-registry-host-replace-gate.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
