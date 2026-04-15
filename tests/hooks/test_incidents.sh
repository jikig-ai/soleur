#!/usr/bin/env bash
# Tests for .claude/hooks/lib/incidents.sh.
# Sources the library in an isolated HOME + repo root tmp dir so each case
# controls its own jsonl file.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/.claude/hooks/lib/incidents.sh"

pass=0
fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1))
    echo "[ok] $label"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label $detail" >&2
  fi
}

_with_fake_repo() {
  # Create a fake repo root mirroring .claude/hooks/lib layout, copy the lib
  # into it, cd there, and export INCIDENTS_REPO_ROOT so emit_incident writes
  # its jsonl under the tmp dir instead of the real repo.
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.claude/hooks/lib"
  cp "$LIB" "$tmp/.claude/hooks/lib/incidents.sh"
  echo "$tmp"
}

# ---------------------------------------------------------------------------
# T1: emit_incident writes a valid JSON line
# ---------------------------------------------------------------------------
t_emit_valid_json() {
  local tmp; tmp=$(_with_fake_repo)
  (
    cd "$tmp"
    # shellcheck source=/dev/null
    source "$tmp/.claude/hooks/lib/incidents.sh"
    emit_incident "hr-test-rule" "deny" "first fifty chars prefix"
  )
  local file="$tmp/.claude/.rule-incidents.jsonl"
  if [[ ! -s "$file" ]]; then
    _report "emit writes jsonl line" fail "file empty or missing"
    rm -rf "$tmp"; return
  fi
  # Valid JSON
  if ! jq empty "$file" 2>/dev/null; then
    _report "emit writes valid JSON" fail
    rm -rf "$tmp"; return
  fi
  # Correct fields
  local rid evt
  rid=$(jq -r '.rule_id' < "$file")
  evt=$(jq -r '.event_type' < "$file")
  if [[ "$rid" == "hr-test-rule" && "$evt" == "deny" ]]; then
    _report "emit writes jsonl line" ok
  else
    _report "emit writes jsonl line" fail "rid=$rid evt=$evt"
  fi
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# T2: concurrent writes don't interleave (flock serializes)
# ---------------------------------------------------------------------------
t_concurrency() {
  local tmp; tmp=$(_with_fake_repo)
  (
    cd "$tmp"
    # shellcheck source=/dev/null
    source "$tmp/.claude/hooks/lib/incidents.sh"
    touch "$tmp/.claude/.rule-incidents.jsonl"
    for i in 1 2 3 4 5 6 7 8 9 10; do
      emit_incident "hr-rule-$i" "deny" "msg $i" &
    done
    wait
  )
  local file="$tmp/.claude/.rule-incidents.jsonl"
  local lines
  lines=$(wc -l < "$file")
  if [[ "$lines" != "10" ]]; then
    _report "concurrency writes 10 lines" fail "got $lines"
    rm -rf "$tmp"; return
  fi
  # Every line must be valid JSON
  if jq empty "$file" 2>/dev/null; then
    _report "concurrency writes valid JSON" ok
  else
    _report "concurrency writes valid JSON" fail
  fi
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# T3: BASH_SOURCE resolution from a nested hook directory still writes
# to <repo>/.claude/.rule-incidents.jsonl (not the caller's cwd).
# ---------------------------------------------------------------------------
t_bash_source_resolution() {
  local tmp; tmp=$(_with_fake_repo)
  mkdir -p "$tmp/.claude/hooks/nested/deep"
  # simulate calling from a nested hook location by writing a caller that
  # sources the lib from a nested sibling, while cwd is elsewhere
  cat > "$tmp/.claude/hooks/nested/deep/caller.sh" <<'CALLER'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/incidents.sh"
emit_incident "hr-from-nested" "deny" "nested prefix"
CALLER
  chmod +x "$tmp/.claude/hooks/nested/deep/caller.sh"
  (
    cd /  # deliberately hostile cwd
    bash "$tmp/.claude/hooks/nested/deep/caller.sh"
  )
  local file="$tmp/.claude/.rule-incidents.jsonl"
  if [[ -s "$file" ]] && jq -e '.rule_id == "hr-from-nested"' < "$file" >/dev/null; then
    _report "BASH_SOURCE resolves repo root from nested hook" ok
  else
    _report "BASH_SOURCE resolves repo root from nested hook" fail "file=$(cat "$file" 2>/dev/null)"
  fi
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# T4: detect_bypass recognizes --no-verify and LEFTHOOK=0 only (v1)
# ---------------------------------------------------------------------------
t_detect_bypass() {
  # shellcheck source=/dev/null
  source "$LIB"

  local r
  r=$(detect_bypass "Bash" "git commit --no-verify -m foo")
  [[ "$r" == "cq-never-skip-hooks" ]] || { _report "detect_bypass --no-verify" fail "got=$r"; return; }

  r=$(detect_bypass "Bash" "LEFTHOOK=0 git commit -m foo")
  [[ "$r" == "cq-when-lefthook-hangs-in-a-worktree-60s" ]] || { _report "detect_bypass LEFTHOOK=0" fail "got=$r"; return; }

  r=$(detect_bypass "Bash" "git push --force origin feature")
  [[ -z "$r" ]] || { _report "detect_bypass ignores --force (v1)" fail "got=$r"; return; }

  r=$(detect_bypass "Bash" "git commit --amend")
  [[ -z "$r" ]] || { _report "detect_bypass ignores --amend (v1)" fail "got=$r"; return; }

  # False-positive guards: substring occurrences in non-git contexts must not trip
  r=$(detect_bypass "Bash" 'echo "do not use --no-verify"')
  [[ -z "$r" ]] || { _report "detect_bypass ignores --no-verify in echo string" fail "got=$r"; return; }

  r=$(detect_bypass "Bash" 'gh pr comment 1 --body "--no-verify was used"')
  [[ -z "$r" ]] || { _report "detect_bypass ignores --no-verify in gh body" fail "got=$r"; return; }

  r=$(detect_bypass "Bash" 'echo "LEFTHOOK=0 is banned"')
  [[ -z "$r" ]] || { _report "detect_bypass ignores LEFTHOOK=0 in echo string" fail "got=$r"; return; }

  # Positive after chain operator still matches
  r=$(detect_bypass "Bash" "cd /tmp && git commit --no-verify -m foo")
  [[ "$r" == "cq-never-skip-hooks" ]] || { _report "detect_bypass chained --no-verify" fail "got=$r"; return; }

  _report "detect_bypass v1 scope" ok
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if [[ ! -f "$LIB" ]]; then
  echo "ERROR: $LIB does not exist — RED phase expected this." >&2
  exit 1
fi

t_emit_valid_json
t_concurrency
t_bash_source_resolution
t_detect_bypass

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
