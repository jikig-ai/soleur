#!/usr/bin/env bash
# assert-dev-doppler-scope.sh -- fail closed unless the soleur/dev_scheduled
# Doppler config resolves to environment=dev AND carries no
# SUPABASE_ACCESS_TOKEN. THE ONE COPY of this security boundary
# (#8028 DC-1): it is the only mechanical guard that a dev-scoped CI job never
# holds the account-wide Supabase Management-API token. Consumed by
# .github/workflows/tenant-integration.yml and
# .github/workflows/scheduled-integration-suites.yml -- extracted because a
# hardening edit to one YAML copy does not flag the other. If you change the
# assertion, you change it for every consumer; that is the point.
#
# Requires: doppler + jq on PATH, DOPPLER_TOKEN exported (dev-scoped service
# token). Names only are read; no secret VALUE is ever fetched.
set -euo pipefail

env_name=$(doppler configs get dev_scheduled -p soleur --json 2>/dev/null \
  | jq -r '.environment // empty') || env_name=""
if [[ -z "$env_name" ]]; then
  echo "::error::doppler configs get dev_scheduled -p soleur returned empty. Config does not exist or token lacks read access."
  exit 1
fi
if [[ "$env_name" != "dev" ]]; then
  # Strip CR/LF + ASCII control bytes via tr, then multi-byte UTF-8
  # separators (U+2028, U+2029, U+200B, U+FEFF) via sed -- bash `tr` is
  # byte-oriented and cannot match multi-byte sequences. Mirrors
  # scheduled-realtime-probe.yml's strip_log_injection (tr + sed
  # two-stage).
  env_safe=$(printf '%s' "$env_name" | LC_ALL=C tr -d '\000-\037\177' \
    | sed -E 's/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g; s/\xe2\x80\x8b//g; s/\xef\xbb\xbf//g; s/\xc2\x85//g')
  echo "::error::dev_scheduled config resolves to environment=${env_safe} (expected: dev). Token rotated to wrong scope; reset before running this job."
  exit 1
fi
echo "Doppler config dev_scheduled -> environment=dev (verified)."

# DC-1 (#8028): a dev-scoped job must never hold the account-scoped
# Supabase Management-API token. The hook soaks the token's ABSENCE as a
# ::notice::; this is the only mechanical guard that the absence still
# holds. Capture first, then test: on a doppler error the pipe form hands
# jq empty input, `jq -e` exits 4, the `if` is false and the step would
# print "(verified)" having verified nothing (advisor consult, #8137).
names_json=$(doppler secrets --only-names --json -p soleur -c dev_scheduled 2>/dev/null) || names_json=""
if [[ -z "$names_json" ]]; then
  echo "::error::doppler secrets --only-names -p soleur -c dev_scheduled returned empty. Cannot verify the token's absence; failing closed."
  exit 1
fi
if printf '%s' "$names_json" | jq -e 'has("SUPABASE_ACCESS_TOKEN")' >/dev/null; then
  echo "::error::SUPABASE_ACCESS_TOKEN is present in Doppler dev_scheduled -- a dev-scoped CI job must not hold a Management-API token (#8028 DC-1)."
  exit 1
fi
echo "Doppler config dev_scheduled carries no SUPABASE_ACCESS_TOKEN (verified)."
