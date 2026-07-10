#!/usr/bin/env bash
# Tests for tests/scripts/lib/registry-region-migrate-gate.sh (sourced by the
# registry_region_migrate job in .github/workflows/apply-web-platform-infra.yml, #6288).
#
# The gate reads a `terraform show -json <plan>` document and PASSes (rc=0) iff the plan is the
# scoped registry REGION migration: the registry server + fresh store volume + NIC + volume-
# attachment CREATED in the new region, the deny-all firewall re-attached (create or update), the
# isolated logs-token secret PRESERVED, and NO out-of-scope resource touched. UNLIKE
# registry-host-replace-gate, it PERMITS the registry's own store volume to be replaced (the store
# is a disposable GHCR mirror that re-fills from GHCR) — but the load-bearing out_of_scope==0 +
# secret-preserve invariants are unchanged.
#
# Non-vacuity discipline (RED-verification for a gating primitive): each FAIL fixture differs from
# the PASS fixture by ONE mutation of the exact class the gate must catch, so a gate that ignored
# that class would wrongly pass. Deterministic; no network. All fixtures are SYNTHESIZED
# (cq-test-fixtures-synthesized-only) — seeded from the expected nbg1->hel1 migration plan shape
# (server/network/volume_attachment = create; volume = delete+create [region ForceNew];
# firewall_attachment = create; logs-token secret preserved). No captured real plan file.
#
# Run: bash tests/scripts/test-registry-region-migrate-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/scripts/lib/registry-region-migrate-gate.sh
source "${DIR}/lib/registry-region-migrate-gate.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rc_obj() { printf '{"address":"%s","change":{"actions":[%s]}}' "$1" "$2"; }

# The scoped region migration (recovery state: old host already destroyed, volume moves region):
#   server / server_network / volume_attachment = CREATE (fresh in the new region);
#   volume = REPLACE (delete old-region + create new-region — ForceNew on location);
#   firewall_attachment = CREATE (fresh attachment to the new server);
#   logs-token secret = CREATE on first apply (preserved — allow-set member).
SERVER_CREATE="$(rc_obj 'hcloud_server.registry' '"create"')"
NET_CREATE="$(rc_obj 'hcloud_server_network.registry' '"create"')"
VA_CREATE="$(rc_obj 'hcloud_volume_attachment.registry' '"create"')"
VOL_REPLACE="$(rc_obj 'hcloud_volume.registry' '"delete","create"')"
FW_CREATE="$(rc_obj 'hcloud_firewall_attachment.registry' '"create"')"
SECRET_CREATE="$(rc_obj 'doppler_secret.registry_betterstack_logs_token' '"create"')"

write_plan() { printf '{"resource_changes":[%s]}' "$1" > "$TMP/plan.json"; }

# --- Test 1: PASS — the exact scoped region migration ---
write_plan "${SERVER_CREATE},${NET_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_CREATE},${SECRET_CREATE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then pass
else fail "T1: the exact scoped registry region migration should PASS (rc=0)"; fi

# --- Test 2: PASS — the STORE VOLUME REPLACE is permitted (the key difference vs host-replace) ---
# A bare delete+create on the registry volume (region move) must NOT abort here — this is exactly
# what registry-host-replace-gate FORBIDS. Mutation-check: a copied store_destroyed==0 clause would
# flip this to FAIL.
write_plan "${SERVER_CREATE},${NET_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_CREATE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then pass
else fail "T2: a registry store-volume replace (region migration) should PASS (rc=0)"; fi

# --- Test 3: FAIL — an out-of-scope resource change (a stray web host update) ---
# The load-bearing safety invariant: nothing outside the registry's own resources may be touched.
WEB_UPDATE="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"update"')"
write_plan "${SERVER_CREATE},${NET_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_CREATE},${WEB_UPDATE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then
  fail "T3: an out-of-scope change (web host) must ABORT (rc=1)"; else pass; fi

# --- Test 4: FAIL — an out-of-scope VOLUME destroy (a DIFFERENT host's volume) ---
# Proves out_of_scope catches a collateral destroy of some OTHER volume (the catastrophic class).
GITDATA_VOL_DELETE="$(rc_obj 'hcloud_volume.git_data' '"delete"')"
write_plan "${SERVER_CREATE},${NET_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_CREATE},${GITDATA_VOL_DELETE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then
  fail "T4: a collateral destroy of a non-registry volume must ABORT (rc=1)"; else pass; fi

# --- Test 5: FAIL — the logs-token secret is DELETED (secret_destroyed backstop) ---
# In the allow-set, so out_of_scope does NOT catch it — the named secret_destroyed backstop must.
# Deleting it bricks the fresh host (3-secret boot guard FATALs without BETTERSTACK_LOGS_TOKEN).
SECRET_DELETE="$(rc_obj 'doppler_secret.registry_betterstack_logs_token' '"delete"')"
write_plan "${SERVER_CREATE},${NET_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_CREATE},${SECRET_DELETE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then
  fail "T5: a logs-token secret delete (secret_destroyed) must ABORT (rc=1)"; else pass; fi

# --- Test 6: FAIL — the fresh store volume is NOT created (delete only) ---
# The old-region volume is destroyed but no new one is created → the host boots with no store.
# ISOLATES volume_created==0 (every other clause holds).
VOL_DELETE_ONLY="$(rc_obj 'hcloud_volume.registry' '"delete"')"
write_plan "${SERVER_CREATE},${NET_CREATE},${VA_CREATE},${VOL_DELETE_ONLY},${FW_CREATE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then
  fail "T6: a store-volume delete with no create (volume_created==0) must ABORT (rc=1)"; else pass; fi

# --- Test 7: FAIL — the registry server is NOT created (no-op / not in plan) ---
SERVER_NOOP="$(rc_obj 'hcloud_server.registry' '"no-op"')"
write_plan "${SERVER_NOOP},${NET_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_CREATE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then
  fail "T7: a plan without a server create (server_created==0) must ABORT (rc=1)"; else pass; fi

# --- Test 8: FAIL — the private NIC is NOT created (host boots with no 10.0.1.30) ---
write_plan "${SERVER_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_CREATE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then
  fail "T8: a NIC-less plan (nic_created==0) must ABORT (rc=1)"; else pass; fi

# --- Test 9: FAIL — the volume-attachment is NOT created (host boots /var/lib/zot UNMOUNTED) ---
write_plan "${SERVER_CREATE},${NET_CREATE},${VOL_REPLACE},${FW_CREATE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then
  fail "T9: an attachment-less plan (attachment_created==0) must ABORT (rc=1)"; else pass; fi

# --- Test 10: FAIL — the deny-all firewall is stripped (host naked on its public IP) ---
FW_DELETE="$(rc_obj 'hcloud_firewall_attachment.registry' '"delete"')"
write_plan "${SERVER_CREATE},${NET_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_DELETE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then
  fail "T10: a firewall-stripped plan (firewall_ok==0) must ABORT (rc=1)"; else pass; fi

# --- Test 11: PASS — firewall attachment shown as an in-place UPDATE (server_ids re-point) ---
# firewall_ok accepts create OR update; if terraform models the attachment as an update rather than
# a fresh create, the gate must still PASS.
FW_UPDATE="$(rc_obj 'hcloud_firewall_attachment.registry' '"update"')"
write_plan "${SERVER_CREATE},${NET_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_UPDATE},${SECRET_CREATE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then pass
else fail "T11: a firewall attachment ['update'] should PASS (rc=0)"; fi

# --- Test 12: PASS — a data-source ['read'] AND an out-of-allow-set ['no-op'] are excluded ---
# The positive-action out_of_scope filter must EXCLUDE both `read` and `no-op`.
DATA_READ="$(rc_obj 'data.hcloud_image.registry_os' '"read"')"
WEB_NOOP="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"no-op"')"
write_plan "${SERVER_CREATE},${NET_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_CREATE},${DATA_READ},${WEB_NOOP}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then pass
else fail "T12: a data-source read + an out-of-scope no-op should still PASS (rc=0)"; fi

# --- Test 13: FAIL — a stray (non-allow-set) doppler secret create is out-of-scope ---
STRAY_SECRET="$(rc_obj 'doppler_secret.some_other_prd' '"create"')"
write_plan "${SERVER_CREATE},${NET_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_CREATE},${STRAY_SECRET}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then
  fail "T13: a stray (non-allow-set) doppler secret create must ABORT (rc=1)"; else pass; fi

# --- Test 14: FAIL — a collateral destroy of ANOTHER HOST (the catastrophic class, explicit) ---
# T4 pins a collateral volume destroy; this makes the "another prod HOST would be destroyed" case
# explicit. A non-registry server delete has a non-allow-set address → out_of_scope>=1 → ABORT.
WEB_DELETE="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"delete"')"
write_plan "${SERVER_CREATE},${NET_CREATE},${VA_CREATE},${VOL_REPLACE},${FW_CREATE},${WEB_DELETE}"
if registry_region_migrate_gate "$TMP/plan.json" >/dev/null; then
  fail "T14: a collateral destroy of a non-registry host must ABORT (rc=1)"; else pass; fi

echo ""
echo "=== test-registry-region-migrate-gate.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
