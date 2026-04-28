// Production canonical-shape guard for NEXT_PUBLIC_SUPABASE_URL.
//
// Lives in its own module (not client.ts) because 9 test files vi.mock the
// client — the mock factory wouldn't expose any constants extracted from there.
// See cq-test-mocked-module-constant-import.

export const PROD_ALLOWED_HOSTS = ["api.soleur.ai"] as const;

const CANONICAL_REF_RE = /^[a-z0-9]{20}\.supabase\.co$/;

const PLACEHOLDER_HOSTS = new Set([
  "test.supabase.co",
  "placeholder.supabase.co",
  "example.supabase.co",
  "localhost",
  "0.0.0.0",
]);

export function assertProdSupabaseUrl(raw: string | undefined): void {
  if (process.env.NODE_ENV !== "production") return;
  if (!raw) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL");
  }
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error(`Invalid NEXT_PUBLIC_SUPABASE_URL: ${raw}`);
  }
  if (parsed.protocol !== "https:") {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_URL must use https; got ${parsed.protocol}`,
    );
  }
  if (PLACEHOLDER_HOSTS.has(parsed.hostname)) {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_URL is a placeholder host (${parsed.hostname}). ` +
        `This indicates a build-arg leak from a test fixture.`,
    );
  }
  const allowed =
    (PROD_ALLOWED_HOSTS as readonly string[]).includes(parsed.hostname) ||
    CANONICAL_REF_RE.test(parsed.hostname);
  if (!allowed) {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_URL host ${parsed.hostname} is not canonical ` +
        `(^[a-z0-9]{20}\\.supabase\\.co$) and not in PROD_ALLOWED_HOSTS.`,
    );
  }
}
