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

# assert_no_intercept <name> <incidents_root> <stdout> <exit_code>
# Inverse of assert_deny: the early-exit (no-merge-detected) path must exit 0,
# emit NO stdout, and write NO incidents jsonl (the hook returns before any
# emit_incident). Used by the #4600 false-positive cases and the malformed-JSON
# fail-open case.
assert_no_intercept() {
  local name="$1" incidents="$2" out="$3" exit_code="$4"
  local jsonl="$incidents/.claude/.rule-incidents.jsonl"
  local ok=1
  if [[ "$exit_code" -ne 0 ]]; then ok=0; fi
  if [[ -n "$out" ]]; then ok=0; fi
  if [[ -f "$jsonl" ]]; then ok=0; fi
  if [[ "$ok" -eq 1 ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  exit=$exit_code stdout=${out:-<empty>} jsonl_exists=$([[ -f "$jsonl" ]] && echo yes || echo no)"
    echo "  expected: exit=0 stdout=<empty> jsonl_exists=no"
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
  git init -q --bare -b main "$origin"

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
  git init -q --bare -b main "$origin"

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

# --- #4600 false-positive cases: gh pr merge text inside a commit message ---
# These commits document the rule "do not hand-roll gh pr merge"; the hook must
# NOT mistake them for a merge. Each asserts the early-exit (no-intercept) path.

# T-FP1: multi-line `git commit -m` body whose body line STARTS with gh pr merge
# (triggers the `^` anchor of the merge-detection regex against the body text).
t_fp1_commit_body_newline() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-fp1

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -m "do not hand-roll
gh pr merge directly"')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_no_intercept "T-FP1 commit body newline-prefixed gh pr merge" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# T-FP2: body contains a chain-operator + gh pr merge inside the quoted message.
t_fp2_commit_body_chain_op() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-fp2

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -m "docs: avoid && gh pr merge --auto in runbooks"')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_no_intercept "T-FP2 commit body chain-op gh pr merge --auto" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# T-FP3: body contains a numbered `gh pr merge 4598` mid-line. NOTE: this case
# already passes against the PRE-FIX hook because the anchor regex requires a
# chain-op/anchor token (^, &&, ||, ;, " -- ") immediately before the verb, and
# a mid-line " ... gh pr merge 4598 ..." has only a space before it. It is kept
# as an ANCHORED-REGEX regression guard: if someone ever loosens the anchor
# group to match the verb anywhere, this case starts failing — and it documents
# why issue option (b) "require a PR-number arg" is insufficient as a sole fix
# (a numbered merge in a body would still match an anchor-free regex).
t_fp3_commit_body_numbered() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-fp3

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -m "docs: never hand-roll gh pr merge 4598 directly"')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_no_intercept "T-FP3 commit body numbered gh pr merge 4598" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# T-FP4: bare `git commit -F - <<EOF … EOF` heredoc body (NOT wrapped in quotes)
# whose body line starts with the verb. This is the shape the branch is named
# for; the quote-strip alone does not cover it (no surrounding quotes), so the
# heredoc-body strip in the SCAN derivation is what makes this no-intercept.
# True RED against the pre-fix hook (which intercepts via the ^-anchor).
t_fp4_commit_body_heredoc() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-fp4

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -F - <<EOF
do not hand-roll
gh pr merge directly
EOF')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_no_intercept "T-FP4 bare heredoc commit body" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# --- Anti-regression: real merges must STILL fire the review-evidence gate ---

# T5: bare `gh pr merge 123 --squash`, no review evidence ⇒ deny (same as T1 but
# kept as an explicit anti-regression anchor for the quote-strip change).
t5_bare_merge_fires() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-t5
  git -C "$work" commit -q --allow-empty -m "feature work"

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 123 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T5 bare merge fires" "$incidents" "$out" "$exit_code" \
    "rf-never-skip-qa-review-before-merging"
  rm -rf "$tmp"
}

# T6: `git commit -m "wip" && gh pr merge 123 --squash` — a REAL chained merge
# after a commit. The quote-strip must blank only "wip" and leave the chained
# `&& gh pr merge` intact so the gate still fires. Guards the boundary the
# rejected leading-`git commit` skip heuristic would have broken.
t6_chained_after_commit_fires() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-t6
  git -C "$work" commit -q --allow-empty -m "feature work"

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -m "wip" && gh pr merge 123 --squash')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T6 chained-after-commit merge fires" "$incidents" "$out" "$exit_code" \
    "rf-never-skip-qa-review-before-merging"
  rm -rf "$tmp"
}

# T7: `with_lock`-wrapped form (`... -- gh pr merge 99 --squash`). The `\s--\s`
# alternative must still fire after the quote-strip.
t7_wrapped_merge_fires() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-t7
  git -C "$work" commit -q --allow-empty -m "feature work"

  local payload out exit_code=0
  payload=$(make_payload "$work" "bash session-state.sh with_lock merge-main 600 -- gh pr merge 99 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T7 with_lock-wrapped merge fires" "$incidents" "$out" "$exit_code" \
    "rf-never-skip-qa-review-before-merging"
  rm -rf "$tmp"
}

# T8: a REAL `gh pr merge` chained AFTER a heredoc terminator must still fire.
# Guards against the heredoc-body strip over-blanking past the closing
# delimiter (which would silently bypass the review-evidence gate).
t8_merge_after_heredoc_fires() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-t8
  git -C "$work" commit -q --allow-empty -m "feature work"

  local payload out exit_code=0
  payload=$(make_payload "$work" 'git commit -F - <<EOF
release notes body
EOF
git push && gh pr merge 8 --squash')
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T8 merge after heredoc terminator fires" "$incidents" "$out" "$exit_code" \
    "rf-never-skip-qa-review-before-merging"
  rm -rf "$tmp"
}

# --- T-MJ1: malformed-JSON stdin must fail open (exit 0, no deny) -----------
# Before the fix, jq exits 5 under `set -eo pipefail` and the hook aborts with
# no JSON. After the fix (`|| true`), CMD="" ⇒ no merge detected ⇒ exit 0.
t_mj1_malformed_json_failopen() {
  local tmp; tmp=$(mktemp -d)
  local incidents="$tmp/incidents"
  mkdir -p "$incidents"

  local out exit_code=0
  out=$(printf 'not json' | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_no_intercept "T-MJ1 malformed JSON fails open" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

t1_review_evidence_gate
t2_uncommitted_changes
t3_merge_conflict
t4_push_failure
t_fp1_commit_body_newline
t_fp2_commit_body_chain_op
t_fp3_commit_body_numbered
t_fp4_commit_body_heredoc
t5_bare_merge_fires
t6_chained_after_commit_fires
t7_wrapped_merge_fires
t8_merge_after_heredoc_fires
t_mj1_malformed_json_failopen

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
