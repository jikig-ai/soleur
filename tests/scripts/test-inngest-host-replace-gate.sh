#!/usr/bin/env bash
# Tests for tests/scripts/lib/inngest-host-replace-gate.sh (sourced by the
# inngest_host_replace job in .github/workflows/apply-web-platform-infra.yml, #6197).
#
# The gate reads a `terraform show -json <plan>` document and PASSes (rc=0) iff the plan
# is EXACTLY the scoped inngest-host recreate: hcloud_server.inngest + its 2 id-referencing
# dependents replaced, the Redis AOF volume preserved, and no out-of-scope change.
#
# Non-vacuity discipline (RED-verification for a gating primitive): each FAIL fixture
# differs from the PASS fixture by ONE mutation of the exact class the gate must catch,
# so a gate that ignored that class would wrongly pass. Deterministic; no network.
# All fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only) — no captured real plan.
#
# Run: bash tests/scripts/test-inngest-host-replace-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/scripts/lib/inngest-host-replace-gate.sh
source "${DIR}/lib/inngest-host-replace-gate.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A resource_change object with the given address + actions array.
rc_obj() { printf '{"address":"%s","change":{"actions":[%s]}}' "$1" "$2"; }

# The 4 allowed replaces (server + 2 id-referencing dependents + the token whose ForceNew
# access change CAUSES the recreate, #6178), each delete+create.
SERVER_REPLACE="$(rc_obj 'hcloud_server.inngest' '"delete","create"')"
NET_REPLACE="$(rc_obj 'hcloud_server_network.inngest' '"delete","create"')"
VA_REPLACE="$(rc_obj 'hcloud_volume_attachment.inngest_redis' '"delete","create"')"
TOKEN_REPLACE="$(rc_obj 'doppler_service_token.inngest' '"delete","create"')"

write_plan() { printf '{"resource_changes":[%s]}' "$1" > "$TMP/plan.json"; }

# --- Test 1: PASS — the exact scoped recreate (server + 2 deps + token, volume preserved) ---
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${TOKEN_REPLACE}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T1: exact scoped inngest recreate (incl. token ForceNew) should PASS (rc=0)"
fi

# --- Test 1b: PASS — server + deps WITHOUT the token (a cloud-init-only recreate, e.g. the
#     #6887 allowlist edit) is still exactly scoped. Admitting the token did not make it
#     MANDATORY — it is permitted, not required. ---
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T1b: a cloud-init-only recreate (no token change) should still PASS (rc=0)"
fi

# --- Test 1c: FAIL (non-vacuity for the allow-set widening) — a DIFFERENT doppler token must
#     still ABORT. Proves the allow-set is EXACT-equality, not a substring/prefix match on
#     'doppler_service_token' that would admit any token (e.g. the read/write arm-write token,
#     which must NEVER ride a host replace). ---
OTHER_TOKEN="$(rc_obj 'doppler_service_token.inngest_arm_write' '"delete","create"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${OTHER_TOKEN}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T1c: a non-inngest doppler_service_token change must ABORT (rc=1) — allow-set is exact-equality"
else
  pass
fi

# --- Test 2: FAIL — Redis AOF volume destroyed (the preservation invariant) ---
VOL_DELETE="$(rc_obj 'hcloud_volume.inngest_redis' '"delete","create"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${VOL_DELETE}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T2: a Redis AOF volume destroy must ABORT (rc=1)"
else
  pass
fi

# --- Test 3: FAIL — an out-of-scope resource change (a stray web-1 update) ---
WEB1_UPDATE="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"update"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${WEB1_UPDATE}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T3: an out-of-scope change must ABORT (rc=1)"
else
  pass
fi

# --- Test 4: FAIL — no-op plan (server not actually replaced) ---
SERVER_NOOP="$(rc_obj 'hcloud_server.inngest' '"no-op"')"
write_plan "${SERVER_NOOP}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T4: a no-op plan (no replace) must ABORT (rc=1)"
else
  pass
fi

# --- Test 5: FAIL — server only updated in-place, not replaced ---
SERVER_UPDATE="$(rc_obj 'hcloud_server.inngest' '"update"')"
write_plan "${SERVER_UPDATE}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T5: an in-place server update (no delete+create) must ABORT (rc=1)"
else
  pass
fi

# --- Test 6: FAIL — missing plan file (fail loud, never silent pass) ---
if inngest_host_replace_gate "$TMP/does-not-exist.json" >/dev/null; then
  fail "T6: a missing plan JSON must ABORT (rc=1)"
else
  pass
fi


# ── #6997: the shared fail-closed preamble is INVOKED, not merely sourced ─────────
#
# A1/A2 pin the two degraded shapes the retrofit closes. Both PASSED this gate's
# predecessor: an entry with "actions": [] is invisible to `any(...)` and to
# `index("delete")` simultaneously, and a scalar `.change` makes a negative-search
# classifiability check read a jq ERROR as "condition false".
#
# A4 is the arm that nothing in test-plan-gate-preamble.sh can replace: it proves THIS
# gate CALLS the preamble. Neutering the call must leave the plan REJECTED (so the
# retrofit never opened a door) while the preamble-distinctive signature DISAPPEARS (so
# the rejection was really the preamble's).
#
# THE ANCHOR IS NOT THE GATE NAME. Every abort this gate emits — including its own
# pre-existing ones — is prefixed with the gate name, so a name anchor cannot tell a
# preamble abort from a gate abort and the arm would be a redness detector, not a
# binding. `unclassifiable plan entry` is text only the preamble can produce.
#
# A3 (the happy plan still PASSES) is NOT duplicated here: this suite's existing PASS
# arms already are it, and an always-aborting gate would redden them.
_PG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${_PG_DIR}/lib/inngest-host-replace-gate.sh"
PREAMBLE="${_PG_DIR}/lib/plan-gate-preamble.sh"
# shellcheck source=tests/scripts/lib/gate-suite-harness.sh
source "${_PG_DIR}/lib/gate-suite-harness.sh"

mk_plan "$TMP/pg-d5.json" "[$(rc_empty_actions 'hcloud_volume.workspaces' 'hcloud_volume')]"
mk_plan "$TMP/pg-d6.json" "[$(rc_scalar_change 'hcloud_volume.workspaces' 'hcloud_volume')]"

gate_check "A1 (D5): an EMPTY actions array hiding a destroy => fail-closed ABORT" \
  inngest_host_replace_gate 1 "unclassifiable plan entry" "$TMP/pg-d5.json"
gate_check "A1 (D5): the ABORT is the preamble's and names this gate" \
  inngest_host_replace_gate 1 "inngest_host_replace_gate: ABORT — unclassifiable" "$TMP/pg-d5.json"
gate_check "A2 (D6): a SCALAR .change => fail-closed ABORT" \
  inngest_host_replace_gate 1 "unclassifiable plan entry" "$TMP/pg-d6.json"
gate_check "A2 (D6): the ABORT names the offending address" \
  inngest_host_replace_gate 1 "hcloud_volume.workspaces" "$TMP/pg-d6.json"

gate_mutate_layered "A4: classifiability call (invoked, not merely sourced)" \
  's/^  plan_gate_assert_classifiable .*/  :/' \
  "unclassifiable plan entry" "plan is NOT the exact scoped" \
  inngest_host_replace_gate "$TMP/pg-d5.json"




# ANTI-VACUITY FLOOR (#6997). Nothing else asserts that the assertions RAN. Every
# non-vacuity mechanism in this suite lives inside a helper — the `cmp -s` mutation floors,
# the layered contract's unmutated control, the preamble-distinctive anchors — so deleting
# the CALLS to those helpers silences all of them at once while the suite still exits 0,
# because the only merge gate is the `fails -eq 0` expression below and CI reads only the
# exit code. Measured: removing one arm block took a sibling suite from 13 assertions to 8,
# still exit 0.
#
# DELIBERATELY SELF-CONTAINED — bash builtins and this suite's own counters only, no
# harness function. The first version called a helper from gate-suite-harness.sh and the
# harness `source` lived INSIDE the arm block, so deleting the arms also undefined the
# floor: it exited 127 under `set -uo pipefail`, recorded nothing, and the suite passed. A
# floor that depends on the thing it guards is not a floor.
#
# A FLOOR, NOT EQUALITY — the count is developer-incremented, so `-eq` would redden the
# suite on every legitimately-added assertion and train people to bump it unread.
_ran=$((passes + fails))
if [[ "$_ran" -lt 11 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 11. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 11)\n' "$_ran"
fi

echo ""
echo "=== test-inngest-host-replace-gate.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
