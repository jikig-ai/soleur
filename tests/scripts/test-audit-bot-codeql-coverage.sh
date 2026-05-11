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

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
