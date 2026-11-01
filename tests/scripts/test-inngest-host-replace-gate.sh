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
# #8754: the replacement server carries the deny-all firewall in firewall_ids at create, and the
# firewall rides the plan as a no-op dependency whose id the gate reads. Synthesized id.
FW_ID=424242
FW_NOOP="{\"address\":\"hcloud_firewall.inngest\",\"change\":{\"actions\":[\"no-op\"],\"before\":{\"id\":\"${FW_ID}\"},\"after\":{\"id\":\"${FW_ID}\"}}}"
srv_replace() { printf '{"address":"hcloud_server.inngest","change":{"actions":["delete","create"],"after":%s}}' "$1"; }
SERVER_REPLACE="$(srv_replace "{\"firewall_ids\":[${FW_ID}]}"),${FW_NOOP}"
NET_REPLACE="$(rc_obj 'hcloud_server_network.inngest' '"delete","create"')"
VA_REPLACE="$(rc_obj 'hcloud_volume_attachment.inngest_redis_luks' '"delete","create"')"
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

# --- Flip-token split (ADR-282 addendum 2026-10-30, #9927 item 4). The FLIP token is a SECOND
#     doppler_service_token upstream of the server's user_data, admitted by exact equality like the
#     boot token. On the first replace after the split the boot token is delete+create (its `access`
#     is ForceNew) and the flip token is a plain create; a later flip-only rotation is delete+create.
#     The plan is STILL required to replace the server, so admitting the address cannot let a
#     destructive plan through (T1h pins that direction). ---
FLIP_CREATE="$(rc_obj 'doppler_service_token.inngest_flip' '"create"')"
FLIP_REPLACE="$(rc_obj 'doppler_service_token.inngest_flip' '"delete","create"')"

# --- Test 1d: PASS — the first replace after the split: server + deps, boot token delete+create,
#     flip token create. ---
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${TOKEN_REPLACE},${FLIP_CREATE}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T1d: server replace + boot token delete/create + flip token create should PASS (rc=0)"
fi

# --- Test 1e: PASS — a flip-token rotation: flip delete+create with the server replaced. ---
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FLIP_REPLACE}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "T1e: server replace + flip token delete/create should PASS (rc=0)"
fi

# --- Test 1f: FAIL — a LOOKALIKE address after a compliant flip token must still ABORT (exact
#     equality, mirrors T1c: a prefix/substring match on `inngest_flip` would admit it). ---
LOOKALIKE_TOKEN="$(rc_obj 'doppler_service_token.inngest_flip_x' '"create"')"
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${FLIP_CREATE},${LOOKALIKE_TOKEN}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T1f: doppler_service_token.inngest_flip_x (lookalike) must ABORT (rc=1) — allow-set is exact-equality"
else
  pass
fi

# --- Test 1g: FAIL — the flip token is created but the server is NOT replaced. The token alone
#     must never be a path to a green plan (fixture direction). ---
write_plan "$(rc_obj 'hcloud_server.inngest' '"no-op"'),${FLIP_CREATE}"
if inngest_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "T1g: a flip token create WITHOUT a server replace must ABORT (rc=1)"
else
  pass
fi

# --- Test 1h: MUTATION — delete the address from the gate's def allow in a COPY and the T1d plan
#     must ABORT. Proves T1d is graded by the allow-set entry, not by something incidental (a
#     gate that admitted every doppler_service_token would pass T1d AND T1c's twin, so T1c/T1f
#     cover the other direction). The copy is sourced in a subshell so the real gate stays loaded. ---
MUT="$TMP/mut"; mkdir -p "$MUT"
cp "${DIR:?}/lib/inngest-host-replace-gate.sh" "${DIR:?}/lib/plan-gate-preamble.sh" "${MUT:?}/"
sed -i '/"doppler_service_token\.inngest_flip"/d' "$MUT/inngest-host-replace-gate.sh"
if cmp -s "${DIR}/lib/inngest-host-replace-gate.sh" "$MUT/inngest-host-replace-gate.sh"; then
  fail "T1h: HARNESS ABORT — the mutation did not land (the gate does not name doppler_service_token.inngest_flip)"
else
  write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${TOKEN_REPLACE},${FLIP_CREATE}"
  if ( source "$MUT/inngest-host-replace-gate.sh"; inngest_host_replace_gate "$TMP/plan.json" >/dev/null ); then
    fail "T1h: with the address removed from def allow, the T1d plan must ABORT (the allow-set entry is what admits it)"
  else
    pass
  fi
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
write_plan "${SERVER_REPLACE},${NET_REPLACE},${VA_REPLACE},${LUKS_VOL_CREATE}"
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
RCHK "C2: the retired AOF volume bare CREATE (no recovery route exists since #8285) => ABORT redis_volume_touched" 1 "reason=redis_volume_touched "
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
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis_luks' '"no-op"')"
RCHK "C7 (must-PASS): LUKS volume no-op + its attachment replaced (in BASE) => PASS" 0 "inngest_host_replace_gate: PASS"

rp "${SERVER_REPLACE},${NET_REPLACE}" "$(rc_obj 'hcloud_volume_attachment.inngest_redis' '"update"')"
RCHK "C8: the RETIRED plaintext attachment UPDATE => ABORT inngest_out_of_scope_changes (outside the allow-set)" 1 "reason=inngest_out_of_scope_changes "
rp "${SERVER_REPLACE},${NET_REPLACE}" "$(rc_obj 'hcloud_volume_attachment.inngest_redis_luks' '"update"')"
RCHK "C9: LUKS attachment bare UPDATE => ABORT attachment_touched" 1 "reason=attachment_touched "
rp "${SERVER_REPLACE},${NET_REPLACE}" "$(rc_obj 'hcloud_volume_attachment.inngest_redis' '"delete"')"
RCHK "C10: the RETIRED plaintext attachment DELETE (the dispatch's job, not this one) => ABORT inngest_out_of_scope_changes" 1 "reason=inngest_out_of_scope_changes "
rp "${SERVER_REPLACE},${NET_REPLACE}" "$(rc_obj 'hcloud_volume_attachment.inngest_redis_luks' '"forget"')"
RCHK "C11: LUKS attachment FORGET => ABORT attachment_touched" 1 "reason=attachment_touched "
rp "${SERVER_REPLACE},${NET_REPLACE}" "$(rc_obj 'hcloud_volume_attachment.inngest_redis_luks' '"create","delete"')"
RCHK "C12 (must-PASS): create-before-destroy LUKS attachment replace => PASS" 0 "inngest_host_replace_gate: PASS"
rp "${BASE_REPLACE}" "$(rc_obj 'hcloud_volume.inngest_redis' '"delete"')"
RCHK "C12b: the RETIRED volume DELETE riding a host replace => ABORT redis_volume_destroyed" 1 "reason=redis_volume_destroyed "

rp "$BASE_REPLACE" "$(rc_obj 'random_password.inngest_redis_luks' '"no-op"')"
RCHK "C13: random_password.inngest_redis_luks present as no-op => ABORT luks_passphrase_in_graph" 1 "reason=luks_passphrase_in_graph "
rp "$BASE_REPLACE" "$(rc_obj 'doppler_secret.inngest_redis_luks_key' '"no-op"')"
RCHK "C14: doppler_secret.inngest_redis_luks_key present as no-op => ABORT luks_passphrase_in_graph" 1 "reason=luks_passphrase_in_graph "

# SUBSTRING: `hcloud_volume.inngest_redis` is a prefix of `hcloud_volume.inngest_redis_luks`, and that
# of `…_luks_staging`. T1c pins exact equality for the token address only; this pins it for volumes.
rp "$BASE_REPLACE" "$(rc_obj 'hcloud_volume.inngest_redis_luks_staging' '"create"')"
RCHK "C15: a prefix-sharing volume address => ABORT inngest_out_of_scope_changes" 1 "reason=inngest_out_of_scope_changes "

# ── #8754: the replacement server must be BORN bound to hcloud_firewall.inngest ─────────
# firewall_ids is Optional+Computed, so a config that drops it plans no firewall change at all; the
# create's `.change.after.firewall_ids` is the one place a replace plan shows the binding. Fail
# closed when the firewall's id cannot be read from its own plan entry.
NET_VA="${NET_REPLACE},${VA_REPLACE}"
rp "$(srv_replace '{"firewall_ids":[]}')" "$FW_NOOP" "$NET_VA"
RCHK "F1: server create with firewall_ids=[] => ABORT firewall_not_bound" 1 "reason=firewall_not_bound "
rp "$(srv_replace '{"firewall_ids":[99]}')" "$FW_NOOP" "$NET_VA"
RCHK "F2: server create bound to ANOTHER firewall id => ABORT firewall_not_bound" 1 "reason=firewall_not_bound "
rp "$(srv_replace '{}')" "$FW_NOOP" "$NET_VA"
RCHK "F3: server create with firewall_ids absent => ABORT firewall_not_bound" 1 "reason=firewall_not_bound "
rp "$(srv_replace "{\"firewall_ids\":[${FW_ID},99]}")" "$FW_NOOP" "$NET_VA"
RCHK "F4: server create bound to the firewall AND another => ABORT firewall_not_bound" 1 "reason=firewall_not_bound "
rp "$(srv_replace "{\"firewall_ids\":[${FW_ID}]}")" "$NET_VA"
RCHK "F5: hcloud_firewall.inngest absent from the plan (id unreadable) => fail-closed ABORT firewall_not_bound" 1 "reason=firewall_not_bound "
rp "$(srv_replace "{\"firewall_ids\":[${FW_ID}]}")" '{"address":"hcloud_firewall.inngest","change":{"actions":["no-op"],"before":{},"after":{}}}' "$NET_VA"
RCHK "F6: the firewall's id unknown in its plan entry => fail-closed ABORT firewall_not_bound" 1 "reason=firewall_not_bound "
rp "$(srv_replace "{\"firewall_ids\":[${FW_ID}]}")" "{\"address\":\"hcloud_firewall.inngest\",\"change\":{\"actions\":[\"no-op\"],\"before\":{\"id\":\"${FW_ID}\"},\"after\":null}}" "$NET_VA"
RCHK "F7 (must-PASS): firewall id read from .before when .after is null => PASS" 0 "inngest_host_replace_gate: PASS"

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

# ── #9879 / AC3: the SANCTIONED host replace still passes once the LUKS volume is delete-protected ─────
# The sole-copy protection pins the volume (prevent_destroy + delete_protection) and deliberately leaves the
# ATTACHMENT unpinned, because a host replace replaces the attachment (detach, then attach to the new server).
# This pair replays that exact shape, with the entry detail a real `terraform show -json` carries (before/after
# objects with ids, as the projection of a real plan keeps only address + action list; every id here is a
# SYNTHESIZED placeholder, no captured plan, no secret):
#   server        delete+create   (the replace; after.firewall_ids bound to the deny-all firewall)
#   network       delete+create   (id-referencing dependent)
#   attachment    delete+create   (the pair member the pin must NOT block)
#   LUKS volume   no-op           (preserved; the pin's target)
# The first row is the PASS counterpart; the second is the PRE-APPLY counterpart: the same plan with the volume
# `update` (what a plan run BEFORE the merge-apply of delete_protection shows) aborts luks_volume_touched, so the
# runbook ordering "merge-apply first, replace after" is a tested fact and not an assertion in prose.
LUKS_VOL_NOOP_ENTRY() { printf '{"address":"hcloud_volume.inngest_redis_luks","change":{"actions":["%s"],"before":{"id":"7000001","delete_protection":%s},"after":{"id":"7000001","delete_protection":true}}}' "$1" "$2"; }
LUKS_ATT_REPLACE_ENTRY='{"address":"hcloud_volume_attachment.inngest_redis_luks","change":{"actions":["delete","create"],"before":{"id":"7000001","volume_id":7000001,"server_id":7000002},"after":{"volume_id":7000001}}}'
rp "$(srv_replace "{\"firewall_ids\":[${FW_ID}]}")" "$FW_NOOP" "$NET_REPLACE" "$LUKS_ATT_REPLACE_ENTRY" "$(LUKS_VOL_NOOP_ENTRY no-op true)"
RCHK "AC3a (must-PASS): host replace = server + attachment delete+create, protected LUKS volume no-op => PASS" 0 "inngest_host_replace_gate: PASS"
rp "$(srv_replace "{\"firewall_ids\":[${FW_ID}]}")" "$FW_NOOP" "$NET_REPLACE" "$LUKS_ATT_REPLACE_ENTRY" "$(LUKS_VOL_NOOP_ENTRY update false)"
RCHK "AC3b (pre-apply): the same plan with the LUKS volume UPDATE (delete_protection not yet applied) => ABORT luks_volume_touched" 1 "reason=luks_volume_touched "

# ── #10136: the Inngest link TLS material stays OUT of the host-replace closure ─────────────────────
# tls_private_key.inngest_link / tls_self_signed_cert.inngest_link and the doppler_secret.inngest_tls_*
# copies are created by the per-merge apply (inngest-tls.tf), never by this dispatch. If a templatefile
# variable in inngest-host.tf ever referenced one, a cert change would force-replace the scheduler host
# and the replace plan would carry the resources; this gate must then ABORT as an out-of-scope change
# (none of these addresses is in its allow-set). The prevent_destroy on the key and cert is the second
# line; this row is the first.
rp "$BASE_REPLACE" "$(rc_obj 'tls_self_signed_cert.inngest_link' '"create"')"
RCHK "T1 (#10136): a tls_self_signed_cert create riding a host replace => ABORT inngest_out_of_scope_changes" 1 "reason=inngest_out_of_scope_changes "
rp "$BASE_REPLACE" "$(rc_obj 'tls_private_key.inngest_link' '"create"')"
RCHK "T2 (#10136): a tls_private_key create riding a host replace => ABORT inngest_out_of_scope_changes" 1 "reason=inngest_out_of_scope_changes "
rp "$BASE_REPLACE" "$(rc_obj 'tls_self_signed_cert.inngest_link' '"delete","create"')"
RCHK "T3 (#10136): a tls_self_signed_cert REPLACE (cert drift) riding a host replace => ABORT" 1 "reason=inngest_out_of_scope_changes "
rp "$BASE_REPLACE" "$(rc_obj 'doppler_secret.inngest_tls_key' '"update"')"
RCHK "T4 (#10136): a doppler_secret.inngest_tls_key update riding a host replace => ABORT inngest_out_of_scope_changes" 1 "reason=inngest_out_of_scope_changes "
rp "$BASE_REPLACE" "$(rc_obj 'tls_self_signed_cert.inngest_link' '"no-op"')"
RCHK "T5 (must-PASS): the cert present as an explicit no-op (already applied by the merge apply) => PASS" 0 "inngest_host_replace_gate: PASS"

# Mutation proof (the matrix row for T1-T4): admit the tls_ prefix into the gate's allow-set on a COPY and
# the create must stop aborting. A row that stays RED here would be redness unrelated to the allow-set.
rp "$BASE_REPLACE" "$(rc_obj 'tls_self_signed_cert.inngest_link' '"create"')"
awk '{ print } /"hcloud_server_network.inngest",/ && !d { print "        \"tls_self_signed_cert.inngest_link\","; d=1 }' "$GATE" > "$TMP/mutated-tls-allow.sh"
if cmp -s "$TMP/mutated-tls-allow.sh" "$GATE"; then
  fail "T6: the allow-set mutation matched NOTHING in the gate; the allow-set shape drifted"
else
  _rc=0; _out="$(bash -c "source '$PREAMBLE'; source '$TMP/mutated-tls-allow.sh'; inngest_host_replace_gate '$TMP/plan.json'" 2>&1)" || _rc=$?
  if [[ "$_rc" -eq 0 && "$_out" == *"inngest_host_replace_gate: PASS"* ]]; then
    pass
  else
    fail "T6: with the cert admitted into the allow-set the create must stop aborting (rc=${_rc}): ${_out}"
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
if [[ "$_ran" -lt 49 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 54. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 54)\n' "$_ran"
fi

echo ""
echo "=== test-inngest-host-replace-gate.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
