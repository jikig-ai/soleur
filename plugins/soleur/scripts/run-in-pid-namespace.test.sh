#!/usr/bin/env bash
# Tests for plugins/soleur/scripts/run-in-pid-namespace.sh: the helper that runs a command as PID 1 of
# a fresh PID namespace and REFUSES (rc 125, marker line, command never started) when it cannot.
#
# Two kinds of rows. ALWAYS-RUN rows use a stub `unshare` on a private PATH, so the helper's logic is
# proven on every host (CI shapes where user namespaces are restricted, macOS). REAL-NAMESPACE rows
# need working user namespaces; one probe decides, and where they are unavailable they are COUNTED as
# skipped (a SKIP line names how many and why) and the real helper's refusal is asserted instead (R8).
# SOLEUR_REQUIRE_REAL_NS=1 turns "unavailable" into a FAIL.
#
# The containment row (N4) never runs a lethal walker: it uses a nonce-scoped fixture walker
# (plugins/soleur/test/fixtures/ancestor-signal/walker-nonce.txt) that signals only ancestors whose
# argv carries a per-run 32-hex nonce, so even a helper that regressed to run in place could only
# reach the fixture's own `victim`.
#
# Run: bash plugins/soleur/scripts/run-in-pid-namespace.test.sh

# shellcheck disable=SC2319  # check() deliberately consumes the status of the condition on the line above
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$DIR/run-in-pid-namespace.sh"
WALKER="$DIR/../test/fixtures/ancestor-signal/walker-nonce.txt"
BASH_BIN="$(type -P bash)"

FIX="$(mktemp -d -t runinns.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$FIX"' EXIT

# shellcheck source=../test/test-helpers.sh
source "$DIR/../test/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail
assert_fixture_dir "$FIX"
[[ -f "$SUT" ]] || { printf '[FATAL] SUT missing at %s\n' "$SUT" >&2; exit 1; }
[[ -f "$WALKER" ]] || { printf '[FATAL] walker fixture missing at %s\n' "$WALKER" >&2; exit 1; }

passes=0; fails=0; cases=0; skipped=0
FAILURES=()
ok() { passes=$((passes + 1)); printf '  ok: %s\n' "$1"; }
bad() { fails=$((fails + 1)); FAILURES+=("$1"); printf '  FAIL: %s\n' "$1"; }
check() { # description condition-result(0=true)
  cases=$((cases + 1))
  if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi
}

# Instrument self-test: drive both verdict helpers once, require both counters to move, then unwind.
_p0=$passes; _f0=$fails; _c0=$cases; _l0=${#FAILURES[@]}
ok "selftest" >/dev/null; bad "selftest" >/dev/null
if [[ $passes -ne $((_p0 + 1)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: ok()/bad() do not record verdicts\n' >&2; exit 1
fi
passes=$_p0; fails=$_f0; cases=$_c0; FAILURES=()

# --- private PATHs ------------------------------------------------------------
mkdir -p "$FIX/nobin" "$FIX/stub"
assert_fixture_dir "$FIX"
for t in bash sh awk tr cut head cat env; do
  src="$(type -P "$t" 2>/dev/null || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$FIX/nobin/$t"
done
REAL_UNSHARE="$(type -P unshare 2>/dev/null || true)"
W="$FIX/witness"

# run the helper with a private PATH; sets OUT (stdout+stderr) and RC
run_helper() { # path-dir cmd...
  local pdir="$1"; shift
  RC=0
  OUT="$(PATH="$pdir" "$BASH_BIN" "$SUT" "$@" 2>&1)" || RC=$?
}
first_line() { printf '%s\n' "$1" | head -n 1; }
witness_cmd=(sh -c ': > "$1"' sh "$W")

mkstub() { # name body -- writes $FIX/stub/<name>/unshare
  mkdir -p "$FIX/stub/$1"; assert_fixture_dir "$FIX"
  printf '#!/bin/sh\n%s\n' "$2" > "$FIX/stub/$1/unshare"; chmod +x "$FIX/stub/$1/unshare"
  for t in bash sh awk tr cut head cat env; do ln -sf "$FIX/nobin/$t" "$FIX/stub/$1/$t" 2>/dev/null || true; done
}

echo "=== always-run rows (stub unshare) ==="

# R6 witness control: the witness command, run directly, DOES create the witness.
rm -f "$W"; "${witness_cmd[@]}"
[[ -e "$W" ]]; check "R6 witness control: the witness command writes its file when it runs" $?
rm -f "$W"

# R1 unshare absent.
rm -f "$W"; run_helper "$FIX/nobin" "${witness_cmd[@]}"
[[ "$RC" -eq 125 && "$(first_line "$OUT")" == "RUN_IN_PID_NAMESPACE_REFUSED reason=missing-unshare"* && ! -e "$W" ]]
check "R1 no unshare on PATH: rc 125, marker reason=missing-unshare, command never started" $?

# R2 unshare fails (EPERM): rc 125, the stub's first line quoted on one line.
mkstub fail 'echo "unshare: unshare failed: Operation not permitted" >&2; exit 1'
rm -f "$W"; run_helper "$FIX/stub/fail" "${witness_cmd[@]}"
[[ "$RC" -eq 125 && "$(first_line "$OUT")" == "RUN_IN_PID_NAMESPACE_REFUSED reason=userns-unavailable"* && ! -e "$W" ]]
check "R2 failing unshare: rc 125, reason=userns-unavailable, command never started" $?
printf '%s\n' "$OUT" | grep -cF >/dev/null -- "Operation not permitted"
check "R2b the unshare message is quoted in the refusal" $?
[[ "$(printf '%s\n' "$OUT" | grep -c '^RUN_IN_PID_NAMESPACE_REFUSED')" -eq 1 ]]
check "R2c exactly one marker line" $?

# R3 dishonest unshare: exits 0 and runs the command in place.
mkstub dishonest 'while [ "$1" != "--" ]; do shift; done; shift; exec "$@"'
rm -f "$W"; run_helper "$FIX/stub/dishonest" "${witness_cmd[@]}"
[[ "$RC" -eq 125 && "$(first_line "$OUT")" == "RUN_IN_PID_NAMESPACE_REFUSED reason=not-isolating"* && ! -e "$W" ]]
check "R3 dishonest unshare (runs in place): rc 125, reason=not-isolating, command never started" $?

# R4 argv: a recording stub (lies on both calls by exiting 0 without running anything).
mkstub rec 'n=$(cat "'"$FIX"'/calln" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "'"$FIX"'/calln"; printf "%s\n" "$@" > "'"$FIX"'/argv.$n"; exit 0'
rm -f "$FIX"/calln "$FIX"/argv.*; run_helper "$FIX/stub/rec" -- sh -c 'echo hi' x '' -n "a b"
[[ "$RC" -eq 0 && -s "$FIX/argv.2" ]]; check "R4 recording stub sees a probe call and a run call" $?
flags_ok=0
for f in -U -r -p -f --kill-child --mount-proc; do
  # combined -Urpf is equivalent to the split spellings
  if [[ "$f" == --* ]]; then
    [[ "$(grep -cxF -- "$f" "$FIX/argv.2")" -eq 1 ]] || flags_ok=1
  else
    letter="${f#-}"
    [[ "$(sed -n '1,/^--$/p' "$FIX/argv.2" | grep -E -- '^-[A-Za-z]+$' | grep -c "$letter")" -ge 1 ]] || flags_ok=1
  fi
done
check "R4b all of -U -r -p -f --kill-child --mount-proc precede -- in the run call" "$flags_ok"
mapfile -t AV < "$FIX/argv.2"
di=-1; for i in "${!AV[@]}"; do [[ "${AV[$i]}" == "--" ]] && { di=$i; break; }; done
rest=""; if [[ "$di" -ge 0 ]]; then for ((i = di + 5; i < ${#AV[@]}; i++)); do rest+="${AV[$i]}|"; done; fi
[[ "$di" -ge 0 && "${AV[$((di + 1))]:-}" == "sh" && "${AV[$((di + 2))]:-}" == "-c" && "${AV[$((di + 3))]:-}" == *'; exec "$@"' && "${AV[$((di + 4))]:-}" == "sh" && "$rest" == 'sh|-c|echo hi|x||-n|a b|' ]]
check "R4c the whole argv after -- is sh -c <RUN ending exec \"\$@\"> sh then the command verbatim (spaces, an empty argument, a leading -n)" $?

# R11 a command word that begins with a dash is refused before anything starts (exec would read it as an
# option, and dash rejects exec --): rc 2, named message, no unshare call, command never started.
rm -f "$W" "$FIX"/calln "$FIX"/argv.*; run_helper "$FIX/stub/rec" -touch "$W"
[[ "$RC" -eq 2 && "$OUT" == *'must not begin with "-"'* && ! -e "$W" && ! -e "$FIX/calln" ]]
check "R11 a command beginning with a dash is refused: rc 2, no unshare call, never started" $?

# R5 usage.
run_helper "$FIX/nobin"
[[ "$RC" -eq 2 && "$OUT" == usage:* ]]; check "R5 no command: usage, rc 2" $?

# R7 the in-namespace re-check: the probe call lies (exit 0), the run call executes in place.
mkstub lateliar 'n=$(cat "'"$FIX"'/call7" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "'"$FIX"'/call7"
if [ "$n" -eq 1 ]; then echo probe-isolated >> "'"$FIX"'/log7"; exit 0; fi
echo run-in-place >> "'"$FIX"'/log7"; while [ "$1" != "--" ]; do shift; done; shift; exec "$@"'
rm -f "$W" "$FIX"/call7 "$FIX"/log7; run_helper "$FIX/stub/lateliar" "${witness_cmd[@]}"
[[ "$RC" -eq 125 && "$OUT" == *"RUN_IN_PID_NAMESPACE_REFUSED reason=not-isolating"* && ! -e "$W" ]]
check "R7 the check inside the namespace refuses when the run is not isolated: rc 125, marker, command never started" $?
[[ "$(cat "$FIX/log7" 2>/dev/null | tr '\n' ' ')" == "probe-isolated run-in-place " ]]
check "R7b positive control: the stub took the isolated branch on the probe and the in-place branch on the run" $?

# R9 an exported function named unshare must not decide the probe: a failing unshare is on PATH, the function
# would succeed, and the refusal must come from the PATH binary.
rm -f "$W"
RC=0; OUT="$(unshare() { return 0; }; export -f unshare; PATH="$FIX/stub/fail" "$BASH_BIN" "$SUT" "${witness_cmd[@]}" 2>&1)" || RC=$?
[[ "$RC" -eq 125 && "$OUT" == "RUN_IN_PID_NAMESPACE_REFUSED reason=userns-unavailable"* && ! -e "$W" ]]
check "R9 an exported shell function unshare does not decide the probe (the PATH binary does)" $?

# R10 below: the helper must not refuse where the host itself can create the namespace.

# --- probe decides the real-namespace branch ---------------------------------
REAL_NS=no; REAL_WHY="no unshare on PATH"
if [[ -n "$REAL_UNSHARE" ]]; then
  PROBE_OUT="$("$BASH_BIN" "$SUT" sh -c 'echo ok' 2>&1)"; PROBE_RC=$?
  if [[ "$PROBE_RC" -eq 0 && "$PROBE_OUT" == "ok" ]]; then REAL_NS=yes
  else REAL_WHY="$(first_line "$PROBE_OUT" | cut -c1-120)"; fi
fi

# An INDEPENDENT host probe (the SUT is not involved): where the host can create the namespace and the helper
# still refuses, the helper is broken, and that must be a FAIL, never a SKIP.
HOST_NS=no
if [[ -n "$REAL_UNSHARE" ]]; then
  HOST_OUT="$("$REAL_UNSHARE" -Urpf --kill-child --mount-proc -- sh -c 'echo ok' 2>&1)"; HOST_RC=$?
  [[ "$HOST_RC" -eq 0 && "$HOST_OUT" == "ok" ]] && HOST_NS=yes
fi
[[ "$HOST_NS" != "yes" || "$REAL_NS" == "yes" ]]
check "R10 the helper does not refuse where the host itself can create the namespace (host=$HOST_NS, helper=$REAL_NS)" $?

if [[ "$REAL_NS" == "yes" ]]; then
  echo "=== real-namespace rows ==="
  # N1 PID 1, no parent, own /proc.
  OUT="$("$BASH_BIN" "$SUT" sh -c 'echo "$$ $PPID $(awk "/^NSpid:/{print NF-1}" /proc/self/status)"' 2>&1)"
  [[ "$OUT" == "1 0 1" ]]; check "N1 the command is PID 1 with PPID 0 and its own /proc" $?
  # N2 exit codes pass through; a wrapped 125 carries no marker.
  "$BASH_BIN" "$SUT" sh -c 'exit 0'; r0=$?; "$BASH_BIN" "$SUT" sh -c 'exit 3'; r3=$?
  OUT="$("$BASH_BIN" "$SUT" sh -c 'exit 125' 2>&1)"; r125=$?
  [[ "$r0" -eq 0 && "$r3" -eq 3 ]]; check "N2 exit codes 0 and 3 pass through" $?
  [[ "$r125" -eq 125 && "$OUT" != *RUN_IN_PID_NAMESPACE_REFUSED* ]]; check "N2b a wrapped command's own 125 passes through with no marker" $?
  # N3 stdin, stdout, stderr, cwd; a dash-leading command name.
  mkdir -p "$FIX/cwd"; assert_fixture_dir "$FIX"
  OUT="$(cd "$FIX/cwd" && printf 'in\n' | "$BASH_BIN" "$SUT" sh -c 'read x; echo "out:$x:$(pwd)"; echo err >&2' 2>"$FIX/err3")"
  [[ "$OUT" == "out:in:$FIX/cwd" && "$(cat "$FIX/err3")" == "err" ]]
  check "N3 stdin, stdout, stderr and cwd pass through, nothing added on stderr" $?
  cat > "$FIX/-dashcmd" <<'EOS'
#!/bin/sh
echo dash-ran
EOS
  chmod +x "$FIX/-dashcmd"
  OUT="$(cd "$FIX" && "$BASH_BIN" "$SUT" -- ./-dashcmd 2>&1)"
  [[ "$OUT" == "dash-ran" ]]; check "N3b a command whose file name begins with a dash runs when given as a path (./-name)" $?
  # N4 containment: victim (outside, argv carries the nonce) -> helper -> top (PID 1, nonce) -> mid (nonce) -> walker.
  NONCE="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"
  [[ "$NONCE" =~ ^[0-9a-f]{32}$ ]]; check "N4 precondition: the nonce is 32 hex characters" $?
  assert_fixture_dir "$FIX"
  cat > "$FIX/top.sh" <<'EOS'
#!/bin/sh
sh "$FIX_DIR/mid.sh" "mid-$1"
echo top-done > "$FIX_DIR/top-done"
EOS
  cat > "$FIX/mid.sh" <<'EOS'
#!/bin/sh
echo mid-started > "$FIX_DIR/mid-started"
sh "$WALKER_PATH"
echo mid-survived > "$FIX_DIR/mid-survived"
EOS
  rm -f "$FIX/mid-started" "$FIX/mid-survived" "$FIX/top-done" "$FIX/victim-survived"
  FIX_DIR="$FIX" WALKER_PATH="$WALKER" WALKER_NONCE="$NONCE" SOLEUR_TEST_SUITE_PID=$$ VOUT="$FIX/victim-survived" \
    timeout -k 5 60 "$BASH_BIN" -c '"$@"; echo victim-survived > "$VOUT"' "victim-$NONCE" \
    "$BASH_BIN" "$SUT" sh "$FIX/top.sh" "top-$NONCE" > "$FIX/n4.out" 2>&1
  [[ -e "$FIX/mid-started" && ! -e "$FIX/mid-survived" ]]
  check "N4b positive control: the walker signalled the in-namespace middle process (it started, and died before its next line)" $?
  [[ -e "$FIX/top-done" && -e "$FIX/victim-survived" ]]
  check "N4c containment: PID 1 of the namespace finished and the outside ancestor carrying the nonce survived" $?
  # Fail-closed preconditions of the fixture walker, rehearsed with kill replaced by echo on the host chain.
  for pre in empty-nonce short-nonce nonhex-nonce unset-suite; do
    case "$pre" in
      empty-nonce) n=""; sp=$$ ;;
      short-nonce) n="abc123"; sp=$$ ;;
      nonhex-nonce) n="zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"; sp=$$ ;;
      unset-suite) n="$NONCE"; sp="" ;;
    esac
    O="$(WALKER_KILL=echo WALKER_NONCE="$n" SOLEUR_TEST_SUITE_PID="$sp" "$BASH_BIN" -c 'sh "$1"' "carrier-$n" "$WALKER" 2>&1)"
    [[ -z "$O" ]]; check "N4d the fixture walker signals nothing: $pre" $?
  done
  O="$(WALKER_KILL=echo WALKER_NONCE="$NONCE" SOLEUR_TEST_SUITE_PID=$$ "$BASH_BIN" -c 'echo $$ > "$2"; sh "$1"; :' "carrier-$NONCE" "$WALKER" "$FIX/carrier.pid" 2>&1)"
  [[ "$O" == "-TERM $(cat "$FIX/carrier.pid" 2>/dev/null)" ]]
  check "N4e rehearsal with kill replaced by echo targets exactly the nonce-carrying ancestor, nothing above it" $?
  # N5 a backgrounded child is gone after the helper returns; N5b the same after the helper is SIGKILLed.
  has_proc() { # tag -> 0 when some process cmdline carries the tag (the bracket keeps this grep's own argv from matching)
    grep -alqE -- "[${1:0:1}]${1:1}" /proc/[0-9]*/cmdline 2>/dev/null
  }
  T5="bgtag-$NONCE"
  "$BASH_BIN" "$SUT" "$BASH_BIN" -c 'exec -a "$1" sleep 40 & exit 0' sh "$T5" >/dev/null 2>&1
  gone=1; for _ in 1 2 3 4 5 6 7 8 9 10; do has_proc "$T5" || { gone=0; break; }; sleep 0.2; done
  check "N5 a backgrounded child does not outlive the command (the helper returned)" "$gone"
  T5b="bgkill-$NONCE"
  "$BASH_BIN" "$SUT" "$BASH_BIN" -c 'exec -a "$1" sleep 40' sh "$T5b" >/dev/null 2>&1 &
  hp=$!
  up=1; for _ in 1 2 3 4 5 6 7 8 9 10; do has_proc "$T5b" && { up=0; break; }; sleep 0.2; done
  [[ "$up" -eq 0 ]]; check "N5b control: the tagged child is running while the helper runs" $?
  kill -KILL "$hp" 2>/dev/null; wait "$hp" 2>/dev/null
  gone=1; for _ in 1 2 3 4 5 6 7 8 9 10; do has_proc "$T5b" || { gone=0; break; }; sleep 0.2; done
  check "N5c SIGKILL of the helper reaps the tree (--kill-child)" "$gone"
  # N6 nested use.
  OUT="$("$BASH_BIN" "$SUT" "$BASH_BIN" "$SUT" sh -c 'echo "$$ $PPID"' 2>&1)"
  [[ "$OUT" == "1 0" ]]; check "N6 a nested helper call works" $?
  # N7 a wrapper unshare that drops --mount-proc is refused.
  mkdir -p "$FIX/stub/noproc"; assert_fixture_dir "$FIX"
  cat > "$FIX/stub/noproc/unshare" <<EOS
#!/bin/sh
for x; do shift; [ "\$x" = "--mount-proc" ] || set -- "\$@" "\$x"; done
exec $REAL_UNSHARE "\$@"
EOS
  chmod +x "$FIX/stub/noproc/unshare"
  for t in bash sh awk tr cut head cat env; do ln -sf "$FIX/nobin/$t" "$FIX/stub/noproc/$t" 2>/dev/null || true; done
  rm -f "$W"; run_helper "$FIX/stub/noproc" "${witness_cmd[@]}"
  [[ "$RC" -eq 125 && "$OUT" == *"reason=not-isolating"* && ! -e "$W" ]]
  check "N7 a wrapper that drops --mount-proc is refused (host /proc has two NSpid fields)" $?
else
  # R8: where namespaces are unavailable the REAL helper must still refuse.
  echo "SKIP real-namespace rows: user namespaces unavailable here ($REAL_WHY)"
  skipped=$((skipped + 18))  # the 18 real-namespace rows: N1 N2 N2b N3 N3b N4 N4b N4c N4d x4 N4e N5 N5b N5c N6 N7
  rm -f "$W"; RC=0; OUT="$("$BASH_BIN" "$SUT" "${witness_cmd[@]}" 2>&1)" || RC=$?
  [[ "$RC" -eq 125 && "$(first_line "$OUT")" == "RUN_IN_PID_NAMESPACE_REFUSED reason="* && ! -e "$W" ]]
  check "R8 the real helper refuses (rc 125, marker, command never started) where namespaces are unavailable" $?
  if [[ "${SOLEUR_REQUIRE_REAL_NS:-}" == "1" ]]; then check "SOLEUR_REQUIRE_REAL_NS=1 but user namespaces are unavailable ($REAL_WHY)" 1; fi
fi

# --- verdict ------------------------------------------------------------------
echo ""
printf '=== run-in-pid-namespace: %d passed, %d failed (%d cases, %d skipped, real-namespace=%s) ===\n' "$passes" "$fails" "$cases" "$skipped" "$REAL_NS"
if [[ "$REAL_NS" != "yes" ]]; then printf 'SKIP: %d real-namespace rows (%s)\n' "$skipped" "$REAL_WHY"; fi
for f in ${FAILURES[@]+"${FAILURES[@]}"}; do printf '  - %s\n' "$f"; done
# Anti-vacuity floors: literal thresholds on the line above each test, reported by printf, appended to the ledger the verdict reads.
if [[ "$cases" -lt 16 ]]; then printf 'FAIL: vacuity floor: only %d cases ran (>= 16 always-run rows expected, R8 counted when namespaces are unavailable)\n' "$cases" >&2; FAILURES+=("always-run floor"); fi
if [[ "$REAL_NS" == "yes" ]]; then
  if [[ "$cases" -lt 33 ]]; then printf 'FAIL: vacuity floor: only %d cases ran (>= 33 expected with real namespaces)\n' "$cases" >&2; FAILURES+=("real-namespace floor"); fi
  if [[ "$cases" -ne 33 ]]; then printf 'FAIL: conservation: %d cases ran, 33 planned with real namespaces\n' "$cases" >&2; FAILURES+=("planned total"); fi
else
  if [[ "$((cases + skipped))" -ne 34 ]]; then printf 'FAIL: conservation: %d cases + %d skipped != 34 planned\n' "$cases" "$skipped" >&2; FAILURES+=("planned total"); fi
fi
if [[ "$((passes + fails))" -ne "$cases" ]]; then printf 'FAIL: verdict conservation: %d passes + %d fails != %d cases\n' "$passes" "$fails" "$cases" >&2; FAILURES+=("conservation"); fi
[[ "${#FAILURES[@]}" -eq 0 ]]
