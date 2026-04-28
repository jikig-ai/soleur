// Production JWT-claims guard for `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
//
// Sibling to `validate-url.ts`. Lives outside `client.ts` for the same
// `cq-test-mocked-module-constant-import` reason (test files mock
// `@/lib/supabase/client`).
//
// Mirrored JWT-claims sites (edit together):
//   - .github/workflows/reusable-release.yml step "Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg"
//   - apps/web-platform/scripts/verify-required-secrets.sh (anon-key shape block)
//   - plugins/soleur/skills/preflight/SKILL.md Check 5 Step 5.4 (deployed-bundle gate)
//
// Depends on `validate-url.ts` to have already validated the URL shape — the
// JWT `ref` cross-check anchors on the URL's canonical first label. Both
// validators are called from `client.ts` at module load.

const CANONICAL_REF = /^[a-z0-9]{20}$/;
const CANONICAL_HOSTNAME = /^([a-z0-9]{20})\.supabase\.co$/;

// Prefix-match deny-list. Each prefix targets common operator-paste patterns
// (test fixtures, placeholder strings). False-positive risk: a real Supabase
// project ref starting with one of these prefixes would be rejected. This is
// considered acceptable because (a) we know the canonical prd ref does NOT
// collide; (b) collision on a NEW project ref is rare (years between project
// creation) and would surface immediately in CI as a clear error; (c) the
// remediation is a one-line list edit. If a real ref ever collides, drop the
// offending prefix here AND in the three mirrored sites.
const PLACEHOLDER_REF_PREFIXES = [
  "test",
  "placeholder",
  "example",
  "service",
  "local",
  "dev",
  "stub",
];

const CUSTOM_DOMAIN_HOSTS = new Set<string>(["api.soleur.ai"]);

function previewValue(raw: string): string {
  if (raw.length <= 32) return raw;
  return `${raw.slice(0, 16)}…${raw.slice(-8)}`;
}

interface JwtPayload {
  iss?: string;
  role?: string;
  ref?: string;
}

function decodeJwtPayload(raw: string): JwtPayload {
  const segments = raw.split(".");
  if (segments.length !== 3) {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_ANON_KEY does not have exactly 3 JWT segments (got ${segments.length})`,
    );
  }
  const middle = segments[1];
  if (!middle || !/^[A-Za-z0-9_-]+$/.test(middle)) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_ANON_KEY payload segment is not valid base64url",
    );
  }
  // Decode base64url manually — `Buffer.from(s, "base64url")` is Node 16+ only
  // and throws `Unknown encoding: base64url` in browser Buffer polyfills. This
  // module is imported by `lib/supabase/client.ts` which runs at module load in
  // the client bundle, so the decode MUST be browser-safe. Validity is enforced
  // by the base64url-charset regex above, so this conversion is total.
  const base64 = middle.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), "=");
  const json =
    typeof atob === "function"
      ? atob(padded)
      : Buffer.from(padded, "base64").toString("utf8");
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_ANON_KEY payload is not valid JSON after base64url decode",
    );
  }
  if (parsed === null || typeof parsed !== "object") {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_ANON_KEY payload is not a JSON object",
    );
  }
  return parsed as JwtPayload;
}

function expectedRefFromUrl(rawUrl: string | undefined): string | null {
  if (!rawUrl) return null;
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    return null;
  }
  const hostname = parsed.hostname;
  // Custom-domain note: the runtime cannot resolve CNAME from the browser, so
  // when the URL is `api.soleur.ai` we trust the JWT `ref` as the
  // source-of-truth and skip the cross-check. The CI Validate step in
  // `reusable-release.yml` does `dig +short CNAME` and IS load-bearing for
  // custom-domain ref binding — do not weaken that step. The Doppler-side
  // gate in `verify-required-secrets.sh` likewise trusts the JWT ref for
  // custom-domain values; CI is the canonical binding.
  if (CUSTOM_DOMAIN_HOSTS.has(hostname)) {
    return null;
  }
  const match = CANONICAL_HOSTNAME.exec(hostname);
  return match ? match[1] : null;
}

/**
 * Throws when a placeholder, malformed, or non-canonical Supabase anon-key JWT
 * would be inlined into the production browser bundle. No-op outside
 * `NODE_ENV=production` so test-fixture JWT setters are unaffected.
 *
 * Intentionally guards the *inlined-bundle* path only (called once at module
 * load from `lib/supabase/client.ts`). Server-side reads of the anon key are
 * checked by `apps/web-platform/scripts/verify-required-secrets.sh` (Doppler
 * `prd`) and the CI Validate step in `.github/workflows/reusable-release.yml`
 * (GitHub repo secret) before the build is produced.
 *
 * Asserts:
 *   - 3-segment JWT shape
 *   - base64url middle segment decodes to a JSON object
 *   - `iss === "supabase"`
 *   - `role === "anon"` (load-bearing for security: rejects service_role paste,
 *     which would silently bypass RLS for every browser visitor)
 *   - `ref` matches `^[a-z0-9]{20}$` and is not in the placeholder prefix set
 *   - `ref` matches the URL's canonical first label (when URL is
 *     `<ref>.supabase.co`; the cross-check is skipped on the `api.soleur.ai`
 *     custom domain — see `expectedRefFromUrl` for the load-bearing CI binding)
 *
 * Intentionally does NOT verify the JWT signature — anon keys are public, the
 * signature check would require either embedding the project's signing secret
 * (impossible) or a network call (defeats fail-fast). Runtime auth is
 * Supabase's responsibility.
 *
 * Depends on `validate-url.ts`'s `assertProdSupabaseUrl` having validated the
 * URL shape FIRST (call order in `client.ts` is load-bearing). The JWT
 * cross-check anchors on the URL's canonical first label, so a malformed URL
 * would invalidate the cross-check.
 */
export function assertProdSupabaseAnonKey(
  rawKey: string | undefined,
  rawUrl: string | undefined,
): void {
  if (process.env.NODE_ENV !== "production") return;
  if (!rawKey) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_ANON_KEY");
  }
  const cleaned = rawKey.replace(/[\r\n]/g, "");
  if (!cleaned) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_ANON_KEY");
  }

  const payload = decodeJwtPayload(cleaned);

  if (payload.iss !== "supabase") {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_ANON_KEY iss="${payload.iss ?? ""}", expected "supabase" ` +
        `(preview: ${previewValue(cleaned)})`,
    );
  }

  if (payload.role !== "anon") {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_ANON_KEY role="${payload.role ?? ""}", expected "anon". ` +
        `A non-anon role in the browser bundle is a critical security issue ` +
        `(role=service_role would grant admin RLS bypass to every visitor).`,
    );
  }

  const ref = payload.ref ?? "";
  if (!CANONICAL_REF.test(ref)) {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_ANON_KEY ref="${ref}" does not match canonical 20-char shape ` +
        `(^[a-z0-9]{20}$). Likely a placeholder or test-fixture JWT.`,
    );
  }

  if (PLACEHOLDER_REF_PREFIXES.some((prefix) => ref.startsWith(prefix))) {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_ANON_KEY ref="${ref}" is a placeholder/test-fixture value. ` +
        `This indicates a build-arg leak from a test fixture.`,
    );
  }

  const expected = expectedRefFromUrl(rawUrl);
  if (expected !== null && ref !== expected) {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_ANON_KEY ref="${ref}" does not match URL canonical ref="${expected}". ` +
        `This indicates a dev/prd key swap or cross-project paste.`,
    );
  }
}
