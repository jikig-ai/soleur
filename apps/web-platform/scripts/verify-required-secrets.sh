#!/usr/bin/env bash
set -uo pipefail

# Assert every hand-maintained required NEXT_PUBLIC_* secret is exported in the
# current environment. Invoke via `doppler run -c prd -- bash <path>` so Doppler
# populates env before we read it.
#
# Drift policy: hand-maintained (brainstorm Decision #5). NEXT_PUBLIC_AGENT_COUNT
# is intentionally excluded — it is a build-time Docker ARG, not a Doppler secret.
#
# `-e` is deliberately NOT set: the loop must continue past each missing key so
# the output enumerates every missing secret in one run. `-u` is safe: `${!key:-}`
# uses an explicit default, which satisfies `-u` on bash 4.4+.

REQUIRED=(
  NEXT_PUBLIC_APP_URL
  NEXT_PUBLIC_SUPABASE_URL
  NEXT_PUBLIC_SUPABASE_ANON_KEY
  NEXT_PUBLIC_SENTRY_DSN
  NEXT_PUBLIC_VAPID_PUBLIC_KEY
  NEXT_PUBLIC_GITHUB_APP_SLUG
)

missing=0
for key in "${REQUIRED[@]}"; do
  value="${!key:-}"
  if [[ -z "$value" ]]; then
    echo "::error::Required secret missing from Doppler prd: $key"
    missing=$((missing + 1))
  else
    echo "ok $key"
  fi
done

if [[ "$missing" -gt 0 ]]; then
  echo "::error::$missing required NEXT_PUBLIC_* secret(s) missing from Doppler prd"
  exit 1
fi

echo "::notice::All ${#REQUIRED[@]} required NEXT_PUBLIC_* secrets present in Doppler prd"
