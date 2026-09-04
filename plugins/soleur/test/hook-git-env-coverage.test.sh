#!/usr/bin/env bash
# Guard 2 — hook entry-point coverage (static).
#
# PROPERTY. Every hook entry point that starts a test runner removes the git-location family, in
# the same shell, BEFORE starting it.
#
# Each clause is load-bearing and each was got wrong in the first revision of this file:
#   * "the git-location family" — the original SCRUB_RE required only the literal GIT_DIR, so
#     mutating the very fix this guard exists to protect down to `unset GIT_DIR && bun test …` read
#     GREEN. An absolute GIT_INDEX_FILE alone still stages into the victim's index (§M-3).
#   * "in the same shell" — `( unset … ); bun test` and `bash -c "unset …"; bun test` both mention
#     the scrub and both leave the runner hostile.
#   * "BEFORE" — `bun test … && unset …` was accepted by an order-blind regex.
#   * "a test runner" — the matcher listed `bun test|vitest|pytest` and missed `npm test`,
#     `bun run test`, and `python3 -m unittest` (the spelling scripts/test-all.sh itself uses).
#
# ASSEMBLY. Every `run:` command lefthook can execute, from a real YAML parse of lefthook.yml (see
# lib/lefthook-commands.py for the five fail-open ways the previous grep+awk parse was wrong), plus
# every file under scripts/hooks/ at any depth.
#
# Why the entry points and not the ~900 test files: all four recurrences of this defect
# (2026-03-24 #1090, 2026-04-03 x2, 2026-09-04 #7833) entered through a hook command that lacked the
# scrub, never through a test file that lacked a helper. That corpus is not enumerable anyway — the
# `execFileSync("git", ["init", …])` array form and python list-spawns match no `git init` grep.
#
# This suite does NOT source test-helpers.sh: that file carries the Guard 3 shell prelude, and this
# suite must stay runnable while diagnosing a hostile environment.
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
EXTRACTOR="$SCRIPT_DIR/lib/lefthook-commands.py"

PASS=0
FAIL=0
RUN_LINES=0
RUNNER_LINES=0
HOOK_FILES=0
ASSERTIONS=0

ok()  { printf '  [ok]   %s\n' "$1"; PASS=$((PASS+1)); ASSERTIONS=$((ASSERTIONS+1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); ASSERTIONS=$((ASSERTIONS+1)); }

_p0=$PASS; _f0=$FAIL
ok  "instrument self-test: ok() increments"
bad "instrument self-test: bad() increments (expected; subtracted below)"
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  printf 'FATAL: instrument self-test did not move both counters\n' >&2
  exit 2
fi
PASS=$((PASS-1)); FAIL=$((FAIL-1)); ASSERTIONS=$((ASSERTIONS-2))
printf '  (instrument verified; counters reset)\n\n'

[[ -f "$LEFTHOOK" ]]  || { printf 'FATAL: lefthook.yml not found at %s\n' "$LEFTHOOK" >&2; exit 2; }
[[ -d "$HOOKS_DIR" ]] || { printf 'FATAL: hooks dir not found at %s\n' "$HOOKS_DIR" >&2; exit 2; }
[[ -f "$EXTRACTOR" ]] || { printf 'FATAL: extractor not found at %s\n' "$EXTRACTOR" >&2; exit 2; }

# A "test runner" is anything that starts a test process. Deliberately broad: an omission is
# fail-OPEN (a new unscrubbed entry point reads green) while an over-match is fail-CLOSED and merely
# asks an author for a scrub they did not need.
RUNNER_RE='(^|[^[:alnum:]_./-])(bun[[:space:]]+(test|run[[:space:]]+test)|bunx[[:space:]]+vitest|vitest|npx[[:space:]]+vitest|(npm|yarn|pnpm)[[:space:]]+(run[[:space:]]+)?test|node[[:space:]]+--test|deno[[:space:]]+test|pytest|python3?[[:space:]]+-m[[:space:]]+(unittest|pytest)|scripts/test-all\.sh)([^[:alnum:]_-]|$)'

# Every name the tripwire refuses. A scrub removing a SUBSET is the defect, not a partial fix.
# Kept in lockstep with GIT_LOCATION_VARS in lib/git-fixture-env.ts and tests/scripts/
# _git_fixture_env.py — enforced by git-env-list-parity.test.sh, not asserted in prose.
readonly REQUIRED_SCRUB_VARS=(
  GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH
)

# Split a command into ordered statements. The extractor already normalised newlines to " ; ", so
# this covers every separator that keeps the SAME shell. A subshell `( … )` deliberately does not
# count as scrubbing: its unset does not outlive the parenthesis.
# The trailing newline is load-bearing: `printf '%s'` leaves the LAST statement unterminated, and
# `while read` returns non-zero on an unterminated final line, so the loop never sees it. Every
# command whose runner is the last statement -- `cd x && npm test`, `( unset … ) ; bun test` --
# then reads as scrubbed. Measured: six escape probes passed GREEN on that one missing newline.
split_statements() { printf '%s\n' "$1" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g'; }

# Does this statement REMOVE every required variable — as an actual unset/env -u, not a mention?
statement_scrubs() {
  local st="$1" v
  # Anchor on the leading verb: `echo "unset GIT_DIR"` and `grep unset foo` contain the words and
  # scrub nothing.
  [[ "$st" =~ ^[[:space:]]*(unset|env)[[:space:]] ]] || return 1
  for v in "${REQUIRED_SCRUB_VARS[@]}"; do
    [[ "$st" =~ (^|[[:space:]])(-u[[:space:]]+)?${v}([[:space:]]|$) ]] || return 1
  done
  return 0
}

# Scrubbed BEFORE the first runner statement, in the same shell?
command_is_scrubbed() {
  local cmd="$1" st scrubbed=0
  while IFS= read -r st || [[ -n "$st" ]]; do
    [[ -z "${st// }" ]] && continue
    # `env -u … <runner>` scrubs and runs in one statement — test that before the runner test.
    if statement_scrubs "$st"; then scrubbed=1; continue; fi
    if [[ "$st" =~ $RUNNER_RE ]]; then
      (( scrubbed == 1 )) && return 0
      return 1
    fi
  done < <(split_statements "$cmd")
  return 0
}

# scripts/test-all.sh scrubs internally, so invoking it needs no prefix. Strip that invocation and
# re-test the REMAINDER: a bare substring test let `bash scripts/test-all.sh && bun test plugins/`
# through — the #7833 defect shape, waved past by a name-drop.
strip_test_all() {
  printf '%s' "$1" | sed -E 's#[^;&|]*scripts/test-all\.sh[^;&|]*##g'
}

printf '=== lefthook.yml: every run: command that starts a test runner ===\n'
while IFS= read -r cmd; do
  RUN_LINES=$((RUN_LINES+1))
  [[ -z "${cmd// }" ]] && continue
  remainder="$(strip_test_all "$cmd")"
  if [[ "$remainder" =~ $RUNNER_RE ]]; then
    RUNNER_LINES=$((RUNNER_LINES+1))
    if command_is_scrubbed "$cmd"; then
      ok "scrubbed runner: $(printf '%s' "$cmd" | cut -c1-64)"
    else
      bad "UNSCRUBBED test runner in lefthook.yml: $(printf '%s' "$cmd" | cut -c1-72)"
    fi
  elif [[ "$cmd" =~ scripts/test-all\.sh ]]; then
    RUNNER_LINES=$((RUNNER_LINES+1))
    ok "runner delegates to test-all.sh, which scrubs internally: $(printf '%s' "$cmd" | cut -c1-48)"
  fi
done < <(python3 "$EXTRACTOR" "$LEFTHOOK")

printf '\n=== scripts/hooks/: every hook script that starts a test runner ===\n'
while IFS= read -r hf; do
  HOOK_FILES=$((HOOK_FILES+1))
  base="$(basename "$hf")"
  # Strip comments before matching. A whole-file `grep -qE` previously accepted a hook whose only
  # mention of the scrub was `# We used to need: unset GIT_DIR …` while it ran `bun test`
  # unscrubbed — the exact defect this guard exists to catch, in the branch that claimed immunity.
  body="$(sed 's/[[:space:]]*#.*$//' "$hf")"
  runner_line=$(printf '%s\n' "$body" | grep -nE "$RUNNER_RE" | head -1 | cut -d: -f1)
  if [[ -z "$runner_line" ]]; then
    ok "hook script starts no test runner (no scrub required): $base"
    continue
  fi
  RUNNER_LINES=$((RUNNER_LINES+1))
  # ORDERING is asserted, not merely presence: the old success message claimed "scrubs BEFORE
  # running a test runner" while the code checked neither order nor position.
  scrub_line=""
  while IFS=: read -r n rest; do
    okv=1
    for v in "${REQUIRED_SCRUB_VARS[@]}"; do
      [[ "$rest" =~ (^|[[:space:]])(-u[[:space:]]+)?${v}([[:space:]]|$) ]] || { okv=0; break; }
    done
    if (( okv == 1 )); then scrub_line="$n"; break; fi
  done < <(printf '%s\n' "$body" | grep -nE '^[[:space:]]*(unset|env)[[:space:]]')
  if [[ -n "$scrub_line" ]] && (( scrub_line < runner_line )); then
    ok "hook script scrubs (line $scrub_line) before its runner (line $runner_line): $base"
  else
    bad "hook script starts a test runner with NO effective scrub before it: $base"
  fi
done < <(find "$HOOKS_DIR" -type f | sort)

printf '\n=== the existing scrub copy on main (N2) ===\n'
TEST_ALL="$REPO_ROOT/scripts/test-all.sh"
if [[ -f "$TEST_ALL" ]]; then
  ta_body="$(sed 's/[[:space:]]*#.*$//' "$TEST_ALL")"
  # Find the unset STATEMENT first, then test each name as a word within it. Testing each name
  # against the whole file with a leading-space requirement can never match the FIRST name, which
  # sits immediately after `unset ` with no space before it — the check would have reported the
  # correct file as unscrubbed.
  ta_line="$(printf '%s\n' "$ta_body" | grep -E '^[[:space:]]*unset[[:space:]]+GIT_' | head -1)"
  ta_ok=1
  if [[ -z "$ta_line" ]]; then
    ta_ok=0
  else
    for v in "${REQUIRED_SCRUB_VARS[@]}"; do
      [[ " $ta_line " == *" $v "* ]] || ta_ok=0
    done
  fi
  if (( ta_ok == 1 )); then
    ok "scripts/test-all.sh unsets the full git-location family (N2)"
  else
    bad "scripts/test-all.sh does NOT unset the full git-location family (N2)"
  fi
else
  bad "scripts/test-all.sh not found (N2)"
fi

printf '\n=== corpus floors (N5, N6) ===\n'
# Floors sit at the CURRENT observed reading, not one below it. A floor with one unit of slack
# absorbs exactly one silent deletion, and here the slack was the `bun test` family — the very one
# #7833 reported. Raise these deliberately when the corpus grows.
if (( RUN_LINES >= 26 )); then
  ok "examined $RUN_LINES lefthook run: commands (floor 26)"
else
  bad "examined only $RUN_LINES lefthook run: commands — corpus shrank or the parse broke (N6)"
fi
if (( RUNNER_LINES >= 3 )); then
  ok "found $RUNNER_LINES test-runner entry points (floor 3)"
else
  bad "found only $RUNNER_LINES test-runner entry points — the matcher stopped matching (N5)"
fi
if (( HOOK_FILES >= 2 )); then
  ok "examined $HOOK_FILES file(s) under scripts/hooks/ (floor 2)"
else
  bad "examined only $HOOK_FILES file(s) under scripts/hooks/ (N6)"
fi

printf '\n=== summary ===\n'
printf '  %d passed, %d failed | run-lines=%d runners=%d hook-files=%d assertions=%d\n' \
  "$PASS" "$FAIL" "$RUN_LINES" "$RUNNER_LINES" "$HOOK_FILES" "$ASSERTIONS"

MIN_ASSERTIONS=8
if (( ASSERTIONS < MIN_ASSERTIONS )); then
  printf 'FLOOR: %d assertions < %d — the guard examined less than it must\n' \
    "$ASSERTIONS" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if (( RUN_LINES < 26 || RUNNER_LINES < 3 || HOOK_FILES < 2 )); then
  printf 'FLOOR: corpus below floor (run-lines=%d runners=%d hook-files=%d)\n' \
    "$RUN_LINES" "$RUNNER_LINES" "$HOOK_FILES" >&2
  exit 1
fi
if (( FAIL > 0 )); then
  printf 'Guard 2: %d entry point(s) unscrubbed\n' "$FAIL" >&2
  exit 1
fi

# Externally-verifiable receipt. Every floor above lives INSIDE this guard, so replacing the body
# with `exit 0` deletes guard and floors together and reports success having asserted nothing — a
# guard cannot detect its own erasure from the inside. hook-git-env-receipt.test.sh runs this guard
# as a subprocess and requires this line with counts above floor. That file is a `.test.sh`, so
# SUITE_GLOBS registers it; the previous consumer was a `.mutation.sh`, which matches no glob, so
# nothing in CI read the receipt at all.
printf 'SOLEUR_GUARD2_RECEIPT run_lines=%d runners=%d hook_files=%d assertions=%d\n' \
  "$RUN_LINES" "$RUNNER_LINES" "$HOOK_FILES" "$ASSERTIONS"
exit 0
