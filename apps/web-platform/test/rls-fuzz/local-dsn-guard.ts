// Fail-closed DSN allowlist for the RLS/authz-fuzz harness (AC7).
//
// The harness drives adversarial cross-tenant queries; it MUST only ever run
// against a LOCAL disposable Postgres. This guard is a literal-host allowlist
// (NOT a DNS resolver, NOT a hosted-suffix denylist): only loopback + an
// explicit CI service host are permitted; everything else — especially hosted
// Supabase (`*.supabase.co` / `*.supabase.com`) and any private-net address —
// hard-errors before a single query runs.

const LOOPBACK_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);

export interface LocalDsnOptions {
  /** An explicit CI Postgres service hostname to allow (e.g. the GH Actions `services:` name). */
  ciHost?: string;
}

/** Parse the host out of a Postgres DSN without any network call. Returns null on a malformed/hostless DSN. */
function parseHost(dsn: string): string | null {
  if (!dsn) return null;
  let url: URL;
  try {
    url = new URL(dsn);
  } catch {
    return null;
  }
  // URL.hostname keeps brackets for IPv6 literals (e.g. "[::1]"); strip them.
  const host = url.hostname.replace(/^\[|\]$/g, "");
  return host.length > 0 ? host : null;
}

/** True iff the DSN's literal host is in the fail-closed allowlist. Never resolves DNS. */
export function isLocalDsnHost(dsn: string, opts: LocalDsnOptions = {}): boolean {
  const host = parseHost(dsn);
  if (host === null) return false;
  if (LOOPBACK_HOSTS.has(host)) return true;
  if (opts.ciHost && host === opts.ciHost) return true;
  return false;
}

/** Throw unless the DSN targets an allowlisted local host. Reads RLS_FUZZ_CI_DB_HOST for the CI service host. */
export function assertLocalDsn(dsn: string, opts: LocalDsnOptions = {}): void {
  const ciHost = opts.ciHost ?? process.env.RLS_FUZZ_CI_DB_HOST ?? undefined;
  if (isLocalDsnHost(dsn, { ciHost })) return;
  const host = parseHost(dsn);
  throw new Error(
    `[rls-fuzz] refusing to run: DSN host ${host ? `"${host}"` : "(unparseable)"} is not in the ` +
      `local allowlist {localhost, 127.0.0.1, ::1${ciHost ? `, ${ciHost}` : ""}}. ` +
      `The RLS-fuzz harness only runs against a local disposable Postgres — never hosted Supabase.`,
  );
}
