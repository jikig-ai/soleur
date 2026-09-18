#!/usr/bin/env bash
# Tests for scripts/classify-workflow-transitions.sh.
#
# WHAT THIS REPLACES. The plan originally specified a record-mode PreToolUse hook
# on the Skill matcher. Plan review cut it: a record-mode event reaches no
# consumer -- it carries no corpus rule-id prefix, so the aggregator files it
# under summary.non_corpus_counts, which nothing reads, and compound's Deviation
# Analyst filters to {deny, bypass, hook_self_fault}, none of which record-mode
# can emit. Meanwhile the data the hook would have recorded ALREADY EXISTS:
# .claude/hooks/skill-invocation-logger.sh appends {ts, skill, session_id}
# on every Skill call. Only the classification was missing, and classification
# does not need a hook. So this is an offline pass over a log that is already
# being written -- no new PreToolUse surface, nothing to wedge a session.
#
# THE PROPERTY: for every session in the invocation log, each consecutive
# (previous skill -> next skill) pair that is absent from the declared edge set
# is reported exactly once, attributed to the session it occurred in.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/classify-workflow-transitions.sh"

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq missing — this suite cannot run its SUT (an exit-0 skip reads as green)"; exit 1; }

TMP_ROOT=$(mktemp -d -t classifytest.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 1; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM

assert_fixture_dir() {
  local d="${1-}"
  [[ -n "$d" && "$d" == /* && -d "$d" && ! -L "$d" ]] || {
    echo "FATAL: refusing to operate on non-fixture dir '${d-}'" >&2; exit 2; }
  case "$d" in "$TMP_ROOT"|"$TMP_ROOT"/*) : ;; *)
    echo "FATAL: '$d' is outside the fixture root" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$TMP_ROOT"

fails=0
passes=0
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# Instrument self-test: drive both helpers before any real case, so a gutted
# helper cannot report a clean sweep. Reports with printf + exit, never through
# the helpers it guards.
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — expected, subtracted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: assertion helpers are not dispatching (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
fails=0
SELFTEST_PASSES=$passes

[[ -x "$SUT" ]] || { echo "  FAIL: $SUT not executable (RED expected before implementation)"; echo "0 passed, 1 failed"; exit 1; }

echo "classify-workflow-transitions.test.sh"

# --- fixture ------------------------------------------------------------------
# TWO sessions, because with one a classifier that stops after the first session
# is indistinguishable from a correct one.
#
# Session A is entirely legal AND exercises a back-edge (review -> work), so it
# also pins that the back-edges are honoured rather than merely declared -- a
# classifier that ignored them would report A as a violation.
# Session B takes plan -> ship, the path that skips review. That is the one the
# edge set exists to make visible.
assert_fixture_dir "$TMP_ROOT"
ROOT="$TMP_ROOT/repo"; mkdir -p "$ROOT/.claude"
cp "$SCRIPT_DIR/../.claude/workflow-transitions.json" "$ROOT/.claude/" 2>/dev/null \
  || { echo "  FAIL: cannot stage the declared view into the fixture"; echo "0 passed, 1 failed"; exit 1; }

log="$ROOT/.claude/.skill-invocations.jsonl"
# The producer's timestamp field is `ts`, not `timestamp`. This fixture matched
# an ASSUMPTION until the first live run discarded all 10,260 real records behind
# a clean-looking "undeclared=0". Fixtures are synthesized, but they are
# synthesized to the PRODUCER's shape -- read a real record, do not infer one.
emit() { printf '{"schema":1,"ts":"%s","skill":"soleur:%s","session_id":"%s","hook_event":"PreToolUse"}\n' "$1" "$2" "$3" >> "$log"; }
emit 2026-09-18T10:00:00Z brainstorm sessA
emit 2026-09-18T10:01:00Z plan       sessA
emit 2026-09-18T10:02:00Z work       sessA
emit 2026-09-18T10:03:00Z review     sessA
emit 2026-09-18T10:04:00Z work       sessA   # declared back-edge
emit 2026-09-18T11:00:00Z plan       sessB
emit 2026-09-18T11:01:00Z ship       sessB   # UNDECLARED: skips review

OUT=$(CLASSIFY_REPO_ROOT="$ROOT" bash "$SUT" 2>&1); RC=$?

# --- 1. exit 0 ----------------------------------------------------------------
if [[ "$RC" -eq 0 ]]; then pass "exits 0 on a readable log"; else fail "exit rc=$RC out='$OUT'"; fi

# --- 2. reports the undeclared transition -------------------------------------
if [[ "$OUT" == *"plan -> ship"* ]]; then
  pass "reports the undeclared plan -> ship transition"
else
  fail "did not report plan -> ship — got: $OUT"
fi

# --- 3. attributes it to the right session ------------------------------------
# Without a session_id filter the 'previous skill' is whatever the last call of a
# DIFFERENT session was, which makes cross-session false positives the dominant
# output rather than the exception.
if [[ "$OUT" == *sessB* ]]; then
  pass "attributes the violation to its own session"
else
  fail "violation not attributed to sessB — got: $OUT"
fi

# --- 4. the all-legal session produces nothing --------------------------------
if [[ "$OUT" != *sessA* ]]; then
  pass "the fully-declared session reports no violation"
else
  fail "sessA reported a violation it should not have — got: $OUT"
fi

# --- 5. exactly one violation, not merely at least one ------------------------
n=$(printf '%s\n' "$OUT" | grep -cE '^[[:space:]]*(sessA|sessB)[[:space:]]' || true)
if [[ "$n" -eq 1 ]]; then
  pass "reports EXACTLY one violation across both sessions"
else
  fail "expected exactly 1 violation row, got $n — out: $OUT"
fi

# --- 6. the declared back-edge is not a violation -----------------------------
if [[ "$OUT" != *"review -> work"* ]]; then
  pass "the declared back-edge review -> work is not reported"
else
  fail "back-edge reported as a violation — got: $OUT"
fi

# --- 7. --summary exits 0 and names a count -----------------------------------
SOUT=$(CLASSIFY_REPO_ROOT="$ROOT" bash "$SUT" --summary 2>&1); SRC=$?
if [[ "$SRC" -eq 0 && "$SOUT" == *"undeclared=1 "* ]]; then
  pass "--summary exits 0 and reports the count"
else
  fail "--summary rc=$SRC out='$SOUT'"
fi

# --- 8. an absent log is LOUD, not silently clean -----------------------------
# A missing log and a log of genuinely zero violations produce the same empty
# report, and the silent one reads as an all-clear. Same reasoning as the
# aggregator's SOLEUR_RULE_METRICS_NO_INCIDENTS marker.
EMPTY="$TMP_ROOT/emptyrepo"; mkdir -p "$EMPTY/.claude"
cp "$ROOT/.claude/workflow-transitions.json" "$EMPTY/.claude/"
EOUT=$(CLASSIFY_REPO_ROOT="$EMPTY" bash "$SUT" 2>&1); ERC=$?
if [[ "$ERC" -eq 0 && "$EOUT" == *NO_INVOCATIONS* ]]; then
  pass "absent invocation log emits a loud null-reading marker"
else
  fail "absent log not loud — rc=$ERC out='$EOUT'"
fi

# --- 9. a missing declared view fails loudly ----------------------------------
# Fail-closed: classifying against an empty edge set would report EVERY
# transition as undeclared, which is a confident wrong answer rather than a
# missing one.
NOVIEW="$TMP_ROOT/noview"; mkdir -p "$NOVIEW/.claude"
cp "$log" "$NOVIEW/.claude/"
NOUT=$(CLASSIFY_REPO_ROOT="$NOVIEW" bash "$SUT" 2>&1); NRC=$?
if [[ "$NRC" -ne 0 ]]; then
  pass "a missing declared view fails loudly rather than reporting everything"
else
  fail "missing view returned rc=0 — out: $NOUT"
fi

# --- 10. a log that parses to NOTHING is loud, not a clean zero ---------------
# The defect this script shipped on its own first live run: a wrong field name
# discarded every record and printed "undeclared=0 pairs=0", which is
# indistinguishable from a pass. Records present but unparseable must fail.
BADSHAPE="$TMP_ROOT/badshape"; mkdir -p "$BADSHAPE/.claude"
cp "$ROOT/.claude/workflow-transitions.json" "$BADSHAPE/.claude/"
printf '{"schema":1,"when":"2026-09-18T10:00:00Z","name":"soleur:plan","sid":"x"}\n' \
  > "$BADSHAPE/.claude/.skill-invocations.jsonl"
BOUT=$(CLASSIFY_REPO_ROOT="$BADSHAPE" bash "$SUT" 2>&1); BRC=$?
if [[ "$BRC" -ne 0 && "$BOUT" == *"kept 0"* ]]; then
  pass "a present-but-unparseable log fails loudly instead of reporting zero"
else
  fail "unparseable log did not fail loudly — rc=$BRC out='$BOUT'"
fi

# --- 11. a sub-skill call is NOT a violation ----------------------------------
# plan -> deepen-plan is plan invoking its own enrichment step; ship -> preflight
# is ship invoking its own gate. Neither is a lifecycle transition. Keying only
# on the `from` endpoint made these the DOMINANT output against real data (736
# and 797 occurrences), burying the two genuine plan -> ship violations. The
# non-node record is dropped from the walk and counted as `nonnode`.
SUBSK="$TMP_ROOT/subskill"; mkdir -p "$SUBSK/.claude"
cp "$ROOT/.claude/workflow-transitions.json" "$SUBSK/.claude/"
slog="$SUBSK/.claude/.skill-invocations.jsonl"
printf '{"schema":1,"ts":"2026-09-18T12:00:00Z","skill":"soleur:plan","session_id":"sessC"}\n' > "$slog"
printf '{"schema":1,"ts":"2026-09-18T12:01:00Z","skill":"soleur:deepen-plan","session_id":"sessC"}\n' >> "$slog"
SUOUT=$(CLASSIFY_REPO_ROOT="$SUBSK" bash "$SUT" --summary 2>&1); SURC=$?
if [[ "$SURC" -eq 0 && "$SUOUT" == *"undeclared=0 "* && "$SUOUT" == *"nonnode=1 "* ]]; then
  pass "a sub-skill call is dropped from the walk (nonnode=1), not reported as a violation"
else
  fail "sub-skill misclassified — rc=$SURC out='$SUOUT'"
fi

# --- 12. a sub-skill hop does NOT launder the lifecycle transition around it --
# The escape two review seats found against the pristine script: with raw
# adjacency and a both-endpoints rule, plan -> deepen-plan -> ship produced two
# unclassified pairs and ZERO violations, so the review-skip was invisible on the
# most common real path. Collapsing to node records pairs plan with ship.
LAUN="$TMP_ROOT/launder"; mkdir -p "$LAUN/.claude"
cp "$ROOT/.claude/workflow-transitions.json" "$LAUN/.claude/"
llog="$LAUN/.claude/.skill-invocations.jsonl"
printf '{"schema":1,"ts":"2026-09-18T13:00:00Z","skill":"soleur:plan","session_id":"sessL"}\n' > "$llog"
printf '{"schema":1,"ts":"2026-09-18T13:01:00Z","skill":"soleur:deepen-plan","session_id":"sessL"}\n' >> "$llog"
printf '{"schema":1,"ts":"2026-09-18T13:02:00Z","skill":"soleur:ship","session_id":"sessL"}\n' >> "$llog"
LOUT=$(CLASSIFY_REPO_ROOT="$LAUN" bash "$SUT" 2>&1); LRC=$?
if [[ "$LRC" -eq 0 && "$LOUT" == *"plan -> ship"* ]]; then
  pass "plan -> deepen-plan -> ship still reports plan -> ship (no laundering through a sub-skill)"
else
  fail "sub-skill laundered the violation — rc=$LRC out='$LOUT'"
fi

# --- 13. rotated archives are part of the corpus -------------------------------
# The producer rotates the live log into .skill-invocations-<ts>.jsonl.gz. A
# session split across the boundary -- plan in the archive, ship live -- must
# still pair. Reading only the live file made this pairs=1 undeclared=0 and let
# the corpus (and the followthrough baseline) shrink silently at every rotation.
ARCH="$TMP_ROOT/archive"; mkdir -p "$ARCH/.claude"
cp "$ROOT/.claude/workflow-transitions.json" "$ARCH/.claude/"
printf '{"schema":1,"ts":"2026-09-18T14:00:00Z","skill":"soleur:plan","session_id":"sessA"}\n' \
  | gzip -c > "$ARCH/.claude/.skill-invocations-20260918T140000Z.jsonl.gz"
printf '{"schema":1,"ts":"2026-09-18T14:05:00Z","skill":"soleur:ship","session_id":"sessA"}\n' \
  > "$ARCH/.claude/.skill-invocations.jsonl"
AOUT=$(CLASSIFY_REPO_ROOT="$ARCH" bash "$SUT" --summary 2>&1); ARC=$?
if [[ "$ARC" -eq 0 && "$AOUT" == *"undeclared=1 "* && "$AOUT" == *"read=2 "* ]]; then
  pass "a rotated .jsonl.gz archive is read and pairs across the rotation boundary"
else
  fail "archive not read — rc=$ARC out='$AOUT'"
fi

# --- 14. pairs follow TIMESTAMP order, not file order --------------------------
# MERGED is a cat across roots, and one session_id can write to two roots, so
# arrival order is not chronological. File order here is compound, ship
# (declared); timestamps make it ship, compound (undeclared). Removing the
# sort_by(.t) flips the verdict, which is what pins it.
ORD="$TMP_ROOT/order"; mkdir -p "$ORD/.claude"
cp "$ROOT/.claude/workflow-transitions.json" "$ORD/.claude/"
olog="$ORD/.claude/.skill-invocations.jsonl"
printf '{"schema":1,"ts":"2026-09-18T15:09:00Z","skill":"soleur:compound","session_id":"sessO"}\n' > "$olog"
printf '{"schema":1,"ts":"2026-09-18T15:01:00Z","skill":"soleur:ship","session_id":"sessO"}\n' >> "$olog"
OOUT=$(CLASSIFY_REPO_ROOT="$ORD" bash "$SUT" 2>&1); ORC=$?
if [[ "$ORC" -eq 0 && "$OOUT" == *"ship -> compound"* ]]; then
  pass "out-of-order arrival is sorted by ts before pairing"
else
  fail "file order used instead of ts order — rc=$ORC out='$OOUT'"
fi

# --- 15. an EMPTY session_id is dropped, not pooled ----------------------------
# "" passes a `!= null` test. Two records from different sessions that both
# carry "" would pool into one phantom session and fabricate a pair.
POOL="$TMP_ROOT/pool"; mkdir -p "$POOL/.claude"
cp "$ROOT/.claude/workflow-transitions.json" "$POOL/.claude/"
plog="$POOL/.claude/.skill-invocations.jsonl"
printf '{"schema":1,"ts":"2026-09-18T16:00:00Z","skill":"soleur:plan","session_id":""}\n' > "$plog"
printf '{"schema":1,"ts":"2026-09-18T16:01:00Z","skill":"soleur:ship","session_id":""}\n' >> "$plog"
printf '{"schema":1,"ts":"2026-09-18T16:02:00Z","skill":"soleur:plan","session_id":"real"}\n' >> "$plog"
POUT=$(CLASSIFY_REPO_ROOT="$POOL" bash "$SUT" --summary 2>&1); PRC=$?
if [[ "$PRC" -eq 0 && "$POUT" == *"undeclared=0 "* && "$POUT" == *"dropped=2"* ]]; then
  pass "empty session_id records are dropped (dropped=2), never pooled into a phantom session"
else
  fail "empty session_id pooled or kept — rc=$PRC out='$POUT'"
fi

# --- 16. a PARTIALLY unparseable log warns and continues --------------------
# Case 10 pins the all-unparseable arm. This pins the mixed one: one good record
# plus one bad must exit 0 with dropped=1 and a WARNING, so the warning branch is
# reachable and `if false` on it reds.
MIX="$TMP_ROOT/mixed"; mkdir -p "$MIX/.claude"
cp "$ROOT/.claude/workflow-transitions.json" "$MIX/.claude/"
mlog="$MIX/.claude/.skill-invocations.jsonl"
printf '{"schema":1,"ts":"2026-09-18T17:00:00Z","skill":"soleur:plan","session_id":"m"}\n' > "$mlog"
printf '{"schema":1,"when":"2026-09-18T17:01:00Z","name":"soleur:ship","sid":"m"}\n' >> "$mlog"
MOUT=$(CLASSIFY_REPO_ROOT="$MIX" bash "$SUT" --summary 2>&1); MRC=$?
if [[ "$MRC" -eq 0 && "$MOUT" == *"WARNING: dropped 1 of 2"* && "$MOUT" == *"dropped=1"* ]]; then
  pass "a partially unparseable log warns (dropped=1) and still classifies the rest"
else
  fail "mixed log did not warn — rc=$MRC out='$MOUT'"
fi

# SELFTEST_PASSES is a LITERAL here, not the variable bound after the self-test:
# guard-vacuity-floor.test.sh slices the floor plus its CONTIGUOUS assignments into
# a mutant, and a binding 130 lines up is unbound there (measured: CONSTRUCTION, not
# FIRES). The self-test above asserts passes == 1, so the literal is proven, not chosen.
SELFTEST_PASSES=1
REAL_PASSES=$((passes - SELFTEST_PASSES))
MIN_CASES=16
if [[ "$fails" -eq 0 && "$REAL_PASSES" -lt "$MIN_CASES" ]]; then
  printf 'FATAL: anti-vacuity floor — %s real assertions passed, expected at least %s\n' \
    "$REAL_PASSES" "$MIN_CASES" >&2
  exit 1
fi

echo "$REAL_PASSES passed, $fails failed"
[[ "$fails" -eq 0 ]] || exit 1
