#!/usr/bin/env bash
# Resolve a Supabase project ref from NEXT_PUBLIC_SUPABASE_URL.
#
# Source: source apps/web-platform/scripts/lib/supabase-ref-resolver.sh
# Use:    resolve_supabase_ref "$NEXT_PUBLIC_SUPABASE_URL"
#         (prints the 20-char project ref to stdout; exits non-zero on failure)
#
# This is the canonical resolver for bash callers. The TypeScript counterpart
# lives at apps/web-platform/lib/supabase/resolve-ref.ts (`resolveSupabaseRef`)
# and is consumed by .github/workflows/reusable-release.yml via `source` of
# this file. Parity between the bash and TS forms is asserted by
# apps/web-platform/test/lib/supabase/resolve-ref-parity.test.ts and
# apps/web-platform/scripts/lib/supabase-ref-resolver.test.sh (T6 covers the
# subdomain-bypass case).
#
# Subdomain-bypass guard: the resolved hostname MUST match
# `^[a-z0-9]{20}\.supabase\.co$` before the first label is extracted as a
# project ref. This prevents attacker-controlled CNAMEs (e.g.,
# `<ref>.supabase.co.evil.com`) from passing a naïve prefix check. Mirrors
# the canonical resolution shape in plugins/soleur/skills/preflight/SKILL.md
# Check 4 Step 4.2.

# resolve_supabase_ref <url>
#   stdout: the 20-char project ref on success
#   stderr: a one-line diagnostic on failure
#   rc:     0 on success, 1 on parse failure
resolve_supabase_ref() {
  local url="${1:-}"
  if [[ -z "$url" ]]; then
    echo "supabase-ref-resolver: empty URL" >&2
    return 1
  fi

  # Fast path: canonical https://<ref>.supabase.co — single sed extract.
  # The {20} length anchor matches the subdomain-bypass guard on the CNAME
  # branch (line ~58) and the TS sibling's CANONICAL_URL_RE. Without the
  # length pin, an off-spec URL like `https://abc.supabase.co` would short-
  # circuit the guard. Parity is locked by resolve-ref-parity.test.ts.
  local ref
  ref="$(printf '%s' "$url" \
    | sed -nE 's#^https?://([a-z0-9]{20})\.supabase\.co/?$#\1#p')"
  if [[ -n "$ref" ]]; then
    printf '%s' "$ref"
    return 0
  fi

  # Custom-domain fallback: strip protocol + trailing path, CNAME-resolve,
  # validate target against the canonical regex, extract the first label.
  if ! command -v dig >/dev/null 2>&1; then
    echo "supabase-ref-resolver: URL '$url' is not a canonical *.supabase.co host AND 'dig' is not installed (required for CNAME fallback on custom domains)" >&2
    return 1
  fi

  local host
  host="${url#http://}"
  host="${host#https://}"
  host="${host%%/*}"

  local cname_target
  cname_target="$(dig +short +time=5 +tries=2 CNAME "$host" 2>/dev/null \
    | head -1 \
    | sed 's/\.$//')"

  if [[ -n "$cname_target" ]] && [[ "$cname_target" =~ ^[a-z0-9]{20}\.supabase\.co$ ]]; then
    printf '%s' "${cname_target%%.supabase.co}"
    return 0
  fi

  echo "supabase-ref-resolver: cannot parse project ref from '$url' (canonical regex did not match, and CNAME fallback did not resolve to a canonical *.supabase.co host)" >&2
  return 1
}
