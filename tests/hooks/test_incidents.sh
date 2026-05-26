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

# ---------------------------------------------------------------------------
# T5: _emit_drop_sentinel writes a fixed-string JSON line, set -u clean,
# uses non-blocking flock that fails open under contention.
# ---------------------------------------------------------------------------
t_emit_drop_sentinel_basic() {
  local tmp; tmp=$(_with_fake_repo)
  local sink="$tmp/.claude/.session-tokens.jsonl"
  : > "$sink"
  (
    set -u   # mirror agent-token-tee.sh's invariant
    cd "$tmp"
    # shellcheck source=/dev/null
    source "$tmp/.claude/hooks/lib/incidents.sh"
    _emit_drop_sentinel "$sink" "PostToolUse" "jq_fail"
  )
  if [[ ! -s "$sink" ]]; then
    _report "_emit_drop_sentinel writes a sentinel" fail "file empty"
    rm -rf "$tmp"; return
  fi
  if ! jq -e '.schema == 1 and .hook_event == "PostToolUse" and .error == "jq_fail" and (.ts | type) == "string"' "$sink" >/dev/null 2>&1; then
    _report "_emit_drop_sentinel writes a sentinel" fail "got=$(cat "$sink")"
    rm -rf "$tmp"; return
  fi
  # Discriminator invariant: sentinel must NOT carry `rule_id` or `event_type`
  # (so consumer-side `select(.rule_id != null)` / `select(.event_type=="deny")`
  # filters exclude it). The aggregator filter contract depends on this.
  if jq -e '.rule_id // .event_type' "$sink" >/dev/null 2>&1; then
    _report "sentinel has no rule_id / event_type" fail "got=$(cat "$sink")"
    rm -rf "$tmp"; return
  fi
  _report "_emit_drop_sentinel writes a sentinel" ok
  rm -rf "$tmp"
}

# Non-blocking flock fallback: when a sibling holds the lock on the sink,
# the helper must NOT hang and must NOT corrupt the file. Drop is silent.
t_emit_drop_sentinel_flock_nonblocking() {
  local tmp; tmp=$(_with_fake_repo)
  local sink="$tmp/.claude/.session-tokens.jsonl"
  : > "$sink"
  # Hold an exclusive lock on the sink in a background subshell for ~3s.
  (
    flock -x 9
    sleep 3
  ) 9>>"$sink" &
  local holder_pid=$!
  # Wait until the holder has acquired the lock so the test is deterministic.
  sleep 0.3
  local start_epoch end_epoch
  start_epoch=$(date +%s)
  (
    set -u
    cd "$tmp"
    # shellcheck source=/dev/null
    source "$tmp/.claude/hooks/lib/incidents.sh"
    _emit_drop_sentinel "$sink" "PostToolUse" "flock_timeout"
  )
  end_epoch=$(date +%s)
  local elapsed=$(( end_epoch - start_epoch ))
  # Don't leave the holder running.
  kill "$holder_pid" 2>/dev/null || true
  wait "$holder_pid" 2>/dev/null || true
  if (( elapsed >= 2 )); then
    _report "_emit_drop_sentinel non-blocking flock" fail "blocked $elapsed seconds (expected <1s)"
    rm -rf "$tmp"; return
  fi
  # The drop is silent; the sink may be empty or still locked — either way,
  # no torn writes. Once the lock releases (kill above), the file is jq-clean
  # if anything landed. We assert no partial bytes (file ends with \n or empty).
  if [[ -s "$sink" ]] && ! jq empty "$sink" >/dev/null 2>&1; then
    _report "_emit_drop_sentinel non-blocking flock" fail "torn write: $(cat "$sink")"
    rm -rf "$tmp"; return
  fi
  _report "_emit_drop_sentinel non-blocking flock" ok
  rm -rf "$tmp"
}

# set -u clean: missing args must NOT error out under `set -u`.
t_emit_drop_sentinel_setu_clean() {
  local tmp; tmp=$(_with_fake_repo)
  local rc
  set +e
  (
    set -u
    cd "$tmp"
    # shellcheck source=/dev/null
    source "$tmp/.claude/hooks/lib/incidents.sh"
    _emit_drop_sentinel "" "" ""
    _emit_drop_sentinel
  )
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    _report "_emit_drop_sentinel set -u clean on missing args" fail "rc=$rc"
    rm -rf "$tmp"; return
  fi
  _report "_emit_drop_sentinel set -u clean on missing args" ok
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# T6: emit_incident on jq_fail emits a sentinel via _emit_drop_sentinel
# ---------------------------------------------------------------------------
# Override jq with a wrapper that fails on the line-build pass (`jq -nc ...`)
# but delegates everything else to real jq.
t_emit_incident_jq_fail() {
  local tmp; tmp=$(_with_fake_repo)
  local fake_bin; fake_bin=$(mktemp -d)
  local real_jq; real_jq=$(command -v jq)
  cat > "$fake_bin/jq" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    -n|-nc|-cn|--null-input) exit 1 ;;
  esac
done
exec "$real_jq" "\$@"
EOF
  chmod +x "$fake_bin/jq"
  (
    cd "$tmp"
    PATH="$fake_bin:$PATH"
    # shellcheck source=/dev/null
    source "$tmp/.claude/hooks/lib/incidents.sh"
    emit_incident "hr-test-rule" "deny" "x" ""
  )
  local file="$tmp/.claude/.rule-incidents.jsonl"
  if [[ ! -f "$file" ]] || ! jq -e 'select(.error == "jq_fail")' "$file" >/dev/null 2>&1; then
    _report "emit_incident emits jq_fail sentinel" fail "got=$(cat "$file" 2>/dev/null)"
  elif jq -e 'select(.event_type == "deny")' "$file" >/dev/null 2>&1; then
    _report "emit_incident emits jq_fail sentinel" fail "data line written: $(cat "$file")"
  else
    _report "emit_incident emits jq_fail sentinel" ok
  fi
  rm -rf "$tmp" "$fake_bin"
}

# ---------------------------------------------------------------------------
# T7: emit_incident on rotation_fail emits a sentinel + writes data line
# ---------------------------------------------------------------------------
# Pre-fill the jsonl past the rotation threshold + chmod 0500 the parent so
# the rotator's archive write fails. The data line should still land (we
# only chmod the parent dir, not the file itself).
t_emit_incident_rotation_fail() {
  if [[ $(id -u) -eq 0 ]]; then
    _report "emit_incident emits rotation_fail sentinel (skipped under root)" ok
    return
  fi
  local tmp; tmp=$(_with_fake_repo)
  local file="$tmp/.claude/.rule-incidents.jsonl"
  for i in $(seq 1 30); do
    printf '{"schema":1,"timestamp":"2026-01-01T00:00:00Z","rule_id":"hr-pre","event_type":"deny","rule_text_prefix":"x","command_snippet":""}\n' >> "$file"
  done
  rm -f "/tmp/log-rotation-warned-$$" 2>/dev/null || true
  chmod 0500 "$tmp/.claude"
  (
    cd "$tmp"
    # shellcheck source=/dev/null
    source "$tmp/.claude/hooks/lib/incidents.sh"
    LOG_ROTATION_SIZE_BYTES=1024 emit_incident "hr-test-rule" "deny" "x" "" 2>/dev/null
  )
  chmod 0700 "$tmp/.claude"
  if ! jq -e 'select(.error == "rotation_fail" and .hook_event == "PreToolUse")' "$file" >/dev/null 2>&1; then
    _report "emit_incident emits rotation_fail sentinel" fail "no sentinel: $(cat "$file" | tail -3)"
  elif ! jq -e 'select(.rule_id == "hr-test-rule")' "$file" >/dev/null 2>&1; then
    _report "emit_incident emits rotation_fail sentinel" fail "data line missing: $(cat "$file" | tail -3)"
  else
    _report "emit_incident emits rotation_fail sentinel" ok
  fi
  rm -f "/tmp/log-rotation-warned-$$" 2>/dev/null || true
  rm -rf "$tmp"
}

t_emit_valid_json
t_concurrency
t_bash_source_resolution
t_detect_bypass
t_emit_drop_sentinel_basic
t_emit_drop_sentinel_flock_nonblocking
t_emit_drop_sentinel_setu_clean
t_emit_incident_jq_fail
t_emit_incident_rotation_fail

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
