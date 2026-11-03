#!/usr/bin/env bash
# affected-tests-pool-default.test.sh — the delegated affected gate's pool-width default (#12013).
#
# PROPERTY. When plugins/soleur/scripts/affected-tests.sh delegates `--affected` to a repo runner
# (scripts/test-all.sh registering --print-selection), it hands the runner a pool width of 4 unless
# the operator already chose one — LOCALLY only. `--full`, a CI environment, and an explicit
# SOLEUR_TEST_JOBS (including 1, the serial override) are left exactly as they were. The default is
# applied to the runner's own environment, so the gate's later steps never see it.
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
#   M5  default to 1 instead of 4             -> C1 red
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

TMP="$(mktemp -d "${TMPDIR:-/var/tmp}/t12013.XXXXXX")" || exit 2
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
mk_repo() {  # <dir>
  local d="$1"
  case "$d" in /*) ;; *) echo "mk_repo: need an absolute path" >&2; return 1 ;; esac
  mkdir -p "$d/scripts" || return 1
  cat > "$d/scripts/test-all.sh" <<'STUB'
#!/usr/bin/env bash
# Stub runner. The capability probe in affected-tests.sh greps for a --print-selection case label.
case "${1:-}" in
  --print-selection) ;;
esac
printf 'JOBS=%s ARGS=%s\n' "${SOLEUR_TEST_JOBS-<unset>}" "$*" > "${STUB_OUT:?STUB_OUT is not set}"
exit "${STUB_RC:-0}"
STUB
  chmod +x "$d/scripts/test-all.sh" || return 1
  git -C "$d" init -q -b main || return 1
  git -C "$d" -c user.email=t@example.invalid -c user.name=t add -A || return 1
  git -C "$d" -c user.email=t@example.invalid -c user.name=t commit -q -m fixture || return 1
}
REPO="$TMP/repo"
mk_repo "$REPO" || { echo "FATAL: fixture repo build failed"; exit 2; }

# run_gate <label> <rc-of-stub> <env assignments...> -- <gate args...>
# Sets: GATE_RC, GATE_OUT, READING (the stub's "JOBS=… ARGS=…" line, or "<stub not run>").
run_gate() {
  local stub_rc="$1"; shift
  local -a envs=()
  while (( $# > 0 )) && [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  local out="$TMP/stub.out"; rm -f "$out"
  GATE_RC=0
  GATE_OUT="$(cd "$REPO" && env -u CI -u SOLEUR_TEST_JOBS -u SOLEUR_SUBAGENT STUB_OUT="$out" STUB_RC="$stub_rc" \
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

# C6 — the default does not leak into the gate's own environment: only the runner invocation sees it.
# A second stub that the gate runs AFTER the runner (the content trigger / epilogue) is not available
# in a fixture, so the pin is structural: no export statement may name the variable.
if ! grep -qE '^[[:space:]]*(export|declare -x|typeset -x)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*SOLEUR_TEST_JOBS' "$GATE"; then
  pass "C6 — the gate never exports SOLEUR_TEST_JOBS (the default is scoped to the runner call)"
else
  fail "C6 — the gate exports SOLEUR_TEST_JOBS"
fi

# --- mutation rows: build each mutant from a copy of the gate and require RED ------------------
if [[ -z "${AFFECTED_GATE_OVERRIDE:-}" ]]; then
  MUT="$TMP/mut"
  mkdir -p "$MUT" || { echo "FATAL: cannot create mutation dir"; exit 2; }
  src_dir="$(dirname "$GATE")"
  mutate() {  # <name> <python expression transforming s>
    local name="$1" expr="$2" dir="$MUT/$1"
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
    if (( rc != 0 )) && grep -q "^\[FAIL\] $3" <<<"$out"; then
      pass "$row — mutant '$name' goes red on $3"
    else
      fail "$row — mutant '$name' survived or failed elsewhere (rc=$rc)"; dump "$(grep -E '^\[(FAIL|pass)\]' <<<"$out" | head -8)"
    fi
  }
  # The expressions anchor on the one statement the production code carries.
  mutate M1 's.replace("SOLEUR_TEST_JOBS=\"${SOLEUR_TEST_JOBS:-4}\" ", "")' && score M1 M1 "C1"
  mutate M2 's.replace("(( ! ARG_FULL )) && ", "")' && score M2 M2 "C3"
  mutate M3 's.replace(" && [[ -z \"${CI:-}\" ]]", "")' && score M3 M3 "C4"
  mutate M4 's.replace("SOLEUR_TEST_JOBS=\"${SOLEUR_TEST_JOBS:-4}\" affected_bound", "export SOLEUR_TEST_JOBS=\"${SOLEUR_TEST_JOBS:-4}\"; affected_bound")' && score M4 M4 "C6"
  mutate M5 's.replace("${SOLEUR_TEST_JOBS:-4}", "${SOLEUR_TEST_JOBS:-1}")' && score M5 M5 "C1"
fi

# Anti-vacuity floor, reported without the helpers it backstops.
TOTAL=$((PASSES + FAILS))
if [[ -z "${AFFECTED_GATE_OVERRIDE:-}" ]]; then FLOOR=16; else FLOOR=11; fi
if (( TOTAL < FLOOR )); then
  printf '[FATAL] only %d assertions ran (floor %d) — the suite is not exercising what it claims\n' "$TOTAL" "$FLOOR"
  exit 1
fi
echo ""
echo "=== affected-tests-pool-default: $PASSES passed, $FAILS failed ==="
(( FAILS == 0 )) || exit 1
exit 0
