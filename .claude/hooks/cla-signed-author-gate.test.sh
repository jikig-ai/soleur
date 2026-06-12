#!/usr/bin/env bash
# Fixture-based tests for cla-signed-author-gate.sh. Asserts the hook blocks
# `gh pr ready`/`merge` when a branch commit is authored/committed by the
# non-CLA-signed identity, and fail-opens on every infra/edge case.
# Isolation pattern mirrors ship-unpushed-commits-gate.test.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/cla-signed-author-gate.sh"
UNSIGNED="noreply@anthropic.com"

PASS=0; FAIL=0; TOTAL=0
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }

init_git_repo() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" config user.email test@test.local
  git -C "$dir" config user.name "Test User"
  git -C "$dir" config commit.gpgsign false
}

# Build a work-tree on feature branch off origin/main. $3 = author email for the
# feature commit (signed test@test.local or the unsigned id). Echoes "$work $inc".
make_branch() {
  local tmp="$1" branch="$2" author_email="$3"
  local work="$tmp/work" origin="$tmp/origin.git" inc="$tmp/inc"
  mkdir -p "$work" "$inc"
  git init -q --bare "$origin"
  init_git_repo "$work"
  echo base > "$work/file.txt"; git -C "$work" add file.txt; git -C "$work" commit -q -m init
  git -C "$work" remote add origin "$origin"; git -C "$work" push -q origin main
  git -C "$work" checkout -q -b "$branch"
  echo feat > "$work/feat.txt"; git -C "$work" add feat.txt
  GIT_AUTHOR_NAME="A" GIT_AUTHOR_EMAIL="$author_email" \
    git -C "$work" commit -q -m "feature work"
  echo "$work $inc"
}

make_payload() { jq -nc --arg c "$1" --arg x "$2" '{tool_input:{command:$x},cwd:$c}'; }
run_hook() { printf '%s' "$2" | INCIDENTS_REPO_ROOT="$1" "$HOOK" 2>/dev/null; }

assert_deny() {
  local name="$1" inc="$2" out="$3" rc="$4"
  local decision jsonl rule
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$inc/.claude/.rule-incidents.jsonl"
  rule=$([[ -f "$jsonl" ]] && jq -r '.rule_id' < "$jsonl" | head -1 || echo "")
  if [[ "$rc" -eq 0 && "$decision" == "deny" && "$rule" == "wg-cla-signed-author-before-merge" ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (rc=$rc decision=$decision rule=$rule)"; FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))
}

assert_pass() {
  local name="$1" inc="$2" out="$3" rc="$4"
  local decision jsonl denied=0
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$inc/.claude/.rule-incidents.jsonl"
  [[ -f "$jsonl" ]] && denied=$(grep -c '"event_type":"deny"' "$jsonl" 2>/dev/null || echo 0)
  if [[ "$rc" -eq 0 && "$decision" != "deny" && "$denied" -eq 0 ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (rc=$rc decision=$decision denied=$denied)"; FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))
}

# T1: unsigned-author commit + gh pr merge → DENY
t1() { local t; t=$(mktemp -d); read -r work inc < <(make_branch "$t" feat-x "$UNSIGNED")
  out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr merge 123 --squash --auto')"); rc=$?
  assert_deny "T1 unsigned author + gh pr merge denies" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T2: all-signed commits + gh pr merge → PASS
t2() { local t; t=$(mktemp -d); read -r work inc < <(make_branch "$t" feat-y test@test.local)
  out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr merge 123 --squash --auto')"); rc=$?
  assert_pass "T2 signed authors pass" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T3: unsigned author + gh pr ready → DENY (gate also covers ready)
t3() { local t; t=$(mktemp -d); read -r work inc < <(make_branch "$t" feat-z "$UNSIGNED")
  out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr ready 123')"); rc=$?
  assert_deny "T3 unsigned author + gh pr ready denies" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T4: unrelated command → no fire (PASS)
t4() { local t; t=$(mktemp -d); read -r work inc < <(make_branch "$t" feat-w "$UNSIGNED")
  out=$(run_hook "$inc" "$(make_payload "$work" 'git status')"); rc=$?
  assert_pass "T4 non-gh-pr command does not fire" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T5: on main → fail-open PASS even with command match
t5() { local t; t=$(mktemp -d); local work="$t/work" inc="$t/inc"; mkdir -p "$work" "$inc"
  git init -q --bare "$t/o.git"; init_git_repo "$work"
  echo b > "$work/f"; git -C "$work" add f
  GIT_AUTHOR_EMAIL="$UNSIGNED" git -C "$work" commit -q -m c
  git -C "$work" remote add origin "$t/o.git"; git -C "$work" push -q origin main
  out=$(run_hook "$inc" "$(make_payload "$work" 'gh pr merge 1 --squash')"); rc=$?
  assert_pass "T5 main branch fail-opens" "$inc" "$out" "$rc"; rm -rf "$t"; }

# T6 (#5192): a `git commit` whose MESSAGE documents `gh pr merge` must NOT
# fire — even with an unsigned-author commit on the branch (which would deny if
# the trigger grep ran on the raw command). The strip blanks the -m body first.
t6() { local t; t=$(mktemp -d); read -r work inc < <(make_branch "$t" feat-fp "$UNSIGNED")
  out=$(run_hook "$inc" "$(make_payload "$work" $'git add . && git commit -m "ship note\ngh pr merge must not be hand-rolled\n"')"); rc=$?
  assert_pass "T6 commit-body gh pr merge does not fire (#5192)" "$inc" "$out" "$rc"; rm -rf "$t"; }

t1; t2; t3; t4; t5; t6
echo "----"
echo "$PASS/$TOTAL passed"
[[ "$FAIL" -eq 0 ]] || exit 1
