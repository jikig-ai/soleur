#!/usr/bin/env bash
# test-all-parallel-contention.test.sh — shared-resource serialization guard (#8231).
#
# The acceptance criterion this suite proves: "shared-resource suites remain
# serialized across worktrees." The guarantee has two halves, and both are
# asserted here:
#
#   C1  CROSS-WORKTREE: a run only goes wide WHILE HOLDING the repo-global
#       advisory lock — the same lock that serializes whole runs across
#       worktrees (ADR-133). The assertion is mechanical and anchored: mode
#       resolution reads _SESSION_LOCK_ACQUIRED, set only by the real acquire
#       path, and the resolve call sits AFTER `tc_acquire "test-all"` in the
#       file. A run whose lock is not taken (skipped, contended, unavailable)
#       never launches a single worker — the serial-fallback banner proves it.
#       Two worktrees therefore still serialize at run granularity; the pool
#       cannot leak concurrency past the lock.
#   C2  INTRA-RUN: suites carrying the same resource token never overlap in
#       time — proven against a REAL shared resource (a flock'd file), not a
#       timing proxy, so the assertion fails if the mechanism regresses even
#       when the schedule would coincidentally serialize.
#   C3  The `*` drain barrier holds under genuine pool pressure — a barrier
#       fixture queued mid-walk still runs alone.
#
# Sandbox convention identical to test-all-parallel-scheduler.test.sh.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
export REPO_ROOT

PASSES=0; FAILURES=0
pass() { PASSES=$((PASSES + 1)); printf '[pass] %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf '[FAIL] %s\n' "$1"; }
dump() { sed 's/^/    /' <<<"${1:-}"; }

TARGET="$REPO_ROOT/scripts/test-all.sh"
[[ -f "$TARGET" ]] || { echo "FATAL: $TARGET not found"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/t8231c.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FIXTURES="$TMP/fixtures"
mkdir -p "$FIXTURES"

# C2 fixture: takes an exclusive flock on a shared file, records S/E inside the
# critical section. If the lane mechanism failed, two holders' S..E windows
# would interleave — which is exactly what the flock log detects.
SHARED_LOCK="$FIXTURES/shared.lock"
mk_flock_fixture() {
  cat > "$FIXTURES/$1.sh" <<EOF
#!/usr/bin/env bash
exec 9>>"$SHARED_LOCK"
flock -x 9
echo "S $1 \$(date +%s%N)" >> "$FIXTURES/flock-timeline.log"
sleep 0.4
echo "E $1 \$(date +%s%N)" >> "$FIXTURES/flock-timeline.log"
flock -u 9
echo "done-$1"
exit 0
EOF
  chmod +x "$FIXTURES/$1.sh"
}
# Same token as each other -> mutually exclusive (correct by mechanism).
mk_flock_fixture resA
mk_flock_fixture resB
# A `*` barrier fixture queued between independent ones.
cat > "$FIXTURES/bar.sh" <<'EOF'
#!/usr/bin/env bash
echo "S bar $(date +%s%N)" >> "TIMELINE"
sleep 0.4
echo "E bar $(date +%s%N)" >> "TIMELINE"
exit 0
EOF
sed -i "s|TIMELINE|$FIXTURES/bar-timeline.log|" "$FIXTURES/bar.sh"
chmod +x "$FIXTURES/bar.sh"
cat > "$FIXTURES/ind.sh" <<'EOF'
#!/usr/bin/env bash
sleep 0.4
echo ok
exit 0
EOF
chmod +x "$FIXTURES/ind.sh"

build_sandbox() {  # <out> <python-body-file>
  local out="$1" bodyfile="$2"
  cp "$TARGET" "$out" || return 1
  mkdir -p "$(dirname "$out")/lib" || return 1
  cp "$REPO_ROOT/scripts/lib/repo-write-boundary.sh" "$(dirname "$out")/lib/" || return 1
  for _lib in test-relevance-paths.sh test-suite-lanes.sh; do
    cp "$REPO_ROOT/scripts/lib/$_lib" "$(dirname "$out")/lib/" || return 1
  done
  python3 - "$out" "$bodyfile" <<'PY'
import sys, re
path, bodyfile = sys.argv[1:3]
s = open(path).read()
a = 'tc_acquire "test-all"'
b = 'tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"'
assert s.count(a) == 1, "start anchor not unique"
assert s.count(b) == 1, "end anchor not unique"
i = s.index(a) + len(a); j = s.index(b)
body = open(bodyfile).read()
# The leading \n is load-bearing: the tc_acquire anchor is neutered with a
# trailing `# sandbox: lock neutered` COMMENT, which would swallow the
# body's first line without a line break between them.
s = s[:i] + "\n" + body + s[j:]
s = s.replace(a, 'true "test-all"  # sandbox: lock neutered', 1)
s = re.sub(r'^tc_preamble\b.*$', 'true  # sandbox: preamble neutered', s, count=1, flags=re.M)
open(path, 'w').write(s)
PY
}

# --- C1a: the lock precedes the pool — anchored file-order assertion ---------
acq_line=$(grep -n '^tc_acquire "test-all"$' "$TARGET" | cut -d: -f1)
res_line=$(grep -n '^_pj_resolve_run_mode$' "$TARGET" | cut -d: -f1)
drain_line=$(grep -n '^_pj_drain$' "$TARGET" | cut -d: -f1)
epi_line=$(grep -n '^tc_epilogue ' "$TARGET" | cut -d: -f1)
if [[ -n "$acq_line" && -n "$res_line" && -n "$drain_line" && -n "$epi_line" \
      && "$acq_line" -lt "$res_line" && "$res_line" -lt "$drain_line" && "$drain_line" -lt "$epi_line" ]]; then
  pass "C1 — ordering: tc_acquire < resolve < drain < epilogue (the lock precedes the pool, the drain precedes the boundary)"
else
  fail "C1 — ordering broken: acquire=$acq_line resolve=$res_line drain=$drain_line epilogue=$epi_line"
fi
# The lock verdict the scheduler reads is the one the real acquire path sets.
if grep -q '_SESSION_LOCK_ACQUIRED\[test-all\]' "$TARGET"; then
  pass "C1 — mode resolution reads the measured lock verdict, not tc_acquire's rc"
else
  fail "C1 — resolve does not consult _SESSION_LOCK_ACQUIRED"
fi

# --- C1b: lock-not-held => never goes wide ------------------------------------
cat > "$TMP/body-nolock.sh" <<EOF
_pj_lock_held=0
_pj_resolve_run_mode
run_suite "indA" bash "$FIXTURES/ind.sh"
run_suite "indB" bash "$FIXTURES/ind.sh"
_pj_drain
EOF
sb="$TMP/runner-nolock.sh"
build_sandbox "$sb" "$TMP/body-nolock.sh" >/dev/null || { fail "nolock sandbox build failed"; }
NL_OUT=$(env -u CI SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= TEST_TIMING_LOG=/dev/null \
        TEST_GROUP=all SOLEUR_TEST_JOBS=4 timeout 60 bash "$sb" 2>&1) || true
if ! grep -q '\[parallel\] mode engaged' <<<"$NL_OUT" && grep -q 'serial fallback — reason=lock-not-held' <<<"$NL_OUT"; then
  pass "C1 — a run without the advisory lock never launches a worker (cross-worktree serialization preserved)"
else
  fail "C1 — lock-not-held run went wide"; dump "$NL_OUT"
fi

# --- C2: same-token fixtures never overlap on a REAL shared resource ---------
cat > "$TMP/body-res.sh" <<EOF
declare -gA _SESSION_LOCK_ACQUIRED 2>/dev/null || true
_SESSION_LOCK_ACQUIRED[test-all]=1
_pj_lock_held=1
_pj_resolve_run_mode
lane_declare "resA" "artifact:shared-flock" "fixture"
lane_declare "resB" "artifact:shared-flock" "fixture"
run_suite "resA" bash "$FIXTURES/resA.sh"
run_suite "resB" bash "$FIXTURES/resB.sh"
_pj_drain
EOF
sb="$TMP/runner-res.sh"
build_sandbox "$sb" "$TMP/body-res.sh" >/dev/null || { fail "res sandbox build failed"; }
rm -f "$FIXTURES/flock-timeline.log"
RES_OUT=$(env -u CI SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= TEST_TIMING_LOG=/dev/null \
         TEST_GROUP=all SOLEUR_TEST_JOBS=4 timeout 60 bash "$sb" 2>&1) || true
if python3 - "$FIXTURES/flock-timeline.log" <<'PY'
import sys
wins = {}
try:
    for line in open(sys.argv[1]):
        k, label, ns = line.split()
        wins.setdefault(label, {})[k] = int(ns)
except FileNotFoundError:
    sys.exit(2)
a, b = wins['resA'], wins['resB']
# resB's flock critical section may not begin inside resA's.
overlap = a['S'] < b['E'] and b['S'] < a['E']
sys.exit(1 if overlap else 0)
PY
then
  pass "C2 — token-intersecting fixtures serialized on a real shared flock"
else
  fail "C2 — shared-resource fixtures overlapped"; dump "$(cat "$FIXTURES/flock-timeline.log" 2>/dev/null)"
fi

# --- C3: the drain barrier holds mid-walk -------------------------------------
cat > "$TMP/body-bar.sh" <<EOF
declare -gA _SESSION_LOCK_ACQUIRED 2>/dev/null || true
_SESSION_LOCK_ACQUIRED[test-all]=1
_pj_lock_held=1
_pj_resolve_run_mode
lane_declare "bar" "*" "fixture barrier"
run_suite "indA" bash "$FIXTURES/ind.sh"
run_suite "bar"  bash "$FIXTURES/bar.sh"
run_suite "indB" bash "$FIXTURES/ind.sh"
run_suite "indC" bash "$FIXTURES/ind.sh"
_pj_drain
EOF
sb="$TMP/runner-bar.sh"
build_sandbox "$sb" "$TMP/body-bar.sh" >/dev/null || { fail "bar sandbox build failed"; }
BAR_OUT=$(env -u CI SOLEUR_SUBAGENT= SOLEUR_ALLOW_FULL_GATE= TEST_TIMING_LOG=/dev/null \
         TEST_GROUP=all SOLEUR_TEST_JOBS=4 timeout 60 bash "$sb" 2>&1) || true
# bar's [run] window must not overlap any other [run] window.
bar_start=$(grep -oE 'pid=[0-9]+' <<<"$(grep '\[run\] bar started' <<<"$BAR_OUT" || true)" || true)
if python3 - "$BAR_OUT" <<'PY'
import sys, re
events = []
for line in sys.argv[1].splitlines():
    m = re.match(r'\[run\] (\S+) (started|done)', line)
    if m:
        events.append((m.group(1), m.group(2)))
live = set()
bar_windows_alone = True
bar_live = False
live_at_bar_start = set()
live_at_bar_end = set()
for label, ev in events:
    if ev == 'started':
        if bar_live:
            live_at_bar_start.add(label)   # joined while bar live -> violation
        if label == 'bar':
            bar_live = True
            live_at_bar_start |= live
        live.add(label)
    else:
        if label == 'bar':
            live.discard('bar')
            bar_live = False
            live_at_bar_end |= (live - {'bar'})
        else:
            if bar_live:
                live_at_bar_end.add(label)
            live.discard(label)
sys.exit(1 if (live_at_bar_start or live_at_bar_end) else 0)
PY
then
  pass "C3 — the * barrier ran with a drained pool under genuine width-4 pressure"
else
  fail "C3 — the * barrier overlapped a live worker"; dump "$BAR_OUT"
fi

echo ""
echo "=== test-all-parallel-contention: $PASSES passed, $FAILURES failed ==="
(( FAILURES == 0 )) || exit 1
exit 0
