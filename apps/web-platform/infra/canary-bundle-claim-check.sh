#!/usr/bin/env bash
# Canary Layer 3 — assert the inlined Supabase anon-key JWT in the deployed
# login bundle has canonical claims (iss=supabase, role=anon,
# ref=^[a-z0-9]{20}$). Mirrors `plugins/soleur/skills/preflight/SKILL.md`
# Check 5 Step 5.4, scoped to the canary's localhost target.
#
# Catches the #3007 regression class: a malformed inlined NEXT_PUBLIC_SUPABASE_*
# value that hydrates and throws on the client. SSR-HTML probes (Layer 1)
# cannot see this because SSR uses the server Supabase module which bypasses
# the client validators.
#
# Usage: canary-bundle-claim-check.sh <base-url>
#
# Exit-reason matrix (every non-zero is a hard FAIL — the canary has no SKIP
# outcome; absence of a determinable answer must NOT proceed to swap):
#   0                                        — claims canonical
#   1 + canary_layer3_login_fetch_failed     — /login fetch failed (curl rc≠0)
#   1 + canary_layer3_no_chunks              — /login HTML had zero <script> refs
#   1 + canary_layer3_no_jwt                 — exhausted candidate chunks, no JWT
#   1 + canary_layer3_jwt_decode_failed      — JWT found but base64/jq parse failed
#   1 + canary_layer3_jwt_claims             — JWT valid but claims non-canonical
#
# Strict-mode discipline: this script keeps `set -uo pipefail` (NOT `-euo`).
# The chunk-traversal loop intentionally tolerates per-iteration failures
# (transient curl errors, grep rc=1 on no-match). `-e` would abort on the
# first per-chunk failure and revert the gate to the brittle behavior the
# fix is closing. Decision points are guarded with explicit per-statement
# rc checks (host union accumulation, JWT match, claim assertion).
# See: knowledge-base/project/learnings/2026-04-21-cloud-task-silence-watchdog-pattern.md

set -uo pipefail

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  echo "canary-bundle-claim-check: missing base-url arg" >&2
  exit 64
fi

LOGIN_HTML=$(mktemp /tmp/canary-l3-login.XXXXXX)
CANDIDATES=$(mktemp /tmp/canary-l3-candidates.XXXXXX)
CHUNK_DIR=$(mktemp -d /tmp/canary-l3-chunks.XXXXXX)
# rm -rf on CHUNK_DIR is load-bearing — without it, repeated canary failures
# across a deploy storm could leak ~100MB across the 20-fetch loop
# (--max-filesize 5242880 × 20 = 100 MB worst-case).
trap 'rm -f "$LOGIN_HTML" "$CANDIDATES"; rm -rf "$CHUNK_DIR"' EXIT

if ! curl -fsSL --max-time 5 -A "Mozilla/5.0" "${BASE_URL%/}/login" -o "$LOGIN_HTML"; then
  echo "canary_layer3_login_fetch_failed: failed to fetch /login from ${BASE_URL%/}" >&2
  exit 1
fi

# Enumerate all /_next/static/chunks/*.js references from the login HTML. Cap
# at 20 — current prod loads 13; F13 fixture in the test exercises the cap.
# Dedupe preserves document (load) order — `awk '!seen[$0]++'` is the canonical
# pattern. `sort -u` would reorder alphabetically and silently bring chunks
# from beyond the cap into the first 20 slots.
# Path validation regex (defense-in-depth against future supply-chain): each
# candidate must match `^/_next/static/chunks/[A-Za-z0-9_/().-]+\.js$` before
# string-interpolation into the curl URL. Mirror of preflight Check 5 Step 5.2.
grep -oE '/_next/static/chunks/[^"]+\.js' "$LOGIN_HTML" | awk '!seen[$0]++' | head -20 > "$CANDIDATES"

if [[ ! -s "$CANDIDATES" ]]; then
  echo "canary_layer3_no_chunks: zero /_next/static/chunks references in /login HTML" >&2
  exit 1
fi

PATH_REGEX='^/_next/static/chunks/[A-Za-z0-9_/().-]+\.js$'
JWT=""

# Redirected-stdin form (`< file`) — NOT `cat ... | while read`. A pipe scopes
# loop variables to a subshell so JWT would be empty at end-of-loop. Same
# precedent as preflight Check 5 Step 5.2 hardening note.
while IFS= read -r candidate; do
  if [[ -z "$candidate" ]]; then
    continue
  fi
  if [[ ! "$candidate" =~ $PATH_REGEX ]]; then
    # Reject paths with traversal, command-injection, or non-allowed chars.
    continue
  fi
  # Per-chunk fetch with --max-time and --max-filesize hardening (DoS defense
  # against a misbehaving CDN response). 5 MB cap is well above any real chunk.
  chunk_file="$CHUNK_DIR/chunk-$(printf '%s' "$candidate" | tr -c 'A-Za-z0-9' '_')"
  if ! curl -fsSL --max-time 5 --max-filesize 5242880 \
        "${BASE_URL%/}${candidate}" -o "$chunk_file" 2>/dev/null; then
    continue
  fi
  match=$(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "$chunk_file" 2>/dev/null | head -1)
  if [[ -n "$match" ]]; then
    JWT="$match"
    break
  fi
done < "$CANDIDATES"

if [[ -z "$JWT" ]]; then
  echo "canary_layer3_no_jwt: exhausted candidate chunks, no eyJ... match" >&2
  exit 1
fi

# Decode pipeline. `jq -er` fails closed on missing/null claim. Verified at
# deepen time (2026-04-29): cloud-init.yml line 7 ships `jq` in the host
# package list, so every canary host has jq installed at provision time.
PAYLOAD=$(printf '%s' "$JWT" | cut -d. -f2)
PAD=$(( (4 - ${#PAYLOAD} % 4) % 4 ))
if [[ $PAD -gt 0 ]]; then
  PADDED="$PAYLOAD$(printf '=%.0s' $(seq 1 $PAD))"
else
  PADDED="$PAYLOAD"
fi

JSON=$(printf '%s' "$PADDED" | tr '_-' '/+' | base64 -d 2>/dev/null) || {
  echo "canary_layer3_jwt_decode_failed: base64 payload could not be decoded" >&2
  exit 1
}

iss=$(printf '%s' "$JSON" | jq -er '.iss // ""' 2>/dev/null) || {
  echo "canary_layer3_jwt_decode_failed: payload not parseable as JSON (.iss)" >&2
  exit 1
}
role=$(printf '%s' "$JSON" | jq -er '.role // ""' 2>/dev/null) || {
  echo "canary_layer3_jwt_decode_failed: payload missing .role" >&2
  exit 1
}
ref=$(printf '%s' "$JSON" | jq -er '.ref // ""' 2>/dev/null) || {
  echo "canary_layer3_jwt_decode_failed: payload missing .ref" >&2
  exit 1
}

# Sanitize claim values for log-injection defense before any echo to stderr.
# Strip C0 controls (\x00–\x1f), DEL (\x7f), and the UTF-8 byte sequences for
# U+2028 (E2 80 A8) and U+2029 (E2 80 A9). LC_ALL=C is load-bearing — `tr`
# without it may NOT strip C0 in non-C locales. The sed pass is also
# load-bearing — U+2028/U+2029 are 3-byte UTF-8 sequences that pass the `tr`
# byte-level strip. Mirrors 2026-04-28 anon-key learning #6.
sanitize() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | sed $'s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'
}
iss=$(sanitize "$iss")
role=$(sanitize "$role")
ref=$(sanitize "$ref")

if [[ "$iss" != "supabase" ]]; then
  echo "canary_layer3_jwt_claims: iss=\"${iss}\", expected \"supabase\"" >&2
  exit 1
fi
if [[ "$role" != "anon" ]]; then
  echo "canary_layer3_jwt_claims: role=\"${role}\", expected \"anon\"" >&2
  exit 1
fi
if [[ ! "$ref" =~ ^[a-z0-9]{20}$ ]]; then
  echo "canary_layer3_jwt_claims: ref=\"${ref}\" does not match canonical 20-char shape" >&2
  exit 1
fi

# Reject placeholder ref prefixes (mirrors validate-anon-key.ts).
for PREFIX in test placeholder example service local dev stub; do
  if [[ "$ref" == "$PREFIX"* ]]; then
    echo "canary_layer3_jwt_claims: ref=\"${ref}\" has placeholder prefix \"${PREFIX}\"" >&2
    exit 1
  fi
done

exit 0
