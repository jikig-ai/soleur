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

# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh (that file also defines assert_eq/PASS/FAIL
# counters this suite owns itself, so it is copied rather than sourced).
# plugins/soleur/test/fixture-dir-operand-assert.test.sh compares every copy in the
# tree against that one with comments stripped — edit there, then re-sync here.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
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
# A truncated line (the shape a crash-mid-write or a partial archive leaves)
# must be DROPPED, not abort the reading: `[inputs]` on parsed JSON aborted at
# the first bad byte with rc 2 and zero rows (review advisor consult).
printf '{"schema":1,"ts":"2026-09-18T17:02:00Z","ski' >> "$mlog"
MOUT=$(CLASSIFY_REPO_ROOT="$MIX" bash "$SUT" --summary 2>&1); MRC=$?
if [[ "$MRC" -eq 0 && "$MOUT" == *"WARNING: dropped 2 of 3"* && "$MOUT" == *"dropped=2"* ]]; then
  pass "wrong-field AND malformed lines are dropped (dropped=2) and the rest is still classified"
else
  fail "mixed log did not warn — rc=$MRC out='$MOUT'"
fi

# --- 17-28. brainstorm sub-step collapse (#8325 §2) ---------------------------
# `brainstorm` invokes `compound` as a designed sub-step and then hands off to
# `plan`, so the log shows `brainstorm compound plan` for the designed handoff
# (127 of the live corpus's undeclared rows were `brainstorm -> compound` and
# 111 its tail `compound -> plan`). The view's `sub_steps` map names it; the
# classifier drops a record whose skill is a sub-step of the PREVIOUS KEPT node
# before pairing and reports the count as `substep=`. It is NOT an edge:
# `review -> compound -> plan` (a ship skip) must still be reported.
#
# Per-root emitter: the exemplar `emit` above is bound to the first root's $log,
# and case 25 needs two sessions in one root with A earlier than B.
emit_to() {
  assert_fixture_dir "$1"
  printf '{"schema":1,"ts":"%s","skill":"soleur:%s","session_id":"%s","hook_event":"PreToolUse"}\n' "$2" "$3" "$4" >> "$1/.claude/.skill-invocations.jsonl"
}
new_root() {
  local r="$TMP_ROOT/$1"
  assert_fixture_dir "$r"
  mkdir -p "$r/.claude"; cp "$ROOT/.claude/workflow-transitions.json" "$r/.claude/"; printf '%s' "$r"
}

# --- 17. the designed handoff pairs as brainstorm -> plan --------------------
R17=$(new_root sub17)
emit_to "$R17" 2026-09-18T18:00:00Z brainstorm s17
emit_to "$R17" 2026-09-18T18:01:00Z compound   s17
emit_to "$R17" 2026-09-18T18:02:00Z plan       s17
O17=$(CLASSIFY_REPO_ROOT="$R17" bash "$SUT" --summary 2>&1); C17=$?
R17ROWS=$(CLASSIFY_REPO_ROOT="$R17" bash "$SUT" 2>/dev/null)
if [[ "$C17" -eq 0 && "$O17" == *"undeclared=0 "* && "$O17" == *"pairs=1 "* && "$O17" == *"substep=1 "* && -z "$R17ROWS" ]]; then
  pass "brainstorm compound plan pairs as brainstorm -> plan (pairs=1 undeclared=0 substep=1), no row"
else
  fail "designed handoff not collapsed — rc=$C17 out='$O17' rows='$R17ROWS'"
fi

# --- 18. the collapse must not launder the edge it exposes -------------------
R18=$(new_root sub18)
emit_to "$R18" 2026-09-18T18:10:00Z brainstorm s18
emit_to "$R18" 2026-09-18T18:11:00Z compound   s18
emit_to "$R18" 2026-09-18T18:12:00Z review     s18
O18=$(CLASSIFY_REPO_ROOT="$R18" bash "$SUT" 2>&1); C18=$?
S18=$(CLASSIFY_REPO_ROOT="$R18" bash "$SUT" --summary 2>/dev/null)
if [[ "$C18" -eq 0 && "$O18" == *"brainstorm -> review"* && "$S18" == *"substep=1 "* ]]; then
  pass "brainstorm compound review still reports brainstorm -> review with substep=1"
else
  fail "collapse laundered brainstorm -> review — rc=$C18 out='$O18' summary='$S18'"
fi

# --- 19. a trailing sub-step forms no pair -----------------------------------
R19=$(new_root sub19)
emit_to "$R19" 2026-09-18T18:20:00Z brainstorm s19
emit_to "$R19" 2026-09-18T18:21:00Z compound   s19
O19=$(CLASSIFY_REPO_ROOT="$R19" bash "$SUT" --summary 2>&1); C19=$?
if [[ "$C19" -eq 0 && "$O19" == *"pairs=0 "* && "$O19" == *"substep=1 "* && "$O19" == *"formed ZERO lifecycle pairs"* ]]; then
  pass "a trailing brainstorm compound forms no pair (pairs=0 substep=1) and warns"
else
  fail "trailing sub-step mis-paired — rc=$C19 out='$O19'"
fi

# --- 20. the sub-step is keyed on brainstorm, not on every predecessor -------
R20=$(new_root sub20)
emit_to "$R20" 2026-09-18T18:30:00Z review   s20
emit_to "$R20" 2026-09-18T18:31:00Z compound s20
emit_to "$R20" 2026-09-18T18:32:00Z plan     s20
O20=$(CLASSIFY_REPO_ROOT="$R20" bash "$SUT" 2>&1); C20=$?
S20=$(CLASSIFY_REPO_ROOT="$R20" bash "$SUT" --summary 2>/dev/null)
if [[ "$C20" -eq 0 && "$O20" == *"compound -> plan"* && "$S20" == *"substep=0 "* ]]; then
  pass "review compound plan keeps compound -> plan as a row (substep=0): the ship skip is not laundered"
else
  fail "sub-step applied to a non-brainstorm predecessor — rc=$C20 out='$O20' summary='$S20'"
fi

# --- 21. the lookup keys on the previous KEPT node ----------------------------
# The second compound's RAW predecessor is compound; keyed on the kept node it
# is still brainstorm, so both drop.
R21=$(new_root sub21)
emit_to "$R21" 2026-09-18T18:40:00Z brainstorm s21
emit_to "$R21" 2026-09-18T18:41:00Z compound   s21
emit_to "$R21" 2026-09-18T18:42:00Z compound   s21
emit_to "$R21" 2026-09-18T18:43:00Z plan       s21
O21=$(CLASSIFY_REPO_ROOT="$R21" bash "$SUT" --summary 2>&1); C21=$?
if [[ "$C21" -eq 0 && "$O21" == *"substep=2 "* && "$O21" == *"pairs=1 "* && "$O21" == *"undeclared=0 "* ]]; then
  pass "brainstorm compound compound plan drops both (substep=2 pairs=1 undeclared=0): keyed on the previous KEPT node"
else
  fail "second compound not dropped — rc=$C21 out='$O21'"
fi

# --- 22. a self-loop the collapse exposes is reported, not hidden -------------
R22=$(new_root sub22)
emit_to "$R22" 2026-09-18T18:50:00Z brainstorm s22
emit_to "$R22" 2026-09-18T18:51:00Z compound   s22
emit_to "$R22" 2026-09-18T18:52:00Z brainstorm s22
emit_to "$R22" 2026-09-18T18:53:00Z compound   s22
emit_to "$R22" 2026-09-18T18:54:00Z plan       s22
O22=$(CLASSIFY_REPO_ROOT="$R22" bash "$SUT" 2>&1); C22=$?
S22=$(CLASSIFY_REPO_ROOT="$R22" bash "$SUT" --summary 2>/dev/null)
if [[ "$C22" -eq 0 && "$O22" == *"brainstorm -> brainstorm"* && "$S22" == *"substep=2 "* && "$S22" == *"pairs=2 "* && "$S22" == *"undeclared=1 "* ]]; then
  pass "brainstorm compound brainstorm compound plan → substep=2 pairs=2 undeclared=1 (brainstorm -> brainstorm exposed)"
else
  fail "self-loop hidden or miscounted — rc=$C22 out='$O22' summary='$S22'"
fi

# --- 23. non-node removal runs BEFORE the sub-step drop -----------------------
# compound's RAW predecessor is one-shot (a non-node); after the node filter its
# predecessor is brainstorm, so it drops.
R23=$(new_root sub23)
emit_to "$R23" 2026-09-18T19:00:00Z brainstorm s23
emit_to "$R23" 2026-09-18T19:01:00Z one-shot   s23
emit_to "$R23" 2026-09-18T19:02:00Z compound   s23
emit_to "$R23" 2026-09-18T19:03:00Z plan       s23
O23=$(CLASSIFY_REPO_ROOT="$R23" bash "$SUT" --summary 2>&1); C23=$?
if [[ "$C23" -eq 0 && "$O23" == *"nonnode=1 "* && "$O23" == *"substep=1 "* && "$O23" == *"pairs=1 "* && "$O23" == *"undeclared=0 "* ]]; then
  pass "brainstorm one-shot compound plan → nonnode=1 substep=1 pairs=1 undeclared=0 (node filter first)"
else
  fail "filter order wrong — rc=$C23 out='$O23'"
fi

# --- 24. a session whose FIRST record is a sub-step skill -----------------------
# `.kept[-1]` on an empty array is null and `$SUB[null]` throws, which `// []`
# does not rescue; the reduce needs an explicit empty-kept branch.
R24=$(new_root sub24)
emit_to "$R24" 2026-09-18T19:10:00Z compound s24
emit_to "$R24" 2026-09-18T19:11:00Z plan     s24
O24=$(CLASSIFY_REPO_ROOT="$R24" bash "$SUT" --summary 2>&1); C24=$?
if [[ "$C24" -eq 0 && "$O24" == *"substep=0 "* && "$O24" == *"pairs=1 "* && "$O24" == *"undeclared=1 "* && "$O24" != *"Cannot index"* ]]; then
  pass "compound plan as a session's first two records → substep=0 pairs=1 undeclared=1, no jq error"
else
  fail "first-record sub-step lookup broke — rc=$C24 out='$O24'"
fi

# --- 25. the drop is scoped to the session, not the merged stream -------------
# Session A's brainstorm precedes session B's compound in time; an ungrouped
# walk would drop B's compound.
R25=$(new_root sub25)
emit_to "$R25" 2026-09-18T19:20:00Z brainstorm sA25
emit_to "$R25" 2026-09-18T19:21:00Z compound   sB25
emit_to "$R25" 2026-09-18T19:22:00Z plan       sB25
O25=$(CLASSIFY_REPO_ROOT="$R25" bash "$SUT" --summary 2>&1); C25=$?
if [[ "$C25" -eq 0 && "$O25" == *"substep=0 "* && "$O25" == *"pairs=1 "* && "$O25" == *"undeclared=1 "* ]]; then
  pass "session A brainstorm then session B compound plan → substep=0 pairs=1 undeclared=1 (grouped by session)"
else
  fail "cross-session drop — rc=$C25 out='$O25'"
fi

# --- 26. a view without an OBJECT sub_steps fails closed -------------------------
# `// {}` or a bare has() would silently reproduce the pre-collapse numbers on a
# stale mirror; `null` and `[]` both pass a presence check.
V26_OK=1
for shape in missing null list; do
  R26=$(new_root "sub26-$shape")
  assert_fixture_dir "$R26"
  case "$shape" in
    missing) jq 'del(.sub_steps)' "$ROOT/.claude/workflow-transitions.json" > "$R26/.claude/workflow-transitions.json" ;;
    null)    jq '.sub_steps = null' "$ROOT/.claude/workflow-transitions.json" > "$R26/.claude/workflow-transitions.json" ;;
    list)    jq '.sub_steps = []' "$ROOT/.claude/workflow-transitions.json" > "$R26/.claude/workflow-transitions.json" ;;
  esac
  emit_to "$R26" 2026-09-18T19:30:00Z brainstorm s26
  emit_to "$R26" 2026-09-18T19:31:00Z plan       s26
  O26=$(CLASSIFY_REPO_ROOT="$R26" bash "$SUT" --summary 2>&1); C26=$?
  if [[ "$C26" -ne 2 || "$O26" != *FATAL* || "$O26" != *sub_steps* ]]; then
    V26_OK=0; echo "    sub_steps=$shape: rc=$C26 out='$O26'"
  fi
done
if [[ "$V26_OK" -eq 1 ]]; then
  pass "a view with sub_steps missing, null or [] exits 2 with a FATAL naming sub_steps"
else
  fail "stale mirror not fail-closed"
fi

# --- 27. the null-reading summary line carries substep=0 -----------------------
# Case 8 runs default mode on an absent log and never prints the line; the
# key set is the contract, so the null line is asserted as ONE string.
N27=$(CLASSIFY_REPO_ROOT="$EMPTY" bash "$SUT" --summary 2>/dev/null); C27=$?
if [[ "$C27" -eq 0 && "$N27" == "undeclared=0 sessions=0 pairs=0 nonnode=0 substep=0 read=0 dropped=0 null_reading=1" ]]; then
  pass "the null-reading --summary line is exactly 'undeclared=0 sessions=0 pairs=0 nonnode=0 substep=0 read=0 dropped=0 null_reading=1'"
else
  fail "null-reading line drifted — rc=$C27 out='$N27'"
fi

# --- 28. postmerge -> work is a declared recovery edge (#8325 §1) ---------------
R28=$(new_root sub28)
emit_to "$R28" 2026-09-18T19:40:00Z postmerge s28
emit_to "$R28" 2026-09-18T19:41:00Z work      s28
emit_to "$R28" 2026-09-18T19:42:00Z review    s28
emit_to "$R28" 2026-09-18T19:43:00Z compound  s28
emit_to "$R28" 2026-09-18T19:44:00Z ship      s28
emit_to "$R28" 2026-09-18T19:45:00Z postmerge s28
O28=$(CLASSIFY_REPO_ROOT="$R28" bash "$SUT" --summary 2>&1); C28=$?
if [[ "$C28" -eq 0 && "$O28" == *"undeclared=0 "* && "$O28" == *"pairs=5 "* ]]; then
  pass "postmerge work review compound ship postmerge is fully declared (undeclared=0)"
else
  fail "postmerge -> work reported — rc=$C28 out='$O28'"
fi

# SELFTEST_PASSES is a LITERAL here, not the variable bound after the self-test:
# guard-vacuity-floor.test.sh slices the floor plus its CONTIGUOUS assignments into
# a mutant, and a binding 130 lines up is unbound there (measured: CONSTRUCTION, not
# FIRES). The self-test above asserts passes == 1, so the literal is proven, not chosen.
SELFTEST_PASSES=1
REAL_PASSES=$((passes - SELFTEST_PASSES))
MIN_CASES=28
if [[ "$fails" -eq 0 && "$REAL_PASSES" -lt "$MIN_CASES" ]]; then
  printf 'FATAL: anti-vacuity floor — %s real assertions passed, expected at least %s\n' \
    "$REAL_PASSES" "$MIN_CASES" >&2
  exit 1
fi

echo "$REAL_PASSES passed, $fails failed"
[[ "$fails" -eq 0 ]] || exit 1
