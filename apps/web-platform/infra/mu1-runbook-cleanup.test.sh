#!/usr/bin/env bash
set -euo pipefail

# Tests for mu1-cleanup-guard.mjs (#2839).
# Each case invokes the guard with an injected env object via `node -e`
# and asserts the throw/no-throw + message shape.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_MODULE="$SCRIPT_DIR/mu1-cleanup-guard.mjs"
DEV_URL="https://mlwiodleouzwniehynfz.supabase.co"

PASS=0
FAIL=0
TOTAL=0

echo "=== mu1-cleanup-guard.mjs tests ==="
echo ""

run_case() {
  # Args: description, doppler-config, url, expected-stdstring
  local description="$1"
  local doppler_config="$2"
  local url="$3"
  local expected_string="$4"

  TOTAL=$((TOTAL + 1))

  # Build the env literal. `undefined` and `null` must be unquoted.
  local cfg_literal
  if [[ "$doppler_config" == "__undefined__" ]]; then
    cfg_literal="undefined"
  else
    cfg_literal="'$doppler_config'"
  fi

  local output actual_exit
  output=$(
    node --input-type=module -e "
      import { assertDevCleanupEnv } from '$GUARD_MODULE';
      try {
        assertDevCleanupEnv({ DOPPLER_CONFIG: $cfg_literal, NEXT_PUBLIC_SUPABASE_URL: '$url' });
        console.log('no-throw');
      } catch (e) {
        console.log('threw: ' + e.message);
      }
    " 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && printf '%s\n' "$output" | grep -qF "$expected_string"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        expected substring: $expected_string"
    echo "        output: $output"
  fi
}

# --- Cases ------------------------------------------------------------------

echo "--- happy path ---"
run_case "DOPPLER_CONFIG=dev + correct URL → no throw" \
  "dev" "$DEV_URL" "no-throw"

echo ""
echo "--- DOPPLER_CONFIG guard ---"
run_case "DOPPLER_CONFIG=prd → throws with DOPPLER_CONFIG" \
  "prd" "$DEV_URL" "DOPPLER_CONFIG is not 'dev'"

run_case "DOPPLER_CONFIG unset → throws with <unset>" \
  "__undefined__" "$DEV_URL" "<unset>"

echo ""
echo "--- hostname guard ---"
run_case "wrong project ref → throws with hostname 'otherref.supabase.co'" \
  "dev" "https://otherref.supabase.co" "hostname 'otherref.supabase.co'"

run_case "empty URL → throws with hostname ''" \
  "dev" "" "hostname ''"

run_case "malformed URL → throws with hostname ''" \
  "dev" "not-a-url" "hostname ''"

# Security regression: split(".")[0] would accept this. Exact-hostname
# equality rejects it (credential-exfiltration vector otherwise).
run_case "subdomain bypass attempt (<ref>.supabase.co.evil.com) → rejected" \
  "dev" "https://mlwiodleouzwniehynfz.supabase.co.evil.com" \
  "hostname 'mlwiodleouzwniehynfz.supabase.co.evil.com'"

# Strip-the-suffix variant: host that starts with DEV_PROJECT_REF but is
# not the exact hostname.
run_case "prefix-match bypass (<ref>supabase.co without dot) → rejected" \
  "dev" "https://mlwiodleouzwniehynfzfoo.supabase.co" \
  "hostname 'mlwiodleouzwniehynfzfoo.supabase.co'"

# --- Results ----------------------------------------------------------------

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[[ "$FAIL" -eq 0 ]]
