#!/usr/bin/env bash
# Canary Layer 3 — assert the inlined Supabase anon-key JWT in the deployed
# /login chunk has canonical claims (iss=supabase, role=anon, ref=^[a-z0-9]{20}$).
# Mirrors the logic in `plugins/soleur/skills/preflight/SKILL.md` Check 5
# Step 5.4, scoped to the canary's localhost target.
#
# Catches the #3007 regression class: a malformed inlined NEXT_PUBLIC_SUPABASE_*
# value that hydrates and throws on the client. SSR-HTML probes (Layer 1)
# cannot see this because SSR uses the server Supabase module which bypasses
# the client validators.
#
# Usage: canary-bundle-claim-check.sh <base-url>
# Returns 0 when the inlined JWT passes; non-zero (with stderr) on any
# violation. SKIP outcomes (chunk not found, JWT not present) return non-zero
# — the canary treats absence as failure to avoid fail-open on a bundling
# change that moves the supabase init out of the login chunk.

set -uo pipefail

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  echo "canary-bundle-claim-check: missing base-url arg" >&2
  exit 64
fi

LOGIN_HTML=$(mktemp /tmp/canary-l3-login.XXXXXX)
CHUNK_FILE=$(mktemp /tmp/canary-l3-chunk.XXXXXX)
trap 'rm -f "$LOGIN_HTML" "$CHUNK_FILE"' EXIT

if ! curl -fsSL --max-time 5 -A "Mozilla/5.0" "${BASE_URL%/}/login" -o "$LOGIN_HTML"; then
  echo "canary-bundle-claim-check: failed to fetch /login" >&2
  exit 1
fi

CHUNK_PATH=$(grep -oE '/_next/static/chunks/app/\(auth\)/login/page-[a-f0-9]+\.js' "$LOGIN_HTML" | head -1)
if [[ -z "$CHUNK_PATH" ]]; then
  echo "canary-bundle-claim-check: login chunk path not found in /login HTML" >&2
  exit 1
fi

if ! curl -fsSL --max-time 5 "${BASE_URL%/}${CHUNK_PATH}" -o "$CHUNK_FILE"; then
  echo "canary-bundle-claim-check: failed to fetch chunk ${CHUNK_PATH}" >&2
  exit 1
fi

JWT=$(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "$CHUNK_FILE" | head -1)
if [[ -z "$JWT" ]]; then
  echo "canary-bundle-claim-check: no JWT found in login chunk" >&2
  exit 1
fi

PAYLOAD=$(printf '%s' "$JWT" | cut -d. -f2)
PAD=$(( (4 - ${#PAYLOAD} % 4) % 4 ))
if [[ $PAD -gt 0 ]]; then PADDED="$PAYLOAD$(printf '=%.0s' $(seq 1 $PAD))"; else PADDED="$PAYLOAD"; fi
JSON=$(printf '%s' "$PADDED" | tr '_-' '/+' | base64 -d 2>/dev/null)

ISS=$(printf '%s' "$JSON" | grep -oE '"iss":"[^"]*"' | head -1 | sed 's/.*:"\([^"]*\)"/\1/')
ROLE=$(printf '%s' "$JSON" | grep -oE '"role":"[^"]*"' | head -1 | sed 's/.*:"\([^"]*\)"/\1/')
REF=$(printf '%s' "$JSON" | grep -oE '"ref":"[^"]*"' | head -1 | sed 's/.*:"\([^"]*\)"/\1/')

if [[ "$ISS" != "supabase" ]]; then
  echo "canary-bundle-claim-check: iss=\"${ISS}\", expected \"supabase\"" >&2
  exit 1
fi
if [[ "$ROLE" != "anon" ]]; then
  echo "canary-bundle-claim-check: role=\"${ROLE}\", expected \"anon\"" >&2
  exit 1
fi
if [[ ! "$REF" =~ ^[a-z0-9]{20}$ ]]; then
  echo "canary-bundle-claim-check: ref=\"${REF}\" does not match canonical 20-char shape" >&2
  exit 1
fi

# Reject placeholder ref prefixes (mirrors validate-anon-key.ts).
for PREFIX in test placeholder example service local dev stub; do
  if [[ "$REF" == "$PREFIX"* ]]; then
    echo "canary-bundle-claim-check: ref=\"${REF}\" has placeholder prefix \"${PREFIX}\"" >&2
    exit 1
  fi
done

exit 0
