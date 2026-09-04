#!/usr/bin/env bash
# Guard 3 driver — the fail-loud runtime tripwire.
#
# PROPERTY. A test-runner process that starts holding any git-location variable ABORTS before
# running a single test, naming the variables and the runner.
#
# This suite asserts the tripwire FIRED — an observed non-zero abort from a real runner
# invocation — never that the tripwire file exists. A source grep is satisfied by a comment
# (harness row L1), and registration is part of the mechanism (mutation row K3): a tripwire whose
# preload line has been removed still exists on disk and protects nothing.
#
# This file deliberately does NOT source test-helpers.sh: that file now carries the shell arm of
# the very tripwire under test, so sourcing it would make this suite abort in exactly the arms it
# exists to exercise.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$SCRIPT_DIR" in
  ""|/|//|/.) printf 'FATAL: SCRIPT_DIR degenerate (%s); refusing\n' "$SCRIPT_DIR" >&2; exit 2 ;;
  /*) : ;;
  *) printf 'FATAL: SCRIPT_DIR is relative; refusing\n' >&2; exit 2 ;;
esac
readonly SCRIPT_DIR
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || exit 2
readonly REPO_ROOT
readonly TRIPWIRE_RC=97

# One owning scratch dir with a single trap (ADR-129). The per-site `mktemp` this replaces left a
# file behind whenever the suite died between allocation and its `rm -f` -- which is precisely the
# window the tripwire arms exercise, since several of them expect a non-zero exit.
WORK="$(mktemp -d -t g3.XXXXXXXX)" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
case "$WORK" in
  ""|/|//|/.) printf 'FATAL: WORK degenerate (%s); refusing\n' "$WORK" >&2; exit 2 ;;
  /*) : ;;
  *) printf 'FATAL: WORK is RELATIVE (%s); refusing\n' "$WORK" >&2; exit 2 ;;
esac
readonly WORK
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

PASS=0
FAIL=0
# Independent, append-only tally of assertions that actually executed. The floors at the bottom
# report through printf + exit and never through ok()/bad(), so neutering those cannot silence
# them (AP-023).
ASSERTIONS=0

ok()  { printf '  [ok]   %s\n' "$1"; PASS=$((PASS+1)); ASSERTIONS=$((ASSERTIONS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); ASSERTIONS=$((ASSERTIONS+1)); }

# Instrument self-test (AP-023): drive both helpers once and refuse to continue unless both
# counters moved. A suite whose pass/fail helpers are broken reports whatever it likes.
_p0=$PASS; _f0=$FAIL
ok   "instrument self-test: ok() increments"
bad  "instrument self-test: bad() increments (this FAIL is expected and is subtracted)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  printf 'FATAL: instrument self-test did not move both counters\n' >&2
  exit 2
fi
PASS=$((PASS-1)); FAIL=$((FAIL-1)); ASSERTIONS=$((ASSERTIONS-2))
printf '  (instrument verified; counters reset)\n\n'

# --- helpers ---------------------------------------------------------------------------------

# run_bun <label> <expected-rc> [VAR=VAL ...]
run_bun() {
  local label="$1" want="$2"; shift 2
  local out rc
  out=$(cd "$REPO_ROOT" && env "$@" bun test plugins/soleur/test/git-fixture-env.test.ts 2>&1)
  rc=$?
  if [[ "$rc" == "$want" ]]; then
    ok "$label (rc=$rc)"
  else
    bad "$label — got rc=$rc, want $want"
    printf '%s\n' "$out" | tail -5 | sed 's/^/        /'
  fi
}

printf '=== K: bun arm — the tripwire must ABORT, not warn ===\n'
run_bun "clean control passes"                     0
run_bun "GIT_DIR aborts"                           "$TRIPWIRE_RC" GIT_DIR=/tmp/hostile
run_bun "GIT_INDEX_FILE alone aborts"              "$TRIPWIRE_RC" GIT_INDEX_FILE=/tmp/hostile/index
run_bun "GIT_WORK_TREE alone aborts"               "$TRIPWIRE_RC" GIT_WORK_TREE=/tmp/hostile
run_bun "GIT_NAMESPACE alone aborts"               "$TRIPWIRE_RC" GIT_NAMESPACE=ns
run_bun "GIT_COMMON_DIR alone aborts"              "$TRIPWIRE_RC" GIT_COMMON_DIR=/tmp/hostile
run_bun "GIT_OBJECT_DIRECTORY alone aborts"        "$TRIPWIRE_RC" GIT_OBJECT_DIRECTORY=/tmp/o
run_bun "GIT_ALTERNATE_OBJECT_DIRECTORIES aborts"  "$TRIPWIRE_RC" GIT_ALTERNATE_OBJECT_DIRECTORIES=/tmp/o

printf '\n=== L2 (must-PASS, not canonical): identity + config vars are NOT a breach ===\n'
# These leak into fixture commit metadata but do not retarget a write. A guard that blocked on them
# would make every ordinary `git commit` hook run unusable.
run_bun "GIT_AUTHOR_NAME + GIT_CONFIG_PARAMETERS pass" 0 \
  GIT_AUTHOR_NAME=probe GIT_CONFIG_PARAMETERS="'a.b'='c'"
run_bun "GIT_COMMITTER_EMAIL passes"                   0 GIT_COMMITTER_EMAIL=probe@example.com

printf '\n=== K: the abort message must NAME the variable and the remedy ===\n'
msg=$(cd "$REPO_ROOT" && GIT_DIR=/tmp/hostile-probe bun test plugins/soleur/test/git-fixture-env.test.ts 2>&1)
for needle in 'GIT_DIR=/tmp/hostile-probe' 'unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE'; do
  if printf '%s' "$msg" | grep -qF -- "$needle"; then
    ok "abort message contains: $needle"
  else
    bad "abort message MISSING: $needle"
  fi
done

printf '\n=== K: shell arm — a suite sourcing test-helpers.sh aborts ===\n'
SHELL_SUITE=""
while IFS= read -r f; do SHELL_SUITE="$f"; break; done < <(grep -l 'test-helpers.sh' "$SCRIPT_DIR"/*.test.sh 2>/dev/null | sort)
if [[ -z "$SHELL_SUITE" ]]; then
  bad "no .test.sh sources test-helpers.sh — the shell arm's corpus is empty"
else
  err="$WORK/shell.err"
  ( cd "$REPO_ROOT" && GIT_DIR=/tmp/hostile bash "$SHELL_SUITE" >/dev/null 2>"$err" )
  rc=$?
  if [[ "$rc" == "$TRIPWIRE_RC" ]]; then
    ok "shell suite $(basename "$SHELL_SUITE") aborts (rc=$rc)"
  else
    bad "shell suite $(basename "$SHELL_SUITE") — got rc=$rc, want $TRIPWIRE_RC"
  fi
  if grep -qF 'GIT_DIR=/tmp/hostile' "$err"; then
    ok "shell abort message names the variable"
  else
    bad "shell abort message does not name the variable"
  fi
fi

printf '\n=== K: vitest arm — the third runtime must abort too ===\n'
# Asserting the tripwire FIRED, not that setup-node.ts imports it. The K4 block below checks
# registration; this checks the observable consequence, which is the half a source grep cannot see.
#
# The expected code is "non-zero", NOT 97: the tripwire calls process.exit(97) inside a vitest
# worker, and vitest reports its own aggregate status (1) rather than propagating the child's.
# Pinning 97 here would red for the wrong reason on any vitest upgrade.
VITEST_BIN="$REPO_ROOT/apps/web-platform/node_modules/.bin/vitest"
if [[ ! -x "$VITEST_BIN" ]]; then
  printf '  [skip] vitest binary absent (%s) — deps not installed\n' "$VITEST_BIN"
else
  probe=""
  while IFS= read -r f; do probe="$f"; break; done \
    < <(cd "$REPO_ROOT/apps/web-platform" && ls test/*.test.ts 2>/dev/null | sort)
  if [[ -z "$probe" ]]; then
    bad "no vitest probe suite found under apps/web-platform/test/"
  else
    vout="$WORK/vitest.out"
    ( cd "$REPO_ROOT/apps/web-platform" && GIT_DIR=/tmp/hostile-vitest "$VITEST_BIN" run "$probe" ) \
      > "$vout" 2>&1
    vrc=$?
    if (( vrc != 0 )) && grep -qF 'GIT_DIR=/tmp/hostile-vitest' "$vout"; then
      ok "vitest aborts under a hostile env (rc=$vrc, message names the variable)"
    else
      bad "vitest did NOT abort as expected — rc=$vrc"
      tail -5 "$vout" | sed 's/^/        /'
    fi
  fi
fi

printf '\n=== K4: one prelude per REGISTERED runtime (derived, not hand-copied) ===\n'
# Derive the vitest setup files from vitest.config.ts rather than restating them. A fourth runtime
# added without a prelude must red here.
VITEST_CONFIG="$REPO_ROOT/apps/web-platform/vitest.config.ts"
if [[ ! -f "$VITEST_CONFIG" ]]; then
  bad "vitest.config.ts not found at $VITEST_CONFIG"
else
  setup_count=0
  while IFS= read -r sf; do
    setup_count=$((setup_count+1))
    abs="$REPO_ROOT/apps/web-platform/$sf"
    if [[ ! -f "$abs" ]]; then
      bad "vitest setupFile declared but missing: $sf"
    elif grep -q 'git-tripwire' "$abs"; then
      ok "vitest setupFile carries the tripwire: $sf"
    else
      bad "vitest setupFile has NO tripwire: $sf"
    fi
  done < <(grep -oE 'setupFiles: \["[^"]+"\]' "$VITEST_CONFIG" | sed 's/.*\["//; s/"\]//' | sort -u)
  if (( setup_count < 1 )); then
    bad "derived ZERO vitest setup files — the derivation stopped matching"
  else
    ok "derived $setup_count distinct vitest setup file(s) from vitest.config.ts"
  fi
fi

# bun registration must be present AND point at a real file.
if grep -qE '^preload = \[.*git-tripwire' "$REPO_ROOT/bunfig.toml"; then
  ok "bunfig.toml registers the tripwire as a preload"
else
  bad "bunfig.toml does NOT register the tripwire preload"
fi
if grep -q 'GIT_DIR' "$REPO_ROOT/plugins/soleur/test/test-helpers.sh"; then
  ok "test-helpers.sh carries the shell prelude"
else
  bad "test-helpers.sh has NO shell prelude"
fi

printf '\n=== summary ===\n'
printf '  %d passed, %d failed, %d assertions\n' "$PASS" "$FAIL" "$ASSERTIONS"

# Floors: printf + exit, never through ok()/bad() (AP-023 — a floor that calls the helper it
# backstops is disarmed by the same edit).
MIN_ASSERTIONS=19
if (( ASSERTIONS < MIN_ASSERTIONS )); then
  printf 'FLOOR: %d assertions < %d — the suite examined less than it must\n' \
    "$ASSERTIONS" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if (( FAIL > 0 )); then
  printf 'Guard 3: %d assertion(s) failed\n' "$FAIL" >&2
  exit 1
fi
exit 0
