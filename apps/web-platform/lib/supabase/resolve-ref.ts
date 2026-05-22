// TypeScript sibling of apps/web-platform/scripts/lib/supabase-ref-resolver.sh
// (`resolve_supabase_ref`). The bash form is the canonical resolver; this file
// mirrors its behavior for TS callers (currently cron-oauth-probe.ts; see also
// `.github/workflows/reusable-release.yml` which sources the bash form directly).
//
// Security-critical: the subdomain-bypass anchored regex
// `^[a-z0-9]{20}\.supabase\.co$` prevents attacker-controlled CNAMEs
// (e.g. `<ref>.supabase.co.evil.com`) from passing a naïve prefix check.
// Parity between this module and the bash form is asserted by
// `test/lib/supabase/resolve-ref-parity.test.ts`. Any change to the regex
// MUST land in BOTH files in the same commit.
//
// Sibling shape-validators that inline the same canonical-host regex
// (different concern: URL build-arg shape vs. ref derivation) are intentional:
//   - apps/web-platform/lib/supabase/validate-url.ts
//   - apps/web-platform/lib/supabase/validate-anon-key.ts
//   - apps/web-platform/scripts/verify-required-secrets.sh
// A future widening of the canonical (e.g. `.io` support) must touch all
// resolver + shape-validator sites together.

import { promises as dnsPromises } from "node:dns";

const CANONICAL_URL_RE = /^https?:\/\/([a-z0-9]{20})\.supabase\.co\/?$/;
const CANONICAL_HOST_RE = /^([a-z0-9]{20})\.supabase\.co$/;

/**
 * Returns the 20-char Supabase project ref derived from `url`, or `null` on
 * any failure (empty input, non-canonical host, NXDOMAIN, subdomain-bypass
 * attempt). The bash counterpart `resolve_supabase_ref` returns rc=1 with a
 * stderr diagnostic on the same failure cases; callers in TS use `??` against
 * an env-sourced fallback (see cron-oauth-probe.ts:351).
 */
export async function resolveSupabaseRef(
  url: string,
): Promise<string | null> {
  if (!url) return null;

  // Fast path — canonical `https://<ref>.supabase.co` (optional trailing slash).
  const fast = url.match(CANONICAL_URL_RE);
  if (fast?.[1]) return fast[1];

  // Custom-domain fallback — strip protocol + path, resolve CNAME, validate
  // the first chain hop against the subdomain-bypass anchored regex.
  let host = url.replace(/^https?:\/\//, "");
  host = host.split("/")[0] ?? "";
  if (!host) return null;

  let cnames: string[];
  try {
    cnames = await dnsPromises.resolveCname(host);
  } catch {
    // ENOTFOUND / ENODATA / ESERVFAIL / network — mirrors the bash form's
    // `dig ... 2>/dev/null` swallow.
    return null;
  }

  const first = cnames[0];
  if (!first) return null;
  const stripped = first.replace(/\.$/, "");
  const matched = stripped.match(CANONICAL_HOST_RE);
  return matched?.[1] ?? null;
}
