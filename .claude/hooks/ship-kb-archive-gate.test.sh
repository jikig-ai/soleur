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
    denied_rows=$(grep -c '"event_type":"deny"' "$jsonl" 2>/dev/null || echo 0)
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
  printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null
}

# --- deny cases ------------------------------------------------------------

t01_specdir_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-leak" specdir)
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
  assert_fixture_has "T02 fixture" "$work/knowledge-base/project/plans/2026-10-12-zz-other-topic-plan.md"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T02 topic-named plan (#7383 shape)" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t03_modspec_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-mod" modspec)
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge")") || exit_code=$?
  assert_deny "T03 M row on base-live spec file" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t04_brainstorm_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-storm" brainstorm)
  assert_fixture_has "T04 fixture" "$work/knowledge-base/project/brainstorms/2026-10-12-zz-topic.md"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash")") || exit_code=$?
  assert_deny "T04 live brainstorm A row" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t05_withlock_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-lock" specdir)
  local out exit_code=0
  # The sanctioned arming form (ship emits this via session-state.sh).
  out=$(run_hook "$incidents" "$(make_payload "$work" 'bash "$SS_LIB" with_lock merge-main 600 -- gh pr merge --squash --auto')") || exit_code=$?
  assert_deny "T05 with_lock -- wrapped merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t06_envprefix_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-env" specdir)
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "FOO=1 gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T06 env-assignment prefix" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t07_pipe_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-pipe" specdir)
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "cat /dev/null | gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T07 pipe-boundary merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t08_subst_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-subst" specdir)
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "x=\$(gh pr merge --squash --auto)")") || exit_code=$?
  assert_deny "T08 paren substitution merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t09_keyword_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-kw" specdir)
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
  local out exit_code=0
  # `877"9"` survives raw but strips to 877 — the two sides disagree.
  out=$(run_hook "$incidents" "$(make_payload "$work" 'gh pr merge 877"9" --squash')") || exit_code=$?
  assert_deny "T17 raw/scan disagreement" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t18_fetchfail_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-nonet" specdir)
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
  local out exit_code=0
  # Flag-first-with-number: conservative deny; the text says to reorder.
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash 48")") || exit_code=$?
  assert_deny "T19 flag-first-with-number" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t20_multi_after_compliant_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-multi" specdir)
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
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T21 flag-only invocation takes HEAD path" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

# --- pass cases ------------------------------------------------------------

t22_archiveonly_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-arch" archive)
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T22 archive-only diff passes" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t23_archived_move_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_archived_branch "$tmp" "feat-moved")
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T23 spec dir git-mv'd under archive/ passes" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t24_learnings_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-learn" learnings)
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T24 learnings/ never gated" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t25_nonkb_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-nonkb" nonkb)
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T25 non-KB diff passes" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t26_ready_nofire_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-ready" specdir)
  local out exit_code=0
  # `gh pr ready` alone is review-readiness, never gated.
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr ready 42")") || exit_code=$?
  assert_pass "T26 gh pr ready does not fire" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t27_help_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-help" specdir)
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --help")") || exit_code=$?
  assert_pass "T27 --help pass-through" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t28_quoted_mention_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-quoted" specdir)
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "echo 'gh pr merge example'")") || exit_code=$?
  assert_pass "T28 quoted mention does not fire" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t29_commitbody_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-cbody" specdir)
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" $'git add . && git commit -m "ship note\ngh pr merge must not be hand-rolled\n"')") || exit_code=$?
  assert_pass "T29 commit-body mention does not fire" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t30_bashc_quoted_pass() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-bashc" specdir)
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
  local out exit_code=0
  out=$(printf '%s' "$(make_payload "$work" "gh pr merge --squash --auto")" \
        | SOLEUR_SKIP_KB_ARCHIVE_GATE=1 INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  assert_pass "T34 SOLEUR_SKIP_KB_ARCHIVE_GATE=1" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t35_bare_numbered_gates() {
  # A bare repo cannot take the HEAD path, but a numbered merge still
  # resolves refs/pull/<N>/head and gates (ruling: numbered merges gate on
  # every checkout state).
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-bare" specdir)
  git -C "$work" push -q origin feat-bare:refs/pull/55/head
  local bare="$tmp/bare.git" binc="$tmp/binc"
  mkdir -p "$binc"
  git init -q --bare "$bare"
  git -C "$bare" remote add origin "$origin"
  git -C "$bare" fetch -q origin main
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
  # fail-open path is never silent.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  git init -q --bare "$tmp/origin.git"
  init_git_repo "$work"
  git -C "$work" remote add origin "$tmp/origin.git"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" push -q origin main
  git -C "$work" checkout -q -b feat-shallow
  # Simulate shallow: no second commit needed — craft a head unrelated to
  # main by orphan checkout so merge-base fails.
  git -C "$work" checkout -q --orphan orphan-head
  git -C "$work" commit -q --allow-empty -m "orphan"
  local out err exit_code=0
  err=$(printf '%s' "$(make_payload "$work" "gh pr merge --squash --auto")" \
        | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>&1 >/dev/null) || exit_code=$?
  out=$(printf '%s' "$(make_payload "$work" "gh pr merge --squash --auto")" \
        | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
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
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    pass "T37 stdout is exactly one JSON object"
  else
    fail "T37 stdout failed jq parse"
  fi
  TOTAL=$((TOTAL + 1))
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
  reb=$(printf '%s\n' "$order" | grep -n "ship-unpushed-commits-gate.sh" | head -1 | cut -d: -f1)
  ship=$(printf '%s\n' "$order" | grep -n "ship-kb-archive-gate.sh" | head -1 | cut -d: -f1)
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
  reb=$(printf '%s\n' "$order" | grep -n "ship-unpushed-commits-gate.sh" | head -1 | cut -d: -f1)
  ship=$(printf '%s\n' "$order" | grep -n "ship-kb-archive-gate.sh" | head -1 | cut -d: -f1)
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

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"

# Anti-vacuity floor: exact case floor, enforced OUTSIDE the verdict
# machinery (a neutered assert cannot disarm it — guard-vacuity-floor's
# mutant contract). Threshold is hand-maintained with the case list:
# 50 assertions across 40 case invocations.
MIN_ASSERTIONS=50
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
