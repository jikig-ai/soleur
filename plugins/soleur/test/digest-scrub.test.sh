#!/usr/bin/env bash
# Test for the operator-digest tuned scrub gate (digest-scrub.sh, #5085).
#
# The digest gate differs from incident/redact-sentinel.sh by design (plan §L3):
#   - HARD-ABORT (exit 1) on true secret classes.
#   - email: ABORT unless the domain is first-party (jikigai.com / soleur.ai).
#   - UUID / IPv4: WARN-only (legitimate in synthesized business prose) — exit 0.
#   - grep error: ABORT (real fail-closed, not the sentinel's per-pattern `|| true`).
#
# Exit codes: 0 = clean (warns allowed); 1 = abort (secret / foreign email / grep error); 2 = usage.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRUB="${SCRIPT_DIR}/../skills/operator-digest/scripts/digest-scrub.sh"

pass=0
fail=0
tmpd="$(mktemp -d)"
trap 'rm -rf "$tmpd"' EXIT

# run <expected-exit> <description> <file-content...>
run() {
  local expected="$1" desc="$2"; shift 2
  local f="${tmpd}/case.md"
  printf '%s\n' "$@" > "$f"
  bash "$SCRUB" "$f" >/dev/null 2>&1
  local rc=$?
  if [[ "$rc" == "$expected" ]]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL: ${desc} — expected exit ${expected}, got ${rc}"
  fi
}

# --- ABORT (exit 1) on true secret classes ---
# NOTE: secret-shaped fixtures are split across a '' concatenation boundary so no
# contiguous token literal exists in SOURCE (GitHub push-protection scans source
# bytes), while bash concatenates adjacent quoted strings into the full token at
# RUNTIME (the value digest-scrub.sh actually greps). See work-skill pitfall:
# "Synthesized secret-SHAPE fixtures trip GitHub Push Protection — split across concatenation."
run 1 "anthropic key aborts"   'synthesis used sk-ant-''api03-0123456789abcdef0123456789abcdef0123456789'
run 1 "github token aborts"    'token ghp_''0123456789abcdefghij0123456789abcdef leaked'
run 1 "stripe live key aborts" 'charge via sk_''live_0123456789abcdefghijklmn'
run 1 "env_var assignment aborts" 'SUPABASE_SERVICE_ROLE_KEY=''eyJabc123def456 in a log line'
run 1 "JWT aborts"             'bearer eyJ''0123456789.eyJ0123456789.sig0123456789abc'
run 1 "PEM private key aborts" '-----BEGIN RSA ''PRIVATE KEY-----'

# --- email: first-party PASS (warn), foreign ABORT ---
run 0 "first-party jikigai email passes" 'Account: <ops@jikigai.com> on the Doppler ledger.'
run 0 "first-party soleur email passes"  'Notifications from notifications@soleur.ai went out.'
run 1 "foreign customer email aborts"    'Incident affected jane.doe@contoso.com this week.'

# --- UUID / IPv4: WARN-only, do NOT abort ---
run 0 "UUID in prose passes (warn)" 'PIR trace id 550e8400-e29b-41d4-a716-446655440000 resolved.'
run 0 "IPv4 in prose passes (warn)" 'Affected node 203.0.113.45 was restarted.'

# --- clean digest passes ---
run 0 "clean business prose passes" 'We shipped faster checkout. Doppler cost held at $0. Nothing broke.'

# --- usage error ---
bash "$SCRUB" >/dev/null 2>&1; [[ $? == 2 ]] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: no-arg should exit 2"; }
bash "$SCRUB" "${tmpd}/does-not-exist.md" >/dev/null 2>&1; [[ $? == 2 ]] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: unreadable file should exit 2"; }

echo "=== digest-scrub: ${pass} passed, ${fail} failed ==="
[[ "$fail" == 0 ]]
