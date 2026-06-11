#!/usr/bin/env bash
# Fixture-based tests for pencil-collapse-guard.sh. Asserts the PostToolUse
# auto-recovery path restores a tracked .pen that open_document collapsed to
# empty document state, and the no-op/fail-open paths leave the working tree
# untouched.
#
# Isolation: the hook is invoked via stdin with synthetic Claude Code payloads;
# no real Pencil MCP call is made. Each case builds a throwaway `git init` repo
# with a tracked .pen. INCIDENTS_REPO_ROOT redirects emit_incident's writes into
# that per-test repo so the telemetry assertion (AC8) reads its own JSONL.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/pencil-collapse-guard.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }

NONEMPTY='{"version":"2.11","children":[{"id":"frame-1","type":"frame","name":"Theme toggle"}]}'
COLLAPSED='{"version":"2.11","children":[]}'

# mk_repo — fresh git repo in a tmp dir; echoes the dir.
mk_repo() {
  local d
  d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "test"
  echo "$d"
}

mk_payload() {
  local path="$1"
  jq -nc --arg p "$path" '{tool_name:"mcp__pencil__open_document", tool_input:{filePath:$p}}'
}

pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; shift; for l in "$@"; do echo "  $l"; done; }

# --- AC2: collapsed tracked .pen → restored byte-identical + message + incident ---
test_restore_on_collapse() {
  TOTAL=$((TOTAL + 1))
  local repo file rel out
  repo="$(mk_repo)"
  file="$repo/design/theme-toggle.pen"
  rel="design/theme-toggle.pen"
  mkdir -p "$repo/design"
  printf '%s' "$NONEMPTY" > "$file"
  git -C "$repo" add "$rel"
  git -C "$repo" commit -q -m "add pen"
  # Simulate open_document collapse on disk.
  printf '%s' "$COLLAPSED" > "$file"

  out="$(INCIDENTS_REPO_ROOT="$repo" mk_payload "$file" | INCIDENTS_REPO_ROOT="$repo" bash "$HOOK" 2>/dev/null)"

  local disk want ctx incident
  disk="$(cat "$file")"
  want="$(git -C "$repo" show "HEAD:$rel")"
  ctx="$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"
  incident="$(grep -c '"rule_id":"cq-pencil-collapse-auto-recover".*"event_type":"warn"' "$repo/.claude/.rule-incidents.jsonl" 2>/dev/null || echo 0)"

  if [[ "$disk" == "$want" ]] && [[ "$ctx" == *"$rel"* ]] && [[ "$ctx" == *"open_document"* ]] && [[ "$incident" -ge 1 ]]; then
    pass "AC2 restore-on-collapse (byte-identical + message + incident)"
  else
    fail "AC2 restore-on-collapse" "disk=$disk" "want=$want" "ctx=$ctx" "incident=$incident"
  fi
  rm -rf "$repo"
}

# --- AC3: healthy tracked .pen → no write, no message ---
test_noop_when_healthy() {
  TOTAL=$((TOTAL + 1))
  local repo file rel out before_bytes after_bytes
  repo="$(mk_repo)"
  file="$repo/a.pen"; rel="a.pen"
  printf '%s' "$NONEMPTY" > "$file"
  git -C "$repo" add "$rel"; git -C "$repo" commit -q -m add
  # Edit it to a DIFFERENT non-empty content (legitimate in-progress edit).
  printf '%s' '{"version":"2.11","children":[{"id":"x","type":"text"}]}' > "$file"
  before_bytes="$(wc -c < "$file")"

  out="$(mk_payload "$file" | INCIDENTS_REPO_ROOT="$repo" bash "$HOOK" 2>/dev/null)"
  after_bytes="$(wc -c < "$file")"

  if [[ "$before_bytes" == "$after_bytes" ]] && [[ -z "$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)" ]]; then
    pass "AC3 no-op when healthy (bytes unchanged, no message)"
  else
    fail "AC3 no-op when healthy" "before=$before_bytes after=$after_bytes out=$out"
  fi
  rm -rf "$repo"
}

# --- AC4: HEAD blob also empty → no write ---
test_noop_when_head_also_empty() {
  TOTAL=$((TOTAL + 1))
  local repo file rel out
  repo="$(mk_repo)"
  file="$repo/scaffold.pen"; rel="scaffold.pen"
  printf '%s' "$COLLAPSED" > "$file"          # committed scaffold is itself empty
  git -C "$repo" add "$rel"; git -C "$repo" commit -q -m add
  printf '%s' "$COLLAPSED" > "$file"          # on-disk still empty

  out="$(mk_payload "$file" | INCIDENTS_REPO_ROOT="$repo" bash "$HOOK" 2>/dev/null)"

  if [[ -z "$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)" ]] && [[ "$(cat "$file")" == "$COLLAPSED" ]]; then
    pass "AC4 no-op when HEAD blob also empty"
  else
    fail "AC4 no-op when HEAD blob also empty" "out=$out"
  fi
  rm -rf "$repo"
}

# --- AC5: untracked .pen → no write ---
test_noop_when_untracked() {
  TOTAL=$((TOTAL + 1))
  local repo file out
  repo="$(mk_repo)"
  file="$repo/untracked.pen"
  printf '%s' "$COLLAPSED" > "$file"   # collapsed but never committed
  out="$(mk_payload "$file" | INCIDENTS_REPO_ROOT="$repo" bash "$HOOK" 2>/dev/null)"
  if [[ -z "$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)" ]] && [[ "$(cat "$file")" == "$COLLAPSED" ]]; then
    pass "AC5 no-op when untracked"
  else
    fail "AC5 no-op when untracked" "out=$out"
  fi
  rm -rf "$repo"
}

# --- AC6: fail-open on bad input → exit 0, no crash ---
test_fail_open() {
  # empty payload
  TOTAL=$((TOTAL + 1))
  if echo '{}' | bash "$HOOK" >/dev/null 2>&1; then
    pass "AC6a empty payload → exit 0"
  else
    fail "AC6a empty payload" "non-zero exit"
  fi

  # non-repo path
  TOTAL=$((TOTAL + 1))
  local tmpf; tmpf="$(mktemp)"; printf '%s' "$COLLAPSED" > "$tmpf"
  if mk_payload "$tmpf" | bash "$HOOK" >/dev/null 2>&1; then
    pass "AC6b non-repo path → exit 0"
  else
    fail "AC6b non-repo path" "non-zero exit"
  fi
  rm -f "$tmpf"

  # malformed JSON
  TOTAL=$((TOTAL + 1))
  if printf 'not json at all' | bash "$HOOK" >/dev/null 2>&1; then
    pass "AC6c malformed JSON → exit 0"
  else
    fail "AC6c malformed JSON" "non-zero exit"
  fi
}

# --- AC2b: 0-byte tracked .pen (raw truncation) + non-empty HEAD → restored ---
test_restore_on_empty_file() {
  TOTAL=$((TOTAL + 1))
  local repo file rel
  repo="$(mk_repo)"
  file="$repo/empty.pen"; rel="empty.pen"
  printf '%s' "$NONEMPTY" > "$file"
  git -C "$repo" add "$rel"; git -C "$repo" commit -q -m add
  : > "$file"   # truncate to 0 bytes
  mk_payload "$file" | INCIDENTS_REPO_ROOT="$repo" bash "$HOOK" >/dev/null 2>&1
  if [[ "$(cat "$file")" == "$(git -C "$repo" show "HEAD:$rel")" ]]; then
    pass "AC2b restore on 0-byte truncation"
  else
    fail "AC2b restore on 0-byte truncation" "disk=$(cat "$file")"
  fi
  rm -rf "$repo"
}

# --- AC3b: unfamiliar valid shape (different top-level container) → NOT clobbered ---
test_noop_on_unfamiliar_shape() {
  TOTAL=$((TOTAL + 1))
  local repo file rel before
  repo="$(mk_repo)"
  file="$repo/variant.pen"; rel="variant.pen"
  printf '%s' "$NONEMPTY" > "$file"
  git -C "$repo" add "$rel"; git -C "$repo" commit -q -m add
  # A future/variant schema whose nodes live under a different key — valid, not collapsed.
  before='{"version":"3.0","document":{"children":[{"id":"x"}]}}'
  printf '%s' "$before" > "$file"
  mk_payload "$file" | INCIDENTS_REPO_ROOT="$repo" bash "$HOOK" >/dev/null 2>&1
  if [[ "$(cat "$file")" == "$before" ]]; then
    pass "AC3b no-clobber on unfamiliar valid shape (no top-level children)"
  else
    fail "AC3b no-clobber on unfamiliar valid shape" "disk=$(cat "$file")"
  fi
  rm -rf "$repo"
}

# --- AC5b: symlink at filePath → no write (no symlink-follow) ---
test_noop_on_symlink() {
  TOTAL=$((TOTAL + 1))
  local repo victim link rel
  repo="$(mk_repo)"
  victim="$(mktemp)"; printf '%s' "$COLLAPSED" > "$victim"   # collapsed-shaped victim
  link="$repo/link.pen"; rel="link.pen"
  ln -s "$victim" "$link"
  git -C "$repo" add "$rel"; git -C "$repo" commit -q -m "add symlink pen"
  mk_payload "$link" | INCIDENTS_REPO_ROOT="$repo" bash "$HOOK" >/dev/null 2>&1
  # Victim (symlink target) must be untouched — still the collapsed content.
  if [[ "$(cat "$victim")" == "$COLLAPSED" ]]; then
    pass "AC5b no symlink-follow write"
  else
    fail "AC5b no symlink-follow write" "victim=$(cat "$victim")"
  fi
  rm -rf "$repo" "$victim"
}

test_restore_on_collapse
test_restore_on_empty_file
test_noop_when_healthy
test_noop_on_unfamiliar_shape
test_noop_when_head_also_empty
test_noop_when_untracked
test_noop_on_symlink
test_fail_open

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
