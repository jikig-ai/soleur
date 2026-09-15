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

# ── #8189 root-key arm fixtures ───────────────────────────────────────────────────
# The gate now ends in git_data_root_key_arm (tests/scripts/lib/git-data-root-key-arm.sh),
# so every PASS fixture carries what that arm reads: data.hcloud_ssh_keys.git_data_root
# resolved in prior_state, hcloud_ssh_key.default in prior_state, both ids on the recreated
# server, and a committed-anchor fingerprint file. The key is SYNTHESIZED here with ssh-keygen
# into $TMP and deleted on exit (cq-test-fixtures-synthesized-only) — never committed.
command -v ssh-keygen >/dev/null 2>&1 || { echo "FATAL: ssh-keygen is required for the root-key arm fixtures" >&2; exit 2; }
ssh-keygen -q -t ed25519 -N '' -C 'synthesized-root-key-under-test' -f "$TMP/root-key" || { echo "FATAL: ssh-keygen (root)" >&2; exit 2; }
ssh-keygen -q -t ed25519 -N '' -C 'synthesized-impostor-key' -f "$TMP/other-key" || { echo "FATAL: ssh-keygen (other)" >&2; exit 2; }
ROOT_KEY_PUB="$(<"$TMP/root-key.pub")"
OTHER_KEY_PUB="$(<"$TMP/other-key.pub")"
ssh-keygen -l -E sha256 -f "$TMP/root-key.pub" | awk '{print $2}' > "$TMP/git-data-root-key.fingerprint"
export GIT_DATA_ROOT_KEY_FINGERPRINT_FILE="$TMP/git-data-root-key.fingerprint"
# The harness's mutation helpers source a COPY of the gate from $TMP, and the gate sources the
# arm from its own directory — so the arm must sit beside that copy.
cp "${DIR}/lib/git-data-root-key-arm.sh" "$TMP/git-data-root-key-arm.sh"

# root_key_prior_state [public_key] — prior_state with the data source resolved to one key
# (id NUMBER 4242) and hcloud_ssh_key.default (id "1111").
root_key_prior_state() {
  jq -nc --arg pub "${1:-$ROOT_KEY_PUB}" '{values:{root_module:{resources:[
    {address:"data.hcloud_ssh_keys.git_data_root",mode:"data",type:"hcloud_ssh_keys",name:"git_data_root",
     values:{with_selector:"soleur-role=git-data-root",ssh_keys:[{id:4242,name:"soleur-git-data-root",fingerprint:"00:11:22:33",labels:{"soleur-role":"git-data-root"},public_key:$pub}]}},
    {address:"hcloud_ssh_key.default",mode:"managed",type:"hcloud_ssh_key",name:"default",values:{id:"1111"}}]}}}'
}
PRIOR_STATE="$(root_key_prior_state)"

# A resource_change object with the given address + actions array.
rc_obj() { printf '{"address":"%s","change":{"actions":[%s]}}' "$1" "$2"; }

# The scoped git-data recreate: server + server_network + BOTH volume_attachments REPLACE
# (delete+create); firewall_attachment UPDATE-in-place (server_ids re-point). The two data
# volumes + the LUKS passphrase are UNTARGETED → they do not appear in resource_changes at all
# (preserved by omission). Test 8 exercises the explicit-no-op variant.
# The recreated server carries BOTH key ids as strings (#8189): default "1111" and root 4242.
SERVER_REPLACE='{"address":"hcloud_server.git_data","change":{"actions":["delete","create"],"after":{"ssh_keys":["1111","4242"]},"after_unknown":{"ssh_keys":[false,false]}}}'
NET_REPLACE="$(rc_obj 'hcloud_server_network.git_data' '"delete","create"')"
VA_REPLACE="$(rc_obj 'hcloud_volume_attachment.git_data' '"delete","create"')"
VA_LUKS_REPLACE="$(rc_obj 'hcloud_volume_attachment.git_data_luks' '"delete","create"')"
FW_UPDATE="$(rc_obj 'hcloud_firewall_attachment.git_data' '"update"')"

write_plan() { printf '{"prior_state":%s,"resource_changes":[%s]}' "${2:-$PRIOR_STATE}" "$1" > "$TMP/plan.json"; }

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

# --- Test 5: FAIL — the LUKS passphrase is ROTATED (random_password replace: delete+create) ---
# A rotated passphrase luksOpens a NEW header on fresh boot, stranding the existing at-rest
# data. random_password.git_data_luks is out of the allow-set → out_of_scope AND the named
# luks_passphrase_touched backstop both fire.
LUKS_PW_ROTATE="$(rc_obj 'random_password.git_data_luks' '"delete","create"')"
write_plan "${PASS_SET},${LUKS_PW_ROTATE}"
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

# --- #6977 P13 REGRESSION ARM --------------------------------------------------------
#
# WHY THIS EXISTS. #6977 added `depends_on = [doppler_secret.git_data_luks_key]` to
# hcloud_server.git_data, to stop terraform booting the host before the LUKS key exists.
# That edge has a CROSS-PATH consequence this suite owns: the passphrase pair is now
# UPSTREAM of the server, so it enters THIS job's transitive closure and terraform emits
# it as an explicit `no-op` where previously it was absent from resource_changes entirely.
#
# The plan asserted that a no-op does not trip `luks_passphrase_touched` because that
# counter filters on the four MUTATING verbs. That is a claim about a jq filter, and this
# is the arm that measures it rather than inferring it — if it were wrong, the #6977 merge
# would have silently wedged the git-data REPLACE path (a gate that always fails is an
# outage, not a tripwire) and nothing else in the tree would have noticed.
PASSPHRASE_NOOP="$(rc_obj 'random_password.git_data_luks' '"no-op"')"
LUKS_SECRET_NOOP="$(rc_obj 'doppler_secret.git_data_luks_key' '"no-op"')"

write_plan "${PASS_SET},${PASSPHRASE_NOOP},${LUKS_SECRET_NOOP}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  pass
else
  fail "P13 regression: an explicit no-op on the LUKS passphrase pair (now upstream of the server via #6977's depends_on) must NOT trip luks_passphrase_touched — the git-data replace path is wedged"
fi

# NON-VACUITY for the arm above: the same pair with a MUTATING verb must still ABORT.
# Without this, the no-op assertion would also pass against a gate whose passphrase
# counter had been deleted outright — which is the failure it exists to detect.
PASSPHRASE_UPDATE="$(rc_obj 'random_password.git_data_luks' '"update"')"
write_plan "${PASS_SET},${PASSPHRASE_UPDATE}"
if git_data_host_replace_gate "$TMP/plan.json" >/dev/null; then
  fail "P13 non-vacuity: an UPDATE on the LUKS passphrase must still ABORT — the counter has been neutered, so the no-op arm above proves nothing"
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
# A4 is the arm that cannot be replaced by anything in test-plan-gate-preamble.sh: it
# proves THIS gate calls the preamble. Neutering the call must leave the plan REJECTED
# (so the retrofit never opened a door) while the preamble-distinctive signature
# DISAPPEARS (so the rejection was really the preamble's).
#
# THE ANCHOR IS NOT THE GATE NAME. Every abort this gate emits — including its own
# pre-existing ones — is prefixed with the gate name, so a name anchor cannot tell a
# preamble abort from a gate abort and the arm would be a redness detector, not a
# binding. `unclassifiable plan entry` is text only the preamble can produce.
_PG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${_PG_DIR}/lib/git-data-host-replace-gate.sh"
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
  git_data_host_replace_gate 1 "unclassifiable plan entry" "$TMP/pg-d5.json"
gate_check "A1 (D5): the ABORT is the preamble's and names this gate" \
  git_data_host_replace_gate 1 "git_data_host_replace_gate: ABORT — unclassifiable" "$TMP/pg-d5.json"
gate_check "A2 (D6): a SCALAR .change => fail-closed ABORT" \
  git_data_host_replace_gate 1 "unclassifiable plan entry" "$TMP/pg-d6.json"
gate_check "A2 (D6): the ABORT names the offending address" \
  git_data_host_replace_gate 1 "hcloud_volume.workspaces" "$TMP/pg-d6.json"

gate_mutate_layered "A4: classifiability call (invoked, not merely sourced)" \
  's/^  plan_gate_assert_classifiable .*/  :/' \
  "unclassifiable plan entry" "plan is NOT the exact scoped" \
  git_data_host_replace_gate "$TMP/pg-d5.json"




# ── #8189: the root-key arm (Guard 4) is wired into THIS gate ─────────────────────
# The arm's own suite (test-git-data-root-key-arm.sh) holds the full matrix; these rows prove
# the replace gate reaches it on an otherwise-perfect scoped recreate.
check_rk() {  # <name> <want_rc> <needle> — runs the gate on $TMP/plan.json
  gate_check "$1" git_data_host_replace_gate "$2" "$3" "$TMP/plan.json"
}

write_plan "${PASS_SET}"
check_rk "RK1 the scoped recreate carrying both key ids => PASS through the root-key arm" 0 "git_data_root_key_arm: PASS"

write_plan "${PASS_SET}" "$(root_key_prior_state "$OTHER_KEY_PUB")"
check_rk "RK2 [Guard 4 fingerprint] right name and label, different key => refused" 1 "verdict=git_data_root_key_not_in_create reason=fingerprint"

write_plan "${PASS_SET}" "$(root_key_prior_state | jq -c '.values.root_module.resources |= map(select(.address != "data.hcloud_ssh_keys.git_data_root"))')"
check_rk "RK3 [Guard 4 presence] data source absent from prior_state => refused" 1 "verdict=git_data_root_key_not_in_create reason=data_source_absent"

SERVER_DEFAULT_ONLY='{"address":"hcloud_server.git_data","change":{"actions":["delete","create"],"after":{"ssh_keys":["1111"]},"after_unknown":{"ssh_keys":[false]}}}'
write_plan "${SERVER_DEFAULT_ONLY},${NET_REPLACE},${VA_REPLACE},${VA_LUKS_REPLACE},${FW_UPDATE}"
check_rk "RK4 [Guard 4 membership] recreated server carries only the default key => refused" 1 "verdict=git_data_root_key_not_in_create reason=server_keys"

SERVER_REORDERED='{"address":"hcloud_server.git_data","change":{"actions":["delete","create"],"after":{"ssh_keys":["4242","1111"]},"after_unknown":{"ssh_keys":[false,false]}}}'
write_plan "${SERVER_REORDERED},${NET_REPLACE},${VA_REPLACE},${VA_LUKS_REPLACE},${FW_UPDATE}"
check_rk "RK5 reordered ssh_keys (numeric id in the data source, strings on the server) => PASS" 0 "git_data_root_key_arm: PASS"

write_plan "${PASS_SET}"
_rk_saved="$GIT_DATA_ROOT_KEY_FINGERPRINT_FILE"
export GIT_DATA_ROOT_KEY_FINGERPRINT_FILE="$TMP/absent.fingerprint"
check_rk "RK6 missing fingerprint file => refused with reason=fingerprint_file_missing" 1 "verdict=git_data_root_key_not_in_create reason=fingerprint_file_missing"
unset GIT_DATA_ROOT_KEY_FINGERPRINT_FILE
check_rk "RK7 fingerprint env unset => refused with reason=fingerprint_file_missing (fail closed)" 1 "verdict=git_data_root_key_not_in_create reason=fingerprint_file_missing"
export GIT_DATA_ROOT_KEY_FINGERPRINT_FILE="$_rk_saved"

# SOLE-GUARD: delete the arm call from a COPY of the gate and the fingerprint-mismatch plan
# PASSES — every counter in the gate is satisfied, so the arm is the only thing refusing it.
write_plan "${PASS_SET}" "$(root_key_prior_state "$OTHER_KEY_PUB")"
cp "$TMP/plan.json" "$TMP/rk-mismatch.json"
gate_mutate_and_check "RK8 root-key arm call (the replace gate's only check on the key set)" \
  '/^    git_data_root_key_arm "\$plan_json" /d' \
  git_data_host_replace_gate "$TMP/rk-mismatch.json"

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
if [[ "$_ran" -lt 31 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 31. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 31)\n' "$_ran"
fi

echo ""
echo "=== test-git-data-host-replace-gate.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
