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

# --- Test 2b: FAIL — the ADR-142 ADDITIVE target volume destroyed (#6894). The TWIN of T2.
#     `luks_volume_destroyed` is a separate counter from `redis_volume_destroyed` on purpose:
#     the additive volume is admitted to the allow-set for CREATE (the recovery route), so the
#     out-of-scope counter cannot see a destroy at that address and would report 0. Without
#     this arm the twin backstop is ungraded, and an edit deleting it leaves the suite green. ---
LUKS_VOL_DELETE="$(rc_obj 'hcloud_volume.inngest_redis_luks' '"delete","create"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${LUKS_VOL_DELETE}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T2b: an ADR-142 additive-target volume destroy must ABORT (rc=1)"
else
  pass
fi

# --- Test 2c: PASS — the additive target volume CREATED (the admitted recovery shape), together
#     with its attachment replacing. Proves the admission is real and not merely absent-from-plan:
#     if the allow-set entry were dropped this plan would abort `out_of_scope`, and if the twin
#     backstop over-matched (counting create as well as delete) it would abort here too. ---
LUKS_VOL_CREATE="$(rc_obj 'hcloud_volume.inngest_redis_luks' '"create"')"
LUKS_VA_REPLACE="$(rc_obj 'hcloud_volume_attachment.inngest_redis_luks' '"delete","create"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${LUKS_VA_REPLACE},${LUKS_VOL_CREATE}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T2c: additive-target create + attachment replace must PASS (rc=0) — the admitted recovery shape"
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


# The harness's own wrappers self-test here. gate_check() and gate_mutate_layered() are defined in
# gate-suite-harness.sh, not in this file, so this suite's local instrument self-test never drove
# them: a bare `pass "$name"` in gate_check left six suites totalling 280 assertions green on ONE
# edit. Placed after GATE/PREAMBLE are set, because gate_mutate_layered reads both.
gate_harness_selftest || true

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


# ── #6894 CTO ruling (Option C): PER-ADDRESS PERMITTED ACTIONS ────────────────────
# Allow-set membership said an address may APPEAR; nothing said what it may DO. RED-FIRST, measured
# on the gate as it stood before these counters: a server replace plus an UPDATE (resize) of the
# live AOF volume printed `inngest_host_replace_gate: PASS` (rc=0) — an update is neither a delete
# nor outside the allow-set. Every row below asserts the specific `reason=` token.
rp() { mk_plan "$TMP/plan.json" "[$(IFS=,; printf '%s' "$*")]"; }
RCHK() { gate_check "$1" inngest_host_replace_gate "$2" "$3" "$TMP/plan.json"; }
BASE_REPLACE="${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE}"

rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis' '"update"')"
RCHK "C1 (the reproduction): server replace + live AOF volume UPDATE => ABORT redis_volume_touched" 1 "reason=redis_volume_touched "
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis' '"create"')"
RCHK "C2 (must-PASS): live AOF volume bare CREATE of an ABSENT volume (before null) => PASS (the #7695 recovery route)" 0 "inngest_host_replace_gate: PASS"
rp "$BASE_REPLACE" '{"address":"hcloud_volume.inngest_redis","change":{"actions":["create"],"before":{"id":"1"}}}'
RCHK "C2b: a CREATE whose before is a live object => ABORT redis_volume_touched (only an absent volume may be created)" 1 "reason=redis_volume_touched "
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis' '"delete","create"')"
RCHK "C2c: live AOF volume REPLACE => ABORT (a re-create is a destroy)" 1 "reason="
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis' '"forget"')"
RCHK "C3: live AOF volume FORGET => ABORT redis_volume_destroyed" 1 "reason=redis_volume_destroyed "
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis' '"no-op"')"
RCHK "C4 (must-PASS): live AOF volume present as an explicit no-op => PASS" 0 "inngest_host_replace_gate: PASS"

rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis_luks' '"update"')"
RCHK "C5: additive LUKS volume UPDATE => ABORT luks_volume_touched" 1 "reason=luks_volume_touched "
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis_luks' '"forget"')"
RCHK "C6: additive LUKS volume FORGET => ABORT luks_volume_destroyed" 1 "reason=luks_volume_destroyed "
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis_luks' '"no-op"')" "$(rc_obj 'hcloud_volume_attachment.inngest_redis_luks' '"delete","create"')"
RCHK "C7 (must-PASS): LUKS volume no-op + its attachment replaced => PASS" 0 "inngest_host_replace_gate: PASS"

rp "${SERVER_REPLACE},${NET_REPLACE}" "$(rc_obj 'hcloud_volume_attachment.inngest_redis' '"update"')"
RCHK "C8: live attachment bare UPDATE => ABORT attachment_touched" 1 "reason=attachment_touched "
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume_attachment.inngest_redis_luks' '"update"')"
RCHK "C9: LUKS attachment bare UPDATE => ABORT attachment_touched" 1 "reason=attachment_touched "
rp "${SERVER_REPLACE},${NET_REPLACE}" "$(rc_obj 'hcloud_volume_attachment.inngest_redis' '"delete"')"
RCHK "C10: live attachment bare DELETE (detach, no re-attach) => ABORT attachment_touched" 1 "reason=attachment_touched "
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume_attachment.inngest_redis_luks' '"forget"')"
RCHK "C11: LUKS attachment FORGET => ABORT attachment_touched" 1 "reason=attachment_touched "
rp "${SERVER_REPLACE},${NET_REPLACE}" "$(rc_obj 'hcloud_volume_attachment.inngest_redis' '"create","delete"')" "$(rc_obj 'hcloud_volume_attachment.inngest_redis_luks' '"create"')"
RCHK "C12 (must-PASS): create-before-destroy attachment replace + a bare LUKS attachment create => PASS" 0 "inngest_host_replace_gate: PASS"

rp "$BASE_REPLACE" "$(rc_obj 'random_password.inngest_redis_luks' '"no-op"')"
RCHK "C13: random_password.inngest_redis_luks present as no-op => ABORT luks_passphrase_in_graph" 1 "reason=luks_passphrase_in_graph "
rp "$BASE_REPLACE" "$(rc_obj 'doppler_secret.inngest_redis_luks_key' '"no-op"')"
RCHK "C14: doppler_secret.inngest_redis_luks_key present as no-op => ABORT luks_passphrase_in_graph" 1 "reason=luks_passphrase_in_graph "

# SUBSTRING: `hcloud_volume.inngest_redis` is a prefix of `hcloud_volume.inngest_redis_luks`, and that
# of `…_luks_staging`. T1c pins exact equality for the token address only; this pins it for volumes.
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis_luks_staging' '"create"')"
RCHK "C15: a prefix-sharing volume address => ABORT inngest_out_of_scope_changes" 1 "reason=inngest_out_of_scope_changes "

# EMPTY-EVALUATING COUNTER (Guard 3's row, carried over). Built on the C1 input, where
# redis_volume_touched is the SOLE catcher: emptied, and without plan_gate_assert_numeric,
# [[ "" -eq 0 ]] is TRUE and the gate would PASS the resize again.
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis' '"update"')"
awk -v n="jq -r '.redis_volume_touched'" '{ if (index($0, n)) sub(n, "jq -r '"'"'empty'"'"'"); print }' "$GATE" > "$TMP/mutated-numeric.sh"
if cmp -s "$TMP/mutated-numeric.sh" "$GATE"; then
  fail "C16: the empty-counter mutation matched NOTHING in the gate; the extraction shape drifted"
else
  _rc=0; _out="$(bash -c "source '$PREAMBLE'; source '$TMP/mutated-numeric.sh'; inngest_host_replace_gate '$TMP/plan.json'" 2>&1)" || _rc=$?
  if [[ "$_rc" -eq 1 && "$_out" == *"counter parse failed"* && "$_out" == *"redis_volume_touched=''"* ]]; then
    pass
  else
    fail "C16: an empty counter must ABORT naming it, not satisfy every threshold (rc=${_rc}): ${_out}"
  fi
fi




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
if [[ "$_ran" -lt 33 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 33. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 33)\n' "$_ran"
fi

echo ""
echo "=== test-inngest-host-replace-gate.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
