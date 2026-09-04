#!/usr/bin/env bash
# Guard 3 driver — the fail-loud runtime tripwire.
#
# PROPERTY. A test-runner process that starts holding any git-location variable ABORTS before
# running a single test, naming the variables it found and a remedy that actually clears them.
#
# This suite asserts the tripwire FIRED — an observed non-zero abort from a real runner invocation —
# never that the tripwire file exists. A source grep is satisfied by a comment, and registration is
# part of the mechanism: a tripwire whose preload line has been removed still exists on disk and
# protects nothing.
#
# This file does NOT source test-helpers.sh: that file carries the shell arm of the tripwire under
# test, so sourcing it would abort this suite in exactly the arms it exists to exercise.
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

WORK="$(mktemp -d -t g3.XXXXXXXX)" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
case "$WORK" in
  ""|/|//|/.) printf 'FATAL: WORK degenerate (%s); refusing\n' "$WORK" >&2; exit 2 ;;
  /*) : ;;
  *) printf 'FATAL: WORK is RELATIVE (%s); refusing\n' "$WORK" >&2; exit 2 ;;
esac
readonly WORK
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

# A one-assertion probe suite. The clean-control arms only need to observe "the tripwire did NOT
# abort this runner" — any suite proves that. Pointing them at the full Guard 1 suite instead cost
# ~1.5s of a 2.9s run (52%) and made those verdicts depend on Guard 1's health, which is a coupling
# as well as a cost.
PROBE="$WORK/probe.test.ts"
cat > "$PROBE" <<'PROBE_EOF'
import { expect, test } from "bun:test";
test("probe", () => { expect(1).toBe(1); });
PROBE_EOF

PASS=0
FAIL=0
ASSERTIONS=0

ok()  { printf '  [ok]   %s\n' "$1"; PASS=$((PASS+1)); ASSERTIONS=$((ASSERTIONS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); ASSERTIONS=$((ASSERTIONS+1)); }

# Instrument self-test (AP-023): drive both helpers once and refuse to continue unless both
# counters moved.
_p0=$PASS; _f0=$FAIL
ok   "instrument self-test: ok() increments"
bad  "instrument self-test: bad() increments (expected; subtracted)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  printf 'FATAL: instrument self-test did not move both counters\n' >&2
  exit 2
fi
PASS=$((PASS-1)); FAIL=$((FAIL-1)); ASSERTIONS=$((ASSERTIONS-2))

# run_bun is the DISPATCHER for most assertions below, and it sits ABOVE ok()/bad() — so the
# self-test above cannot see it. One token here (`bad` -> `ok` in its mismatch branch) would report
# every arm as passing against a completely broken tripwire, at a byte-identical summary line.
# Drive it once with a deliberately wrong expectation and require FAIL to move.
run_bun() {
  local label="$1" want="$2"; shift 2
  local out rc
  out=$(cd "$REPO_ROOT" && env "$@" bun test "$PROBE" 2>&1)
  rc=$?
  if [[ "$rc" == "$want" ]]; then
    ok "$label (rc=$rc)"
  else
    bad "$label — got rc=$rc, want $want"
    printf '%s\n' "$out" | tail -5 | sed 's/^/        /'
  fi
}
_p1=$PASS; _f1=$FAIL
run_bun "dispatcher self-test: a wrong expectation must FAIL" 999
if (( FAIL != _f1 + 1 || PASS != _p1 )); then
  printf 'FATAL: run_bun did not report a mismatch as a failure — every arm below is unverified\n' >&2
  exit 2
fi
PASS=$_p1; FAIL=$_f1; ASSERTIONS=$((ASSERTIONS-1))
printf '  (instruments verified; counters reset)\n\n'

printf '=== K: bun arm — the tripwire must ABORT, not warn ===\n'
run_bun "clean control passes"                     0
run_bun "GIT_DIR aborts"                           "$TRIPWIRE_RC" GIT_DIR=/tmp/hostile
run_bun "GIT_INDEX_FILE alone aborts"              "$TRIPWIRE_RC" GIT_INDEX_FILE=/tmp/hostile/index
run_bun "GIT_WORK_TREE alone aborts"               "$TRIPWIRE_RC" GIT_WORK_TREE=/tmp/hostile
run_bun "GIT_NAMESPACE alone aborts"               "$TRIPWIRE_RC" GIT_NAMESPACE=ns
run_bun "GIT_COMMON_DIR alone aborts"              "$TRIPWIRE_RC" GIT_COMMON_DIR=/tmp/hostile
run_bun "GIT_OBJECT_DIRECTORY alone aborts"        "$TRIPWIRE_RC" GIT_OBJECT_DIRECTORY=/tmp/o
run_bun "GIT_ALTERNATE_OBJECT_DIRECTORIES aborts"  "$TRIPWIRE_RC" GIT_ALTERNATE_OBJECT_DIRECTORIES=/tmp/o
# The two the first revision's name list missed, both proven to EXECUTE arbitrary code: git init
# copies $GIT_TEMPLATE_DIR/hooks into the fixture before any config is consulted, and GIT_EXEC_PATH
# is prepended to PATH for every subprogram git spawns.
run_bun "GIT_TEMPLATE_DIR aborts (hook execution)" "$TRIPWIRE_RC" GIT_TEMPLATE_DIR=/tmp/tmpl
run_bun "GIT_EXEC_PATH aborts (PATH injection)"    "$TRIPWIRE_RC" GIT_EXEC_PATH=/tmp/exec

printf '\n=== L2 (must-PASS): identity and config vars are NOT a write-boundary breach ===\n'
run_bun "GIT_AUTHOR_NAME + GIT_CONFIG_PARAMETERS pass" 0 \
  GIT_AUTHOR_NAME=probe GIT_CONFIG_PARAMETERS="'a.b'='c'"
run_bun "GIT_COMMITTER_EMAIL passes"                   0 GIT_COMMITTER_EMAIL=probe@example.com

printf '\n=== K: the abort message names the FOUND variable and a remedy that clears it ===\n'
# The remedy must be DERIVED from what was found. A fixed three-name spelling was a loop: the guard
# refuses nine variables, so an environment carrying GIT_TEMPLATE_DIR was told to unset three names
# that would not clear it, re-ran, and aborted again with the same message.
msg=$(cd "$REPO_ROOT" && GIT_TEMPLATE_DIR=/tmp/hostile-probe bun test "$PROBE" 2>&1)
if printf '%s' "$msg" | grep -qF -- 'GIT_TEMPLATE_DIR=/tmp/hostile-probe'; then
  ok "abort message names the offending variable and its value"
else
  bad "abort message does not name the offending variable"
fi
if printf '%s' "$msg" | grep -qE '^[[:space:]]*unset[[:space:]]+GIT_TEMPLATE_DIR[[:space:]]+&&'; then
  ok "remedy names the variable actually found (not a fixed spelling)"
else
  bad "remedy does not name the found variable — an operator following it would loop"
  printf '%s\n' "$msg" | grep -m1 'unset' | sed 's/^/        got: /'
fi

printf '\n=== K: the escape hatch works and ANNOUNCES itself ===\n'
esc=$(cd "$REPO_ROOT" && env GIT_DIR=/tmp/hostile SOLEUR_GIT_TRIPWIRE_ALLOW=1 bun test "$PROBE" 2>&1)
esc_rc=$?
if (( esc_rc == 0 )); then ok "SOLEUR_GIT_TRIPWIRE_ALLOW=1 permits the run"; else bad "escape hatch did not permit the run (rc=$esc_rc)"; fi
if printf '%s' "$esc" | grep -qF 'DISARMED by SOLEUR_GIT_TRIPWIRE_ALLOW=1'; then
  ok "the escape announces itself on stderr"
else
  bad "the escape is SILENT — a switch that disarms a write-boundary guard with no trace"
fi

printf '\n=== K: shell arm — a suite sourcing test-helpers.sh aborts ===\n'
SHELL_SUITE=""
while IFS= read -r f; do SHELL_SUITE="$f"; break; done < <(grep -l 'test-helpers.sh' "$SCRIPT_DIR"/*.test.sh 2>/dev/null | sort)
if [[ -z "$SHELL_SUITE" ]]; then
  bad "no .test.sh sources test-helpers.sh — the shell arm's corpus is empty"
else
  ( cd "$REPO_ROOT" && GIT_DIR=/tmp/hostile bash "$SHELL_SUITE" >/dev/null 2>"$WORK/shell.err" )
  rc=$?
  if [[ "$rc" == "$TRIPWIRE_RC" ]]; then
    ok "shell suite $(basename "$SHELL_SUITE") aborts (rc=$rc)"
  else
    bad "shell suite $(basename "$SHELL_SUITE") — got rc=$rc, want $TRIPWIRE_RC"
  fi
  if grep -qF 'GIT_DIR=/tmp/hostile' "$WORK/shell.err"; then
    ok "shell abort message names the variable"
  else
    bad "shell abort message does not name the variable"
  fi
fi

printf '\n=== K: vitest arm — the third runtime, now via globalSetup ===\n'
# Since the tripwire moved from per-project `setupFiles` to a single `globalSetup`, it runs in
# vitest's MAIN process — the one that actually inherited the environment — so the real exit code
# propagates and this arm can pin 97 exactly. Under `setupFiles` the `process.exit(97)` happened in
# a worker and vitest reported its own aggregate 1, which this arm previously had to accept.
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
    ( cd "$REPO_ROOT/apps/web-platform" && GIT_DIR=/tmp/hostile-vitest "$VITEST_BIN" run --project=unit "$probe" ) \
      > "$WORK/vitest.out" 2>&1
    vrc=$?
    if (( vrc == TRIPWIRE_RC )) && grep -qF 'GIT_DIR=/tmp/hostile-vitest' "$WORK/vitest.out"; then
      ok "vitest aborts with rc=$vrc and names the variable"
    else
      bad "vitest did NOT abort as expected — rc=$vrc (want $TRIPWIRE_RC)"
      tail -5 "$WORK/vitest.out" | sed 's/^/        /'
    fi
  fi
fi

printf '\n=== K4: one prelude per REGISTERED runtime (derived, not hand-copied) ===\n'
# bun registration.
if grep -qE '^preload = \[.*git-tripwire' "$REPO_ROOT/bunfig.toml"; then
  ok "bunfig.toml registers the tripwire as a preload"
else
  bad "bunfig.toml does NOT register the tripwire preload"
fi
# bun resolves bunfig.toml from the INVOCATION cwd, so a preload registered only at the repo root
# does not apply to `cd plugins/soleur && bun test`. Measured: from the root a hostile GIT_DIR
# aborts rc=97; from plugins/soleur the same command ran with rc=0 and no tripwire. That path is
# live — grok-fidelity-gate.sh cd's there before running four bun test files.
if grep -qE '^preload = \[.*git-tripwire' "$REPO_ROOT/plugins/soleur/bunfig.toml" 2>/dev/null; then
  ok "plugins/soleur/bunfig.toml registers the tripwire (cwd-scoped preload)"
else
  bad "plugins/soleur/bunfig.toml has NO preload — cd plugins/soleur && bun test is unguarded"
fi
# And the entry point itself scrubs, which is the layer that PREVENTS rather than detects.
if grep -qE '^unset[[:space:]]+GIT_DIR[[:space:]]' "$REPO_ROOT/plugins/soleur/scripts/grok-fidelity-gate.sh"; then
  ok "grok-fidelity-gate.sh scrubs before its bun test invocation"
else
  bad "grok-fidelity-gate.sh starts a test runner with no scrub"
fi
# vitest registration, derived from the config rather than restated.
VITEST_CONFIG="$REPO_ROOT/apps/web-platform/vitest.config.ts"
if grep -qE '^[[:space:]]*globalSetup:[[:space:]]*\[[^]]*git-tripwire' "$VITEST_CONFIG"; then
  ok "vitest.config.ts registers the tripwire as globalSetup"
else
  bad "vitest.config.ts does NOT register the tripwire globalSetup"
fi
# shell registration — anchored on the executable prelude, NOT a bare token. `grep -q GIT_DIR`
# over this file is satisfied by the comment block that explains the prelude, so deleting the
# whole executable body left that assertion passing.
if grep -qE '^[[:space:]]*for _v in GIT_DIR[[:space:]]' "$REPO_ROOT/plugins/soleur/test/test-helpers.sh"; then
  ok "test-helpers.sh carries the executable shell prelude (loop, not a comment)"
else
  bad "test-helpers.sh has NO executable shell prelude"
fi

printf '\n=== summary ===\n'
printf '  %d passed, %d failed, %d assertions\n' "$PASS" "$FAIL" "$ASSERTIONS"

MIN_ASSERTIONS=24
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
