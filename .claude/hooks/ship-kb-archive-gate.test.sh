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
    specflat)
      echo "flat" > "$work/knowledge-base/project/specs/2026-10-12-loose-note.md" ;;
    gitkeep)
      echo "" > "$work/knowledge-base/project/specs/.gitkeep" ;;
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

# assert_deny_why <name> <incidents_root> <stdout> <exit_code> <substring> —
# assert_deny plus the reason: a deny row that does not name WHICH arm fired
# would pass on any deny, including one from an arm the row never targets.
assert_deny_why() {
  local name="$1" incidents="$2" out="$3" exit_code="$4" want="$5"
  local decision reason jsonl count=0 seen_rule="" seen_event=""
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
  jsonl="$incidents/.claude/.rule-incidents.jsonl"
  if [[ -f "$jsonl" ]]; then
    count=$(wc -l < "$jsonl" | tr -d ' ')
    seen_rule=$(jq -r '.rule_id' < "$jsonl" | head -1)
    seen_event=$(jq -r '.event_type' < "$jsonl" | head -1)
  fi
  if [[ -n "$want" && "$exit_code" -eq 0 && "$decision" == "deny" && "$reason" == *"$want"* && "$count" == "1" \
        && "$seen_rule" == "wg-kb-artifacts-archived-in-pr" && "$seen_event" == "deny" ]]; then
    pass "$name"
  else
    fail "$name"
    echo "  exit=$exit_code decision=$decision count=$count want-reason='$want'"
    echo "  reason=${reason:0:240}"
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
  # CLAUDECODE='' (empty) pins headless_or_stderr to its stderr arm — under a
  # real session it routes warns to $LOG_DIR/$PPID.log and stderr checks
  # see nothing. SOLEUR_SESSION_STATE_ROOT keeps the session-state lib's
  # mkdir side effects inside the fixture, not the real repo's .git dir.
  printf '%s' "$payload" | CLAUDECODE='' SOLEUR_SESSION_STATE_ROOT="$incidents/state" \
    INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null
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

t06b_rtk_deny() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-rtk" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "rtk gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T06b rtk-prefixed merge (#10248)" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$incidents"; mkdir -p "$incidents"
  out=$(run_hook "$incidents" "$(make_payload "$work" "rtk run gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T06b2 rtk run exec-form merge (#10248)" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$incidents"; mkdir -p "$incidents"
  out=$(run_hook "$incidents" "$(make_payload "$work" "rtk-foo gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T06b3 rtk-foo glued suffix is not rtk (#10248)" "$incidents" "$out" "${exit_code:-0}"
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
        | SOLEUR_SKIP_KB_ARCHIVE_GATE=1 CLAUDECODE='' SOLEUR_SESSION_STATE_ROOT="$incidents/state" INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
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
        | CLAUDECODE='' SOLEUR_SESSION_STATE_ROOT="$incidents/state" INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>&1 >/dev/null) || exit_code=$?
  out=$(printf '%s' "$(make_payload "$work" "gh pr merge --squash --auto")" \
        | CLAUDECODE='' SOLEUR_SESSION_STATE_ROOT="$incidents/state" INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
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

# --- advisor-pass residuals: quoted/IFS spellings + specs depth-1 ----------

t77_quoted_subcommand_deny() {
  # `gh pr 'merge'` — a whole-WORD quote after `pr` survives
  # strip_command_bodies only as a blank, so the trigger misses while gh
  # would execute it. The miss-arm detect denies the unparseable form.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-qsc" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr 'merge' --squash")") || exit_code=$?
  assert_deny "T77a gh pr 'merge'" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$incidents"
  mkdir -p "$incidents"
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh 'pr' merge --squash")") || exit_code=$?
  assert_deny "T77b gh 'pr' merge" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t78_ifs_split_deny() {
  # `gh${IFS}pr${IFS}merge` and `gh pr${IFS}merge` — IFS-joined tokens
  # carry no whitespace for the trigger and expand correctly for gh.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-ifs" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" 'gh${IFS}pr${IFS}merge')") || exit_code=$?
  assert_deny "T78a gh IFS-joined" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$incidents"
  mkdir -p "$incidents"
  out=$(run_hook "$incidents" "$(make_payload "$work" 'gh pr${IFS}merge')") || exit_code=$?
  assert_deny "T78b pr IFS-joined" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t79_specflat_deny() {
  # A depth-1 file committed flat at specs/<file>.md — unconventional but
  # leaks just the same; only specs/.gitkeep stays exempt.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-flat" specflat)
  assert_fixture_dir "$work"
  assert_fixture_has "T79 fixture" "$work/knowledge-base/project/specs/2026-10-12-loose-note.md"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_deny "T79 depth-1 specs/ file" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t80_gitkeep_pass() {
  # specs/.gitkeep is the repo's own live flat file — exempt, not a leak.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-gk" gitkeep)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr merge --squash --auto")") || exit_code=$?
  assert_pass "T80 specs/.gitkeep exempt" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t81_quoted_string_pass() {
  # `echo 'gh pr merge'` — a fully-quoted documentation string carries its
  # quote BEFORE `gh`, not inside the subcommand tokens; the miss-arm
  # detect must not deny prose. Regression guard for the detect's width.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-echo" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" "echo 'gh pr merge --squash --auto'")") || exit_code=$?
  assert_pass "T81a quoted prose string" "$incidents" "$out" "${exit_code:-0}"
  # `gh pr view --jq '.title'` — non-merge call whose quotes sit AFTER the
  # subcommand tokens; must stay exempt.
  out=$(run_hook "$incidents" "$(make_payload "$work" "gh pr view 5 --jq '.title'")") || exit_code=$?
  assert_pass "T81b gh pr view --jq" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

t82_partial_word_quote_pass() {
  # `gh pr m"erge"` — mid-word quoting slips the detect (documented
  # residual, header list). Pinned as pass so a future tightening changes
  # a test, not the corpus silently.
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-pwq" specdir)
  assert_fixture_dir "$work"
  local out exit_code=0
  out=$(run_hook "$incidents" "$(make_payload "$work" 'gh pr m"erge" --squash')") || exit_code=$?
  assert_pass "T82 partial-word quote (documented residual)" "$incidents" "$out" "${exit_code:-0}"
  rm -rf "$tmp"
}

# --- Guard 1: the documented arm form, and nothing wider (T83+) ------------
# Plan 2026-11-28-fix-ship-poll-stderr-missing-check-kb-gate, `## Guard
# Contract` → Guard 1. Row names carry the matrix id (G1-r<n>, G1-H-<x>) so
# every matrix and harness row is findable by name. The arm sites are NEVER
# restated here: the site list is parsed out of arm-check-sites.test.sh and
# each span is extracted from the live skill text, so a doc edit that moves an
# arm re-runs these rows on the new text.
G1_SITES_SUITE="$REPO_ROOT/plugins/soleur/test/arm-check-sites.test.sh"
G1_PR=4387   # synthesized fixture PR number; substituted for every placeholder token

# g1_parse_sites <suite-file> — "<kind><TAB><relpath>" per site: `auto` for
# SITES and CANON (the --auto arms), `admin` for LINK_ONLY (the admin hatch).
# Any of the three assignments missing or empty → FATAL on stderr, rc 2:
# a renamed array must never read as a zero-row pass.
g1_parse_sites() {
  local f="$1" sites link canon
  sites=$(awk '/^SITES=\(/{on=1; next} on && /^\)/{exit} on{gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "") print}' "$f" 2>/dev/null || true)
  link=$(sed -nE 's/^LINK_ONLY=\(([^)]*)\)[[:space:]]*(#.*)?$/\1/p' "$f" 2>/dev/null | tr ' ' '\n' | grep -v '^$' || true)
  canon=$(sed -nE 's/^CANON=([^[:space:]]+)[[:space:]]*$/\1/p' "$f" 2>/dev/null || true)
  if [[ -z "$sites" || -z "$link" || -z "$canon" ]]; then
    printf 'FATAL: site list empty in %s (SITES=%s LINK_ONLY=%s CANON=%s)\n' "$f" \
      "$(grep -c . <<<"$sites" || true)" "$(grep -c . <<<"$link" || true)" "$(grep -c . <<<"$canon" || true)" >&2
    return 2
  fi
  { sed 's/^/auto\t/' <<<"$sites"; printf 'auto\t%s\n' "$canon"; sed 's/^/admin\t/' <<<"$link"; }
}

# g1_extract <root> <kind> <relpath> <outdir> — writes one file per arm span
# (placeholders <number>/<N>/<pr-number>/PR_NUMBER → $G1_PR) and prints each
# path. An arm span is a fenced block one of whose lines INVOKES the merge (it
# carries `gh pr merge` and `--match-head-commit`, is not a comment, and its
# `gh pr merge` sits outside double quotes: the Phase 7 fence's echo naming
# the hatch is a mention), or an inline-code span that starts with
# `gh pr merge` and gives --match-head-commit an operand (the dequeue site;
# prose such as `gh pr merge --admin --match-head-commit` is not an arm).
# For `admin` (LINK_ONLY) sites the span is the fence's invoking statement,
# not the whole fence: that fence runs inside a Monitor, where no merge gate
# is bound, and its `echo "… (gh pr merge failed …)"` text reads as a second
# invocation on the raw side. The Bash-visible merge is the `err=$(…)` line.
g1_extract() {
  python3 -I - "$@" "$G1_PR" <<'PY'
import os, re, sys
root, kind, rel, outdir, pr = sys.argv[1:6]
TOK = ("gh pr merge", "--match-head-commit")
PH = re.compile(r"<number>|<N>|<pr-number>|PR_NUMBER")
INLINE = re.compile(r"^gh pr merge .*--match-head-commit\s+\S")
def invokes(line):
    if not all(t in line for t in TOK) or line.lstrip().startswith("#"):
        return False
    return line[:line.index(TOK[0])].count('"') % 2 == 0
spans = []
with open(os.path.join(root, rel), encoding="utf-8") as fh:
    lines = fh.read().split("\n")
fence, body, ind = None, [], 0
for line in lines:
    m = re.match(r"([ \t]*)(`{3,}|~{3,})(.*)$", line)
    if m and fence is None:
        fence, body, ind = (m.group(2)[0], len(m.group(2))), [], len(m.group(1))
        continue
    if m and fence and m.group(2)[0] == fence[0] and len(m.group(2)) >= fence[1] and not m.group(3).strip():
        hits = [b for b in body if invokes(b)]
        if hits:
            spans.append("\n".join(hits if kind == "admin" else body))
        fence = None
        continue
    if fence:
        body.append(line[ind:] if line[:ind].strip() == "" else line.lstrip())
        continue
    spans += [s for s in re.findall(r"`([^`]+)`", line) if INLINE.match(s)]
for k, s in enumerate(spans):
    p = os.path.join(outdir, "%s-%d.txt" % (re.sub(r"[^A-Za-z0-9]+", "_", rel), k))
    with open(p, "w", encoding="utf-8") as out:
        out.write(PH.sub(pr, s))
    print(p)
PY
}

# g1_site_spans <root> <kind> <relpath> <outdir> — g1_extract, then the
# per-site count pin: every listed site carries exactly ONE arm span (one
# --auto lock block / arm line per site, one admin merge statement). Any other
# count → FATAL naming the file and the extraction anchor, rc 3.
g1_site_spans() {
  local got n
  got=$(g1_extract "$@") || { printf 'FATAL: %s: span extractor failed (python)\n' "$3" >&2; return 3; }
  n=$(grep -c . <<<"$got" || true)
  if [[ "$n" != "1" ]]; then
    printf 'FATAL: %s: extracted %s spans, want 1 (anchor: a fenced or inline-code span invoking gh pr merge with --match-head-commit)\n' "$3" "$n" >&2
    return 3
  fi
  printf '%s\n' "$got"
}

# g1_fixture <tmp> archived|live — a feature head published as
# refs/pull/{4387,5,6}/head, origin parseable as jikig-ai/soleur (insteadOf
# keeps the fetch local, T13 mechanism). `archived` = the post-archive diff
# as PRs 4387 and 5, and a DIFFERENT, live head as PR 6 (so a census that
# reads the wrong PR number cannot pass unnoticed: T91 pins 5-allow /
# 6-deny); `live` = an unarchived specs/<branch>/tasks.md as all three.
# Echoes the work dir.
g1_fixture() {
  local tmp="$1" variant="$2" work origin incidents n
  if [[ "$variant" == archived ]]; then
    read -r work origin incidents < <(make_archived_branch "$tmp" "feat-g1arch")
  else
    read -r work origin incidents < <(make_kb_branch "$tmp" "feat-g1live" specdir)
  fi
  assert_fixture_dir "$work"
  git -C "$work" remote set-url origin "git@github.com:jikig-ai/soleur.git"
  git -C "$work" config url."$origin".insteadOf "git@github.com:jikig-ai/soleur.git"
  for n in "$G1_PR" 5 6; do git -C "$work" push -q origin "HEAD:refs/pull/$n/head"; done
  if [[ "$variant" == archived ]]; then
    git -C "$work" checkout -q -b g1-live6 main
    mkdir -p "$work/knowledge-base/project/specs/g1-live6"
    echo "live" > "$work/knowledge-base/project/specs/g1-live6/tasks.md"
    git -C "$work" add -A
    git -C "$work" commit -q -m "live spec for PR 6"
    git -C "$work" push -q -f origin "HEAD:refs/pull/6/head"
  fi
  git -C "$work" checkout -q -b reviewer main
  echo "$work"
}

# g1_run <work> <cmd> — one hook run with a FRESH incidents root (the deny
# asserts count exactly one row). Sets G1_OUT, G1_RC, G1_INC.
g1_run() {
  G1_INC=$(mktemp -d -p "$SUITE_TMP"); G1_RC=0
  G1_OUT=$(run_hook "$G1_INC" "$(make_payload "$1" "$2")") || G1_RC=$?
}
g1_deny() { g1_run "$2" "$3"; assert_deny_why "$1" "$G1_INC" "$G1_OUT" "$G1_RC" "$4"; }
g1_pass() { g1_run "$2" "$3"; assert_pass "$1" "$G1_INC" "$G1_OUT" "$G1_RC"; }

# g1_lock_block <arm-a> <arm-b> [<intruder>] — the documented
# locked/degrade-open if/else shape with each branch's invocation supplied
# (synthesized mutation inputs; the verbatim doc blocks come from
# g1_extract). An <intruder> line is placed in the else branch just before
# <arm-b>, i.e. strictly between the two copies.
g1_lock_block() {
  local -a intr=()
  [[ -n "${3-}" ]] && intr=("  $3")
  printf '%s\n' 'SS_LIB="${CLAUDE_PLUGIN_ROOT}/scripts/lib/session-state.sh"' \
    'if [[ -r "$SS_LIB" ]] && command -v flock >/dev/null 2>&1; then' \
    '  bash "$SS_LIB" with_lock merge-main 600 -- \' \
    "    $1" \
    '  rc=$?' \
    'else' \
    '  echo "SOLEUR_SESSION_STATE_UNAVAILABLE path=$SS_LIB reason=running-unlocked"' \
    ${intr[@]+"${intr[@]}"} \
    "  $2" \
    '  rc=$?' \
    'fi'
}

G1_ARCH=""; G1_LIVE=""; G1_SPANS=""; G1_SHIP=""; G1_CANON=""; G1_ADMIN=""
t83_g1_sites_and_spans() {
  local tmp sites kind rel f
  tmp=$(mktemp -d -p "$SUITE_TMP")
  mkdir -p "$tmp/spans"
  if ! sites=$(g1_parse_sites "$G1_SITES_SUITE"); then
    fail "T83 site list parsed from arm-check-sites.test.sh"
    TOTAL=$((TOTAL + 1)); return
  fi
  pass "T83 site list parsed from arm-check-sites.test.sh ($(grep -c . <<<"$sites") sites)"
  TOTAL=$((TOTAL + 1))
  while IFS=$'\t' read -r kind rel; do
    if f=$(g1_site_spans "$REPO_ROOT" "$kind" "$rel" "$tmp/spans"); then
      pass "T83 $rel yields exactly 1 $kind arm span"
      G1_SPANS+="${kind}"$'\t'"${rel}"$'\t'"${f}"$'\n'
    else
      fail "T83 $rel yields exactly 1 $kind arm span"
    fi
    TOTAL=$((TOTAL + 1))
  done <<<"$sites"
  G1_SHIP=$(awk -F'\t' '$2 == "plugins/soleur/skills/ship/SKILL.md" { print $3 }' <<<"$G1_SPANS")
  G1_CANON=$(awk -F'\t' -v c="$(sed -nE 's/^CANON=([^[:space:]]+)[[:space:]]*$/\1/p' "$G1_SITES_SUITE")" '$2 == c { print $3 }' <<<"$G1_SPANS")
  G1_ADMIN=$(awk -F'\t' '$1 == "admin" { print $3 }' <<<"$G1_SPANS" | head -1)
  G1_ARCH=$(g1_fixture "$(mktemp -d -p "$SUITE_TMP")" archived)
  G1_LIVE=$(g1_fixture "$(mktemp -d -p "$SUITE_TMP")" live)
}

t84_g1_red_reasons() {
  # RED evidence (pre-fix hook, measured 2026-11-28): the verbatim ship block
  # denied with `more than one gh pr merge invocation` (it tripped the
  # multi-invocation arm before any other), and the admin hatch's statement
  # passed every earlier arm and stopped at `names no 40-hex sha`. Both are
  # now ADMITTED (T85). These rows keep the two reasons reachable from a
  # one-token near miss of each verbatim span, so a fourth, unexpected
  # reason cannot hide behind a generic deny: the ship block with its
  # degrade-open copy naming another PR, and the hatch with a defaulted sha.
  local ship admin
  ship=$(awk -v n="$G1_PR" '{ if (index($0, "gh pr merge " n) && ++k == 2) sub("gh pr merge " n, "gh pr merge " n + 1); print }' "$G1_SHIP")
  admin=$(sed 's/"\$SHA"/"${SHA:-x}"/' "$G1_ADMIN")
  if [[ "$ship" == "$(cat "$G1_SHIP")" || "$admin" == "$(cat "$G1_ADMIN")" ]]; then
    fail "T84 near-miss spans are identical to the verbatim spans (the edit did not apply)"
    TOTAL=$((TOTAL + 1))
  fi
  g1_deny "T84 ship block, copies name different PRs: multi-invocation reason" "$G1_ARCH" "$ship" "more than one gh pr merge invocation"
  g1_deny "T84 admin hatch with a defaulted sha: no-sha reason" "$G1_ARCH" "$admin" "names no 40-hex sha"
}

t85_g1_sites_allow_and_census() {
  # G1-r8/r12 (every --auto arm span, SITES + CANON) and G1-r9 (the admin
  # hatch): allowed on an archived head, denied BY THE CENSUS on a live one
  # (G1-r5 for the ship block: an accepted shape must reach the census).
  local kind rel f
  while IFS=$'\t' read -r kind rel f; do
    [[ -n "$f" ]] || continue
    local id="G1-r8/r12"; [[ "$kind" == admin ]] && id="G1-r9"
    g1_pass "T85 $id $rel span allowed on an archived head" "$G1_ARCH" "$(cat "$f")"
    [[ "$rel" == */ship/SKILL.md ]] && id="G1-r5"
    g1_deny "T85 $id $rel span denied by the census on a live head" "$G1_LIVE" "$(cat "$f")" "lands KB artifacts at live paths"
  done <<<"$G1_SPANS"
}

t86_g1_multi_invocation_rows() {
  local a='gh pr merge 5 --squash --auto --match-head-commit "${H:?x}"'
  local blk
  blk="$(g1_lock_block "$a" "$a")"$'\n''gh pr merge 6 --squash --auto --match-head-commit "${H:?x}"'
  g1_deny "T86 G1-r1 a third, different invocation" "$G1_ARCH" "$blk" "more than one gh pr merge invocation"
  # Same PR number on the third copy, so only the residue comparison (not
  # the first-token check) can see it differ.
  blk="$(g1_lock_block "$a" "$a")"$'\n''gh pr merge 5 --squash --auto --delete-branch --match-head-commit "${H:?x}"'
  g1_deny "T86 G1-r1b a third copy differing only in a flag" "$G1_ARCH" "$blk" "more than one gh pr merge invocation"
  g1_deny "T86 G1-r2 operands \"\$H\" vs \"\${!H}\"" "$G1_ARCH" \
    "$(g1_lock_block 'gh pr merge 5 --squash --auto --match-head-commit "$H"' 'gh pr merge 5 --squash --auto --match-head-commit "${!H}"')" "operands differ"
  g1_deny "T86 G1-r2b quoted flag values differ (--subject \"a\" vs \"b\")" "$G1_ARCH" \
    "$(g1_lock_block 'gh pr merge 5 --squash --auto --subject "a" --match-head-commit "${H:?x}"' 'gh pr merge 5 --squash --auto --subject "b" --match-head-commit "${H:?x}"')" \
    "more than one gh pr merge invocation"
  local s1 s2
  s1=$(git -C "$G1_ARCH" rev-parse "refs/remotes/origin/feat-g1arch")
  s2=$(git -C "$G1_ARCH" rev-parse main)
  g1_deny "T86 G1-r6 two branches, different literal SHAs" "$G1_ARCH" \
    "$(g1_lock_block "gh pr merge 5 --squash --auto --match-head-commit $s1" "gh pr merge 5 --squash --auto --match-head-commit $s2")" \
    "more than one gh pr merge invocation"
  g1_deny "T86 G1-r7 two branches, different PR numbers" "$G1_ARCH" \
    "$(g1_lock_block 'gh pr merge 5 --squash --auto --match-head-commit "${H:?x}"' 'gh pr merge 6 --squash --auto --match-head-commit "${H:?x}"')" \
    "more than one gh pr merge invocation"
  g1_deny "T86 G1-r11 operands \"\${H:?x}\" vs \"\${G:?x}\"" "$G1_ARCH" \
    "$(g1_lock_block 'gh pr merge 5 --squash --auto --match-head-commit "${H:?x}"' 'gh pr merge 5 --squash --auto --match-head-commit "${G:?x}"')" "operands differ"
  g1_deny "T86 G1-r14 foreign GH_REPO prefix beside several invocations" "$G1_ARCH" \
    'GH_REPO=o/r gh pr merge 5 --squash --auto --match-head-commit "$H" || gh pr merge 5 --squash --auto --match-head-commit "$H"' \
    "beside several gh pr merge invocations"
}

t87_g1_operand_rows() {
  local op
  # The msg class bars `$`, backtick and `\` too: a widened class would admit
  # a substitution (or an escaped quote) hidden in the `:?` message.
  for op in '"${H:-x}"' '"$H$G"' '"${!H}"' '"${H[@]}"' '"${H:?$(id)}"' '"${H:?`id`}"' '"${H:?a\"b}"'; do
    g1_deny "T87 G1-r3 operand $op is not a simple expansion" "$G1_ARCH" "gh pr merge 5 --squash --auto --match-head-commit $op" "simple variable"
  done
  local sha digits
  sha=$(git -C "$G1_ARCH" rev-parse "refs/remotes/origin/feat-g1arch")
  digits=$(printf '%040d' 7)
  g1_deny "T87 G1-r4 40-digit first positional beside a literal sha" "$G1_ARCH" \
    "gh pr merge $digits --squash --auto --match-head-commit $sha" "not a bare PR number"
  for op in '"$@"' '"$*"' '"${A[@]}"' '"${!N}"'; do
    g1_deny "T87 G1-r15 multi-word/indirect operand $op" "$G1_ARCH" "gh pr merge 5 --squash --auto --match-head-commit $op" "simple variable"
  done
  g1_deny "T87 G1-r15 nameref makes \"\$H\" run code" "$G1_ARCH" \
    "declare -n H='x[\$(id)]'; gh pr merge 5 --squash --auto --match-head-commit \"\$H\"" "nameref"
  g1_deny "T87 G1-r16 echo decoy before the real operand" "$G1_ARCH" \
    'echo --match-head-commit "$H"; gh pr merge 5 --squash --auto --match-head-commit "$@"' "simple variable"
  g1_deny "T87 G1-r16 comment decoy before the real operand" "$G1_ARCH" \
    ': # --match-head-commit "$H"'$'\n''gh pr merge 5 --squash --auto --match-head-commit "$@"' "simple variable"
  g1_deny "T87 G1-r17 a positional after the operand" "$G1_ARCH" \
    'gh pr merge 5 --squash --auto --match-head-commit "$H" 6' "LAST argument"
  g1_deny "T87 G1-r10 dequeue arm with a variable PR number stays denied" "$G1_ARCH" \
    'gh pr merge "$N" --squash --auto --match-head-commit "${H:?run the arm check in this call}"' "differ once quoted text is removed"
}

t88_g1_composite_and_fail_opens() {
  # G1-r13: the composite one-call form (the arm check's first statement,
  # then the lock block) — the same verdict as the lock block alone.
  local first
  first=$(grep -v 'gh pr merge' "$G1_CANON" || true)
  g1_pass "T88 G1-r13 arm check + lock block in one call allowed" "$G1_ARCH" "${first}"$'\n'"$(cat "$G1_SHIP")"
  # G1-r18 (G2): ls-remote failing under set -eo pipefail must reach the
  # fail-closed deny, not kill the hook with no JSON.
  local url
  assert_fixture_dir "$G1_ARCH"
  url=$(git -C "$G1_ARCH" config --get remote.origin.url)
  # The insteadOf rewrite keys on the github URL, so it does not apply here.
  git -C "$G1_ARCH" remote set-url origin /nonexistent/g1-unreachable.git
  g1_deny "T88 G1-r18 unreachable origin denies (G2)" "$G1_ARCH" "$(cat "$G1_SHIP")" "ls-remote"
  git -C "$G1_ARCH" remote set-url origin "$url"
  # G1-r19 (G1 b/c): text that points gh nowhere must not take the
  # proven-foreign exit; each reaches the census and denies the live head.
  local c
  for c in 'gh pr merge 5 --squash --auto; : GH_HOST=evil.example' \
           'gh pr merge 5 --squash --auto && echo GH_REPO=o/r' \
           'gh pr merge 5 --squash --auto --body -Ro/r'; do
    g1_deny "T88 G1-r19 '$c' reaches the census" "$G1_LIVE" "$c" "lands KB artifacts at live paths"
  done
}

t89_g1_harness_rows() {
  local tmp rc=0 err
  tmp=$(mktemp -d -p "$SUITE_TMP")
  # G1-H-a: a renamed SITES array, and a site whose arm span was removed,
  # each FAIL loudly naming the file — never a 0-row pass.
  sed 's/^SITES=(/SITES_RENAMED=(/' "$G1_SITES_SUITE" > "$tmp/arm-check-sites.test.sh"
  err=$(g1_parse_sites "$tmp/arm-check-sites.test.sh" 2>&1 >/dev/null) || rc=$?
  if [[ "$rc" -ne 0 && "$err" == *"site list empty in $tmp/arm-check-sites.test.sh"* ]]; then
    pass "T89 G1-H-a renamed SITES fails loudly"
  else
    fail "T89 G1-H-a renamed SITES fails loudly (rc=$rc err=$err)"
  fi
  TOTAL=$((TOTAL + 1))
  local rel=plugins/soleur/skills/drain-prs/SKILL.md
  mkdir -p "$tmp/root/$(dirname "$rel")" "$tmp/spans"
  grep -v 'gh pr merge' "$REPO_ROOT/$rel" > "$tmp/root/$rel" || true
  rc=0; err=$(g1_site_spans "$tmp/root" auto "$rel" "$tmp/spans" 2>&1 >/dev/null) || rc=$?
  if [[ "$rc" -ne 0 && "$err" == *"$rel: extracted 0 spans, want 1"* ]]; then
    pass "T89 G1-H-a site with its span removed fails loudly"
  else
    fail "T89 G1-H-a site with its span removed fails loudly (rc=$rc err=$err)"
  fi
  TOTAL=$((TOTAL + 1))
  # G1-H-b / G1-H-c: non-canonical shapes that must still PASS.
  g1_pass "T89 G1-H-b braced \"\${SHA}\" operand allowed" "$G1_ARCH" "gh pr merge $G1_PR --squash --auto --match-head-commit \"\${SHA}\""
  g1_pass "T89 G1-H-c ship block without its else branch allowed" "$G1_ARCH" \
    "$(awk '/^else$/{skip=1} /^fi$/{skip=0} !skip' "$G1_SHIP")"
  # G1-H-d: positive control — an inverted assertion and a wrong reason
  # substring must each move the failure counter.
  local f0=$FAIL t0=$TOTAL moved=0
  g1_run "$G1_ARCH" "gh pr merge $G1_PR --squash --auto"
  assert_deny_why "H-d probe (inverted)" "$G1_INC" "$G1_OUT" "$G1_RC" "x" >/dev/null
  (( FAIL == f0 + 1 )) && moved=$((moved + 1))
  g1_run "$G1_LIVE" "gh pr merge $G1_PR --squash --auto"
  assert_deny_why "H-d probe (wrong reason)" "$G1_INC" "$G1_OUT" "$G1_RC" "no-such-reason-substring" >/dev/null
  (( FAIL == f0 + 2 )) && moved=$((moved + 1))
  FAIL=$f0; TOTAL=$t0
  if [[ "$moved" == "2" ]]; then
    pass "T89 G1-H-d assert_deny_why positive control moves the failure counter"
  else
    fail "T89 G1-H-d assert_deny_why positive control (moved=$moved/2)"
  fi
  TOTAL=$((TOTAL + 1))
}

t90_g1_rule_ii_narrowing() {
  # Rule (ii) admits several invocations only as NUMBERED identical copies.
  # (a) A trailing arg-less `gh pr merge` used to vanish from the residue
  # count (`$(…)` drops trailing newlines), so only PR 5 was censused while
  # the bare merge took the session branch's PR — here a live one.
  local tmp work origin incidents
  tmp=$(mktemp -d -p "$SUITE_TMP")
  read -r work origin incidents < <(make_kb_branch "$tmp" "feat-g1trail" specdir)
  assert_fixture_dir "$work"
  git -C "$work" push -q origin main:refs/pull/5/head
  g1_deny "T90 trailing arg-less invocation is counted" "$work" "gh pr merge 5 --squash && gh pr merge" "more than one gh pr merge invocation"
  # (b) identical FLAG-ONLY copies stay denied: the HEAD path can move
  # between them (a `git checkout` in between), a PR number cannot.
  g1_deny "T90 identical flag-only copies denied" "$work" \
    "$(g1_lock_block 'gh pr merge --squash --auto' 'gh pr merge --squash --auto')" "more than one gh pr merge invocation"
  # (c) identical numbered copies without --match-head-commit: one object.
  g1_pass "T90 identical numbered copies allowed" "$G1_ARCH" \
    "$(g1_lock_block 'gh pr merge 5 --squash --auto' 'gh pr merge 5 --squash --auto')"
  # (d) a copy chained on the same line is not the documented shape.
  g1_deny "T90 same-line chained copies denied" "$G1_ARCH" \
    'gh pr merge 5 --squash --auto; gh pr merge 5 --squash --auto' "more than one gh pr merge invocation"
}

# --- review fixes for PR #13112 (T91+) ---------------------------------------

t91_rule_ii_allowlist() {
  # Rule (ii): byte-identical copies are one object only when NOTHING but the
  # documented if/else skeleton sits between them. Each intruder below would
  # let copy 2 merge in another repository, with another H, or another gh.
  local a='gh pr merge 5 --squash --auto --match-head-commit "${H:?x}"'
  local sha6 intr
  sha6=$(git -C "$G1_ARCH" rev-parse g1-live6)
  for intr in 'cd /tmp' 'pushd /tmp' 'export GH_REPO=o/r' 'export GIT_DIR=/x' \
              "H=$sha6" 'git push origin HEAD' 'git remote set-url origin /x' \
              'gh repo set-default o/r' 'alias gh=true' 'gh() { :; }'; do
    g1_deny "T91 rule (ii) '$intr' between the copies denied" "$G1_ARCH" \
      "$(g1_lock_block "$a" "$a" "$intr")" "not the documented locked/degrade-open if/else skeleton"
  done
  g1_deny "T91 rule (ii) text after the first copy's operand denied" "$G1_ARCH" \
    "$(g1_lock_block "$a; cd /tmp" "$a")" "continues past its operand"
  g1_deny "T91 rule (ii) a third identical copy denied (exactly two)" "$G1_ARCH" \
    "$(g1_lock_block "$a" "$a")"$'\n'"$a" "more than the two copies"
  # The first copy's lead is pinned to the whole with_lock prefix: an env
  # or launcher word after `--` could steer copy 1 alone.
  g1_deny "T91 rule (ii) first copy prefixed GIT_DIR=/x denied" "$G1_ARCH" \
    "$(g1_lock_block "GIT_DIR=/x $a" "$a")" "more than one gh pr merge invocation"
  g1_deny "T91 rule (ii) first copy prefixed env -C /x denied" "$G1_ARCH" \
    "$(g1_lock_block "env -C /x $a" "$a")" "more than one gh pr merge invocation"
  # The census reads the PR the command names: PR 5 is archived, PR 6 live.
  g1_pass "T91 rule (i) PR 5 (archived head) allowed" "$G1_ARCH" "$a"
  g1_deny "T91 rule (i) PR 6 (live head) denied by the census" "$G1_ARCH" \
    'gh pr merge 6 --squash --auto --match-head-commit "${H:?x}"' "lands KB artifacts at live paths"
  # A PR number beside a literal sha: the sha is what is censused.
  local s_arch s_live
  s_arch=$(git -C "$G1_ARCH" rev-parse "refs/remotes/origin/feat-g1arch")
  s_live=$(git -C "$G1_LIVE" rev-parse "refs/remotes/origin/feat-g1live")
  g1_pass "T91 PR number + literal archived sha allowed" "$G1_ARCH" \
    "gh pr merge 5 --squash --auto --match-head-commit $s_arch"
  g1_deny "T91 PR number + literal live sha denied by the census" "$G1_LIVE" \
    "gh pr merge 5 --squash --auto --match-head-commit $s_live" "lands KB artifacts at live paths"
}

t92_flag_value_spellings() {
  # A `-R…` token that gh reads as a value-taking flag's VALUE is not a
  # pointer, in every pflag spelling; each must reach the census (live head),
  # never the proven-foreign exit.
  local f sp l
  for f in t b F A; do
    for sp in "-${f}Ro/r" "-s${f} -Ro/r" "-sd${f}Ro/r"; do
      g1_deny "T92 '$sp' (value of -$f) reaches the census" "$G1_LIVE" \
        "gh pr merge 5 --squash --auto $sp" "lands KB artifacts at live paths"
    done
  done
  for l in subject body body-file author-email; do
    g1_deny "T92 '--$l=-Ro/r' reaches the census" "$G1_LIVE" \
      "gh pr merge 5 --squash --auto --$l=-Ro/r" "lands KB artifacts at live paths"
  done
  for sp in '--match-head-commit -Ro/r' '--match-head-commit=-Ro/r'; do
    g1_deny "T92 '$sp' is a sha operand, not a pointer" "$G1_LIVE" \
      "gh pr merge 5 --squash --auto $sp" "names no 40-hex sha"
  done
  # Twins: a genuine pointer after a value still takes the foreign exit.
  g1_pass "T92 '--body x -R o/r' still takes the proven-foreign exit" "$G1_LIVE" \
    'gh pr merge 5 --squash --auto --body x -R o/r'
  g1_pass "T92 '-sbx -Ro/r' still takes the proven-foreign exit" "$G1_LIVE" \
    'gh pr merge 5 --squash --auto -sbx -Ro/r'
}

t93_net_timeouts() {
  # The census network reads are bounded: a hung origin times out into the
  # deny instead of holding the hook (a killed hook lets the merge through).
  # A PATH-shimmed git hangs one call per mode with the real sleep; the
  # three runs go in parallel so the suite pays one bound-sized window.
  local tmp real slp mode rc to_lines kill bound
  # The bound the hook declares, read from BOTH _NET_TO lines (the `if`
  # timeout line Linux runs, and the `elif` gtimeout line ending `; fi`);
  # both must parse and carry the same kill/bound, so the rows below test the
  # value every platform ships. A parse miss is a FAIL row, never an errexit.
  local raw n_lines
  raw=$(grep -E '^(if|elif) command -v g?timeout .*_NET_TO=\(g?timeout -k [0-9]+ [0-9]+\)(; fi)?$' "$HOOK") || raw=""
  n_lines=$(grep -c . <<< "$raw") || n_lines=0
  to_lines=$(sed -E 's/.*-k ([0-9]+) ([0-9]+)\).*/\1 \2/' <<< "$raw" | sort -u) || to_lines=""
  if [[ "$n_lines" -ne 2 || $(grep -c . <<< "$to_lines") -ne 1 \
        || "$(grep -cE '_NET_TO=\(g?timeout' "$HOOK")" -ne 2 ]]; then
    fail "T93 hook declares one _NET_TO bound on both its timeout and gtimeout lines (lines=$n_lines, got: ${to_lines:-none})"
    TOTAL=$((TOTAL + 1))
    # The three timing rows cannot run without a bound: count them as failed
    # so the floor reads 215 on this path too.
    for mode in lsremote pullfetch mainfetch; do
      fail "T93 hung $mode not measured: no single parsable _NET_TO bound"
      TOTAL=$((TOTAL + 1))
    done
    return
  fi
  read -r kill bound <<< "$to_lines"
  # Worst case on the PR-number path: two reads succeed just under the bound,
  # the third is killed (a timed-out read denies at once, so three timeouts
  # cannot chain): 3 x bound + kill. Budget 60 s, a conservative figure —
  # settings.json sets no timeout for this hook, and a longer harness default
  # only adds margin. 20 s (62) on either line, or any kill/bound pair over
  # budget, reds here.
  if (( 3 * bound + kill < 60 )); then
    pass "T93 census worst case 3 x ${bound} + ${kill} s fits a 60 s hook budget"
  else
    fail "T93 census worst case 3 x ${bound} + ${kill} = $(( 3 * bound + kill )) s exceeds a 60 s hook budget"
  fi
  TOTAL=$((TOTAL + 1))
  tmp=$(mktemp -d -p "$SUITE_TMP")
  real=$(command -v git); slp=$(command -v sleep)
  mkdir -p "$tmp/bin"
  cat > "$tmp/bin/git" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *" ls-remote "*) [[ "\${KBG_HANG-}" == lsremote ]] && exec "$slp" 300 ;;
  *" cat-file "*) [[ "\${KBG_HANG-}" == pullfetch ]] && exit 1 ;;
  *" fetch "*refs/pull/*) [[ "\${KBG_HANG-}" == pullfetch ]] && exec "$slp" 300 ;;
  *" fetch "*" main "*) [[ "\${KBG_HANG-}" == mainfetch ]] && exec "$slp" 300 ;;
esac
exec "$real" "\$@"
EOF
  chmod +x "$tmp/bin/git"
  local payload
  payload=$(make_payload "$G1_ARCH" "$(cat "$G1_SHIP")")
  for mode in lsremote pullfetch mainfetch; do
    mkdir -p "$tmp/$mode/inc"
    (
      s=$(date +%s); rc=0
      printf '%s' "$payload" | PATH="$tmp/bin:$PATH" KBG_HANG="$mode" CLAUDECODE='' \
        SOLEUR_SESSION_STATE_ROOT="$tmp/$mode/inc/state" INCIDENTS_REPO_ROOT="$tmp/$mode/inc" \
        timeout -k 5 60 "$HOOK" > "$tmp/$mode/out" 2>/dev/null || rc=$?
      printf '%s %s\n' "$rc" "$(( $(date +%s) - s ))" > "$tmp/$mode/rc"
    ) &
  done
  wait
  local want el
  for mode in lsremote pullfetch mainfetch; do
    case "$mode" in
      lsremote) want="ls-remote origin refs/pull/" ;;
      pullfetch) want="fetch origin refs/pull/" ;;
      mainfetch) want="fetch origin main" ;;
    esac
    read -r rc el < "$tmp/$mode/rc"
    if [[ "$el" -lt $(( bound + kill + 3 )) ]]; then
      assert_deny_why "T93 hung $mode times out into a deny (${el}s)" "$tmp/$mode/inc" "$(cat "$tmp/$mode/out")" "$rc" "$want"
    else
      fail "T93 hung $mode times out into a deny (took ${el}s, rc=$rc)"
      TOTAL=$((TOTAL + 1))
    fi
  done
}

t94_nameref_spellings() {
  # The nameref sighting runs after quote removal: quoted or escaped option
  # spellings, a quoted builtin name, and an option word that is an
  # expansion all deny.
  local d
  for d in "declare '-n' H='x[\$(id)]'" 'declare -\n H=x' '"declare" -n H=x' \
           "typeset -\\n H=x" 'o=-n; local $o H=x' 'declare {-n,} H=x' \
           $'declare \\\n-n H=x' 'declare${IFS}-n H=x' 'declare -[n] H=x'; do
    g1_deny "T94 nameref spelling '$d' denied" "$G1_ARCH" \
      "$d; gh pr merge 5 --squash --auto --match-head-commit \"\$H\"" "nameref"
  done
}

t95_deny_reason_text() {
  # Deny reasons name the fix: the operand goes LAST, the variable needs the
  # space-separated spelling, and the shared tail names the arm form.
  g1_deny "T95 flags after the operand: operand must be LAST" "$G1_ARCH" \
    'gh pr merge 5 --match-head-commit "$H" --squash --auto' "LAST argument"
  g1_deny "T95 --admin after the operand: operand must be LAST" "$G1_ARCH" \
    'gh pr merge 5 --squash --match-head-commit "$H" --admin' "LAST argument"
  g1_deny "T95 --match-head-commit=\"\$H\": space-separated spelling" "$G1_ARCH" \
    'gh pr merge 5 --squash --auto --match-head-commit="$H"' "space-separated spelling"
  g1_deny "T95 shared deny tail points at the arm check" "$G1_ARCH" \
    'gh pr merge 5 --squash --auto --match-head-commit="$H"' "review-evidence-comment.md#arm-check"
}

t96_assert_pass_control() {
  # Positive control for assert_pass: it must REJECT a deny decision, a
  # non-zero exit and a deny incident row. Counters are unwound and the
  # verdict is reported outside the helpers, so a neutered assert_pass
  # cannot vouch for itself.
  local f0=$FAIL p0=$PASS t0=$TOTAL moved=0 inc
  inc=$(mktemp -d -p "$SUITE_TMP")
  assert_pass "control: deny decision" "$inc" '{"hookSpecificOutput":{"permissionDecision":"deny"}}' 0 >/dev/null
  (( FAIL == f0 + 1 )) && moved=$((moved + 1))
  assert_pass "control: non-zero exit" "$inc" '' 1 >/dev/null
  (( FAIL == f0 + 2 )) && moved=$((moved + 1))
  mkdir -p "$inc/.claude"
  printf '%s\n' '{"rule_id":"x","event_type":"deny"}' > "$inc/.claude/.rule-incidents.jsonl"
  assert_pass "control: deny incident row" "$inc" '' 0 >/dev/null
  (( FAIL == f0 + 3 )) && moved=$((moved + 1))
  FAIL=$f0; PASS=$p0; TOTAL=$t0
  if [[ "$moved" != "3" ]]; then
    printf '[FATAL] assert_pass positive control: it rejected %d/3 deny probes — every allow row is vacuous\n' "$moved" >&2
    exit 1
  fi
  printf 'CONTROL: assert_pass rejects a deny decision, a non-zero exit and a deny incident row (3/3)\n'
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
t06b_rtk_deny
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
t77_quoted_subcommand_deny
t78_ifs_split_deny
t79_specflat_deny
t80_gitkeep_pass
t81_quoted_string_pass
t82_partial_word_quote_pass
t83_g1_sites_and_spans
t84_g1_red_reasons
t85_g1_sites_allow_and_census
t86_g1_multi_invocation_rows
t87_g1_operand_rows
t88_g1_composite_and_fail_opens
t89_g1_harness_rows
t90_g1_rule_ii_narrowing
t91_rule_ii_allowlist
t92_flag_value_spellings
t93_net_timeouts
t94_nameref_spellings
t95_deny_reason_text
t96_assert_pass_control

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"

# Anti-vacuity floor: exact case floor, enforced OUTSIDE the verdict
# machinery (a neutered assert cannot disarm it — guard-vacuity-floor's
# mutant contract). Threshold is hand-maintained with the case list:
# 94 assertions across 80 case invocations — 80 case verdicts + 5
# assert_fixture_has preconditions (T01/T02/T04/T20/T79) + 9 second-verdict
# arms (T01b/T09b/T15b/T18b/T35b/T48b/T77b/T78b/T81b). Guard 1 (T83-T90)
# adds 61: T83 1 parse + 7 derived sites (one per SITES/CANON/LINK_ONLY
# entry), T84 2, T85 14 (7 spans x archived/live), T86 9, T87 14, T88 5,
# T89 5, T90 4. The suite measured 157 before the #13112 review fixes (the
# itemisation above under-counts it by two; the measured total is what is
# pinned). Those fixes add 57: T87 +3 operand rows, T91 18 (10 intruders +
# tail + third copy + 2 leads + PR 5/6 pair + literal-sha pair), T92 20 (12
# short spellings + 4 long `=` + 2 --match-head-commit + 2 twins), T93 3,
# T94 9, T95 4; T96 is a control reported outside the counters. T93 +1
# budget row (3 x bound + kill < 60 s). The floor
# is the exact measured total (215) — a dropped row is a FATAL, not a quiet
# shrink.
MIN_ASSERTIONS=215
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
