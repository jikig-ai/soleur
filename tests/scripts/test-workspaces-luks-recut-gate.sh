#!/usr/bin/env bash
# Tests for tests/scripts/lib/workspaces-luks-recut-gate.sh (sourced by the workspaces_luks_recut
# job in .github/workflows/apply-web-platform-infra.yml, #6855 / #6812).
#
# The gate reads a `terraform show -json <plan>` document and PASSes (rc=0) iff the plan is EXACTLY
# the scoped workspaces-luks RECUT: hcloud_volume.workspaces_luks REPLACED (actions include BOTH
# "delete" AND "create") OR the RECOVERY bare create (["create"] with before==null), plus
# hcloud_volume_attachment.workspaces_luks re-CREATED, with web-1's then-serving plaintext /mnt/data
# volume + its attachment + the web-1 server PRESERVED (untouched), the passphrase + its doppler_secret REUSED
# (untouched — NOT re-minted), the replaced-volume id matching the operator-supplied expected id
# (when provided), and nothing else out of scope.
#
# HISTORICAL since #6604 step 7: the recut is retired (the LUKS volume carries prevent_destroy, so
# the job's -replace plan-fails first) and web-1's plaintext volume is out of state. The fixtures
# model the 2026-07 recut plan shape; they pin the gate's decision logic, not today's topology.
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
LIVE_ID="105149570"     # web-1's then-serving plaintext volume (retired #6604 step 7) — never the destroy target

# A resource_change object with the given address + actions array (no `before`).
rc_obj() { printf '{"address":"%s","change":{"actions":[%s]}}' "$1" "$2"; }
# A resource_change object carrying a `before.id` (the physical volume being acted on).
rc_obj_id() { printf '{"address":"%s","change":{"actions":[%s],"before":{"id":"%s"}}}' "$1" "$2" "$3"; }
write_plan() { printf '{"resource_changes":[%s]}' "$1" > "$TMP/plan.json"; }

# The scoped recut: the LUKS volume shows a REPLACE (["delete","create"]) carrying the orphaned id;
# its attachment shows a REPLACE too.
VOL_REPLACE_ID="$(rc_obj_id 'hcloud_volume.workspaces_luks' '"delete","create"' "$ORPHAN_ID")"
ATT_REPLACE="$(rc_obj 'hcloud_volume_attachment.workspaces_luks' '"delete","create"')"
# The (retired) web-1 plaintext volume/attachment + web-1 server appear as no-op (untargeted deps).
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

# --- Test 4: web-1 plaintext volume hcloud_volume.workspaces["web-1"] touched ⇒ ABORT ---
write_plan "${VOL_REPLACE_ID},${ATT_REPLACE},$(rc_obj 'hcloud_volume.workspaces[\"web-1\"]' '"delete","create"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 4: touching the web-1 plaintext volume should ABORT"; else pass; fi

# --- Test 5: web-1 plaintext attachment touched ⇒ ABORT ---
write_plan "${VOL_REPLACE_ID},${ATT_REPLACE},$(rc_obj 'hcloud_volume_attachment.workspaces[\"web-1\"]' '"delete"'),${PW_NOOP},${SECRET_NOOP}"
if workspaces_luks_recut_gate "$TMP/plan.json" "$ORPHAN_ID" >/dev/null; then fail "Test 5: touching the web-1 plaintext attachment should ABORT"; else pass; fi

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
GATE="${_PG_DIR}/lib/workspaces-luks-recut-gate.sh"
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
  workspaces_luks_recut_gate 1 "unclassifiable plan entry" "$TMP/pg-d5.json"
gate_check "A1 (D5): the ABORT is the preamble's and names this gate" \
  workspaces_luks_recut_gate 1 "workspaces_luks_recut_gate: ABORT — unclassifiable" "$TMP/pg-d5.json"
gate_check "A2 (D6): a SCALAR .change => fail-closed ABORT" \
  workspaces_luks_recut_gate 1 "unclassifiable plan entry" "$TMP/pg-d6.json"
gate_check "A2 (D6): the ABORT names the offending address" \
  workspaces_luks_recut_gate 1 "hcloud_volume.workspaces" "$TMP/pg-d6.json"

gate_mutate_layered "A4: classifiability call (invoked, not merely sourced)" \
  's/^  plan_gate_assert_classifiable .*/  :/' \
  "unclassifiable plan entry" "plan is NOT the exact scoped" \
  workspaces_luks_recut_gate "$TMP/pg-d5.json"

# ── #6604 PR B: the workspaces_luks_recut JOB is hard-retired ─────────────────────
# prevent_destroy refuses the -replace only while hcloud_volume.workspaces_luks is in state. With the
# volume out of state and the attachment still in it, this job plans a bare create (the gate's
# recovery arm PASSes it) plus an attachment replace that detaches the sole copy. So the job's FIRST
# step refuses every dispatch. Parsed as YAML (a grep would match the job-header prose), and the
# step body is EXECUTED under GitHub's own shell flags rather than read.
APPLY_WF="${_PG_DIR}/../../.github/workflows/apply-web-platform-infra.yml"
python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml
RETIRE_META="$(python3 - "$APPLY_WF" "$TMP/recut-step0.sh" <<'PY'
import sys, yaml
job = ((yaml.safe_load(open(sys.argv[1])) or {}).get("jobs") or {}).get("workspaces_luks_recut") or {}
st = (job.get("steps") or [{}])[0]
open(sys.argv[2], "w").write(str(st.get("run") or ""))
print(f"run={int(bool(st.get('run')))} uses={int('uses' in st)} if={int('if' in st)} coe={int(bool(st.get('continue-on-error')))} shell={st.get('shell', 'default')}")
PY
)"
if [[ "$RETIRE_META" == "run=1 uses=0 if=0 coe=0 shell=default" ]]; then pass
else fail "R1: workspaces_luks_recut's FIRST step must be an unconditional, non-soft run: step (got: ${RETIRE_META:-<no job>})"; fi
_rrc=0
_rout="$(env -i PATH="$PATH" bash --noprofile --norc -eo pipefail "$TMP/recut-step0.sh" 2>&1)" || _rrc=$?
if [[ "$_rrc" == 1 && "$_rout" == *"::error::"*"#6604"* && "$_rout" == *"new PR"* ]]; then pass
else fail "R2: workspaces_luks_recut's first step must print ::error:: naming #6604 and the new-PR recovery, then exit 1 (rc=${_rrc} out=${_rout:0:160})"; fi


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
if [[ "$_ran" -lt 28 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 28. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 28)\n' "$_ran"
fi

echo ""
echo "workspaces-luks-recut-gate: ${passes} passed, ${fails} failed"
[[ "$fails" -eq 0 ]]
