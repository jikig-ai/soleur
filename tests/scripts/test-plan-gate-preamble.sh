#!/usr/bin/env bash
# Test suite for tests/scripts/lib/plan-gate-preamble.sh (#6977, cto F1).
#
# The preamble is the fail-CLOSED half of every tfplan gate. Its whole value is that it
# refuses documents the gate cannot read, so the property under test is never "does the
# good document pass" — it is "does each malformed document ABORT, and does the message
# name what was wrong with it".
#
# A preamble that aborts with a generic message is only marginally better than one that
# does not abort: the operator reading a mid-dispatch failure has to open the gate source
# to learn which counter or which entry broke. So every reject arm below pins BOTH the
# return code AND a message substring.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
LIB="${ROOT}/tests/scripts/lib/plan-gate-preamble.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"; printf '       rc=%s\n' "${2:-?}"; printf '       out=%s\n' "${3:-}"
}

# shellcheck source=/dev/null
source "$LIB"

# mk_plan <file> <json-array-of-resource_changes>
mk_plan() {
  local f="$1" changes="$2"
  printf '{"format_version":"1.2","resource_changes":%s}\n' "$changes" > "$f"
}

# rc_entry <address> <type> <actions-json>
rc_entry() {
  printf '{"address":%s,"type":%s,"change":{"actions":%s,"before":null,"after":{}}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)" "$3"
}

# rc_noactions <address> <type> — an entry with NO .change.actions key at all.
rc_noactions() {
  printf '{"address":%s,"type":%s,"change":{"before":null,"after":{}}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"
}

# check <name> <fn> <want_rc> <needle> <args…>
check() {
  local name="$1" fn="$2" want_rc="$3" needle="$4"; shift 4
  local out rc
  out="$("$fn" "$@" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

printf '\n=== plan-gate-preamble ===\n\n'

# ── plan_gate_assert_readable ─────────────────────────────────────────────────────
mk_plan "$TMP/good.json" "$(printf '[%s]' "$(rc_entry 'hcloud_server.x' 'hcloud_server' '["create"]')")"
check "a well-formed plan => rc 0" plan_gate_assert_readable 0 "" "demo_gate" "$TMP/good.json"

# An EMPTY resource_changes array is well-formed and must pass the readability check.
# The preamble's job is document shape, not plan content — a gate that conflated the two
# would refuse a legitimately empty plan here instead of in its own cardinality arm,
# where the message can actually explain what was expected.
mk_plan "$TMP/empty.json" '[]'
check "an EMPTY resource_changes array is still READABLE => rc 0" plan_gate_assert_readable 0 "" "demo_gate" "$TMP/empty.json"

check "missing plan file => ABORT" plan_gate_assert_readable 1 "not found" "demo_gate" "$TMP/nope.json"
check "the missing-file ABORT names the gate" plan_gate_assert_readable 1 "demo_gate" "demo_gate" "$TMP/nope.json"

check "empty path argument => ABORT" plan_gate_assert_readable 1 "no plan JSON path" "demo_gate" ""

printf 'not json at all\n' > "$TMP/garbage.json"
check "unparseable JSON => ABORT" plan_gate_assert_readable 1 "unparseable" "demo_gate" "$TMP/garbage.json"

# EXPLICIT null resource_changes. This is failure mode 1 and the reason the array-type
# test is separate from has(): `has("resource_changes")` is TRUE here, so a has()-only
# check waves this through and every downstream counter reads 0 from `null | length`.
mk_plan "$TMP/null.json" 'null'
check "null resource_changes => ABORT" plan_gate_assert_readable 1 "no resource_changes array" "demo_gate" "$TMP/null.json"

# The key absent entirely.
printf '{"format_version":"1.2"}\n' > "$TMP/nokey.json"
check "absent resource_changes key => ABORT" plan_gate_assert_readable 1 "no resource_changes array" "demo_gate" "$TMP/nokey.json"

# resource_changes present but the WRONG type. An object is not an array, and
# `.resource_changes[]` over an object iterates its VALUES — so a gate reading this
# document would grade whatever the object happened to contain.
printf '{"format_version":"1.2","resource_changes":{"a":1}}\n' > "$TMP/obj.json"
check "object-typed resource_changes => ABORT" plan_gate_assert_readable 1 "no resource_changes array" "demo_gate" "$TMP/obj.json"

# ── plan_gate_assert_classifiable ─────────────────────────────────────────────────
check "all entries carry array actions => rc 0" plan_gate_assert_classifiable 0 "" "demo_gate" "$TMP/good.json"

mk_plan "$TMP/noactions.json" "$(printf '[%s,%s]' \
  "$(rc_entry 'hcloud_server.x' 'hcloud_server' '["create"]')" \
  "$(rc_noactions 'hcloud_volume.y' 'hcloud_volume')")"
check "an entry with no .change.actions => ABORT" plan_gate_assert_classifiable 1 "unclassifiable" "demo_gate" "$TMP/noactions.json"
check "the unclassifiable ABORT names the offending address" plan_gate_assert_classifiable 1 "hcloud_volume.y" "demo_gate" "$TMP/noactions.json"

# actions present but a STRING rather than an array. `"delete" | index("delete")` is 0 —
# a truthy-looking index into a string — so a type-blind check reads this as classifiable
# and the destroy arm's `index("delete")` behaves unpredictably on it.
mk_plan "$TMP/stractions.json" "$(printf '[%s]' \
  '{"address":"hcloud_server.x","type":"hcloud_server","change":{"actions":"delete","before":null,"after":{}}}')"
check "string-typed actions => ABORT" plan_gate_assert_classifiable 1 "unclassifiable" "demo_gate" "$TMP/stractions.json"

# null actions explicitly — failure mode 2 verbatim.
mk_plan "$TMP/nullactions.json" "$(printf '[%s]' \
  '{"address":"hcloud_server.x","type":"hcloud_server","change":{"actions":null,"before":null,"after":{}}}')"
check "null actions => ABORT" plan_gate_assert_classifiable 1 "unclassifiable" "demo_gate" "$TMP/nullactions.json"

# ── plan_gate_assert_numeric ──────────────────────────────────────────────────────
check "all counters numeric => rc 0" plan_gate_assert_numeric 0 "" "demo_gate" "creates=1" "destroys=0"
check "zero is numeric => rc 0" plan_gate_assert_numeric 0 "" "demo_gate" "creates=0"

# THE failure this function exists for: an uncomputed counter is the empty string, and
# `[[ "" -gt 0 ]]` is FALSE, so it satisfies every threshold it is compared against.
check "an EMPTY counter => ABORT" plan_gate_assert_numeric 1 "counter parse failed" "demo_gate" "creates=" "destroys=0"
check "the empty-counter ABORT names WHICH counter" plan_gate_assert_numeric 1 "creates=''" "demo_gate" "creates=" "destroys=0"
check "a non-numeric counter => ABORT" plan_gate_assert_numeric 1 "counter parse failed" "demo_gate" "destroys=null"
check "a NEGATIVE counter => ABORT" plan_gate_assert_numeric 1 "counter parse failed" "demo_gate" "creates=-1"
check "a jq error string => ABORT" plan_gate_assert_numeric 1 "counter parse failed" "demo_gate" "out_of_scope=jq: error"

# Only the BAD counters are named; a good one alongside a bad one must not be reported.
out="$(plan_gate_assert_numeric "demo_gate" "creates=3" "destroys=" 2>&1)"
if [[ "$out" == *"destroys="* && "$out" != *"creates="* ]]; then
  pass "the ABORT names only the FAILING counter, not its healthy siblings"
else
  fail "the ABORT must name only the failing counter" "n/a" "$out"
fi

# A value containing '=' is reported intact. `${pair#*=}` splits on the FIRST '=', so a
# truncating split could yield a fragment that coincidentally matches ^[0-9]+$ and turn
# a fail-closed abort into a silent pass.
out="$(plan_gate_assert_numeric "demo_gate" "creates=jq: error: x=1" 2>&1)"
if [[ "$out" == *"jq: error: x=1"* ]]; then
  pass "a counter value containing '=' is reported intact (split on FIRST '=')"
else
  fail "the value must not be truncated at an embedded '='" "n/a" "$out"
fi

# ── MUTATION SECTION ──────────────────────────────────────────────────────────────
# Each arm here is a SOLE-GUARD: the preamble has no second line of defence by design —
# it IS the line of defence. Neutering any arm must let the malformed document through.
printf '\nmutation checks (each neuters one guard; the arm it protects must flip)\n'

# mutate_and_check <label> <sed-expr> <fn> <args…>
mutate_and_check() {
  local label="$1" sed_expr="$2" fn="$3"; shift 3
  local mutated out rc
  mutated="$TMP/mutated-preamble.sh"
  sed "$sed_expr" "$LIB" > "$mutated"
  # NON-VACUITY FLOOR: sed exits 0 when it matches nothing, so a mutation aimed at a
  # guard that does not exist emits a byte-identical copy and the malformed document
  # sails through the UN-neutered library — reporting the arm load-bearing for the
  # weakest possible reason.
  if cmp -s "$mutated" "$LIB"; then
    fail "$label — the mutation matched NOTHING (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  out="$(bash -c "source '$mutated'; $fn $(printf "'%s' " "$@")" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "$label (arm is load-bearing — neutering it accepts the malformed document)"
  else
    fail "$label — the arm did NOT change behavior when neutered; it may be dead code" "$rc" "$out"
  fi
}

# mutate_layered <label> <sed-expr> <own-signature> <fallback-signature> <fn> <args…>
#
# The LAYERED contract, for an arm that is NOT the last line of defence for its fixture.
# Asserts four things after neutering: the file changed (non-vacuity), the document is
# STILL refused, this arm's signature is GONE, and the fallback arm's signature is
# present. Dropping any one turns this into a check that cannot fail.
#
# The unmutated control is what makes it honest: without it, an arm that never fired for
# this fixture would trivially satisfy "own signature absent".
mutate_layered() {
  local label="$1" sed_expr="$2" own="$3" fallback="$4" fn="$5"; shift 5
  local mutated base out rc
  mutated="$TMP/mutated-layered.sh"
  sed "$sed_expr" "$LIB" > "$mutated"
  if cmp -s "$mutated" "$LIB"; then
    fail "$label — the mutation matched NOTHING (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  base="$("$fn" "$@" 2>&1)"
  if [[ "$base" != *"$own"* ]]; then
    fail "$label — the unmutated preamble did not refuse via the '$own' arm; the fixture does not exercise it." "n/a" "$base"
    return
  fi
  out="$(bash -c "source '$mutated'; $fn $(printf "'%s' " "$@")" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 && "$out" != *"$own"* && "$out" == *"$fallback"* ]]; then
    pass "$label (layered — owns the rejection; neutering it hands off to '$fallback', never to rc 0)"
  else
    fail "$label — layered contract broken (want rc=1, '$own' absent, '$fallback' present)" "$rc" "$out"
  fi
}

# SOLE-GUARD: the array-type test is genuinely the last line for a null resource_changes.
# Anchored on the ABORT line's own literal rather than the `if ! jq -e` condition, which
# spans two lines and is dense with metacharacters — a sed aimed at it produces a
# syntactically broken file, which the floor correctly reports rather than a real result.
mutate_and_check "readable: array-type guard" \
  's/^    echo "${gate}: ABORT — jq filter failed.*/    return 0/' \
  plan_gate_assert_readable "demo_gate" "$TMP/null.json"

# LAYERED, not sole — and this classification was corrected BY the mutation, not by
# reading the code. A missing FILE is also unreadable to jq, so neutering the -f test
# hands the refusal to the array-type arm one check below. The -f arm still earns its
# place: it owns the MESSAGE ("not found" tells an operator the path is wrong; "the
# document is unparseable" sends them looking for malformed JSON that does not exist).
mutate_layered "readable: missing-file guard" \
  's/^  if \[\[ ! -f "\$plan_json" \]\]; then/  if false; then/' \
  "not found" "unparseable" \
  plan_gate_assert_readable "demo_gate" "$TMP/nope.json"

mutate_and_check "classifiable: actions-shape guard" \
  's/^    echo "${gate}: ABORT — unclassifiable.*/    return 0/' \
  plan_gate_assert_classifiable "demo_gate" "$TMP/noactions.json"

# Anchored on the accumulator rather than the `=~ ^[0-9]+$` condition: `+` and `$` are
# BRE metacharacters whose escaping differs between sed dialects, and a mis-escaped
# expression matches nothing — which the floor reports as a missing guard (it did).
mutate_and_check "numeric: counter-shape guard" \
  's/^      bad+=.*/      :/' \
  plan_gate_assert_numeric "demo_gate" "creates="

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
