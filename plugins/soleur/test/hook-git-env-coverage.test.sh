#!/usr/bin/env bash
# Guard 2 — hook entry-point coverage (static).
#
# PROPERTY. Every hook entry point that starts a test runner removes the git-location family
# before starting it.
#
# ASSEMBLY. The complete, CLOSED set of hook entry points: every `run:` line in lefthook.yml plus
# every file under scripts/hooks/. Because the set is closed and small, the rule is ALL, not
# all-except-baselined — there is no grandfathering ledger and therefore no ledger to quietly grow.
#
# Why the entry points and not the ~900 test files: all four recurrences of this defect
# (2026-03-24 #1090, 2026-04-03 x2, 2026-09-04 #7833) entered through a hook command that lacked
# the scrub, never through a test file that lacked a helper. A guard over the test corpus would
# quantify over the wrong thing — and that corpus is not even enumerable, since the
# `execFileSync("git", ["init", ...])` array form and python list-spawns match no `git init` grep.
#
# This suite does NOT source test-helpers.sh: that file carries the Guard 3 shell prelude, and
# this suite must stay runnable while diagnosing a hostile environment.
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

LEFTHOOK="${SOLEUR_GUARD2_LEFTHOOK:-$REPO_ROOT/lefthook.yml}"
HOOKS_DIR="${SOLEUR_GUARD2_HOOKS_DIR:-$REPO_ROOT/scripts/hooks}"

PASS=0
FAIL=0
# Two INDEPENDENT observables, both incremented at the call site (AP-023). RUN_LINES counts the
# corpus the guard examined; ASSERTIONS counts the checks it actually ran. A guard body replaced
# with `exit 0` moves neither, and both are floored below through printf + exit rather than
# through ok()/bad() — a floor that calls the helper it backstops is disarmed by the same edit.
RUN_LINES=0
RUNNER_LINES=0
ASSERTIONS=0

ok()  { printf '  [ok]   %s\n' "$1"; PASS=$((PASS+1)); ASSERTIONS=$((ASSERTIONS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); ASSERTIONS=$((ASSERTIONS+1)); }

# Instrument self-test: drive both helpers once, refuse to continue unless both counters moved.
_p0=$PASS; _f0=$FAIL
ok  "instrument self-test: ok() increments"
bad "instrument self-test: bad() increments (expected; subtracted below)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  printf 'FATAL: instrument self-test did not move both counters\n' >&2
  exit 2
fi
PASS=$((PASS-1)); FAIL=$((FAIL-1)); ASSERTIONS=$((ASSERTIONS-2))
printf '  (instrument verified; counters reset)\n\n'

[[ -f "$LEFTHOOK" ]] || { printf 'FATAL: lefthook.yml not found at %s\n' "$LEFTHOOK" >&2; exit 2; }
[[ -d "$HOOKS_DIR" ]] || { printf 'FATAL: hooks dir not found at %s\n' "$HOOKS_DIR" >&2; exit 2; }

# --- what counts as "starts a test runner" ----------------------------------------------------
# Anchored on the `run:` COMMAND form, never a bare token: a comment line mentioning `bun test`
# must not register as an entry point (harness row J4). The command body is everything after
# `run:`, so a token appearing in a `#` comment line never reaches this matcher.
RUNNER_RE='(^|[^[:alnum:]_-])(bun[[:space:]]+test|vitest|npx[[:space:]]+vitest|pytest|scripts/test-all\.sh)([^[:alnum:]_-]|$)'
# Both spellings are measured-equivalent (measurements.md §M-6) and the contract permits either
# (harness row J2).
SCRUB_RE='(unset[[:space:]]+[^&|;]*GIT_DIR|env[[:space:]]+(-u[[:space:]]+GIT_[A-Z_]+[[:space:]]+)*-u[[:space:]]+GIT_DIR)'

printf '=== lefthook.yml: every run: line that starts a test runner ===\n'
while IFS= read -r line; do
  RUN_LINES=$((RUN_LINES+1))
  # Strip the leading `run:` key to get the command body.
  cmd="${line#*run:}"
  # A block scalar (`run: |`) carries its body on following lines; the multi-line case is handled
  # by the block-scalar sweep below, so an empty/`|` body here is not a runner line.
  [[ "$cmd" =~ ^[[:space:]]*\|?[[:space:]]*$ ]] && continue
  if [[ "$cmd" =~ $RUNNER_RE ]]; then
    RUNNER_LINES=$((RUNNER_LINES+1))
    if [[ "$cmd" =~ $SCRUB_RE ]]; then
      ok "scrubbed runner: $(printf '%s' "$cmd" | sed 's/^[[:space:]]*//' | cut -c1-64)"
    else
      # scripts/test-all.sh carries the unset INTERNALLY (verified as its own assertion below), so
      # an invocation of it needs no prefix. Every other runner does.
      if [[ "$cmd" =~ scripts/test-all\.sh ]]; then
        ok "runner delegates to test-all.sh, which scrubs internally: $(printf '%s' "$cmd" | sed 's/^[[:space:]]*//' | cut -c1-48)"
      else
        bad "UNSCRUBBED test runner in lefthook.yml: $(printf '%s' "$cmd" | sed 's/^[[:space:]]*//' | cut -c1-64)"
      fi
    fi
  fi
done < <(grep -E '^[[:space:]]+run:' "$LEFTHOOK")

# Block scalars (`run: |`) — their bodies are indented continuation lines, invisible to the sweep
# above. Scan them for runner tokens so a multi-line command cannot smuggle one past the guard.
while IFS= read -r bl; do
  if [[ "$bl" =~ $RUNNER_RE ]] && [[ ! "$bl" =~ ^[[:space:]]*# ]]; then
    RUNNER_LINES=$((RUNNER_LINES+1))
    if [[ "$bl" =~ $SCRUB_RE ]] || [[ "$bl" =~ scripts/test-all\.sh ]]; then
      ok "block-scalar runner is scrubbed: $(printf '%s' "$bl" | sed 's/^[[:space:]]*//' | cut -c1-56)"
    else
      bad "UNSCRUBBED runner inside a block scalar: $(printf '%s' "$bl" | sed 's/^[[:space:]]*//' | cut -c1-56)"
    fi
  fi
done < <(awk '/^[[:space:]]+run:[[:space:]]*\|/{inblk=1; next} inblk && /^[[:space:]]{8,}/{print; next} {inblk=0}' "$LEFTHOOK")

printf '\n=== scripts/hooks/: every hook script that starts a test runner ===\n'
HOOK_FILES=0
while IFS= read -r hf; do
  HOOK_FILES=$((HOOK_FILES+1))
  base="$(basename "$hf")"
  # A hook that starts no test runner needs no scrub — 1 of the 2 files here is a lefthook shim
  # whose only `test` occurrences are `test -n` / `test -f` shell builtins.
  if grep -qE "$RUNNER_RE" "$hf"; then
    RUNNER_LINES=$((RUNNER_LINES+1))
    if grep -qE "$SCRUB_RE" "$hf"; then
      ok "hook script scrubs before running a test runner: $base"
    else
      bad "hook script starts a test runner with NO scrub: $base"
    fi
  else
    ok "hook script starts no test runner (no scrub required): $base"
  fi
done < <(find "$HOOKS_DIR" -maxdepth 1 -type f | sort)

printf '\n=== the two existing scrub copies on main (N2, N3) ===\n'
# N2: test-all.sh's own --- Git Hook Isolation --- block. Every lefthook invocation of it depends
# on this, so it is asserted directly rather than assumed.
TEST_ALL="$REPO_ROOT/scripts/test-all.sh"
if [[ -f "$TEST_ALL" ]] && grep -qE "$SCRUB_RE" "$TEST_ALL"; then
  ok "scripts/test-all.sh carries its internal git-location unset (N2)"
else
  bad "scripts/test-all.sh has LOST its internal git-location unset (N2)"
fi

printf '\n=== corpus floors (N5, N6): a corpus that stopped matching must not read as green ===\n'
# Asserted, not merely printed. A matcher that matches nothing examines 0 commands and would
# otherwise report a clean sweep.
if (( RUN_LINES >= 20 )); then
  ok "examined $RUN_LINES lefthook run: lines (floor 20)"
else
  bad "examined only $RUN_LINES lefthook run: lines — the corpus stopped matching (N6)"
fi
if (( RUNNER_LINES >= 2 )); then
  ok "found $RUNNER_LINES test-runner entry points (floor 2)"
else
  bad "found only $RUNNER_LINES test-runner entry points — the matcher stopped matching (N5)"
fi
if (( HOOK_FILES >= 1 )); then
  ok "examined $HOOK_FILES file(s) under scripts/hooks/"
else
  bad "examined ZERO files under scripts/hooks/ — the corpus is empty (N6)"
fi

printf '\n=== summary ===\n'
printf '  %d passed, %d failed | run-lines=%d runners=%d hook-files=%d assertions=%d\n' \
  "$PASS" "$FAIL" "$RUN_LINES" "$RUNNER_LINES" "$HOOK_FILES" "$ASSERTIONS"

# Floors report through printf + exit (AP-023), never through ok()/bad().
MIN_ASSERTIONS=6
if (( ASSERTIONS < MIN_ASSERTIONS )); then
  printf 'FLOOR: %d assertions < %d — the guard examined less than it must\n' \
    "$ASSERTIONS" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if (( RUN_LINES < 20 || RUNNER_LINES < 2 )); then
  printf 'FLOOR: corpus below floor (run-lines=%d runners=%d)\n' "$RUN_LINES" "$RUNNER_LINES" >&2
  exit 1
fi
if (( FAIL > 0 )); then
  printf 'Guard 2: %d entry point(s) unscrubbed\n' "$FAIL" >&2
  exit 1
fi

# Externally-verifiable receipt. Every floor above lives INSIDE this guard, so replacing the whole
# body with `exit 0` deletes the guard and its floors together and reports success having asserted
# nothing -- a guard cannot detect its own erasure from the inside. The receipt moves that check to
# the CALLER: a green verdict is only trustworthy when accompanied by this line with counts above
# floor. Measured: without it, mutation row J1 SURVIVED.
printf 'SOLEUR_GUARD2_RECEIPT run_lines=%d runners=%d hook_files=%d assertions=%d\n' \
  "$RUN_LINES" "$RUNNER_LINES" "$HOOK_FILES" "$ASSERTIONS"
exit 0
