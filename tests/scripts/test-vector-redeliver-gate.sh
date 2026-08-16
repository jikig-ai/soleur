#!/usr/bin/env bash
# Mutation-matrix suite for tests/scripts/lib/vector-redeliver-gate.sh.
#
# It sources THE SAME BYTES the workflow's vector_redeliver gate step sources, so this
# suite and CI cannot drift into two implementations of one decision.
#
# EVERY ROW BELOW IS AN EDIT THAT MUST DRIVE THE GUARD RED (or, for M4, to a distinct
# green). The rows are grouped by AXIS, because N edits on one axis is one mutation:
#   A — fixture CONTENT   (what the plan says)
#   B — fixture SHAPE     (documents the gate cannot read/classify)
#   C — the SUT itself    (mutating the gate file, to pin a redundant backstop)
# Axis D (workflow wiring — is the gate actually invoked?) cannot be tested from here and
# lives in test-vector-redeliver-wiring.sh. Counting assertions in THIS file has no bearing
# on whether the WORKFLOW calls the gate; conflating the two was a category error worth
# naming rather than repeating.
#
# Fixtures are SYNTHESIZED, never captured from a real plan (cq-test-fixtures-synthesized-only).

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s (rc=%s)\n%s\n' "$1" "${2:-n/a}" "${3:-}" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

GATE="${DIR}/lib/vector-redeliver-gate.sh"
PREAMBLE="${DIR}/lib/plan-gate-preamble.sh"

# shellcheck source=tests/scripts/lib/gate-suite-harness.sh
source "${DIR}/lib/gate-suite-harness.sh"
# shellcheck source=tests/scripts/lib/vector-redeliver-gate.sh
source "$GATE"

check() { local n="$1"; shift; gate_check "$n" vector_redeliver_gate "$@"; }

ALLOW='terraform_data.journald_persistent'

# A compliant delivery: the replace shape.
DELIVER="$(rc_entry "$ALLOW" 'terraform_data' '["delete","create"]' '{}')"
# The bare-create shape — admitted by design (stranded-recovery; see the gate header).
DELIVER_BARE="$(rc_entry "$ALLOW" 'terraform_data' '["create"]')"

# ── T1 — the happy paths, and the counter line the liveness signal depends on ────────
mk_plan "$TMP/t1.json" "[${DELIVER}]"
check "T1: exactly one replace-shaped delivery PASSes" 0 "PASS — exactly one delivery" "$TMP/t1.json"
check "T1b: the PASS path PRINTS its counter line (nothing else asserts the gate is observable)" \
  0 "vector_out_of_scope_changes=0 host_destroyed=0 journald_entries=1 journald_noop=0 journald_family=1 journald_delivered=1" "$TMP/t1.json"

mk_plan "$TMP/t1c.json" "[${DELIVER_BARE}]"
check "T1c: a BARE create is a delivery too (refusing it would brick the recovery arm)" \
  0 "PASS — exactly one delivery" "$TMP/t1c.json"

# ── Axis A — fixture content ─────────────────────────────────────────────────────────

# M1 — the second-member row: proves the gate does not stop at the first compliant entry.
M1_EXTRA="$(rc_entry 'cloudflare_bot_management.soleur_ai' 'cloudflare_bot_management' '["update"]' '{}')"
mk_plan "$TMP/m1.json" "[${DELIVER},${M1_EXTRA}]"
check "M1: a compliant delivery PLUS one out-of-scope update is REFUSED" \
  1 "outside the allow-set" "$TMP/m1.json"

# M2 — the address is present but the shape is not a delivery.
M2_ENTRY="$(rc_entry "$ALLOW" 'terraform_data' '["update"]' '{}')"
mk_plan "$TMP/m2.json" "[${M2_ENTRY}]"
check "M2: an update-in-place at the allowed address is NOT a delivery" \
  1 "neither a delivery nor an already-delivered no-op" "$TMP/m2.json"

# M4 — absence is the arm's own success condition one dispatch later, NOT a failure.
# Asserted as a distinct GREEN, and on the message text, because the whole point of F12 is
# that this outcome is legible rather than merely non-red.
mk_plan "$TMP/m4.json" "[]"
check "M4: an empty plan is NO-OP SUCCESS, not a refusal" 0 "NO-OP" "$TMP/m4.json"
check "M4b: the no-op message says 'no entry matched the allow-set', never 'state already matches' \
(zero entries is ALSO what a broken allow-set looks like)" \
  0 "no entry matched the allow-set" "$TMP/m4.json"

# ── M13/M14 — the two branches the FIRST CUT OF THIS GATE GOT WRONG ──────────────────
# Both rows exist because the original three-counter design keyed "already delivered" on
# journald_entries==0, and that is not the shape terraform produces.
#
# M13 IS THE REGRESSION PIN. Terraform emits ["no-op"] rows for targeted-but-unchanged
# resources — measured on this repo's own captured plan fixture
# (tests/scripts/fixtures/tfplan-web-platform-real-baseline.json: 73 resource_changes, ALL
# ["no-op"]). So a re-dispatch after a successful delivery — the single most routine dispatch
# this arm has, and one F12 names as legitimate — scored entries=1 delivered=0 and ABORTED,
# telling the operator to hunt a destroy that does not exist. The M4 fixture below could not
# catch it: an EMPTY plan is not a no-op row at the address.
NOOP_AT_ALLOW="$(rc_entry "$ALLOW" 'terraform_data' '["no-op"]' '{}')"
mk_plan "$TMP/m13.json" "[${NOOP_AT_ALLOW}]"
check "M13: a NO-OP row at the allowed address is already-delivered SUCCESS, not a refusal" \
  0 "ALREADY delivered" "$TMP/m13.json"
check "M13b: the already-delivered message is distinct from the absent-address one (they are different states and must not share prose)" \
  0 "in the plan as a no-op" "$TMP/m13.json"

# M14 — the un-indexed-address assumption, converted from a comment into a counter. If the
# resource ever moves under for_each/count its address becomes …journald_persistent["web-1"],
# exact equality stops matching, and entries reads 0 — which under the first cut printed the
# REASSURING "nothing to redeliver" for a gate that had gone permanently blind. The
# index-agnostic family counter (keyed on .address, see the gate) is the only thing that can
# still see it.
M14="$(rc_entry "${ALLOW}[\\\"web-1\\\"]" 'terraform_data' '["delete","create"]' '{}')"
mk_plan "$TMP/m14.json" "[${M14}]"
check "M14: an INDEXED address (the for_each move) is refused as a STALE ALLOW-SET, never as no-op success" \
  1 "allow-set is STALE" "$TMP/m14.json"
check "M14b: the stale-allow-set refusal is named BEFORE the generic out-of-scope one (a moved resource is also out-of-scope, and that message sends the operator after drift that does not exist)" \
  1 "moved under for_each/count" "$TMP/m14.json"

# M14c — the family regex must be anchored at BOTH ends. Measured: dropping the trailing `$`
# left this suite fully green, because every other family row also carries a real entry at the
# exact address, so `entries == 0` never held and the branch never fired. This row is the one
# shape that isolates it — a near-miss address ALONE, with the real one absent. Unanchored,
# `journald_persistent_v2` matches as a prefix and the operator is told the allow-set is stale
# and the resource has moved, when in truth an unrelated resource merely shares a name prefix.
M14C="$(rc_entry "${ALLOW}_v2" 'terraform_data' '["delete","create"]' '{}')"
mk_plan "$TMP/m14c.json" "[${M14C}]"
check "M14c: a near-miss address ALONE is out-of-scope, NOT a stale allow-set (pins the regex end anchor)" \
  1 "outside the allow-set" "$TMP/m14c.json"

# M7 — duplicate entries at the allowed address.
mk_plan "$TMP/m7.json" "[${DELIVER},${DELIVER}]"
check "M7: two entries for the allowed address are REFUSED" \
  1 "neither a delivery nor an already-delivered no-op" "$TMP/m7.json"

# M9 — the ONLY rows distinguishing exact-equality from a prefix/contains implementation.
# With a one-member allow-set, nothing else can tell IN(.address; allow[]) from `inside`.
M9A="$(rc_entry 'terraform_data.journald_persistent_v2' 'terraform_data' '["update"]' '{}')"
mk_plan "$TMP/m9a.json" "[${DELIVER},${M9A}]"
check "M9a: a SUFFIXED near-miss address (…_v2) is out-of-scope, not the allowed address" \
  1 "outside the allow-set" "$TMP/m9a.json"

M9B="$(rc_entry 'module.staging.terraform_data.journald_persistent' 'terraform_data' '["delete","create"]' '{}')"
mk_plan "$TMP/m9b.json" "[${DELIVER},${M9B}]"
check "M9b: a MODULE-PREFIXED near-miss address is out-of-scope, not the allowed address" \
  1 "outside the allow-set" "$TMP/m9b.json"

# M10 — the MEASURED production hole: a hidden destroy that scored zeroes and PASSED a
# sibling gate. "actions": [] is invisible to every positive filter at once.
#
# MEASURED HERE, AND THE MECHANISM IS NOT THE ONE THE DESIGN PREDICTED. The design expected
# this to land on vector_out_of_scope_changes. It does not reach the counters at all: the
# fail-closed preamble classifies an empty-actions entry as UNCLASSIFIABLE and refuses
# first. That is a strictly stronger guarantee — it fires before any counter can be wrong —
# so the row is asserted on what actually happens rather than on the predicted path. The
# negative action filter would also have counted it (`[]` is neither ["no-op"] nor
# ["read"]), so the shape is closed twice; this asserts the OUTER layer, which is the one
# that decides.
M10A="$(rc_empty_actions 'hcloud_server.web["web-1"]' 'hcloud_server')"
mk_plan "$TMP/m10a.json" "[${DELIVER},${M10A}]"
check "M10a: an EMPTY-actions entry (the measured hidden-destroy shape) is REFUSED — by the preamble, before any counter runs" \
  1 "unclassifiable plan entry" "$TMP/m10a.json"

M10B="$(rc_scalar_change 'hcloud_server.web["web-1"]' 'hcloud_server')"
mk_plan "$TMP/m10b.json" "[${DELIVER},${M10B}]"
check "M10b: a SCALAR .change entry is refused by the fail-closed preamble, not silently classified" \
  1 "unclassifiable plan entry" "$TMP/m10b.json"

# M11 — the most destructive single-address shape this arm can emit. host_destroyed is
# TYPE-scoped (so it cannot see a terraform_data) and out-of-scope EXCLUDES the allowed
# address, so ONLY the entries-vs-delivered split catches this. Without it, a destroy of
# the delivery resource would have returned NO-OP SUCCESS — the reassuring message for the
# alarming condition.
M11A="$(rc_entry "$ALLOW" 'terraform_data' '["delete"]' '{}')"
mk_plan "$TMP/m11a.json" "[${M11A}]"
check "M11a: a LONE delete at the allowed address is REFUSED (never reported as 'nothing to redeliver')" \
  1 "neither a delivery nor an already-delivered no-op" "$TMP/m11a.json"

M11B="$(rc_entry "$ALLOW" 'terraform_data' '["forget"]' '{}')"
mk_plan "$TMP/m11b.json" "[${M11B}]"
check "M11b: a LONE forget at the allowed address is REFUSED" \
  1 "neither a delivery nor an already-delivered no-op" "$TMP/m11b.json"

# M12 — the workspaces volumes are sole-copy user data and sit in this arm's closure.
M12="$(rc_entry 'hcloud_volume.workspaces["web-1"]' 'hcloud_volume' '["delete"]' '{}')"
mk_plan "$TMP/m12.json" "[${DELIVER},${M12}]"
check "M12: a workspaces-VOLUME delete trips the named destroy backstop (sole-copy user data)" \
  1 "would DESTROY a server or volume" "$TMP/m12.json"

# ── Axis B — fixture shape (the fail-closed preamble) ────────────────────────────────

printf '{}\n' > "$TMP/m5a.json"
check "M5a: a document with no resource_changes is REFUSED, not scored as zero-of-everything" \
  1 "Fail-closed" "$TMP/m5a.json"

M5B="$(rc_noactions 'hcloud_server.web["web-1"]' 'hcloud_server')"
mk_plan "$TMP/m5b.json" "[${DELIVER},${M5B}]"
check "M5b: an entry with NO actions key is unclassifiable, not benign" \
  1 "unclassifiable plan entry" "$TMP/m5b.json"

# M5c — a counter that fails to evaluate. Neuter one counter's jq so it yields empty, and
# assert the numeric preamble names it rather than letting "" satisfy every threshold.
gate_mutate_and_check "M5c: an EMPTY counter is caught by plan_gate_assert_numeric, not coerced past every threshold" \
  's/journald_entries: (/journald_entries: (""|/' \
  vector_redeliver_gate "$TMP/t1.json"

# ── Axis C — the SUT itself (pinning a deliberately-redundant backstop) ──────────────
#
# host_destroyed is REDUNDANT with out-of-scope by construction: any server/volume destroy
# is also outside the allow-set. A FIXTURE row for it is therefore vacuous — out-of-scope
# reddens first, so the fixture passes whether or not the backstop exists. The only honest
# way to pin a redundant arm is to neuter it and assert the fallback takes over.
M3_FIXTURE="$(rc_entry 'hcloud_server.web["web-1"]' 'hcloud_server' '["delete","create"]' '{}')"
mk_plan "$TMP/m3.json" "[${DELIVER},${M3_FIXTURE}]"
gate_mutate_layered "M3: neutering host_destroyed hands off to out-of-scope, never to PASS" \
  's/"\$hdel" -gt 0/"\$hdel" -gt 999999/' \
  "would DESTROY a server or volume" \
  "outside the allow-set" \
  vector_redeliver_gate "$TMP/m3.json"

# M6b (insert an early `return 0` in the gate) is COVERED by M1/M2/M7 above — any of them
# goes green if the gate returns early. It is recorded as covered rather than claimed as an
# independent detector, because a row that cannot fail independently is not a row.

# ── Anti-vacuity floor ───────────────────────────────────────────────────────────────
#
# DELIBERATELY SELF-CONTAINED — bash builtins and this suite's own counters only, no
# harness call. A sibling suite measured the failure this avoids: its floor called a
# harness helper whose `source` sat inside the block the mutation deleted, so the floor
# exited 127, recorded nothing, and the suite passed. A floor that depends on the thing it
# guards is not a floor.
#
# A FLOOR, NOT EQUALITY — the count is developer-incremented, so `-eq` would redden the
# suite on every legitimately-added assertion and train people to bump it unread.
_ran=$((passes + fails))
if [[ "$_ran" -lt 24 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 24. Arms were deleted, skipped, or the suite exited early — a suite that runs NO assertions exits 0 exactly like one that passes.\n' "$_ran" >&2
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 24)\n' "$_ran"
fi

echo ""
echo "=== test-vector-redeliver-gate.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
