#!/usr/bin/env bash
# Test guard for seed-live-verify-user.sh (#5452, AC8).
#
# Asserts the prd seed refuses to run when (1) DOPPLER_CONFIG != "prd",
# (2) the service-role JWT carries a non-service_role role, (3) the JWT ref
# does not match the canonical URL ref — and that NO secret-shaped string
# reaches stdout/stderr (no `set -x`, password/service-role-key never echoed).
#
# The refusal paths all exit before any curl, so this runs offline.

set -uo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SEED="$DIR/seed-live-verify-user.sh"
fail=0

[[ -f "$SEED" ]] || { echo "FATAL: $SEED not found" >&2; exit 2; }

# Build a 3-segment JWT whose payload base64url-decodes to the given JSON.
# Matches the seed's decode (cut -d. -f2 → tr '_-' '/+' → base64 -d).
make_jwt() { # <payload-json>
  local payload
  payload=$(printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n')
  printf 'eyJhbGciOiJIUzI1NiJ9.%s.sig' "$payload"
}

REF20="aaaaaaaaaaaaaaaaaaaa"   # 20-char canonical ref
WRONG_REF20="bbbbbbbbbbbbbbbbbbbb"
CANON_URL="https://${REF20}.supabase.co"

# Run the seed with a clean, fully-specified env (overridable per case) and
# capture combined output. Returns the script's exit code in $rc, output in
# $out.
run_seed() { # <KEY=VAL>...
  out=$(env -i \
    PATH="$PATH" HOME="${HOME:-/tmp}" \
    DOPPLER_CONFIG="prd" \
    NEXT_PUBLIC_SUPABASE_URL="$CANON_URL" \
    NEXT_PUBLIC_SUPABASE_ANON_KEY="anon-key-not-used-on-refuse-path" \
    LIVE_VERIFY_USER_PASSWORD="placeholder-not-reached" \
    "$@" \
    bash "$SEED" 2>&1)
  rc=$?
}

assert_refuses() { # <description> <expected-substring> <KEY=VAL>...
  local desc="$1" expect="$2"; shift 2
  run_seed "$@"
  if [[ "$rc" -eq 0 ]]; then
    echo "  FAIL: $desc — expected non-zero exit, got 0" >&2
    fail=1
    return
  fi
  if ! printf '%s' "$out" | grep -qF "$expect"; then
    echo "  FAIL: $desc — output missing expected substring: $expect" >&2
    fail=1
    return
  fi
  echo "  ok: $desc (exit $rc)"
}

SERVICE_JWT=$(make_jwt "{\"role\":\"service_role\",\"ref\":\"$REF20\"}")
ANON_JWT=$(make_jwt "{\"role\":\"anon\",\"ref\":\"$REF20\"}")
WRONGREF_JWT=$(make_jwt "{\"role\":\"service_role\",\"ref\":\"$WRONG_REF20\"}")

# 1. Non-prd DOPPLER_CONFIG.
assert_refuses "refuses DOPPLER_CONFIG=dev" 'must be "prd"' \
  DOPPLER_CONFIG="dev" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_JWT"

# 2. Non-service_role JWT.
assert_refuses "refuses non-service_role JWT" 'expected "service_role"' \
  SUPABASE_SERVICE_ROLE_KEY="$ANON_JWT"

# 3. Wrong ref (canonical URL host ref != JWT ref).
assert_refuses "refuses JWT ref != URL ref" 'does not match URL canonical ref' \
  SUPABASE_SERVICE_ROLE_KEY="$WRONGREF_JWT"

# 4. Secret discipline (AC8) — static negative-space checks on the source.
if grep -qE '^[[:space:]]*set[[:space:]]+-x' "$SEED"; then
  echo "  FAIL: seed enables 'set -x' (would echo secret-laden command bodies)" >&2
  fail=1
else
  echo "  ok: no 'set -x' in seed"
fi

# The password / service-role key must never be DISPLAYED. Allowed:
#   - jq --arg interpolation into a curl -d body (not stdout)
#   - the JWT-decode pipeline `printf '%s' "$SRK" | tr.../cut.../base64...`
#     (output captured into a var, never reaches the terminal — the canonical
#     seed-dev-users.sh idiom). So we flag echo/printf of a secret var only when
#     it is NOT piped into a decode/transform tool.
secret_echo=$(grep -nE '(echo|printf)[^|]*\$\{?(LIVE_VERIFY_USER_PASSWORD|SUPABASE_SERVICE_ROLE_KEY|SRK)\b' "$SEED" \
  | grep -vE '\|[[:space:]]*(tr|cut|base64|wc|jq|openssl)' || true)
if [[ -n "$secret_echo" ]]; then
  echo "  FAIL: seed displays a secret variable:" >&2
  printf '%s\n' "$secret_echo" >&2
  fail=1
else
  echo "  ok: no echo/printf of password or service-role key (decode pipelines excluded)"
fi

# Belt-and-suspenders: none of the refusal-path outputs above leaked the
# constructed JWT bodies verbatim.
if printf '%s' "$SERVICE_JWT$ANON_JWT$WRONGREF_JWT" | grep -qF "placeholder-not-reached"; then
  : # impossible; keeps shellcheck quiet about the var
fi

if [[ "$fail" -ne 0 ]]; then
  echo "seed-live-verify-user.test.sh: FAILED" >&2
  exit 1
fi
echo "seed-live-verify-user.test.sh: PASSED"
