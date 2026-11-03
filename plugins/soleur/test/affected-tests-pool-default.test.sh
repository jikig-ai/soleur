#!/usr/bin/env bash
# affected-tests-pool-default.test.sh — the delegated affected gate's pool-width default (#12013).
#
# PROPERTY. When plugins/soleur/scripts/affected-tests.sh delegates `--affected` to a repo runner
# (scripts/test-all.sh registering --print-selection), it hands the runner a pool width of 4 unless
# the operator already chose one — LOCALLY only, and only when the runner itself mentions the knob.
# `--full`, a CI environment, an explicit SOLEUR_TEST_JOBS (including 1, the serial override) and a
# runner that does not know the knob are left exactly as they were. The default is applied to the
# runner's own environment, so the gate's later steps never see it.
#
# WHY A STUB RUNNER. The property is about what the gate HANDS the runner, not what the runner does
# with it (that is scripts/test-all-parallel-scheduler.test.sh). A stub that registers the capability
# probe's token and writes its own environment to a file makes the hand-over observable without
# running a single real suite.
#
# MUTATIONS (this suite is pointed at a mutant via AFFECTED_GATE_OVERRIDE and must go red):
#   M1  delete the default                    -> C1 red
#   M2  drop the --full guard                 -> C3 red
#   M3  drop the CI guard                     -> C4 red
#   M4  make the default a global export      -> C6 red
#   M5  drop the runner-capability probe      -> C7 red
# The mutants are built from a copy of the gate (it resolves its libs by BASH_SOURCE) and each
# mutation is asserted to have LANDED against the pristine copy before it is scored.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATE="${AFFECTED_GATE_OVERRIDE:-$REPO_ROOT/plugins/soleur/scripts/affected-tests.sh}"
[[ -f "$GATE" ]] || { echo "FATAL: gate not found: $GATE"; exit 2; }

PASSES=0; FAILS=0
pass() { PASSES=$((PASSES + 1)); printf '[pass] %s\n' "$1"; }
fail() { FAILS=$((FAILS + 1)); printf '[FAIL] %s\n' "$1"; }
dump() { sed 's/^/    /' <<<"${1:-}"; }

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
TMP="$(mktemp -d "${TMPDIR:-/var/tmp}/t12013.XXXXXX")" || exit 2
assert_fixture_dir "$TMP"
trap 'rm -rf "$TMP"' EXIT

# Instrument self-test: both verdict helpers must move their counters, or nothing below means anything.
_p0=$PASSES; _f0=$FAILS
{ pass "instrument: pass() moves its counter"; fail "instrument: fail() moves its counter (expected)"; } >/dev/null
if (( PASSES == _p0 + 1 && FAILS == _f0 + 1 )); then
  PASSES=$_p0; FAILS=$_f0
else
  echo "FATAL: verdict helpers do not move their counters"; exit 2
fi

# Build the fixture repository: a stub runner that registers the probe token and records its
# environment and argv. Everything is written inside this function, under the directory it binds.
mk_repo() {  # <dir> <knows-the-knob: 1|0>
  local d="$1" knows="${2:-1}"
  assert_fixture_dir "$d"
  mkdir -p "$d/scripts" || return 1
  if [[ "$knows" == 1 ]]; then
    cat > "$d/scripts/test-all.sh" <<'STUB'
#!/usr/bin/env bash
# Stub runner. The capability probe in affected-tests.sh greps for a --print-selection case label.
case "${1:-}" in
  --print-selection) ;;
esac
printf 'JOBS=%s ARGS=%s\n' "${SOLEUR_TEST_JOBS-<unset>}" "$*" > "${STUB_OUT:?STUB_OUT is not set}"
exit "${STUB_RC:-0}"
STUB
  else
    # Same stub, but the file never spells the knob out (the name is assembled at run time), as a
    # customer runner with no pool would.
    cat > "$d/scripts/test-all.sh" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --print-selection) ;;
esac
n="SOLEUR_TEST_"; n="${n}JOBS"
printf 'JOBS=%s ARGS=%s\n' "${!n-<unset>}" "$*" > "${STUB_OUT:?STUB_OUT is not set}"
exit "${STUB_RC:-0}"
STUB
  fi
  chmod +x "$d/scripts/test-all.sh" || return 1
  git -C "$d" init -q -b main || return 1
  git -C "$d" -c user.email=t@example.invalid -c user.name=t add -A || return 1
  git -C "$d" -c user.email=t@example.invalid -c user.name=t commit -q -m fixture || return 1
}
REPO="$TMP/repo"
mk_repo "$REPO" 1 || { echo "FATAL: fixture repo build failed"; exit 2; }
REPO2="$TMP/repo2"
mk_repo "$REPO2" 0 || { echo "FATAL: second fixture repo build failed"; exit 2; }

# run_gate <rc-of-stub> <env assignments...> -- <gate args...>   (GATE_REPO selects the fixture repo)
# Sets: GATE_RC, GATE_OUT, READING (the stub's "JOBS=… ARGS=…" line, or "<stub not run>").
run_gate() {
  local stub_rc="$1"; shift
  local -a envs=()
  while (( $# > 0 )) && [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  local out="$TMP/stub.out"; rm -f "$out"
  GATE_RC=0
  GATE_OUT="$(cd "${GATE_REPO:-$REPO}" && env -u CI -u SOLEUR_TEST_JOBS -u SOLEUR_SUBAGENT STUB_OUT="$out" STUB_RC="$stub_rc" \
              "${envs[@]}" timeout 120 bash "$GATE" "$@" 2>&1)" || GATE_RC=$?
  READING="$(cat "$out" 2>/dev/null || echo '<stub not run>')"
}

echo "=== affected-tests pool-default ==="

# C1 — the default: a local --affected run hands the runner width 4.
run_gate 0 --
if [[ "$READING" == "JOBS=4 ARGS=--affected" && "$GATE_RC" == 0 ]]; then
  pass "C1 — a local affected run hands the runner SOLEUR_TEST_JOBS=4 and --affected"
else
  fail "C1 — expected 'JOBS=4 ARGS=--affected' rc=0, got '$READING' rc=$GATE_RC"; dump "$GATE_OUT"
fi

# C2 — an operator's choice wins, including the serial override.
run_gate 0 SOLEUR_TEST_JOBS=1 --
[[ "$READING" == "JOBS=1 ARGS=--affected" ]] && pass "C2a — SOLEUR_TEST_JOBS=1 (serial override) is passed through" \
  || { fail "C2a — got '$READING'"; dump "$GATE_OUT"; }
run_gate 0 SOLEUR_TEST_JOBS=6 --
[[ "$READING" == "JOBS=6 ARGS=--affected" ]] && pass "C2b — an explicit width is passed through unchanged" \
  || { fail "C2b — got '$READING'"; dump "$GATE_OUT"; }
run_gate 0 SOLEUR_TEST_JOBS= --
[[ "$READING" == "JOBS=4 ARGS=--affected" ]] && pass "C2c — a set-but-empty value counts as unset (width 4)" \
  || { fail "C2c — got '$READING'"; dump "$GATE_OUT"; }

# C3 — --full is never given a pool default.
run_gate 0 -- --full
if [[ "$READING" == "JOBS=<unset> ARGS=--full" ]]; then
  pass "C3 — --full runs with no injected width"
else
  fail "C3 — expected 'JOBS=<unset> ARGS=--full', got '$READING'"; dump "$GATE_OUT"
fi

# C4 — a CI environment never gets the local default (the runner would only print a serial-fallback line).
run_gate 0 CI=1 --
if [[ "$READING" == "JOBS=<unset> ARGS=--affected" ]]; then
  pass "C4 — CI set: no injected width"
else
  fail "C4 — expected 'JOBS=<unset> ARGS=--affected', got '$READING'"; dump "$GATE_OUT"
fi

# C5 — the exit-code map is unchanged under the default width: 0 -> 0, 1 -> 1, 3 -> 1, 2|4 -> 4.
for pair in "0:0" "1:1" "3:1" "2:4" "4:4"; do
  want_in="${pair%%:*}"; want_out="${pair##*:}"
  run_gate "$want_in" --
  if [[ "$GATE_RC" == "$want_out" && "$READING" == "JOBS=4 ARGS=--affected" ]]; then
    pass "C5 — runner rc $want_in maps to gate rc $want_out with the default width in place"
  else
    fail "C5 — runner rc $want_in: gate rc $GATE_RC (want $want_out), reading '$READING'"; dump "$GATE_OUT"
  fi
done

# C6 — the default is scoped to the runner call: of the gate's non-comment lines, exactly two mention the
# variable (the guard and the prefixed runner call), and the second has the prefix-assignment form. An
# export, a `declare -gx`, or a third mention anywhere breaks this, whatever it is spelled as.
mentions="$(sed -e 's/^[[:space:]]*#.*$//' "$GATE" | grep -n 'SOLEUR_TEST_JOBS' || true)"
n_ment="$(printf '%s\n' "$mentions" | grep -c . || true)"
scoped_re='^[0-9]+:[[:space:]]*SOLEUR_TEST_JOBS="\$\{SOLEUR_TEST_JOBS:-4\}" affected_bound bash "\$RUNNER" "\$_flag" \|\| rc=\$\?$'
n_scoped="$(printf '%s\n' "$mentions" | grep -cE "$scoped_re" || true)"
if [[ "$n_ment" == 2 && "$n_scoped" == 1 ]]; then
  pass "C6 — the variable appears on exactly two code lines and only as a call prefix (never exported)"
else
  fail "C6 — $n_ment code lines mention SOLEUR_TEST_JOBS, $n_scoped in the scoped-prefix form (want 2 and 1)"; dump "$mentions"
fi

# C7 — a runner that never mentions the knob is not handed one (customer repos with their own runner).
GATE_REPO="$REPO2" run_gate 0 --
if [[ "$READING" == "JOBS=<unset> ARGS=--affected" ]]; then
  pass "C7 — a runner that does not know SOLEUR_TEST_JOBS gets no injected width"
else
  fail "C7 — expected 'JOBS=<unset> ARGS=--affected', got '$READING'"; dump "$GATE_OUT"
fi

# --- mutation rows: build each mutant from a copy of the gate and require RED ------------------
if [[ -z "${AFFECTED_GATE_OVERRIDE:-}" ]]; then
  MUT="$TMP/mut"
  mkdir -p "$MUT" || { echo "FATAL: cannot create mutation dir"; exit 2; }
  src_dir="$(dirname "$GATE")"
  mutate() {  # <name> <python expression transforming s>
    local name="$1" expr="$2" dir="$MUT/$1"
    assert_fixture_dir "$dir"
    mkdir -p "$dir/lib" || return 1
    cp "$GATE" "$dir/affected-tests.sh" || return 1
    cp -R "$src_dir/lib/affected-tests" "$dir/lib/" || return 1
    python3 -I - "$dir/affected-tests.sh" "$expr" <<'PY' || return 1
import sys
p, expr = sys.argv[1:3]
s = open(p).read()
orig = s
env = {"s": s}
exec("s = " + expr, {}, env)
s = env["s"]
if s == orig:
    sys.exit(7)  # the mutation did not land
open(p, "w").write(s)
PY
  }
  score() {  # <row> <name> <expected-failing-label>
    local row="$1" name="$2"
    local out rc=0
    out="$(AFFECTED_GATE_OVERRIDE="$MUT/$name/affected-tests.sh" bash "${BASH_SOURCE[0]}" 2>&1)" || rc=$?
    if (( rc != 0 )) && grep -q "^\[FAIL\] $3" <<<"$out" && ! grep -q '<stub not run>' <<<"$out"; then
      pass "$row — mutant '$name' goes red on $3"
    else
      fail "$row — mutant '$name' survived or failed elsewhere (rc=$rc)"; dump "$(grep -E '^\[(FAIL|pass)\]' <<<"$out" | head -8)"
    fi
  }
  # The expressions anchor on the one statement the production code carries.
  row() {  # <row> <expected-failing-label> <python expression>
    if mutate "$1" "$3"; then score "$1" "$1" "$2"; else fail "$1 — the mutation did not land (the expression no longer matches the gate)"; fi
  }
  row M1 C1 's.replace("SOLEUR_TEST_JOBS=\"${SOLEUR_TEST_JOBS:-4}\" ", "")'
  row M2 C3 's.replace("(( ! ARG_FULL )) && ", "")'
  row M3 C4 's.replace(" && [[ -z \"${CI:-}\" ]]", "")'
  row M4 C6 's.replace("SOLEUR_TEST_JOBS=\"${SOLEUR_TEST_JOBS:-4}\" affected_bound", "export SOLEUR_TEST_JOBS=\"${SOLEUR_TEST_JOBS:-4}\"; affected_bound")'
  row M5 C7 's.replace(" && grep -q SOLEUR_TEST_JOBS \"$RUNNER\"", "")'
fi

# Anti-vacuity floor, reported without the helpers it backstops.
# 13 contract assertions + 5 mutation rows; a run against a mutant executes only the 13, so it always ends
# at this floor. That is expected: the mutation rows score on the named failing label, not on the exit code.
# TOTAL and FLOOR sit directly above the test so the vacuity meta-guard's mutant carries both bindings.
TOTAL=$((PASSES + FAILS))
FLOOR=18
if (( TOTAL < FLOOR )); then
  printf '[FATAL] only %d assertions ran (floor %d) — the suite is not exercising what it claims\n' "$TOTAL" "$FLOOR"
  exit 1
fi
echo ""
echo "=== affected-tests-pool-default: $PASSES passed, $FAILS failed ==="
(( FAILS == 0 )) || exit 1
exit 0
