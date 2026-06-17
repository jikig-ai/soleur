#!/usr/bin/env bash
# Drift guard for live-verify.tf (#5452, AC7).
#
# Asserts the synthetic-prod-principal password is Soleur-generated and
# published to Doppler prd with NO operator-mint variable
# (hr-tf-variable-no-operator-mint-default). Anchors on tokens only the real
# HCL config lines carry (resource declarations, attribute names), never bare
# literals that a comment could also contain.

set -uo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TF="$DIR/live-verify.tf"
fail=0

check() { # <description> <grep-args...>
  local desc="$1"; shift
  if grep -qE "$@" "$TF"; then
    echo "  ok: $desc"
  else
    echo "  FAIL: $desc" >&2
    fail=1
  fi
}

refute() { # <description> <grep-args...>
  local desc="$1"; shift
  if grep -qE "$@" "$TF"; then
    echo "  FAIL: $desc" >&2
    fail=1
  else
    echo "  ok: $desc"
  fi
}

[[ -f "$TF" ]] || { echo "FATAL: $TF not found" >&2; exit 2; }

check "random_password resource declared" \
  '^resource[[:space:]]+"random_password"[[:space:]]+"live_verify_user"'
check "doppler_secret resource declared" \
  '^resource[[:space:]]+"doppler_secret"[[:space:]]+"live_verify_user_password"'
check "secret pinned to prd config" \
  '^[[:space:]]*config[[:space:]]*=[[:space:]]*"prd"'
check "secret name is LIVE_VERIFY_USER_PASSWORD" \
  '^[[:space:]]*name[[:space:]]*=[[:space:]]*"LIVE_VERIFY_USER_PASSWORD"'
check "value derives from the random_password (provider-side mint)" \
  '^[[:space:]]*value[[:space:]]*=[[:space:]]*random_password\.live_verify_user\.result'

# No operator-mint: a `variable "...sensitive..."` for the password is the
# anti-pattern this guard exists to prevent.
refute "no operator-mint variable for the password" \
  '^variable[[:space:]]+"live_verify_user_password"'

if [[ "$fail" -ne 0 ]]; then
  echo "live-verify.tf.test.sh: FAILED" >&2
  exit 1
fi
echo "live-verify.tf.test.sh: PASSED"
