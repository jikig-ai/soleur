#!/usr/bin/env bash
# Fixture-based tests for ship-kb-archive-gate.sh. Asserts the hook denies
# `gh pr merge` when the merge head's diff vs origin/main carries A/M rows
# at live (non-archive) paths under knowledge-base/project/{specs/<dir>,
# plans,brainstorms}, and fail-opens/closed per the documented ladder.
#
# Isolation pattern matches ship-unpushed-commits-gate.test.sh: each test
# builds its own tmp work-tree + tmp incidents root; INCIDENTS_REPO_ROOT
# redirects the jsonl off the operator's real .claude/.rule-incidents.jsonl.

set -euo pipefail
SUITE_TMP=$(mktemp -d)
[[ "$SUITE_TMP" == /* ]] || { echo "FATAL: SUITE_TMP is not absolute: $SUITE_TMP" >&2; exit 2; }
trap 'rm -rf "$SUITE_TMP"' EXIT

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

# Byte-equal copy of the canonical assert_fixture_dir in
# plugins/soleur/test/test-helpers.sh; pinned by
# fixture-dir-operand-assert.test.sh. Do not reword it in one file only. #7652
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/ship-kb-archive-gate.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

# Terminal verdict helpers — the ONLY functions that move a verdict
# counter (ARM 10d shape: every other function's TOTAL++ then moves
# independently of the verdict, keeping PASS+FAIL == TOTAL non-tautological).
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }
command -v git >/dev/null 2>&1 || { echo "UNRESOLVED: git missing — this suite asserted nothing; install git"; exit 3; }

init_git_repo() {
  local dir="$1"
  assert_fixture_dir "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email test@test.local
  git -C "$dir" config user.name "Test User"
  git -C "$dir" config commit.gpgsign false
}

# Build a work repo with a bare origin on a feature branch carrying a LIVE
# KB artifact (the leak shape). Echoes "$work $origin $incidents".
# Variant selects which artifact the branch adds:
#   specdir      -> knowledge-base/project/specs/<branch>/tasks.md
#   topicplan    -> knowledge-base/project/plans/<date>-<other-slug>-plan.md
#   brainstorm   -> knowledge-base/project/brainstorms/<date>-topic.md
#   modspec      -> modifies a spec file that was already live at base
#   archive      -> adds only under specs/archive/ + plans/archive/
#   learnings    -> adds only knowledge-base/project/learnings/x.md
#   nonkb        -> adds only a non-KB file
#   multi        -> specs/<branch>/file + plans/<date>-<branch>-plan.md
#   clean        -> no KB artifacts at all
make_kb_branch() {
  local tmp="$1" branch="$2" variant="${3:-specdir}"
  local work="$tmp/work" origin="$tmp/origin.git" incidents="$tmp/incidents"
  assert_fixture_dir "$tmp"
  mkdir -p "$work" "$incidents"
  git init -q --bare "$origin"
  init_git_repo "$work"
  mkdir -p "$work/knowledge-base/project/specs/$branch" \
          "$work/knowledge-base/project/specs/archive" \
          "$work/knowledge-base/project/plans" \
          "$work/knowledge-base/project/brainstorms" \
          "$work/knowledge-base/project/learnings"
  echo "live at base" > "$work/knowledge-base/project/specs/$branch/spec.md"
  echo "base" > "$work/file.txt"
  git -C "$work" add -A
  git -C "$work" commit -q -m "init"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin main
  git -C "$work" checkout -q -b "$branch"
  case "$variant" in
    specdir)
      echo "tasks" > "$work/knowledge-base/project/specs/$branch/tasks.md" ;;
    topicplan)
      echo "plan" > "$work/knowledge-base/project/plans/2026-10-12-zz-other-topic-plan.md" ;;
    brainstorm)
      echo "storm" > "$work/knowledge-base/project/brainstorms/2026-10-12-zz-topic.md" ;;
    modspec)
      echo "edited live spec" >> "$work/knowledge-base/project/specs/$branch/spec.md" ;;
    archive)
      mkdir -p "$work/knowledge-base/project/specs/archive/2026-10-12-$branch"
      echo "archived" > "$work/knowledge-base/project/specs/archive/2026-10-12-$branch/spec.md"
      mkdir -p "$work/knowledge-base/project/plans/archive"
      echo "archived" > "$work/knowledge-base/project/plans/archive/2026-10-12-old-plan.md" ;;
    learnings)
      echo "l" > "$work/knowledge-base/project/learnings/2026-10-12-note.md" ;;
    nonkb)
      echo "code" > "$work/code.sh" ;;
    multi)
      echo "s" > "$work/knowledge-base/project/specs/$branch/session-state.md"
      echo "p" > "$work/knowledge-base/project/plans/2026-10-12-$branch-plan.md" ;;
    clean) ;;
  esac
  git -C "$work" add -A
  git -C "$work" commit -q --allow-empty -m "feature work"
  git -C "$work" push -qu origin "$branch"
  echo "$work $origin $incidents"
}

# Variant of the above where the branch archives its spec dir in the same
# diff — the post-archive shape: specs/<branch> git-mv'd under
# specs/archive/<ts>-<branch>/.
make_archived_branch() {
  local tmp="$1" branch="$2"
  local work origin incidents
  read -r work origin incidents < <(make_kb_branch "$tmp" "$branch" clean)
  assert_fixture_dir "$work"
  git -C "$work" mv "$work/knowledge-base/project/specs/$branch" \
    "$work/knowledge-base/project/specs/archive/2026-10-12-$branch"
  git -C "$work" add -A
  git -C "$work" commit -q -m "archive spec dir"
  git -C "$work" push -qu origin "$branch"
  echo "$work $origin $incidents"
}

make_payload() {
  local cwd="$1" cmd="$2"
  jq -nc --arg c "$cwd" --arg x "$cmd" '{tool_input: {command: $x}, cwd: $c}'
}

# assert_deny <name> <incidents_root> <stdout> <exit_code>
assert_deny() {
  local name="$1" incidents="$2" out="$3" exit_code="$4"
  local decision jsonl seen_rule seen_event count
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$incidents/.claude/.rule-incidents.jsonl"
  if [[ ! -f "$jsonl" ]]; then
    fail "$name (no incidents jsonl at $jsonl; exit=$exit_code decision=$decision)"
    TOTAL=$((TOTAL + 1)); return
  fi
  count=$(wc -l < "$jsonl" | tr -d ' ')
  seen_rule=$(jq -r '.rule_id' < "$jsonl" | head -1)
  seen_event=$(jq -r '.event_type' < "$jsonl" | head -1)
  if [[ "$exit_code" -eq 0 && "$decision" == "deny" && "$count" == "1" \
        && "$seen_rule" == "wg-kb-artifacts-archived-in-pr" && "$seen_event" == "deny" ]]; then
    pass "$name"
  else
    fail "$name"
    echo "  exit=$exit_code decision=$decision count=$count rule=$seen_rule event=$seen_event"
  fi
  TOTAL=$((TOTAL + 1))
}

# assert_pass <name> <incidents_root> <stdout> <exit_code>
assert_pass() {
  local name="$1" incidents="$2" out="$3" exit_code="$4"
  local decision jsonl
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$incidents/.claude/.rule-incidents.jsonl"
  local denied_rows=0
  if [[ -f "$jsonl" ]]; then
    denied_rows=$(grep -c '"event_type":"deny"' "$jsonl" 2>/dev/null || true)
  fi
  if [[ "$exit_code" -eq 0 && "$decision" != "deny" && "$denied_rows" -eq 0 ]]; then
    pass "$name"
  else
    fail "$name"
    echo "  exit=$exit_code decision=$decision denied_rows=$denied_rows"
  fi
  TOTAL=$((TOTAL + 1))
}

# Fixture-nonempty vacuity control: prove the fixture actually carries the
# artifact the deny is attributed to BEFORE asserting the deny — a fixture
# that produces nothing cannot silently pass a deny case either, but this
# names the broken precondition rather than reporting a gate failure.
assert_fixture_has() {
  local name="$1" abspath="$2"
  if [[ -f "$abspath" ]]; then
    pass "$name (fixture carries $abspath)"
  else
    fail "$name (fixture MISSING $abspath — the deny below is unattributable)"
  fi
  TOTAL=$((TOTAL + 1))
}

run_hook() {
  local incidents="$1" payload="$2"
  # CLAUDECODE= (empty) pins headless_or_stderr to its stderr arm — under a
  # real session it routes warns to $LOG_DIR/$PPID.log and stderr checks
  # see nothing. SOLEUR_SESSION_STATE_ROOT keeps the session-state lib's
  # mkdir side effects inside the fixture, not the real repo's .git dir.
  printf '%s' "$payload" | CLAUDECODE= SOLEUR_SESSION_STATE_ROOT="$incidents/state" \
    INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null
}

# --- deny cases ------------------------------------------------------------

t01_specdir_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-leak" specdir)
  assert_fixture_dir "$work"
  assert_fixture_dir "$work"
  assert_fixture_has "T01 fixture" "$work/knowledge-base/project/specs/feat-leak/tasks.md"
  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge --squash --auto")
  out=$(run_hook "$incidents" "$payload") || exit_code=$?
  assert_deny "T01 live spec dir" "$incidents" "$out" "${exit_code:-0}"
  local reason
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  local ok=1
  for tok in "archive-kb.sh" "step 2.5" "Operator Holds" "Phase 6.45" "git mv" "SOLEUR_SKIP_KB_ARCHIVE_GATE"; do
    [[ "$reason" == *"$tok"* ]] || { ok=0; echo "  missing deny token: $tok"; }
  done
  if [[ "$ok" == "1" ]]; then
    pass "T01b deny reason carries remediation + ordering + hatch"
  else
    fail "T01b deny reason missing tokens"
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

t02_topicplan_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-topic" topicplan)
  assert_fixture_dir "$work"
  assert_fixture_has "T02 fixture" "$work/knowledge-base/project/plans/2026-10-12-zz-other-topic-plan.md"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T02 topic-named plan (#7383 shape)" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t03_modspec_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-mod" modspec)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge")") || exit_code=$?
  assert_deny "T03 M row on base-live spec file" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t04_brainstorm_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-storm" brainstorm)
  assert_fixture_dir "$work"
  assert_fixture_has "T04 fixture" "$work/knowledge-base/project/brainstorms/2026-10-12-zz-topic.md"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash")") || exit_code=$?
  assert_deny "T04 live brainstorm A row" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t05_withlock_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-lock" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  # The sanctioned arming form (ship emits this via session-state.sh).
  out=$(run_hook "$incidents" "$(make_payload "$work" 'bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge --squash --auto')") || exit_code=$?
  assert_deny "T05 with_lock -- wrapped merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t06_envprefix_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-env" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "FOO=1 gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T06 env-assignment prefix" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t07_pipe_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-pipe" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "cat /dev/null | gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T07 pipe-boundary merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t08_subst_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-subst" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "x=\$(gh pr merge --squash --auto)")") || exit_code=$?
  assert_deny "T08 paren substitution merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t09_keyword_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-kw" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "time gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T09a time-prefixed merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$incidents"
  mkdir -p "$incidents"
  out=$(run_hook "$incidents" "$(make_payload "$work" "if gh pr merge --squash --auto; then echo merged; fi")") || exit_code=$?
  assert_deny "T09b if-prefixed merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t10_pullref_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-remote" specdir)
  assert_fixture_dir "$work"
  # Publish the leaky head as refs/pull/42/head, then sit on a CLEAN branch.
  git -C "$work" push -q origin feat-remote:refs/pull/42/head
  git -C "$work" checkout -q -b reviewer main
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge 42 --squash")") || exit_code=$?
  assert_deny "T10 gh pr merge <N> reads REMOTE pull head" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t11_pullref_clean_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-ok" clean)
  assert_fixture_dir "$work"
  git -C "$work" push -q origin feat-ok:refs/pull/43/head
  git -C "$work" checkout -q -b reviewer main
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge 43 --squash")") || exit_code=$?
  assert_pass "T11 clean remote head passes" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t12_matchhead_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-mhc" specdir)
  assert_fixture_dir "$work"
  local sha
  sha=$(git -C "$work" rev-parse HEAD)
  git -C "$work" checkout -q -b reviewer main
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --admin --match-head-commit $sha")") || exit_code=$?
  assert_deny "T12 --match-head-commit pinned sha gated" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

# Same-repo -R: origin URL must PARSE as a remote (a local-path origin
# proves nothing), yet fetch must stay local — url.insteadOf rewrites the
# fetch while config --get still reports the parseable URL. This is the
# mechanism the copied resolver is built to read.
t13_samerepo_R_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-samer" specdir)
  assert_fixture_dir "$work"
  git -C "$work" remote set-url origin "git@github.com:jikig-ai/soleur.git"
  git -C "$work" config url."$origin".insteadOf "git@github.com:jikig-ai/soleur.git"
  git -C "$work" push -q origin feat-samer:refs/pull/44/head
  git -C "$work" checkout -q -b reviewer main
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge -R jikig-ai/soleur 44 --squash")") || exit_code=$?
  assert_deny "T13 -R same-repo proven -> pull head gated" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t14_foreign_R_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-foreign" specdir)
  assert_fixture_dir "$work"
  git -C "$work" remote set-url origin "git@github.com:jikig-ai/soleur.git"
  git -C "$work" config url."$origin".insteadOf "git@github.com:jikig-ai/soleur.git"
  local out exit_code=0
  # A parseable pointer at a DIFFERENT slug: proven foreign → not ours.
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge -R some-org/other-repo 45 --squash")") || exit_code=$?
  assert_pass "T14 proven-foreign -R exits 0" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t15_unprovable_R_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-unprov" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  # -R with no operand cannot be verified → deny carrying MERGE_TARGET_WHY.
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge 46 -R")") || exit_code=$?
  assert_deny "T15 unprovable repo pointer" "$incidents" "$out" "${exit_code:-0}"
  local reason
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  if [[ "$reason" == *"repositor"* ]]; then
    pass "T15b deny carries the pointer why"
  else
    fail "T15b deny lacks the pointer why: '$reason'"
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

t16_foreign_cd_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-cd" specdir)
  assert_fixture_dir "$work"
  local foreign="$tmp/foreign"
  mkdir -p "$foreign"
  init_git_repo "$foreign"
  git -C "$foreign" remote add origin /nonexistent/foreign.git
  git -C "$foreign" commit -q --allow-empty -m "f"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "cd $foreign && gh pr merge 47 --squash")") || exit_code=$?
  assert_deny "T16 in-command cd to foreign checkout" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t17_scancmd_disagree_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-disagree" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  # `877"9"` survives raw but strips to 877 — the two sides disagree.
  out=$(run_hook "$incidents" "$(make_payload "$work" 'gh pr merge 877"9" --squash')") || exit_code=$?
  assert_deny "T17 raw/scan disagreement" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t18_fetchfail_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-nonet" specdir)
  assert_fixture_dir "$work"
  git -C "$work" remote set-url origin /nonexistent/path/to/repo.git
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T18 fetch failure fail-closed" "$incidents" "$out" "${exit_code:-0}"
  local reason
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  if [[ "$reason" == *"git fetch"* ]]; then
    pass "T18b deny reason cites fetch failure"
  else
    fail "T18b deny reason does not cite fetch: '$reason'"
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

t19_flagfirst_number_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-reorder" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  # Flag-first-with-number: conservative deny; the text says to reorder.
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash 48")") || exit_code=$?
  assert_deny "T19 flag-first-with-number" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t20_multi_after_compliant_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-multi" specdir)
  assert_fixture_dir "$work"
  # Archive the base-live spec dir AND add a second live dir: second
  # member still leaks → deny (first-member short-circuit is the class).
  mkdir -p "$work/knowledge-base/project/specs/b-second"
  echo "x" > "$work/knowledge-base/project/specs/b-second/spec.md"
  git -C "$work" add -A
  git -C "$work" commit -qm "second live dir"
  git -C "$work" push -q origin feat-multi
  assert_fixture_has "T20 fixture" "$work/knowledge-base/project/specs/b-second/spec.md"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T20 second live dir after compliant state" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t21_flagonly_headpath_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-flagonly" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T21 flag-only invocation takes HEAD path" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

# --- pass cases ------------------------------------------------------------

t22_archiveonly_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-arch" archive)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T22 archive-only diff passes" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t23_archived_move_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_archived_branch "$tmp" "feat-moved")
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T23 spec dir git-mv'd under archive/ passes" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t24_learnings_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-learn" learnings)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T24 learnings/ never gated" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t25_nonkb_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-nonkb" nonkb)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T25 non-KB diff passes" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t26_ready_nofire_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-ready" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  # `gh pr ready` alone is review-readiness, never gated.
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr ready 42")") || exit_code=$?
  assert_pass "T26 gh pr ready does not fire" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t27_help_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-help" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --help")") || exit_code=$?
  assert_pass "T27 --help pass-through" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t28_quoted_mention_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-quoted" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "echo 'gh pr merge example'")") || exit_code=$?
  assert_pass "T28 quoted mention does not fire" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t29_commitbody_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-cbody" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" $'git add . && git commit -m "ship note\ngh pr merge must not be hand-rolled\n"')") || exit_code=$?
  assert_pass "T29 commit-body mention does not fire" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t30_bashc_quoted_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-bashc" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  # Documented residual shared with every sibling: the quoted payload is
  # blanked by strip_command_bodies and does not fire.
  out=$(run_hook "$incidents" "$(make_payload "$work" "bash -c 'gh pr merge --squash'")") || exit_code=$?
  assert_pass "T30 bash -c quoted payload (documented residual)" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t31_on_main_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  # Stay on main — HEAD path exempts main even with the merge form.
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T31 HEAD path on main" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t32_detached_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  echo a > "$work/a"; git -C "$work" add a; git -C "$work" commit -qm first
  echo b > "$work/b"; git -C "$work" add b; git -C "$work" commit -qm second
  local sha; sha=$(git -C "$work" rev-parse HEAD)
  git -C "$work" checkout -q "$sha"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T32 detached HEAD path" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t33_nongitdir_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  local work="$tmp/nowork" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T33 non-git dir" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t34_skip_env_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-skip" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(printf '%s' "$(make_payload "$work" "gh pr merge --squash --auto")" \
        | SOLEUR_SKIP_KB_ARCHIVE_GATE=1 CLAUDECODE= SOLEUR_SESSION_STATE_ROOT="$incidents/state" INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  assert_pass "T34 SOLEUR_SKIP_KB_ARCHIVE_GATE=1" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t35_bare_numbered_gates() {
  # A bare repo cannot take the HEAD path, but a numbered merge still
  # resolves refs/pull/<N>/head and gates (ruling: numbered merges gate on
  # every checkout state).
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-bare" specdir)
  assert_fixture_dir "$work"
  git -C "$work" push -q origin feat-bare:refs/pull/55/head
  local bare="$tmp/bare.git" binc="$tmp/binc"
  mkdir -p "$binc"
  git init -q --bare "$bare"
  git -C "$bare" remote add origin "$origin"
  git -C "$bare" fetch -q --no-tags origin main
  local out exit_code=0
  out=$(run_hook "$binc" "$(make_payload "$bare" "gh pr merge 55 --squash")") || exit_code=$?
  assert_deny "T35 bare repo still gates a numbered merge" "$binc" "$out" "${exit_code:-0}"
  # and the flag-only HEAD path correctly exempts the bare checkout:
  rm -rf "$binc"; mkdir -p "$binc"
  out=$(run_hook "$binc" "$(make_payload "$bare" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T35b bare repo exempts the HEAD path" "$binc" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t36_shallow_warn_pass() {
  # Unresolvable merge-base: exit 0 WITH a headless_or_stderr warn — the
  # fail-open path is never silent. The head the gate censuses is
  # origin/<branch>, so the unrelated history must be PUSHED, not local.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  git init -q --bare "$tmp/origin.git"
  init_git_repo "$work"
  git -C "$work" remote add origin "$tmp/origin.git"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" push -q origin main
  # Orphan history pushed as the branch's remote head: merge-base with
  # origin/main is empty — the shallow-clone class the warn covers.
  git -C "$work" checkout -q --orphan orphan-head
  git -C "$work" commit -q --allow-empty -m "orphan"
  git -C "$work" push -q origin orphan-head
  local out err exit_code=0
  err=$(printf '%s' "$(make_payload "$work" "gh pr merge --squash --auto")" \
        | CLAUDECODE= SOLEUR_SESSION_STATE_ROOT="$incidents/state" INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>&1 >/dev/null) || exit_code=$?
  out=$(printf '%s' "$(make_payload "$work" "gh pr merge --squash --auto")" \
        | CLAUDECODE= SOLEUR_SESSION_STATE_ROOT="$incidents/state" INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  if [[ "$err" == *"ship-kb-archive-gate"* ]] && [[ "$err" == *"merge-base"* ]]; then
    assert_pass "T36 unresolvable merge-base warns + passes" "$incidents" "$out" "${exit_code:-0}"
  else
    fail "T36 merge-base fail-open was SILENT (err='$err')"
    TOTAL=$((TOTAL + 1))
  fi
  rm -rf "$tmp"
}

t37_stdout_json_clean() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-json" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  # jq -s 'length==1', not `jq -e .`: the latter accepts a STREAM of N
  # objects; the contract is exactly one.
  if printf '%s' "$out" | jq -s 'length == 1' -e >/dev/null 2>&1; then
    pass "T37 stdout is exactly one JSON object"
  else
    fail "T37 stdout failed jq parse or emitted a stream"
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

t44_lsremote_empty_deny() {
  # Numbered merge whose pull ref does not exist: ls-remote returns
  # nothing — unverifiable head → deny (fail-closed on the commonest
  # mis-target).
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-nopr" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge 999 --squash")") || exit_code=$?
  assert_deny "T44 ls-remote-empty numbered merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t45_unreachable_sha_deny() {
  # --match-head-commit with a sha not present and not fetchable → deny.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-badsha" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --admin --match-head-commit 0000000000000000000000000000000000000001")") || exit_code=$?
  assert_deny "T45 unreachable pinned sha" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t46_clean_sha_pass() {
  # --match-head-commit on a clean head → pass (the sha arm is not
  # deny-only).
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-mhclean" clean)
  assert_fixture_dir "$work"
  local sha out exit_code=0
  sha=$(git -C "$work" rev-parse "origin/feat-mhclean")
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --admin --match-head-commit $sha")") || exit_code=$?
  assert_pass "T46 clean pinned sha" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t47_no_upstream_pass() {
  # Flag-only merge on a branch that was never pushed: no origin/<branch>
  # exists, gh has no head to merge — the gate's subject doesn't exist.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  local work="$tmp/work" origin="$tmp/origin.git" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  git init -q --bare "$origin"
  init_git_repo "$work"
  git -C "$work" remote add origin "$origin"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" push -q origin main
  git -C "$work" checkout -q -b feat-local
  mkdir -p "$work/knowledge-base/project/specs/feat-local"
  echo "x" > "$work/knowledge-base/project/specs/feat-local/spec.md"
  git -C "$work" add -A
  git -C "$work" commit -q -m "leaky, unpushed"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T47 never-pushed branch" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t48_global_flags_deny() {
  # `gh -R o/r pr merge 5` — Cobra global flags sit between gh and pr,
  # invisible to the residue census → deny with the canonical-form hint.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-gf" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh -R jikig-ai/soleur pr merge 5")") || exit_code=$?
  assert_deny "T48 global-flag merge" "$incidents" "$out" "${exit_code:-0}"
  local reason
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  if [[ "$reason" == *"global flags"* ]]; then
    pass "T48b deny names the global-flags arm"
  else
    fail "T48b deny reason missing 'global flags': $reason"
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

t49_multi_invocation_deny() {
  # `gh pr merge --match-head-commit A && gh pr merge 6` — the sha arm's
  # precedence would swallow the second invocation's census entirely.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-multi" clean)
  assert_fixture_dir "$work"
  local sha out exit_code=0
  sha=$(git -C "$work" rev-parse "origin/feat-multi")
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --match-head-commit $sha && gh pr merge 6")") || exit_code=$?
  assert_deny "T49 second invocation uncensused" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t50_comment_pointer_still_gates() {
  # P1 regression: `# -R other/repo` is a comment, never a pointer. Before
  # the scan-side gather the raw-text operand proved "foreign" and the
  # merge passed silently. Now the comment is stripped → pr census → deny.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-cmt" specdir)
  assert_fixture_dir "$work"
  git -C "$work" push -q origin feat-cmt:refs/pull/50/head
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge 50 --squash # -R other/repo")") || exit_code=$?
  assert_deny "T50 comment -R does not foreign-exit" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t51_quoted_env_still_gates() {
  # A quoted `GH_REPO=` inside another command's string is text, never an
  # assignment — must not foreign-exit the real merge.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-qenv" specdir)
  assert_fixture_dir "$work"
  git -C "$work" push -q origin feat-qenv:refs/pull/51/head
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" 'gh pr merge 51 --squash; echo "GH_REPO=other/repo"')") || exit_code=$?
  assert_deny "T51 quoted GH_REPO does not foreign-exit" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t52_rename_R_deny() {
  # `git mv <archived> <live>` — rename detection emits R (not A), and an
  # AM-only census passes it silently. The dst path must be judged.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  local work origin incidents
  read -r work origin incidents < <(make_archived_branch "$tmp" "b-archrevive")
  assert_fixture_dir "$work"
  git -C "$work" mv "$work/knowledge-base/project/specs/archive/2026-10-12-b-archrevive" \
    "$work/knowledge-base/project/specs/b-revived"
  git -C "$work" commit -q -m "revive spec dir live"
  git -C "$work" push -qu origin "b-archrevive"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T52 rename-in to live path" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t53_subst_clean_pass() {
  # `x=$(gh pr merge 5)` leaves a `)` in the residue — after cleaning the
  # number resolves and a clean head passes (not a resolver deny).
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-subok" clean)
  assert_fixture_dir "$work"
  git -C "$work" push -q origin feat-subok:refs/pull/53/head
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "x=\$(gh pr merge 53)")") || exit_code=$?
  assert_pass "T53 substitution clean head" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t54_subshell_cd_census_pass() {
  # `(cd other-checkout; gh pr merge)` — same origin, DIFFERENT branch:
  # the gate must census the cd'd checkout's branch, not the session's.
  # Session branch is leaky; the cd'd branch is clean → pass proves the
  # miscensus is closed (a session-branch census would deny).
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-session" specdir)
  assert_fixture_dir "$work"
  git -C "$work" checkout -q -b clean-b main
  git -C "$work" push -q origin clean-b
  git -C "$work" checkout -q feat-session
  local other="$tmp/other"
  git clone -q "$origin" "$other" 2>/dev/null
  git -C "$other" config user.email t@t.local
  git -C "$other" config user.name "T"
  git -C "$other" checkout -q clean-b
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "(cd $other; gh pr merge --squash --auto)")") || exit_code=$?
  assert_pass "T54 subshell cd censuses the cd'd branch" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t55_unresolvable_cd_deny() {
  # `cd $VAR && gh pr merge` — the operand is a variable the hook cannot
  # resolve; the merge's execution checkout is unprovable → deny.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-cdvar" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" 'cd $OTHER_DIR && gh pr merge 5')") || exit_code=$?
  assert_deny "T55 variable cd operand" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t56_brace_group_deny() {
  # `{ gh pr merge 5; }` — brace-group boundary.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-brace" specdir)
  assert_fixture_dir "$work"
  git -C "$work" push -q origin feat-brace:refs/pull/56/head
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "{ gh pr merge 56 --squash; }")") || exit_code=$?
  assert_deny "T56 brace-group merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t57_launcher_args_deny() {
  # `timeout 60 gh pr merge` — argument-taking launcher prefix.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-timeout" specdir)
  assert_fixture_dir "$work"
  git -C "$work" push -q origin feat-timeout:refs/pull/57/head
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "timeout 60 gh pr merge 57 --squash")") || exit_code=$?
  assert_deny "T57 timeout-launcher merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t58_redirect_clean_pass() {
  # `gh pr merge 5 > /tmp/log` — the redirect word and target are not
  # merge operands; a clean head passes rather than false-denying on a
  # phantom positional.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-redir" clean)
  assert_fixture_dir "$work"
  git -C "$work" push -q origin feat-redir:refs/pull/58/head
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge 58 --squash > /tmp/merge-log")") || exit_code=$?
  assert_pass "T58 redirect does not false-deny" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t59_nested_archive_deny() {
  # specs/<live-dir>/archive/x.md is INSIDE a live spec dir — only
  # <root>/archive/ is exempt, not any path containing an archive/
  # component.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-nested" clean)
  assert_fixture_dir "$work"
  mkdir -p "$work/knowledge-base/project/specs/feat-nested/archive"
  echo "x" > "$work/knowledge-base/project/specs/feat-nested/archive/inner.md"
  git -C "$work" add -A
  git -C "$work" commit -q -m "nested archive"
  git -C "$work" push -qu origin feat-nested
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T59 nested archive/ under a live spec dir" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t60_mhc_no_sha_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-nosha" clean)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --match-head-commit --squash")") || exit_code=$?
  assert_deny "T60 --match-head-commit without sha" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t61_two_shas_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-twosha" clean)
  assert_fixture_dir "$work"
  local sha out exit_code=0
  sha=$(git -C "$work" rev-parse "origin/feat-twosha")
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --match-head-commit $sha $sha")") || exit_code=$?
  assert_deny "T61 two shas after --match-head-commit" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t62_unprovable_env_deny() {
  # GH_REPO with no owner/repo shape cannot be proven same or foreign →
  # unprovable → deny (T51 covered the quoted non-pointer; this is a real
  # unparseable env operand).
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-envptr" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "GH_REPO=noslash gh pr merge --squash")") || exit_code=$?
  assert_deny "T62 unparseable GH_REPO env" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t63_background_multi_deny() {
  # `gh pr merge 5 & gh pr merge 6` — a bare `&` is a command boundary
  # too; two heads, one census → deny.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-amp" clean)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge 5 & gh pr merge 6")") || exit_code=$?
  assert_deny "T63 & separated invocations" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t64_brace_cd_deny() {
  # `{ cd /foreign; gh pr merge; }` — the cd-scan shares the merge
  # boundary set, so a brace-grouped foreign cd is seen.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-bcd" clean)
  assert_fixture_dir "$work"
  local foreign="$tmp/foreign" finc="$tmp/finc"
  mkdir -p "$foreign" "$finc"
  init_git_repo "$foreign"
  git -C "$foreign" remote add origin https://github.com/other-org/other-repo.git
  git -C "$foreign" commit -q --allow-empty -m "init"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "{ cd $foreign; gh pr merge 5; }")") || exit_code=$?
  assert_deny "T64 brace-grouped foreign cd" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t65_comment_gflags_pass() {
  # `gh pr merge 5 # runbook: gh -R o/r pr merge` — the global-flags
  # detect reads the comment-stripped text; a mention must not deny.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-cmtgf" clean)
  assert_fixture_dir "$work"
  git -C "$work" push -q origin feat-cmtgf:refs/pull/65/head
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge 65 --squash # runbook: gh -R o/r pr merge")") || exit_code=$?
  assert_pass "T65 global-flags mention in comment" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t66_subdir_cd_deny() {
  # `(cd $work/subdir; gh pr merge)` — same origin, a SUBDIRECTORY: the
  # census pathspecs are cwd-relative, so without toplevel normalization
  # the diff resolves to subdir/knowledge-base/…, matches nothing, and a
  # leaky head passes vacuously. Deny proves the fix.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-subdir" specdir)
  assert_fixture_dir "$work"
  mkdir -p "$work/docs"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "(cd $work/docs; gh pr merge --squash --auto)")") || exit_code=$?
  assert_deny "T66 subdir cd still censuses the repo" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t67_trailing_cd_no_launder() {
  # `gh pr merge && cd /foreign` — a cd AFTER the merge cannot steer its
  # head; the leaky session branch must still census.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-trailcd" specdir)
  assert_fixture_dir "$work"
  local foreign="$tmp/foreign"
  mkdir -p "$foreign"
  init_git_repo "$foreign"
  git -C "$foreign" remote add origin https://github.com/other-org/other-repo.git
  git -C "$foreign" commit -q --allow-empty -m "init"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto && cd $foreign")") || exit_code=$?
  assert_deny "T67 trailing cd cannot launder" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t68_cumulative_cd_deny() {
  # `cd a && cd b && gh pr merge` — the LAST dir-change governs; chaining
  # a same-origin cd then a foreign one must deny on the foreign target,
  # not pass on the first.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-cdcd" clean)
  assert_fixture_dir "$work"
  local foreign="$tmp/foreign"
  mkdir -p "$foreign"
  init_git_repo "$foreign"
  git -C "$foreign" remote add origin https://github.com/other-org/other-repo.git
  git -C "$foreign" commit -q --allow-empty -m "init"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "cd $work && cd $foreign && gh pr merge 5")") || exit_code=$?
  assert_deny "T68 cumulative last-cd foreign" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t69_popd_deny() {
  # popd's target lives in the dir stack — unprovable → deny.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-popd" clean)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "pushd /tmp >/dev/null; popd; gh pr merge 5")") || exit_code=$?
  assert_deny "T69 popd unresolvable" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t70_xargs_deny() {
  # `echo 5 | xargs gh pr merge` — the operand rides stdin; the residue
  # is flag-only but the merge is numbered → unprovable → deny.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-xargs" clean)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "echo 5 | xargs gh pr merge")") || exit_code=$?
  assert_deny "T70 xargs stdin operand" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t71_nested_subst_deny() {
  # `gh pr merge $(gh pr merge 5)` — the inner merge is a second
  # invocation via the `(` boundary → multi-invocation deny, not a census
  # of whichever head the greedy extraction would pick.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-nest" clean)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge \$(gh pr merge 5)")") || exit_code=$?
  assert_deny "T71 nested merge invocation" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t72_cdk_word_pass() {
  # `cdk deploy && gh pr merge` — `cdk` is not `cd`; the word boundary
  # prevents a phantom dir-change from denying a clean merge.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-cdk" clean)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "cdk deploy && gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T72 cdk-prefix is not cd" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t73_var_operand_deny() {
  # `gh pr merge $PR_NUM` — the operand is a variable; excluding `$` from
  # the residue makes it read flag-only, so the raw-match detect denies
  # rather than miscensusing the session branch.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-varop" clean)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" 'gh pr merge $PR_NUM')") || exit_code=$?
  assert_deny "T73 variable merge operand" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t74_nonrepo_cd_numbered_deny() {
  # `cd /tmp && gh pr merge -R jikig-ai/soleur 5` — a numbered merge
  # resolves the remote PR even from a non-repo cwd; the non-repo exit
  # is head-path-only, so this denies.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-nrcd" clean)
  assert_fixture_dir "$work"
  git -C "$work" remote set-url origin "git@github.com:jikig-ai/soleur.git"
  git -C "$work" config url."$origin".insteadOf "git@github.com:jikig-ai/soleur.git"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "cd /tmp && gh pr merge -R jikig-ai/soleur 5")") || exit_code=$?
  assert_deny "T74 non-repo cd + numbered merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t75_subshell_scoped_cd_deny() {
  # `(cd /foreign; make) && gh pr merge` — the cd lives and dies in the
  # subshell, so it cannot steer the merge; the `)` between it and the
  # merge marks the scope unprovable → deny.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-scd" specdir)
  assert_fixture_dir "$work"
  local other="$tmp/other"
  mkdir -p "$other"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "(cd $other; make) && gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T75 subshell-scoped cd" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t76_quoted_R_body_still_gates() {
  # `gh pr merge -R jikig-ai/soleur 76 --body "-R other/repo"` — the
  # quoted foreign pointer is message text, not a pointer; without the
  # `$_cmd_args` rebind it mixes into the same-repo proof and exits 0
  # foreign. The census must deny the leaky head instead.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-bfp" specdir)
  assert_fixture_dir "$work"
  git -C "$work" remote set-url origin "git@github.com:jikig-ai/soleur.git"
  git -C "$work" config url."$origin".insteadOf "git@github.com:jikig-ai/soleur.git"
  git -C "$work" push -q origin feat-bfp:refs/pull/76/head
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" 'gh pr merge -R jikig-ai/soleur 76 --body "-R other/repo"')") || exit_code=$?
  assert_deny "T76 quoted foreign -R in --body" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

# --- registration + parity (integration) -----------------------------------

t40_settings_registration() {
  local settings="$REPO_ROOT/.claude/settings.json"
  if [[ ! -f "$settings" ]] || ! grep -q "ship-kb-archive-gate.sh" "$settings"; then
    fail "T40 ship-kb-archive-gate.sh not registered in settings.json"
    TOTAL=$((TOTAL + 1)); return
  fi
  local order reb ship
  order=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$settings" 2>/dev/null)
  reb=$(printf '%s\n' "$order" | grep -n "ship-unpushed-commits-gate.sh" | head -1 | cut -d: -f1 || true)
  ship=$(printf '%s\n' "$order" | grep -n "ship-kb-archive-gate.sh" | head -1 | cut -d: -f1 || true)
  if [[ -n "$reb" && -n "$ship" && "$ship" -gt "$reb" ]]; then
    pass "T40 settings.json registration after ship-unpushed-commits-gate"
  else
    fail "T40 ordering unpushed=$reb kb=$ship"
  fi
  TOTAL=$((TOTAL + 1))
}

t41_devin_registration() {
  local devin_cfg="$REPO_ROOT/.devin/config.json"
  if [[ ! -f "$devin_cfg" ]] || ! grep -q "ship-kb-archive-gate.sh" "$devin_cfg"; then
    fail "T41 ship-kb-archive-gate.sh missing from .devin/config.json"
    TOTAL=$((TOTAL + 1)); return
  fi
  local order reb ship
  order=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "^exec$") | .hooks[].command' "$devin_cfg" 2>/dev/null)
  reb=$(printf '%s\n' "$order" | grep -n "ship-unpushed-commits-gate.sh" | head -1 | cut -d: -f1 || true)
  ship=$(printf '%s\n' "$order" | grep -n "ship-kb-archive-gate.sh" | head -1 | cut -d: -f1 || true)
  if [[ -n "$reb" && -n "$ship" && "$ship" -gt "$reb" ]]; then
    pass "T41 .devin ^exec$ twin registered after unpushed gate"
  else
    fail "T41 .devin ordering unpushed=$reb kb=$ship"
  fi
  TOTAL=$((TOTAL + 1))
}

t42_dispositions_row() {
  local tsv="$REPO_ROOT/.claude/hooks/devin-dispositions.tsv"
  if [[ -f "$tsv" ]] && grep -qE $'^claude-settings\t\\.claude/hooks/ship-kb-archive-gate\\.sh\tPreToolUse\tBash\tbind\tdevin-tool=exec' "$tsv"; then
    pass "T42 devin-dispositions bind row present"
  else
    fail "T42 devin-dispositions.tsv lacks the bind row"
  fi
  TOTAL=$((TOTAL + 1))
}

t43_resolver_parity() {
  # The copied helpers are the ones that RUN — pin them byte-equal to the
  # source, body for body (a presence grep cannot see drift).
  local src="$REPO_ROOT/.claude/hooks/pre-merge-rebase.sh"
  local fn ok=1
  for fn in _repo_url_parts _repo_flag_operands _repo_env_operands _repo_pointers_same_repo _strip_repo_flags; do
    local a b
    a=$(awk -v f="$fn" '$0 ~ "^"f"\\(\\) \\{" {on=1} on{print} on&&/^}/{exit}' "$src")
    b=$(awk -v f="$fn" '$0 ~ "^"f"\\(\\) \\{" {on=1} on{print} on&&/^}/{exit}' "$HOOK")
    if [[ -z "$a" || -z "$b" || "$a" != "$b" ]]; then
      ok=0
      echo "  parity FAIL: $fn body differs from pre-merge-rebase.sh (or missing)"
    fi
  done
  if [[ "$ok" == "1" ]]; then
    pass "T43 resolver helpers byte-equal to pre-merge-rebase.sh"
  else
    fail "T43 resolver helper drift"
  fi
  TOTAL=$((TOTAL + 1))
}

t01_specdir_deny
t02_topicplan_deny
t03_modspec_deny
t04_brainstorm_deny
t05_withlock_deny
t06_envprefix_deny
t07_pipe_deny
t08_subst_deny
t09_keyword_deny
t10_pullref_deny
t11_pullref_clean_pass
t12_matchhead_deny
t13_samerepo_R_deny
t14_foreign_R_pass
t15_unprovable_R_deny
t16_foreign_cd_deny
t17_scancmd_disagree_deny
t18_fetchfail_deny
t19_flagfirst_number_deny
t20_multi_after_compliant_deny
t21_flagonly_headpath_deny
t22_archiveonly_pass
t23_archived_move_pass
t24_learnings_pass
t25_nonkb_pass
t26_ready_nofire_pass
t27_help_pass
t28_quoted_mention_pass
t29_commitbody_pass
t30_bashc_quoted_pass
t31_on_main_pass
t32_detached_pass
t33_nongitdir_pass
t34_skip_env_pass
t35_bare_numbered_gates
t36_shallow_warn_pass
t37_stdout_json_clean
t40_settings_registration
t41_devin_registration
t42_dispositions_row
t43_resolver_parity
t44_lsremote_empty_deny
t45_unreachable_sha_deny
t46_clean_sha_pass
t47_no_upstream_pass
t48_global_flags_deny
t49_multi_invocation_deny
t50_comment_pointer_still_gates
t51_quoted_env_still_gates
t52_rename_R_deny
t53_subst_clean_pass
t54_subshell_cd_census_pass
t55_unresolvable_cd_deny
t56_brace_group_deny
t57_launcher_args_deny
t58_redirect_clean_pass
t59_nested_archive_deny
t60_mhc_no_sha_deny
t61_two_shas_deny
t62_unprovable_env_deny
t63_background_multi_deny
t64_brace_cd_deny
t65_comment_gflags_pass
t66_subdir_cd_deny
t67_trailing_cd_no_launder
t68_cumulative_cd_deny
t69_popd_deny
t70_xargs_deny
t71_nested_subst_deny
t72_cdk_word_pass
t73_var_operand_deny
t74_nonrepo_cd_numbered_deny
t75_subshell_scoped_cd_deny
t76_quoted_R_body_still_gates

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"

# Anti-vacuity floor: exact case floor, enforced OUTSIDE the verdict
# machinery (a neutered assert cannot disarm it — guard-vacuity-floor's
# mutant contract). Threshold is hand-maintained with the case list:
# 84 assertions across 74 case invocations — 74 case verdicts + 4
# assert_fixture_has preconditions (T01/T02/T04/T20) + 6 second-verdict
# arms (T01b/T09b/T15b/T18b/T35b/T48b).
MIN_ASSERTIONS=84
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] vacuity floor: only %d assertions ran (floor %d) — the suite did not execute\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi

# Accounting conservation: every case produced exactly one verdict — a case
# that exits without asserting is invisible to PASS+FAIL alone.
if [[ $((PASS + FAIL)) -ne $TOTAL ]]; then
  printf '[FATAL] accounting: PASS+FAIL (%d) != TOTAL (%d) — a case produced no verdict\n' "$((PASS + FAIL))" "$TOTAL" >&2
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
