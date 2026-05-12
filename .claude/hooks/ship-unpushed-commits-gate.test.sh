#!/usr/bin/env bash
# Fixture-based tests for ship-unpushed-commits-gate.sh. Asserts the hook
# blocks `gh pr merge` when local commits are ahead of origin/<branch> and
# fail-opens on every infra/edge case.
#
# Isolation pattern matches pre-merge-rebase.test.sh: each test builds its own
# tmp work-tree + tmp incidents root; INCIDENTS_REPO_ROOT redirects the jsonl
# off the operator's real .claude/.rule-incidents.jsonl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/ship-unpushed-commits-gate.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

# Build a work-tree cloned from a fresh bare origin, on a feature branch
# tracking origin/<branch>. Echoes "$work $origin $incidents" to stdout.
make_synced_branch() {
  local tmp="$1" branch="$2"
  local work="$tmp/work" origin="$tmp/origin.git" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  git init -q --bare "$origin"
  init_git_repo "$work"
  echo "base" > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m "init"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin main
  git -C "$work" checkout -q -b "$branch"
  echo "feature" > "$work/feat.txt"
  git -C "$work" add feat.txt
  git -C "$work" commit -q -m "feature work"
  # Push so origin/<branch> exists and tracking is current.
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
    echo "FAIL: $name (no incidents jsonl at $jsonl; exit=$exit_code decision=$decision)"
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); return
  fi
  count=$(wc -l < "$jsonl" | tr -d ' ')
  seen_rule=$(jq -r '.rule_id' < "$jsonl" | head -1)
  seen_event=$(jq -r '.event_type' < "$jsonl" | head -1)
  if [[ "$exit_code" -eq 0 && "$decision" == "deny" && "$count" == "1" \
        && "$seen_rule" == "wg-ship-push-before-merge" && "$seen_event" == "deny" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  exit=$exit_code decision=$decision count=$count rule=$seen_rule event=$seen_event"
    echo "  expected: rule=wg-ship-push-before-merge event=deny count=1 decision=deny"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

# assert_pass <name> <incidents_root> <stdout> <exit_code>
# Hook exits 0 with EITHER empty output OR additionalContext JSON (no deny).
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
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  exit=$exit_code decision=$decision denied_rows=$denied_rows"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

run_hook() {
  local incidents="$1" payload="$2"
  INCIDENTS_REPO_ROOT="$incidents" printf '%s' "$payload" | "$HOOK" 2>/dev/null
}

# --- T1: unpushed commits → DENY -----------------------------------------
t1_unpushed_commits_deny() {
  local tmp; tmp=$(mktemp -d)
  read -r work origin incidents < <(make_synced_branch "$tmp" "feat-unpushed")
  # Add a local commit AFTER the initial push; do not push.
  echo "fix" > "$work/fix.txt"
  git -C "$work" add fix.txt
  git -C "$work" commit -q -m "the actual fix"

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 123 --squash --auto")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T1 unpushed commits" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# --- T2: clean state → PASS ----------------------------------------------
t2_clean_state_pass() {
  local tmp; tmp=$(mktemp -d)
  read -r work origin incidents < <(make_synced_branch "$tmp" "feat-clean")
  # No local commits ahead of origin/<branch>.

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 124 --squash --auto")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_pass "T2 clean state" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# --- T3: on main → PASS (fail-open) --------------------------------------
t3_on_main_pass() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  # Stay on main.

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 125 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_pass "T3 on main" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# --- T4: detached HEAD → PASS (fail-open) --------------------------------
t4_detached_head_pass() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  echo a > "$work/a"
  git -C "$work" add a
  git -C "$work" commit -q -m "first"
  echo b > "$work/b"
  git -C "$work" add b
  git -C "$work" commit -q -m "second"
  # Detach.
  local sha
  sha=$(git -C "$work" rev-parse HEAD)
  git -C "$work" checkout -q "$sha"

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 126 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_pass "T4 detached HEAD" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# --- T5: no upstream tracking → PASS (fail-open) -------------------------
t5_no_upstream_pass() {
  local tmp; tmp=$(mktemp -d)
  local work="$tmp/work" incidents="$tmp/incidents"
  mkdir -p "$work" "$incidents"
  init_git_repo "$work"
  git -C "$work" commit -q --allow-empty -m "init"
  git -C "$work" checkout -q -b feat-lonely
  # No remote, no upstream.

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 127 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_pass "T5 no upstream" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# --- T6: non-merge command → PASS (no-op early exit) ---------------------
t6_non_merge_command_pass() {
  local tmp; tmp=$(mktemp -d)
  read -r work origin incidents < <(make_synced_branch "$tmp" "feat-status")
  echo "x" > "$work/x.txt"
  git -C "$work" add x.txt
  git -C "$work" commit -q -m "local only"

  local payload out exit_code=0
  payload=$(make_payload "$work" "git status")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_pass "T6 non-merge command (unpushed but irrelevant)" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# --- T7: chained command form → DENY -------------------------------------
t7_chained_command_deny() {
  local tmp; tmp=$(mktemp -d)
  read -r work origin incidents < <(make_synced_branch "$tmp" "feat-chained")
  echo "fix" > "$work/fix.txt"
  git -C "$work" add fix.txt
  git -C "$work" commit -q -m "the fix"

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr ready 128 && gh pr merge 128 --squash --auto")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T7 chained && gh pr merge" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# --- T8: substring false-positive in echo string → PASS ------------------
t8_substring_false_positive_pass() {
  local tmp; tmp=$(mktemp -d)
  read -r work origin incidents < <(make_synced_branch "$tmp" "feat-echoes")
  echo "fix" > "$work/fix.txt"
  git -C "$work" add fix.txt
  git -C "$work" commit -q -m "local commit"

  local payload out exit_code=0
  # The literal `gh pr merge` is INSIDE an echo string, not at start-of-cmd.
  payload=$(make_payload "$work" "echo 'gh pr merge example'")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_pass "T8 substring not anchored" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# --- T9: fetch network failure → PASS (fail-open) ------------------------
t9_fetch_failure_pass() {
  local tmp; tmp=$(mktemp -d)
  read -r work origin incidents < <(make_synced_branch "$tmp" "feat-no-net")
  echo "fix" > "$work/fix.txt"
  git -C "$work" add fix.txt
  git -C "$work" commit -q -m "local commit"
  # Repoint origin to an unreachable URL so `git fetch origin <branch>` fails.
  git -C "$work" remote set-url origin /nonexistent/path/to/repo.git

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 129 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  assert_pass "T9 fetch failure fail-open" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# --- T10: settings.json structural validity (integration) ----------------
# Skips if settings.json does not yet reference the hook (Phase B not done).
t10_settings_json_valid() {
  local settings="$REPO_ROOT/.claude/settings.json"
  if [[ ! -f "$settings" ]]; then
    echo "SKIP: T10 settings.json not found"
    return
  fi
  if ! grep -q "ship-unpushed-commits-gate.sh" "$settings"; then
    echo "SKIP: T10 hook not yet wired in settings.json (Phase B pending)"
    return
  fi
  if jq . "$settings" > /dev/null 2>&1; then
    echo "PASS: T10 settings.json structural validity"
    PASS=$((PASS + 1))
  else
    echo "FAIL: T10 settings.json failed jq parse"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

# --- T11: hook ordering (integration) ------------------------------------
# Confirms the unpushed-commits-gate hook is listed AFTER pre-merge-rebase.sh.
t11_hook_ordering() {
  local settings="$REPO_ROOT/.claude/settings.json"
  if [[ ! -f "$settings" ]]; then
    echo "SKIP: T11 settings.json not found"
    return
  fi
  if ! grep -q "ship-unpushed-commits-gate.sh" "$settings"; then
    echo "SKIP: T11 hook not yet wired in settings.json (Phase B pending)"
    return
  fi
  # Extract Bash-matcher hook commands in document order.
  local order
  order=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$settings" 2>/dev/null)
  local rebase_line ship_line
  rebase_line=$(printf '%s\n' "$order" | grep -n "pre-merge-rebase.sh" | head -1 | cut -d: -f1)
  ship_line=$(printf '%s\n' "$order" | grep -n "ship-unpushed-commits-gate.sh" | head -1 | cut -d: -f1)
  if [[ -n "$rebase_line" && -n "$ship_line" && "$ship_line" -gt "$rebase_line" ]]; then
    echo "PASS: T11 hook ordering (ship-unpushed-commits-gate after pre-merge-rebase)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: T11 hook ordering rebase=$rebase_line ship=$ship_line"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
}

# --- T12: emit_incident prefix length ≤50 chars --------------------------
t12_emit_incident_prefix_length() {
  local tmp; tmp=$(mktemp -d)
  read -r work origin incidents < <(make_synced_branch "$tmp" "feat-prefix")
  echo "fix" > "$work/fix.txt"
  git -C "$work" add fix.txt
  git -C "$work" commit -q -m "local"

  local payload exit_code=0
  payload=$(make_payload "$work" "gh pr merge 130 --squash")
  printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" >/dev/null 2>/dev/null || exit_code=$?
  local jsonl="$incidents/.claude/.rule-incidents.jsonl"
  if [[ -f "$jsonl" ]]; then
    local plen
    plen=$(jq -r '.rule_text_prefix | length' < "$jsonl" | head -1)
    if [[ "$plen" -le 50 ]]; then
      echo "PASS: T12 emit_incident prefix length ($plen ≤ 50)"
      PASS=$((PASS + 1))
    else
      echo "FAIL: T12 emit_incident prefix length ($plen > 50)"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "FAIL: T12 no incidents jsonl"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

# --- T13: emit_incident INCIDENTS_REPO_ROOT redirect ---------------------
t13_incidents_redirect() {
  local tmp; tmp=$(mktemp -d)
  read -r work origin incidents < <(make_synced_branch "$tmp" "feat-redirect")
  echo "fix" > "$work/fix.txt"
  git -C "$work" add fix.txt
  git -C "$work" commit -q -m "local"

  local payload exit_code=0
  payload=$(make_payload "$work" "gh pr merge 131 --squash")
  printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" >/dev/null 2>/dev/null || exit_code=$?
  if [[ -f "$incidents/.claude/.rule-incidents.jsonl" ]]; then
    echo "PASS: T13 INCIDENTS_REPO_ROOT redirect lands in tmp"
    PASS=$((PASS + 1))
  else
    echo "FAIL: T13 jsonl not at $incidents/.claude/.rule-incidents.jsonl"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

# --- T14: stdout JSON not corrupted by git progress (R5) -----------------
t14_stdout_json_clean() {
  local tmp; tmp=$(mktemp -d)
  read -r work origin incidents < <(make_synced_branch "$tmp" "feat-clean-stdout")
  echo "fix" > "$work/fix.txt"
  git -C "$work" add fix.txt
  git -C "$work" commit -q -m "local"

  local payload out exit_code=0
  payload=$(make_payload "$work" "gh pr merge 132 --squash")
  out=$(printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?
  # Validate stdout is exactly one JSON object.
  if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    echo "PASS: T14 stdout is valid JSON (no git progress leak)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: T14 stdout failed jq parse"
    echo "  stdout='${out:0:200}...'"
    FAIL=$((FAIL + 1))
  fi
  TOTAL=$((TOTAL + 1))
  rm -rf "$tmp"
}

t1_unpushed_commits_deny
t2_clean_state_pass
t3_on_main_pass
t4_detached_head_pass
t5_no_upstream_pass
t6_non_merge_command_pass
t7_chained_command_deny
t8_substring_false_positive_pass
t9_fetch_failure_pass
t10_settings_json_valid
t11_hook_ordering
t12_emit_incident_prefix_length
t13_incidents_redirect
t14_stdout_json_clean

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
