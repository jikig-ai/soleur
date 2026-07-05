#!/usr/bin/env bash
# Fixture-based tests for context-reviewed-gate.sh (issue #5999, ADR-085).
#
# Each case builds a throwaway git repo, stages/edits a `last_reviewed` delta,
# composes a PreToolUse(Bash) input, pipes it to the hook, and asserts on the
# JSON permissionDecision (NOT exit code — a PreToolUse deny exits 0). The hook
# only INSPECTS repo state; the crafted `git commit …` string is never executed.
#
# Isolation pattern mirrors follow-through-directive-gate.test.sh. INCIDENTS_REPO_ROOT
# is redirected per-run to a tmp dir so incident rows are assertable and the
# operator's real .claude/.rule-incidents.jsonl is never touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/context-reviewed-gate.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }
command -v perl >/dev/null 2>&1 || { echo "SKIP: perl missing"; exit 0; }
if [[ ! -f "$HOOK" ]]; then
  echo "SKIP: $HOOK not yet present (RED)"
  exit 0
fi

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "FAIL: $1"; echo "  detail: ${2:-}"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }

# Build a git repo whose HEAD commit contains doc.md with the given body.
# Echoes the repo path. Args: <initial doc.md body> (empty → no doc.md).
INCIDENTS_DIR=""
new_repo() {
  local tmp; tmp=$(mktemp -d)
  git -C "$tmp" init -q
  git -C "$tmp" config user.email t@t.dev
  git -C "$tmp" config user.name t
  git -C "$tmp" config commit.gpgsign false
  if [[ -n "${1:-}" ]]; then
    printf '%s\n' "$1" > "$tmp/doc.md"
    git -C "$tmp" add doc.md
  else
    printf 'seed\n' > "$tmp/seed.txt"
    git -C "$tmp" add seed.txt
  fi
  git -C "$tmp" commit -q -m "init"
  echo "$tmp"
}

# Compose the PreToolUse input JSON. Args: <command> <cwd>
make_input() { jq -n --arg cmd "$1" --arg cwd "$2" '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}'; }

# Run the hook with a fresh incident ledger. Sets HOOK_OUT.
run_hook() {
  INCIDENTS_DIR=$(mktemp -d)
  HOOK_OUT=$(printf '%s' "$1" | INCIDENTS_REPO_ROOT="$INCIDENTS_DIR" "$HOOK" 2>/dev/null)
}

decision_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null; }

assert_deny() {
  local name="$1"
  if [[ "$(decision_of "$HOOK_OUT")" == "deny" ]]; then pass "$name"; else fail "$name" "expected deny, got: ${HOOK_OUT:0:200}"; fi
}
assert_allow() {
  local name="$1"
  if [[ "$(decision_of "$HOOK_OUT")" != "deny" ]]; then pass "$name"; else fail "$name" "expected allow (no deny), got deny"; fi
}
assert_incident() {
  local name="$1" kind="$2" ledger="$INCIDENTS_DIR/.claude/.rule-incidents.jsonl"
  if [[ -f "$ledger" ]] && grep -q "$kind" "$ledger"; then pass "$name"; else fail "$name" "expected incident '$kind' in ledger; ledger: $([[ -f $ledger ]] && cat "$ledger" || echo MISSING)"; fi
}

# --- AC1: staged last_reviewed bump, no trailer → deny --------------------
t_ac1_staged_bump_deny() {
  local r; r=$(new_repo "last_reviewed: 2026-01-01")
  printf 'last_reviewed: 2026-07-05\n' > "$r/doc.md"; git -C "$r" add doc.md
  run_hook "$(make_input "git -C $r commit -m 'docs: bump'" "$r")"
  assert_deny "AC1 staged bump no-trailer → deny"
  rm -rf "$r" "$INCIDENTS_DIR"
}

# --- AC2: `git commit -am` bump (working-tree, unstaged), no trailer → deny
#     Regression for P0-2: --cached-only detection would have missed this. -----
t_ac2_am_bump_deny() {
  local r; r=$(new_repo "last_reviewed: 2026-01-01")
  printf 'last_reviewed: 2026-07-05\n' > "$r/doc.md"   # modified, NOT staged
  run_hook "$(make_input "git -C $r commit -am 'docs: bump'" "$r")"
  assert_deny "AC2 -am working-tree bump no-trailer → deny (P0-2)"
  rm -rf "$r" "$INCIDENTS_DIR"
}

# --- AC3a: net-new doc adding last_reviewed for the first time → allow ------
t_ac3a_netnew_add_allow() {
  local r; r=$(new_repo "")
  printf 'last_reviewed: 2026-07-05\n' > "$r/newdoc.md"; git -C "$r" add newdoc.md
  run_hook "$(make_input "git -C $r commit -m 'docs: new'" "$r")"
  assert_allow "AC3a net-new add (only +) → allow without trailer"
  rm -rf "$r" "$INCIDENTS_DIR"
}

# --- AC3b: quoted / space-before-colon / case-variant CHANGE, no trailer → deny
t_ac3b_quoted_variant_deny() {
  local r; r=$(new_repo '"Last_Reviewed" : 2026-01-01')
  printf '"Last_Reviewed" : 2026-07-05\n' > "$r/doc.md"; git -C "$r" add doc.md
  run_hook "$(make_input "git -C $r commit -m 'docs: bump'" "$r")"
  assert_deny "AC3b quoted/spaced/case variant change → deny (P1-4)"
  rm -rf "$r" "$INCIDENTS_DIR"
}

# --- AC3c: last_reviewed line DELETION, no trailer → deny ------------------
t_ac3c_deletion_deny() {
  local r; r=$(new_repo "$(printf 'title: x\nlast_reviewed: 2026-01-01')")
  printf 'title: x\n' > "$r/doc.md"; git -C "$r" add doc.md   # last_reviewed removed
  run_hook "$(make_input "git -C $r commit -m 'docs: drop clock'" "$r")"
  assert_deny "AC3c deletion → deny"
  rm -rf "$r" "$INCIDENTS_DIR"
}

# --- AC4a: trailer in a 2nd -m paragraph → allow --------------------------
t_ac4a_trailer_2nd_m_allow() {
  local r; r=$(new_repo "last_reviewed: 2026-01-01")
  printf 'last_reviewed: 2026-07-05\n' > "$r/doc.md"; git -C "$r" add doc.md
  run_hook "$(make_input "git -C $r commit -m 'docs: bump' -m 'Context-Reviewed: all'" "$r")"
  assert_allow "AC4a trailer in 2nd -m → allow (P1-5)"
  rm -rf "$r" "$INCIDENTS_DIR"
}

# --- AC4b: trailer via -F file → allow ------------------------------------
t_ac4b_trailer_F_allow() {
  local r; r=$(new_repo "last_reviewed: 2026-01-01")
  printf 'last_reviewed: 2026-07-05\n' > "$r/doc.md"; git -C "$r" add doc.md
  printf 'docs: bump\n\nContext-Reviewed: all\n' > "$r/msg.txt"
  run_hook "$(make_input "git -C $r commit -F $r/msg.txt" "$r")"
  assert_allow "AC4b trailer via -F file → allow"
  rm -rf "$r" "$INCIDENTS_DIR"
}

# --- last_updated-only change → allow (not a last_reviewed delta) ----------
t_last_updated_only_allow() {
  local r; r=$(new_repo "$(printf 'last_updated: 2026-01-01\nlast_reviewed: 2026-01-01')")
  printf 'last_updated: 2026-07-05\nlast_reviewed: 2026-01-01\n' > "$r/doc.md"; git -C "$r" add doc.md
  run_hook "$(make_input "git -C $r commit -m 'docs: touch'" "$r")"
  assert_allow "last_updated-only change → allow"
  rm -rf "$r" "$INCIDENTS_DIR"
}

# --- AC5: -F file unreadable on a real last_reviewed commit → fail-open + warn
t_ac5_F_unreadable_failopen() {
  local r; r=$(new_repo "last_reviewed: 2026-01-01")
  printf 'last_reviewed: 2026-07-05\n' > "$r/doc.md"; git -C "$r" add doc.md
  run_hook "$(make_input "git -C $r commit -F $r/does-not-exist.txt" "$r")"
  assert_allow "AC5 -F unreadable → fail-open (allow)"
  assert_incident "AC5 -F unreadable → warn hook_self_fault incident" "hook_self_fault"
  rm -rf "$r" "$INCIDENTS_DIR"
}

# --- non-commit git command → silent fail-open (no deny) -------------------
t_noncommit_silent() {
  local r; r=$(new_repo "last_reviewed: 2026-01-01")
  printf 'last_reviewed: 2026-07-05\n' > "$r/doc.md"; git -C "$r" add doc.md
  run_hook "$(make_input "git -C $r status" "$r")"
  assert_allow "non-commit (git status) → silent fail-open"
  rm -rf "$r" "$INCIDENTS_DIR"
}

# --- self-trigger guard: a commit MESSAGE documenting last_reviewed but with
#     NO actual last_reviewed delta → allow (bodies stripped before trigger) --
t_message_documents_but_no_delta_allow() {
  local r; r=$(new_repo "last_reviewed: 2026-01-01")
  printf 'x\n' > "$r/other.md"; git -C "$r" add other.md   # unrelated staged change
  run_hook "$(make_input "git -C $r commit -m 'docs: note about last_reviewed convention'" "$r")"
  assert_allow "message mentions last_reviewed but no delta → allow"
  rm -rf "$r" "$INCIDENTS_DIR"
}

t_ac1_staged_bump_deny
t_ac2_am_bump_deny
t_ac3a_netnew_add_allow
t_ac3b_quoted_variant_deny
t_ac3c_deletion_deny
t_ac4a_trailer_2nd_m_allow
t_ac4b_trailer_F_allow
t_last_updated_only_allow
t_ac5_F_unreadable_failopen
t_noncommit_silent
t_message_documents_but_no_delta_allow

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]]
