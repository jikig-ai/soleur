/**
 * Rewrite a Supabase storage URL's origin to the public Supabase host
 * (`NEXT_PUBLIC_SUPABASE_URL`).
 *
 * `createServiceClient` signs storage URLs against `SUPABASE_URL`, which in prod
 * is the raw `<ref>.supabase.co` host. But the browser's CSP fetch directives
 * (`img-src`, `connect-src`, …) are built from `NEXT_PUBLIC_SUPABASE_URL` (the
 * public custom domain, e.g. `api.soleur.ai`). A storage URL handed to the
 * browser on the raw host is therefore silently **CSP-blocked** — server-side
 * `curl` succeeds (no CSP), so it only reproduces in a real browser. Both hosts
 * route to the same project and the signed token is host-agnostic, so rewriting
 * the origin is safe.
 *
 * Use this for ANY signed/public storage URL that reaches the browser as an
 * asset (`<img>`, `<script>`, `fetch`, a 302 `Location` followed by an asset
 * request). See
 * `knowledge-base/project/learnings/bug-fixes/2026-06-08-supabase-update-eq-zero-rows-silent-noop-and-code-trace-repro.md`.
 */
export function toPublicStorageUrl(storageUrl: string): string {
  const publicBase = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!publicBase) return storageUrl;
  try {
    const u = new URL(storageUrl);
    const pub = new URL(publicBase);
    if (u.host === pub.host) return storageUrl;
    u.protocol = pub.protocol;
    u.host = pub.host;
    return u.toString();
  } catch {
    // Malformed URL on either side — leave the original untouched.
    return storageUrl;
  }
}
