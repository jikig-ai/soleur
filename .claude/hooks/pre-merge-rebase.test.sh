#!/usr/bin/env bash
# Fixture-based tests for pre-merge-rebase.sh. Asserts each of the four deny
# branches calls emit_incident with the expected rule_id + event_type=deny.
#
# Isolation: each test builds its own work-tree (git repo) plus a separate
# "incidents root" directory under mktemp. INCIDENTS_REPO_ROOT redirects
# emit_incident's writes into the incidents root so the operator's real
# .claude/.rule-incidents.jsonl is not polluted.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/pre-merge-rebase.sh"

PASS=0
FAIL=0
TOTAL=0

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

seed_review_evidence() {
  local work="$1"
  mkdir -p "$work/todos"
  echo "code-review" > "$work/todos/sample.md"
}

make_payload() {
  local cwd="$1" cmd="$2"
  jq -nc --arg c "$cwd" --arg x "$cmd" \
    '{tool_input: {command: $x}, cwd: $c}'
}

# assert_deny <name> <incidents_root> <stdout> <exit_code> <expected_rule_id>
assert_deny() {
  local name="$1" incidents="$2" out="$3" exit_code="$4" expected="$5"
  local decision jsonl seen_rule seen_event count
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  jsonl="$incidents/.claude/.rule-incidents.jsonl"
  if [[ ! -f "$jsonl" ]]; then
    echo "FAIL: $name (no incidents jsonl at $jsonl; exit=$exit_code decision=$decision)"
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); return
  fi
  count=$(wc -l < "$jsonl" | tr -d ' ')
  seen_rule=$(jq -r '.rule_id' < "$jsonl" | head -1)
  seen_event=$(jq -r '.event_type' < "$jsonl" | head -1)
  if [[ "$exit_code" -eq 0 && "$decision" == "deny" && "$count" == "1" \
        && "$seen_rule" == "$expected" && "$seen_event" == "deny" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  exit=$exit_code decision=$decision count=$count rule=$seen_rule event=$seen_event"
    echo "  expected: rule=$expected event=deny count=1 decision=deny"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

run_hook() {
  local incidents="$1" payload="$2"
  # Capture stdout; stderr goes to /dev/null to keep test output clean.
  INCIDENTS_REPO_ROOT="$incidents" printf '%s' "$payload" | "$HOOK" 2>/dev/null
}

# --- T1: review-evidence gate (no review evidence present) ---------------
t1_review_evidence_gate() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-no-review
  git -C "$work" commit -q --allow-empty -m "feature work"
  # No todos/, no review commit, no remote with open PR.

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 123 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T1 review-evidence gate" "$incidents" "$out" "$exit_code" \
    "rf-never-skip-qa-review-before-merging"
  rm -rf "$tmp"
}

# --- T2: uncommitted changes ---------------------------------------------
t2_uncommitted_changes() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  echo "initial" > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m "init"
  git -C "$work" checkout -q -b feat-dirty
  seed_review_evidence "$work"
  git -C "$work" add todos/
  git -C "$work" commit -q -m "feature work"
  # Dirty the tree (tracked file modified but not committed).
  echo "dirty" > "$work/file.txt"

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 124 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T2 uncommitted changes" "$incidents" "$out" "$exit_code" \
    "hr-when-a-command-exits-non-zero-or-prints"
  rm -rf "$tmp"
}

# --- T3: merge conflict --------------------------------------------------
t3_merge_conflict() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" origin="$tmp/origin.git" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  git init -q --bare "$origin"

  init_git_repo "$work"
  echo "base" > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m "init"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin main

  # Feature branch with conflicting change.
  git -C "$work" checkout -q -b feat-conflict
  echo "feature side" > "$work/file.txt"
  git -C "$work" commit -aq -m "feature change"
  seed_review_evidence "$work"
  git -C "$work" add todos/
  git -C "$work" commit -q -m "review: findings (P1)"

  # Update origin/main with a diverging change via a second clone.
  local other="$tmp/other"
  git clone -q "$origin" "$other"
  git -C "$other" config user.email test@test.local
  git -C "$other" config user.name "Test User"
  echo "main side" > "$other/file.txt"
  git -C "$other" commit -aq -m "main change"
  git -C "$other" push -q origin main

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 125 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T3 merge conflict" "$incidents" "$out" "$exit_code" \
    "hr-when-a-command-exits-non-zero-or-prints"
  rm -rf "$tmp"
}

# --- T4: push failure ----------------------------------------------------
t4_push_failure() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" origin="$tmp/origin.git" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  git init -q --bare "$origin"

  init_git_repo "$work"
  echo "base" > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m "init"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin main

  # Feature branch with a non-conflicting change (different file).
  git -C "$work" checkout -q -b feat-pushfail
  echo "feat" > "$work/feature.txt"
  git -C "$work" add feature.txt
  git -C "$work" commit -q -m "feature change"
  seed_review_evidence "$work"
  git -C "$work" add todos/
  git -C "$work" commit -q -m "review: findings (P1)"

  # Diverge origin/main so the hook actually attempts a merge + push.
  local other="$tmp/other"
  git clone -q "$origin" "$other"
  git -C "$other" config user.email test@test.local
  git -C "$other" config user.name "Test User"
  echo "main-only" > "$other/mainfile.txt"
  git -C "$other" add mainfile.txt
  git -C "$other" commit -q -m "main change"
  git -C "$other" push -q origin main

  # Install pre-receive hook on origin that rejects every push.
  cat > "$origin/hooks/pre-receive" <<'EOF'
#!/bin/sh
echo "rejected by test pre-receive hook" >&2
exit 1
EOF
  chmod +x "$origin/hooks/pre-receive"

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 126 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T4 push failure" "$incidents" "$out" "$exit_code" \
    "hr-when-a-command-exits-non-zero-or-prints"
  rm -rf "$tmp"
}

t1_review_evidence_gate
t2_uncommitted_changes
t3_merge_conflict
t4_push_failure

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
