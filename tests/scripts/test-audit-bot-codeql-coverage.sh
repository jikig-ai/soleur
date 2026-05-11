#!/usr/bin/env bash
# Tests for scripts/audit-bot-codeql-coverage.sh.
# Deterministic; no live API. Uses AUDIT_FIXTURE_OVERRIDE to mock check-runs payloads.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/audit-bot-codeql-coverage.sh"
FIXTURE_DIR="$REPO_ROOT/scripts/fixtures/audit-bot-codeql-coverage"
pass=0; fail=0

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

# Run audit script with a single fixture pinned via AUDIT_FIXTURE_OVERRIDE +
# AUDIT_FIXED_WORKFLOWS (workflow,pr,sha triple — script bypasses gh pr list
# enumeration). Returns "tmpdir:rc".
_run() {
  local fixture="$1" workflow="${2:-scheduled-skill-freshness.yml}"
  local tmp; tmp=$(mktemp -d)
  local rc=0
  AUDIT_FIXTURE_OVERRIDE="$FIXTURE_DIR/$fixture" \
  AUDIT_FIXED_WORKFLOWS="$workflow:1:abcdef1234567890" \
  AUDIT_TELEMETRY_DIR="$tmp/state" \
    bash "$SCRIPT" --json >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  echo "$tmp:$rc"
}

_envelope_field() {
  local tmp="$1" jq_path="$2"
  jq -r "$jq_path // empty" < "$tmp/stdout" 2>/dev/null || true
}

# T1: neutral-passing -> exit 0, codeql_state=neutral/passing
t_neutral_passing() {
  local r; r=$(_run neutral-passing.json)
  local tmp="${r%:*}" rc="${r##*:}"
  local passing drift; passing=$(_envelope_field "$tmp" '.summary.passing')
  drift=$(_envelope_field "$tmp" '.summary.drift')
  if [[ "$rc" == "0" && "$passing" == "1" && "$drift" == "0" ]]; then
    _report "T1 neutral-passing -> exit 0, passing=1, drift=0" ok
  else
    _report "T1 neutral-passing -> exit 0, passing=1, drift=0" fail "rc=$rc passing='$passing' drift='$drift' stderr=$(cat "$tmp/stderr" 2>/dev/null | head -3)"
  fi
  rm -rf "$tmp"
}

# T2: missing CodeQL -> exit 1, codeql_state=missing
t_missing() {
  local r; r=$(_run missing.json)
  local tmp="${r%:*}" rc="${r##*:}"
  local state; state=$(_envelope_field "$tmp" '.drift[0].codeql_state')
  if [[ "$rc" == "1" && "$state" == "missing" ]]; then
    _report "T2 missing CodeQL -> exit 1, codeql_state=missing" ok
  else
    _report "T2 missing CodeQL -> exit 1, codeql_state=missing" fail "rc=$rc state='$state'"
  fi
  rm -rf "$tmp"
}

# T3: failure conclusion -> exit 1, codeql_state=failure
t_failure() {
  local r; r=$(_run failure.json)
  local tmp="${r%:*}" rc="${r##*:}"
  local state; state=$(_envelope_field "$tmp" '.drift[0].codeql_state')
  if [[ "$rc" == "1" && "$state" == "failure" ]]; then
    _report "T3 failure conclusion -> exit 1, codeql_state=failure" ok
  else
    _report "T3 failure conclusion -> exit 1, codeql_state=failure" fail "rc=$rc state='$state'"
  fi
  rm -rf "$tmp"
}

# T4: wrong-app (CodeQL posted by github-actions, not GHAS) -> exit 1, wrong_app
t_wrong_app() {
  local r; r=$(_run wrong-app.json)
  local tmp="${r%:*}" rc="${r##*:}"
  local state; state=$(_envelope_field "$tmp" '.drift[0].codeql_state')
  if [[ "$rc" == "1" && "$state" == "wrong_app" ]]; then
    _report "T4 wrong-app (app.id=15368) -> exit 1, codeql_state=wrong_app" ok
  else
    _report "T4 wrong-app (app.id=15368) -> exit 1, codeql_state=wrong_app" fail "rc=$rc state='$state'"
  fi
  rm -rf "$tmp"
}

# T5: in-progress -> exit 2, codeql_state=in_progress (re-poll, not escalate)
t_in_progress() {
  local r; r=$(_run in-progress.json)
  local tmp="${r%:*}" rc="${r##*:}"
  local state; state=$(_envelope_field "$tmp" '.drift[0].codeql_state')
  if [[ "$rc" == "2" && "$state" == "in_progress" ]]; then
    _report "T5 in_progress -> exit 2, codeql_state=in_progress" ok
  else
    _report "T5 in_progress -> exit 2, codeql_state=in_progress" fail "rc=$rc state='$state'"
  fi
  rm -rf "$tmp"
}

# T6: dynamic enumeration smoke — script can list >= 8 workflows from
# the bot-workflow union (composite + inline) without AUDIT_FIXED_WORKFLOWS.
t_enumeration_count() {
  local tmp; tmp=$(mktemp -d)
  local count; count=$(AUDIT_ENUMERATE_ONLY=1 bash "$SCRIPT" 2>"$tmp/stderr" | wc -l)
  if [[ "$count" -ge 8 ]]; then
    _report "T6 dynamic enumeration -> >= 8 workflows (got $count)" ok
  else
    _report "T6 dynamic enumeration -> >= 8 workflows (got $count)" fail "count=$count stderr=$(cat "$tmp/stderr")"
  fi
  rm -rf "$tmp"
}

# T7: dry-run does not write telemetry
t_dry_run_no_telemetry() {
  local tmp; tmp=$(mktemp -d)
  local rc=0
  AUDIT_FIXTURE_OVERRIDE="$FIXTURE_DIR/neutral-passing.json" \
  AUDIT_FIXED_WORKFLOWS="scheduled-skill-freshness.yml:1:abcdef1234567890" \
  AUDIT_TELEMETRY_DIR="$tmp/state" \
    bash "$SCRIPT" --json --dry-run >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  if [[ "$rc" == "0" && ! -d "$tmp/state" ]]; then
    _report "T7 --dry-run does not write telemetry" ok
  else
    _report "T7 --dry-run does not write telemetry" fail "rc=$rc state_dir_exists=$(test -d "$tmp/state" && echo yes || echo no)"
  fi
  rm -rf "$tmp"
}

# T8: telemetry file is written on non-dry-run
t_telemetry_written() {
  local tmp; tmp=$(mktemp -d)
  local rc=0
  AUDIT_FIXTURE_OVERRIDE="$FIXTURE_DIR/neutral-passing.json" \
  AUDIT_FIXED_WORKFLOWS="scheduled-skill-freshness.yml:1:abcdef1234567890" \
  AUDIT_TELEMETRY_DIR="$tmp/state" \
    bash "$SCRIPT" --json >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  local count; count=$(find "$tmp/state" -name 'codeql-bot-coverage-*.json' 2>/dev/null | wc -l)
  if [[ "$count" -ge 1 ]]; then
    _report "T8 telemetry file written under AUDIT_TELEMETRY_DIR" ok
  else
    _report "T8 telemetry file written under AUDIT_TELEMETRY_DIR" fail "count=$count"
  fi
  rm -rf "$tmp"
}

# T9: integration_id=57789 invariant — fixtures + production canonical
t_integration_id_invariant() {
  local f="$FIXTURE_DIR/neutral-passing.json"
  local app_id; app_id=$(jq -r '.check_runs[] | select(.name=="CodeQL") | .app.id' < "$f")
  if [[ "$app_id" == "57789" ]]; then
    _report "T9 fixture CodeQL.app.id == 57789 (GHAS pin)" ok
  else
    _report "T9 fixture CodeQL.app.id == 57789 (GHAS pin)" fail "app_id=$app_id"
  fi
}

# T10: say() output sanitizes ANSI escape / CR / U+2028 from branch name.
# Use AUDIT_FIXED_WORKFLOWS with a branch-like first field containing
# control chars; assert the captured stdout contains zero of those bytes.
t_say_sanitizes_log_injection() {
  local tmp; tmp=$(mktemp -d)
  # Embed: ESC (\x1b), CR (\x0d), and U+2028 (\xe2\x80\xa8) inside the workflow
  # slot of AUDIT_FIXED_WORKFLOWS. say() should strip all three from the
  # rendered `[ok]` line.
  local malicious_wf
  malicious_wf=$(printf 'workflow\x1b\x0d\xe2\x80\xa8X.yml:1:abcdef1234567890')
  AUDIT_FIXTURE_OVERRIDE="$FIXTURE_DIR/neutral-passing.json" \
  AUDIT_FIXED_WORKFLOWS="$malicious_wf" \
  AUDIT_TELEMETRY_DIR="$tmp/state" \
    bash "$SCRIPT" >"$tmp/stdout" 2>"$tmp/stderr" || true
  # Captured stdout must contain zero ESC/CR bytes and zero U+2028 bytes.
  local has_esc has_cr has_u2028
  # grep -c returns non-zero per-file when count is 0; awk sums regardless.
  # `|| true` keeps set -e from aborting the harness.
  has_esc=$( (grep -cP '\x1b' "$tmp/stdout" "$tmp/stderr" 2>/dev/null || true) | awk -F: '{s+=$2} END{print s+0}')
  has_cr=$( (grep -cP '\r' "$tmp/stdout" "$tmp/stderr" 2>/dev/null || true) | awk -F: '{s+=$2} END{print s+0}')
  has_u2028=$( (grep -cP '\xe2\x80\xa8' "$tmp/stdout" "$tmp/stderr" 2>/dev/null || true) | awk -F: '{s+=$2} END{print s+0}')
  if [[ "$has_esc" == "0" && "$has_cr" == "0" && "$has_u2028" == "0" ]]; then
    _report "T10 say() strips ANSI/CR/U+2028 from operator-rendered output" ok
  else
    _report "T10 say() strips ANSI/CR/U+2028 from operator-rendered output" fail "esc=$has_esc cr=$has_cr u2028=$has_u2028"
  fi
  rm -rf "$tmp"
}

# T11: silent-success guard — when AUDIT_FIXED_WORKFLOWS is unset and gh
# is unreachable (simulated via PATH override), the script must exit 1
# rather than emitting total=0/passing=0/exit 0.
t_silent_success_guard() {
  local tmp; tmp=$(mktemp -d)
  # Stub `gh` to a dummy that returns `[]` from `gh pr list ... --json ...`.
  # The audit script must detect the zero-PRs case and abort with exit 1.
  cat > "$tmp/gh" <<'GHSTUB'
#!/usr/bin/env bash
# Stub: always return empty array for `gh pr list`, empty SHA for `gh pr view`.
case "$1" in
  pr) shift
      case "$1" in
        list) echo '[]' ;;
        view) echo '' ;;
        *) echo '' ;;
      esac
      ;;
  api) echo '{"check_runs":[]}' ;;
esac
GHSTUB
  chmod +x "$tmp/gh"
  local rc=0
  PATH="$tmp:$PATH" AUDIT_TELEMETRY_DIR="$tmp/state" \
    bash "$SCRIPT" >"$tmp/stdout" 2>"$tmp/stderr" || rc=$?
  if [[ "$rc" == "1" ]] && grep -qF 'gh pr list returned no bot PRs' "$tmp/stderr"; then
    _report "T11 silent-success guard fires when gh returns empty bot-PR list" ok
  else
    _report "T11 silent-success guard fires when gh returns empty bot-PR list" fail "rc=$rc stderr=$(head -1 "$tmp/stderr")"
  fi
  rm -rf "$tmp"
}

# T12: shared strip-log-injection lib is sourced (not redeclared inline)
t_shared_lib_used() {
  local audit_file="$REPO_ROOT/scripts/audit-bot-codeql-coverage.sh"
  local lib_file="$REPO_ROOT/scripts/lib/strip-log-injection.sh"
  if [[ ! -f "$lib_file" ]]; then
    _report "T12 scripts/lib/strip-log-injection.sh exists" fail "missing"
    return
  fi
  if ! grep -qF 'lib/strip-log-injection.sh' "$audit_file"; then
    _report "T12 audit script sources shared strip-log-injection lib" fail
    return
  fi
  # Audit script must NOT redeclare strip_log_injection() inline (function definition)
  if grep -qE '^strip_log_injection\(\) \{' "$audit_file"; then
    _report "T12 audit script does not redeclare strip_log_injection inline" fail
    return
  fi
  _report "T12 shared strip-log-injection lib sourced by audit script" ok
}

if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT does not exist — RED phase expected this." >&2
  exit 1
fi

t_neutral_passing
t_missing
t_failure
t_wrong_app
t_in_progress
t_enumeration_count
t_dry_run_no_telemetry
t_telemetry_written
t_integration_id_invariant
t_say_sanitizes_log_injection
t_silent_success_guard
t_shared_lib_used

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
