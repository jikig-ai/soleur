// Production canonical-shape guard for `NEXT_PUBLIC_SUPABASE_URL`.
//
// Lives outside `client.ts` because 9 test files `vi.mock("@/lib/supabase/client")`
// — the mock factory wouldn't expose any constants extracted from there.
// See AGENTS.md `cq-test-mocked-module-constant-import` and
// knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md.
//
// Regex literal duplicated in:
//   - `.github/workflows/reusable-release.yml` step "Validate NEXT_PUBLIC_SUPABASE_URL build-arg"
//   - `apps/web-platform/scripts/verify-required-secrets.sh` (`SUPABASE_URL_RE`)
// All three sites enforce the same canonical-shape contract. Edit together.
//
// Also paired with the JWT-claims gates for `NEXT_PUBLIC_SUPABASE_ANON_KEY`:
//   - `./validate-anon-key.ts` (sibling validator, cross-checks JWT ref against URL canonical first label)
//   - `.github/workflows/reusable-release.yml` step "Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg"
//   - `plugins/soleur/skills/preflight/SKILL.md` Check 5 (Steps 5.3 + 5.4)
// `validate-anon-key.ts` consumes this module's URL canonical shape — any
// regex change here breaks the JWT ref derivation there. Update both.

const CANONICAL_HOSTNAME = /^[a-z0-9]{20}\.supabase\.co$/;

const PROD_ALLOWED_HOSTS = new Set<string>(["api.soleur.ai"]);

const PLACEHOLDER_HOSTS = new Set<string>([
  "test.supabase.co",
  "placeholder.supabase.co",
  "example.supabase.co",
  "localhost",
  "0.0.0.0",
]);

function previewValue(raw: string): string {
  // Truncate the echoed value so a stray secret-class paste (e.g., service-role
  // JWT) doesn't reach Sentry breadcrumbs verbatim. Keep enough to identify the
  // shape (placeholder vs. canonical vs. malformed).
  if (raw.length <= 32) return raw;
  return `${raw.slice(0, 16)}…${raw.slice(-8)}`;
}

/**
 * Throws when a placeholder, malformed, or non-canonical Supabase URL would be
 * inlined into the production browser bundle. No-op outside
 * `NODE_ENV=production` so the 24 test files that set `https://test.supabase.co`
 * are unaffected.
 *
 * Intentionally guards the *inlined-bundle* path only (called once at module
 * load from `lib/supabase/client.ts`). Server-side reads
 * (`lib/supabase/server.ts`, `lib/supabase/service.ts`, `middleware.ts`) read
 * `NEXT_PUBLIC_SUPABASE_URL` at runtime against Doppler `prd`, which is checked
 * separately by `apps/web-platform/scripts/verify-required-secrets.sh`.
 */
export function assertProdSupabaseUrl(raw: string | undefined): void {
  if (process.env.NODE_ENV !== "production") return;
  if (!raw) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL");
  }
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error(
      `Invalid NEXT_PUBLIC_SUPABASE_URL: ${previewValue(raw)}`,
    );
  }
  // `URL.protocol` retains the trailing colon (`"https:"`).
  if (parsed.protocol !== "https:") {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_URL must use https; got ${parsed.protocol}`,
    );
  }
  if (parsed.username !== "" || parsed.password !== "") {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL must not include userinfo");
  }
  if (parsed.port !== "") {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_URL must not include a port; got :${parsed.port}`,
    );
  }
  if (PLACEHOLDER_HOSTS.has(parsed.hostname)) {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_URL is a placeholder host (${parsed.hostname}). ` +
        `This indicates a build-arg leak from a test fixture.`,
    );
  }
  const allowed =
    PROD_ALLOWED_HOSTS.has(parsed.hostname) ||
    CANONICAL_HOSTNAME.test(parsed.hostname);
  if (!allowed) {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_URL host ${parsed.hostname} is not canonical ` +
        `(^[a-z0-9]{20}\\.supabase\\.co$) and not in the allowlist.`,
    );
  }
}
