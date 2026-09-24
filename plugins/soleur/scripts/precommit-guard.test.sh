#!/usr/bin/env bash
#
# Tests for precommit-guard.sh — the hook-independent commit-on-main refusal
# (Soleur Cloud Mode, FR5).
#
# WHY THIS SUITE EXISTS. The guard exists because hooks do not run in cloud
# sessions, so the refusal has to be structural in the command path. Its two
# failure directions are asymmetric: a missed `git commit` on main silently
# re-opens the bypass the script exists to close (fail-open), while a false
# refusal on a feature branch breaks every legitimate commit a skill makes.
# Both directions get arms.
#
# EVERY ARM RUNS AGAINST THROWAWAY REPOS. The guard itself never writes — it
# only runs `rev-parse` — but the fixtures need a real first commit to give
# the branch a resolvable name, so they are built here and never in-tree.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$DIR/precommit-guard.sh"

# assert_fixture_dir lives here; it is the guard the fixture scanners
# (fixture-relative-assert, fixture-dir-operand-assert) recognize. The source
# sets -euo pipefail, so the +e below restores this suite's prior contract.
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$DIR/../test/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

TMP="$(mktemp -d -t precg.XXXXXXXX)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
CASES=0

pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
  return 0
}

assert() {
  CASES=$((CASES + 1))
  if eval "$2"; then
    pass "$1"
  else
    fail "$1" "${3:-$2}"
  fi
}

printf '\n=== precommit-guard commit-on-main refusal ===\n\n'

[[ -f "$SUT" ]] || {
  printf '\n[FATAL] SUT missing at %s — nothing to test.\n' "$SUT" >&2
  exit 1
}

# A repo needs a first commit before `rev-parse --abbrev-ref HEAD` can name a
# branch — an unborn HEAD resolves to nothing and the guard has no branch to
# refuse on. Local config, not `-c`: the fixture commits are ours but the
# environment a later suite process inherits must not carry a synthesized
# identity into a repo it did not create.
new_repo() { # $1 = name, $2 = branch to leave checked out
  local d="$TMP/$1"; mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email soleur-test@example.invalid
  git -C "$d" config user.name  "Soleur Test"
  git -C "$d" config commit.gpgsign false
  git -C "$d" commit -q --allow-empty -m "base"
  [[ "$2" != "main" ]] && git -C "$d" checkout -q -b "$2"
  printf '%s' "$d"
}

# Bound as $TMP derivations rather than captured from new_repo's stdout: the
# fixture scanners resolve a `VAR="$TMP/x"` binding to the mktemp-abs root, but a
# `VAR="$(new_repo …)"` call resolves inside new_repo's body where the top-level
# $TMP binding is invisible, so the cp destinations below scanned never-bound.
MAIN_REPO="$TMP/on-main";    new_repo on-main    main   >/dev/null
FEAT_REPO="$TMP/on-feat";    new_repo on-feat    feat-x >/dev/null
OTHER_MAIN="$TMP/other-main"; new_repo other-main main  >/dev/null
# Belt for the scanner's suspenders: refuse an empty or relative root outright
# before it reaches a cp destination or a `git -C` operand below.
assert_fixture_dir "$MAIN_REPO"
assert_fixture_dir "$FEAT_REPO"
assert_fixture_dir "$OTHER_MAIN"
# A repo that failed to build would make run_guard's `cd` exit non-zero, which
# reads as a refusal (rc=1) in every "denied" arm below — a silent PASS. Prove
# the fixtures exist before any arm can inherit the failure.
for _repo in "$MAIN_REPO" "$FEAT_REPO" "$OTHER_MAIN"; do
  [[ -d "$_repo/.git" ]] || { echo "FATAL: fixture repo missing at $_repo" >&2; exit 2; }
done

run_guard() { # $1 = command string, $2 = cwd to run the guard from
  (cd "$2" && bash "$SUT" "$1" 2>/dev/null)
}

# ── Baseline: the refusal fires at all ───────────────────────────────────────
run_guard 'git commit -m x' "$MAIN_REPO"; rc=$?
assert "plain 'git commit' on main is refused (exit 1)" '[[ $rc -eq 1 ]]' "rc=$rc"

run_guard 'git commit -m x' "$FEAT_REPO"; rc=$?
assert "plain 'git commit' on a feature branch is allowed" '[[ $rc -eq 0 ]]' "rc=$rc"

run_guard 'git status' "$MAIN_REPO"; rc=$?
assert "a non-commit command on main is allowed" '[[ $rc -eq 0 ]]' "rc=$rc"

# ── Chain operators: a commit can hide anywhere in the chain ─────────────────
run_guard 'git add -A && git commit -m x' "$MAIN_REPO"; rc=$?
assert "&&-chained commit on main is refused" '[[ $rc -eq 1 ]]' "rc=$rc"

run_guard 'false || git commit -m x' "$MAIN_REPO"; rc=$?
assert "||-chained commit on main is refused" '[[ $rc -eq 1 ]]' "rc=$rc"

run_guard 'git add -A; git commit -m x' "$MAIN_REPO"; rc=$?
assert ";-chained commit on main is refused" '[[ $rc -eq 1 ]]' "rc=$rc"

run_guard 'printf msg | git commit -F -' "$MAIN_REPO"; rc=$?
assert "commit behind a pipe on main is refused" '[[ $rc -eq 1 ]]' "rc=$rc"

# ── Prefixes and launchers ───────────────────────────────────────────────────
# LEFTHOOK=0 is a repo-sanctioned invocation (skills use it for intermediate
# commits); an env prefix must not exempt the commit from the branch check.
run_guard 'LEFTHOOK=0 git commit -m x' "$MAIN_REPO"; rc=$?
assert "env-assignment prefix does not exempt the commit" '[[ $rc -eq 1 ]]' "rc=$rc"

run_guard 'sudo git commit -m x' "$MAIN_REPO"; rc=$?
assert "sudo launcher does not exempt the commit" '[[ $rc -eq 1 ]]' "rc=$rc"

run_guard 'env GIT_AUTHOR_NAME=x git commit -m x' "$MAIN_REPO"; rc=$?
assert "env launcher with its own assignment does not exempt the commit" '[[ $rc -eq 1 ]]' "rc=$rc"

# ── Repo selection: -C / --git-dir attached to the commit win ───────────────
# The load-bearing case is the MIXED chain: the cd points one way, the -C on
# the commit points another. Resolving the cd's repo would refuse (or allow)
# the wrong repository.
run_guard "git -C $MAIN_REPO commit -m x" "$FEAT_REPO"; rc=$?
assert "git -C <main> from a feature cwd is refused" '[[ $rc -eq 1 ]]' "rc=$rc"

run_guard "git -C $FEAT_REPO commit -m x" "$MAIN_REPO"; rc=$?
assert "git -C <feature> from a main cwd is allowed (own -C beats ambient)" '[[ $rc -eq 0 ]]' "rc=$rc"

run_guard "cd $FEAT_REPO && git -C $MAIN_REPO commit -m x" "$MAIN_REPO"; rc=$?
assert "commit segment's own -C wins over the chain's cd" '[[ $rc -eq 1 ]]' "rc=$rc"

run_guard "cd $MAIN_REPO && git commit -m x" "$FEAT_REPO"; rc=$?
assert "a cd into a main checkout earlier in the chain is refused" '[[ $rc -eq 1 ]]' "rc=$rc"

run_guard "git -C $FEAT_REPO commit -m x && git -C $OTHER_MAIN commit -m x" "$FEAT_REPO"; rc=$?
assert "mixed -C chain refuses when ANY commit lands on main" '[[ $rc -eq 1 ]]' "rc=$rc"

# ── --git-dir and GIT_DIR ────────────────────────────────────────────────────
run_guard "git --git-dir=$MAIN_REPO/.git commit -m x" "$FEAT_REPO"; rc=$?
assert "--git-dir=<main>/.git is refused" '[[ $rc -eq 1 ]]' "rc=$rc"

run_guard "GIT_DIR=$MAIN_REPO/.git git commit -m x" "$FEAT_REPO"; rc=$?
assert "GIT_DIR env prefix to <main>/.git is refused" '[[ $rc -eq 1 ]]' "rc=$rc"

# ── --cwd flag ──────────────────────────────────────────────────────────────
out="$(cd "$FEAT_REPO" && bash "$SUT" --cwd "$MAIN_REPO" 'git commit -m x' 2>/dev/null)"; rc=$?
assert "--cwd <main> with no in-command dir is refused" '[[ $rc -eq 1 ]]' "rc=$rc out=$out"

# ── Declared limits are allowed, not misdetected ────────────────────────────
run_guard 'git commit-tree HEAD -m x' "$MAIN_REPO"; rc=$?
assert "git commit-tree is out of declared scope (allowed)" '[[ $rc -eq 0 ]]' "rc=$rc"

run_guard 'git merge --no-commit feature' "$MAIN_REPO"; rc=$?
assert "merge --no-commit is out of declared scope (allowed)" '[[ $rc -eq 0 ]]' "rc=$rc"

# ── Usage errors ────────────────────────────────────────────────────────────
out="$(bash "$SUT" --bogus 'git commit' 2>&1)"; rc=$?
assert "unknown flag exits 2" '[[ $rc -eq 2 ]]' "rc=$rc out=$out"

# ── End-to-end through the .claude hook ──────────────────────────────────────
# The canonical script is only half the control: the hook must RECOGNIZE the
# command shapes the script refuses. A trigger regex narrower than COMMIT_RE
# leaves arms the script could refuse never reached. These arms feed real
# envelopes through the hook on fixture repos.
#
# The hand-ported hook mirror these arms were originally doubled against was retired
# on 2026-09-23 (ADR-245, closes #8306); only the `.claude` half remains.
REPO_ROOT="$(cd "$DIR/../.." && git rev-parse --show-toplevel)"
CLAUDE_HOOK="$REPO_ROOT/.claude/hooks/guardrails.sh"

# The .claude hook delegates to the plugin script when it can resolve it —
# `$REPO_ROOT/plugins/soleur/scripts/precommit-guard.sh` under the hook's own
# rev-parse root. The fixture gets a copy so BOTH paths (delegation and the
# inline fallback on a repo without the plugin tree) are exercised.
mkdir -p "$MAIN_REPO/plugins/soleur/scripts" "$FEAT_REPO/plugins/soleur/scripts"
cp "$SUT" "$MAIN_REPO/plugins/soleur/scripts/precommit-guard.sh"
cp "$SUT" "$FEAT_REPO/plugins/soleur/scripts/precommit-guard.sh"

if command -v jq >/dev/null 2>&1 && [[ -f "$CLAUDE_HOOK" ]]; then

  # .claude envelope: {tool_name:"Bash", tool_input:{command}, cwd} — allow is
  # EMPTY output; deny is a permissionDecision JSON. INCIDENTS_REPO_ROOT
  # sandboxes the incident ledger to a scratch dir.
  claude_decision() { # $1 = command, $2 = cwd
    local out
    out="$(jq -nc --arg c "$1" --arg w "$2" \
      '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}' \
      | (cd "$2" && INCIDENTS_REPO_ROOT="$TMP/incidents" bash "$CLAUDE_HOOK" 2>/dev/null))"
    if [[ -z "${out//[[:space:]]/}" ]]; then echo "allow"; return; fi
    printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo "<jq-fail>"
  }

  d="$(claude_decision 'git commit -m x' "$MAIN_REPO")"
  assert "claude hook: plain commit on main denies (delegated)" '[[ "$d" == "deny" ]]' "got: '$d'"

  d="$(claude_decision 'LEFTHOOK=0 git commit -m x' "$MAIN_REPO")"
  assert "claude hook: env-prefix commit on main denies (regex parity)" '[[ "$d" == "deny" ]]' "got: '$d'"

  d="$(claude_decision 'git commit -m x' "$FEAT_REPO")"
  assert "claude hook: commit on feature branch allows" '[[ "$d" == "allow" ]]' "got: '$d'"

  d="$(claude_decision "git -C $FEAT_REPO commit -m x" "$MAIN_REPO")"
  assert "claude hook: -C feature from a main cwd allows" '[[ "$d" == "allow" ]]' "got: '$d'"

else
  # One placeholder per arm inside the `if`, so a missing jq or hook fails the
  # suite loudly instead of quietly shrinking the assertion count past the floor.
  for _ in 1 2 3 4; do
    CASES=$((CASES + 1)); fail "hook end-to-end arms skipped (jq or the .claude hook missing)"
  done
fi

# ── Accounting conservation (ADR-193 #3) ─────────────────────────────────────
if [[ $((passes + fails)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != CASES (%d).\n' \
    "$((passes + fails))" "$CASES" >&2
  printf '\n=== precommit-guard: %d passed, %d failed (%d assertions) ===\n\n' \
    "$passes" "$fails" "$CASES"
  exit 1
fi

# ── Anti-vacuity floor (ADR-193 #1) ──────────────────────────────────────────
# Ratchet when adding arms; read a floor failure on an otherwise-green run as
# "you added assertions, update this number".
#
# Lowered 30 -> 25 on 2026-09-23 when the hand-ported hook mirror was retired
# (ADR-245, closes #8306): its five end-to-end hook arms went with it. The floor
# is the new MEASURED count — nothing else shrank.
PRECOMMIT_MIN_ASSERTIONS=25
if (( CASES < PRECOMMIT_MIN_ASSERTIONS )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$CASES" "$PRECOMMIT_MIN_ASSERTIONS" >&2
  printf '\n=== precommit-guard: %d passed, %d failed (%d assertions) ===\n\n' \
    "$passes" "$fails" "$CASES"
  exit 1
fi

printf '\n=== precommit-guard: %d passed, %d failed (%d assertions) ===\n\n' \
  "$passes" "$fails" "$CASES"
