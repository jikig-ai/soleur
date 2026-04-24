#!/usr/bin/env bash
# Fixture-based tests for docs-cli-verification.sh.
# Runs the hook with synthetic tool-input payloads and asserts the advisory
# warning either appears on stderr (for unverified CLI invocations in docs
# files) or is absent (for verified snippets and non-docs paths).
set -euo pipefail

HOOK="$(dirname "${BASH_SOURCE[0]}")/docs-cli-verification.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# shellcheck disable=SC2317  # Reachable through indirection.
run_case() {
  local name=$1 fixture_path=$2 fixture_content=$3 expect_warn=$4
  printf '%s' "$fixture_content" > "$fixture_path"
  local payload
  payload=$(jq -nc --arg p "$fixture_path" '{tool_input: {file_path: $p}}')
  local stderr
  stderr=$(echo "$payload" | "$HOOK" 2>&1 >/dev/null || true)
  local has_warn=false
  [[ "$stderr" == *"docs-cli-verify"* ]] && has_warn=true
  if [[ "$has_warn" == "$expect_warn" ]]; then
    echo "ok  - $name"
    pass=$((pass + 1))
  else
    echo "FAIL - $name (expect_warn=$expect_warn, got=$has_warn)"
    echo "  stderr: $stderr"
    fail=$((fail + 1))
  fi
}

# (a) unverified CLI snippet in a .md file → warn
run_case "warn on unverified ollama snippet in markdown" \
  "$TMP/fixture.md" \
  $'# Title\n\n```bash\nollama run gemma2:27b\n```\n' \
  true

# (b) annotated snippet in .md → no warn
run_case "no warn when snippet is annotated verified" \
  "$TMP/verified.md" \
  $'# Title\n\n<!-- verified: 2026-04-18 source: https://ollama.com/library/gemma2 -->\n```bash\nollama run gemma2:27b\n```\n' \
  false

# (c) CLI token inside a .ts source file → no warn (file-pattern gate skips)
run_case "no warn on ollama inside a .ts source literal" \
  "$TMP/source.ts" \
  $'export const cmd = "ollama run gemma2:27b";\n' \
  false

# (d) README with no extension → warn (new file-pattern coverage)
run_case "warn on unverified CLI inside a bare README" \
  "$TMP/README" \
  $'Quick start:\n\n```bash\npnpm install\npnpm run dev\n```\n' \
  true

# (e) annotation with a short intro paragraph above fence → no warn
# The window tolerates a one-line paragraph between the annotation and
# the fence — the common "verified: … \n\nUsage:\n\n```bash\n...```" layout.
run_case "no warn when annotation precedes fence by a short intro" \
  "$TMP/wide-window.md" \
  $'<!-- verified: 2026-04-18 source: https://ollama.com -->\n\nUsage:\n\n```bash\nollama run gemma2:27b\n```\n' \
  false

# (f) env-var prefix is stripped before CLI match
run_case "warn when CLI is preceded by env-var assignment" \
  "$TMP/envvar.md" \
  $'```bash\nOLLAMA_HOST=127.0.0.1:11434 ollama run gemma2:27b\n```\n' \
  true

# --- Emission assertions (plan T2.3) ------------------------------------
# Per-fence warn events must land in .claude/.rule-incidents.jsonl under
# rule_id=cq-docs-cli-verification. Each case runs with INCIDENTS_REPO_ROOT
# pointing at a fresh per-case directory for isolation.

run_emit_case() {
  local name=$1 fixture_path=$2 fixture_content=$3 expected_lines=$4
  printf '%s' "$fixture_content" > "$fixture_path"
  local incidents; incidents=$(mktemp -d)
  local payload
  payload=$(jq -nc --arg p "$fixture_path" '{tool_input: {file_path: $p}}')
  echo "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" >/dev/null 2>&1 || true
  local jsonl="$incidents/.claude/.rule-incidents.jsonl"

  local actual=0
  local rule_ok=true event_ok=true
  if [[ -f "$jsonl" ]]; then
    actual=$(wc -l < "$jsonl" | tr -d ' ')
    if [[ "$expected_lines" -gt 0 ]]; then
      local bad_rules bad_events
      bad_rules=$(jq -r 'select(.rule_id != "cq-docs-cli-verification") | .rule_id' < "$jsonl" | wc -l | tr -d ' ')
      bad_events=$(jq -r 'select(.event_type != "warn") | .event_type' < "$jsonl" | wc -l | tr -d ' ')
      [[ "$bad_rules" -eq 0 ]] || rule_ok=false
      [[ "$bad_events" -eq 0 ]] || event_ok=false
    fi
  fi

  if [[ "$actual" == "$expected_lines" ]] && $rule_ok && $event_ok; then
    echo "ok  - $name"
    pass=$((pass + 1))
  else
    echo "FAIL - $name (expected $expected_lines JSONL line(s), got $actual; rule_ok=$rule_ok event_ok=$event_ok)"
    [[ -f "$jsonl" ]] && { echo "  contents:"; sed 's/^/    /' "$jsonl"; }
    fail=$((fail + 1))
  fi
  rm -rf "$incidents"
}

run_emit_case "emit one warn per unverified CLI fence" \
  "$TMP/emit-one.md" \
  $'# Title\n\n```bash\nollama run gemma2:27b\n```\n' \
  1

run_emit_case "no emit when snippet is annotated verified" \
  "$TMP/emit-none.md" \
  $'# Title\n\n<!-- verified: 2026-04-18 source: https://ollama.com/library/gemma2 -->\n```bash\nollama run gemma2:27b\n```\n' \
  0

run_emit_case "emit two warns for two unverified fences" \
  "$TMP/emit-two.md" \
  $'# Title\n\n```bash\nollama run gemma2:27b\n```\n\nMore:\n\n```bash\nsupabase login\n```\n' \
  2

echo
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
