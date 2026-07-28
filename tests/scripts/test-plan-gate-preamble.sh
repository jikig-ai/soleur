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

# D5, EXPLICIT. An EMPTY actions array is the MEASURED hole, and it is the one shape a
# type-only check cannot catch: `[]` IS an array. It is then invisible to every downstream
# arm at once — `[] | any(...)` is false so the out-of-scope and firewall selects skip it,
# `[] | index("delete")` is null so the destroy select skips it. Measured on a real plan: a
# happy 18-address birth that also carried hcloud_server.web["web-1"] with "actions": [] and
# "after": null — a destroy of the singleton behind app.soleur.ai — scored destroys=0,
# out_of_scope=0 and PASSED.
#
# `length > 0` is what rejects it, and NOTHING ELSE DOES: jq's `all` over an empty stream is
# vacuously TRUE, so the actions-are-strings conjunct below is satisfied by `[]`.
mk_plan "$TMP/emptyactions.json" "$(printf '[%s]' \
  '{"address":"hcloud_server.web[\"web-1\"]","type":"hcloud_server","change":{"actions":[],"before":{"id":9},"after":null}}')"
check "D5: an EMPTY actions array => ABORT" plan_gate_assert_classifiable 1 "unclassifiable" "demo_gate" "$TMP/emptyactions.json"
check "D5: the ABORT names the address whose destroy it hides" plan_gate_assert_classifiable 1 'hcloud_server.web["web-1"]' "demo_gate" "$TMP/emptyactions.json"

# D6. `.change` is a SCALAR. `.change.actions` on a number raises
# `Cannot index number with string "actions"`, so jq exits 5 — and `if jq -e '[...|select(bad)]
# | length > 0'` reads a jq ERROR as "condition false", reporting the plan CLASSIFIABLE. That
# is the shape the positive `all(...)` form exists to close; asserted here so a future
# "simplification" back to a negative search fails loudly.
mk_plan "$TMP/scalarchange.json" "$(printf '[%s]' \
  '{"address":"hcloud_volume.workspaces","type":"hcloud_volume","change":42}')"
check "D6: a SCALAR .change => ABORT" plan_gate_assert_classifiable 1 "unclassifiable" "demo_gate" "$TMP/scalarchange.json"

# The OFFENDER-EXTRACTION filter must survive the same scalar. Without a `?` on
# `.change.actions` in the offender jq, the extraction raises on the very entry it is trying
# to name, jq exits 5, `2>/dev/null` swallows it, and the ABORT names NO offender — verdict
# correct, operator's only diagnostic blank. web-host-replace-gate.sh documents this exact
# reason for its own `?`.
check "D6: the ABORT still NAMES the offender on a scalar .change" plan_gate_assert_classifiable 1 "hcloud_volume.workspaces" "demo_gate" "$TMP/scalarchange.json"

# A NESTED array. `["delete"]` is a string list; `[["delete"]]` is a list of lists. It is a
# non-empty array of the right outer type, so length > 0 and the type test both pass — only
# an assertion about the ELEMENTS rejects it. `index("delete")` on it is null, so a destroy
# hiding here is dropped by the destroy select exactly like a missing-actions entry.
#
# web-host-replace-gate.sh already carried this conjunct inline while this shared helper did
# not, so retrofitting that gate onto the helper WITHOUT adding it here would have been a
# REGRESSION. That is why the conjunct lands before any retrofit.
mk_plan "$TMP/nestedactions.json" "$(printf '[%s]' \
  '{"address":"hcloud_server.git_data","type":"hcloud_server","change":{"actions":[["delete"]],"before":null,"after":{}}}')"
check "a NESTED actions array => ABORT" plan_gate_assert_classifiable 1 "unclassifiable" "demo_gate" "$TMP/nestedactions.json"

# A NON-OBJECT ELEMENT of resource_changes. The verdict was always right — `.change` on a
# number raises, jq exits 5, and `if !` aborts — but it aborted because jq ERRORED, not
# because the assertion was false, and the offender list came back EMPTY. Measured before
# the element-type guard: "unclassifiable plan entry:  has no non-empty array
# .change.actions" — a correct refusal with a blank diagnostic.
#
# Both halves are pinned: the abort must survive, AND it must name something. A bare
# `.address?` would satisfy the first and silently fail the second by yielding empty.
printf '{"format_version":"1.2","resource_changes":[42]}\n' > "$TMP/scalarelem.json"
check "a NON-OBJECT element => ABORT" plan_gate_assert_classifiable 1 "unclassifiable" "demo_gate" "$TMP/scalarelem.json"
check "the ABORT on a non-object element is NOT blank" plan_gate_assert_classifiable 1 "<entry with no address>" "demo_gate" "$TMP/scalarelem.json"

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

# ── COVERAGE DRIFT CHECK (#6997) ──────────────────────────────────────────────────
#
# A thirteenth gate added later is born without the preamble call unless something fails.
# This is that something. It lives here rather than in a new lint script because the check
# is ten lines and this suite is already registered in scripts/test-all.sh — an unregistered
# guard is a guard that never runs, which is the defect class this whole file exists for.
#
# THREE THINGS ARE LOAD-BEARING AND EACH IS PROVEN BELOW RATHER THAN ASSERTED.
#
#   1. THE CALL ANCHOR. `grep -L plan_gate_assert_readable` is a PRESENCE check, and every
#      retrofitted gate contains that literal inside `if ! declare -F plan_gate_assert_readable`.
#      So the obvious form is satisfied by the re-source guard alone and a gate that SOURCES
#      the preamble and never CALLS it reports clean — the exact "sourced but not invoked"
#      vacuity the retrofit had to be proved against. `-E '^\s*plan_gate_assert_readable'`
#      matches the call form; `if ! declare -F …` does not match it.
#
#   2. `xargs -r`. Without it an empty first stage leaves `grep -L` with no file operands, so
#      it READS STDIN. Measured: `printf '' | xargs grep -L PAT` prints `(standard input)` and
#      exits 0 — a broken glob would hang or report clean.
#
#   3. A SCANNED-FILE FLOOR. A guard whose glob silently matches nothing reports a clean
#      sweep. The floor turns that into a loud failure.
printf '\ncoverage drift check (a new gate must be born on the preamble)\n'

LIBDIR="${ROOT}/tests/scripts/lib"

# The two gates deliberately NOT on the preamble, tracked in #7044. Each still carries its
# own inline checks; #7044 records their residual holes, the re-evaluation trigger, and why
# stock-preflight-gate.sh's "tier 2" label understates it (it is sourced 8x by
# apply-web-platform-infra.yml, more than any gate that WAS retrofitted).
EXPECTED_EXCLUSIONS="stock-preflight-gate.sh
web-host-replace-gate.sh"

drift_offenders() {
  grep -l "local plan_json" "$1"/*gate*.sh 2>/dev/null \
    | xargs -r grep -LE '^\s*plan_gate_assert_readable' \
    | xargs -r -n1 basename | sort
}
drift_scanned() {
  grep -l "local plan_json" "$1"/*gate*.sh 2>/dev/null | wc -l
}
# Any lib file that grades a plan but is named OFF the *gate* glob would never be scanned by
# the derivation at all — invisible to the check rather than merely uncovered.
drift_offglob() {
  grep -l "local plan_json" "$1"/*.sh 2>/dev/null \
    | grep -vE '/[^/]*gate[^/]*\.sh$' | xargs -r -n1 basename | sort
}

actual_offenders="$(drift_offenders "$LIBDIR")"
if [[ "$actual_offenders" == "$EXPECTED_EXCLUSIONS" ]]; then
  pass "every plan-grading gate calls the preamble, except the two tracked in #7044"
else
  fail "gate coverage drifted — a gate grades a plan without calling the preamble, or an exclusion was resolved without updating this list (see #7044)" "n/a" "got:
${actual_offenders}
want:
${EXPECTED_EXCLUSIONS}"
fi

scanned="$(drift_scanned "$LIBDIR")"
if [[ "$scanned" -ge 12 ]]; then
  pass "the derivation scanned ${scanned} gate files (floor: 12)"
else
  fail "the derivation scanned only ${scanned} gate files — the glob is broken and this check is reporting clean vacuously" "n/a" "scanned=${scanned}"
fi

offglob="$(drift_offglob "$LIBDIR")"
if [[ -z "$offglob" ]]; then
  pass "no plan-grading lib file is named off the *gate* glob"
else
  fail "a lib file grades a plan but is named off the *gate* glob, so the derivation cannot see it" "n/a" "$offglob"
fi

# ── The drift check's own non-vacuity, in four directions ─────────────────────────
# Without these, a typo in the derivation would make the three assertions above pass
# forever. Each synthetic gate below MUST be reported.
SYN="$TMP/synthetic-lib"
mkdir -p "$SYN"
cp "$LIBDIR"/*gate*.sh "$SYN"/

# (a) A thirteenth gate that grades a plan and never mentions the preamble at all.
printf 'thirteenth_gate() {\n  local plan_json="$1"\n  echo "$plan_json"\n}\n' > "$SYN/thirteenth-gate.sh"
if [[ "$(drift_offenders "$SYN")" == *"thirteenth-gate.sh"* ]]; then
  pass "drift check REPORTS a new gate that never calls the preamble"
else
  fail "drift check missed a new gate with no preamble call at all" "n/a" "$(drift_offenders "$SYN")"
fi

# (b) THE ONE THAT MATTERS. A gate that SOURCES the preamble — carrying the exact
# `declare -F` guard line every retrofitted gate has — and never CALLS it. A presence-based
# `grep -L` is satisfied by that guard line and reports this file clean.
cat > "$SYN/sourced-never-called-gate.sh" <<'SYNEOF'
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _SNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${_SNC_DIR}/plan-gate-preamble.sh"
fi
sourced_never_called_gate() {
  local plan_json="$1"
  echo "$plan_json"
}
SYNEOF
if [[ "$(drift_offenders "$SYN")" == *"sourced-never-called-gate.sh"* ]]; then
  pass "drift check REPORTS a gate that sources the preamble but never calls it (call anchor, not presence)"
else
  fail "drift check anchors on PRESENCE, not the CALL — a gate that sources and never invokes passes" "n/a" "$(drift_offenders "$SYN")"
fi

# (c) A plan-grading file named off the *gate* glob.
printf 'off_glob_grader() {\n  local plan_json="$1"\n  echo "$plan_json"\n}\n' > "$SYN/plan-classifier.sh"
if [[ "$(drift_offglob "$SYN")" == *"plan-classifier.sh"* ]]; then
  pass "drift check REPORTS a plan-grading lib file named off the *gate* glob"
else
  fail "drift check cannot see a plan-grading file named off the *gate* glob" "n/a" "$(drift_offglob "$SYN")"
fi

# (d) An EMPTY directory must fail the floor, not report a clean sweep. This is the
# `xargs -r` / broken-glob direction: the offender list is legitimately empty here, so only
# the floor distinguishes "nothing is wrong" from "nothing was looked at".
EMPTY="$TMP/empty-lib"; mkdir -p "$EMPTY"
if [[ "$(drift_scanned "$EMPTY")" -lt 12 && -z "$(drift_offenders "$EMPTY")" ]]; then
  pass "an empty glob yields zero scanned files (the floor, not the offender list, catches it)"
else
  fail "an empty glob did not produce a zero scan count — the vacuity floor cannot fire" "n/a" "scanned=$(drift_scanned "$EMPTY") offenders=$(drift_offenders "$EMPTY")"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
