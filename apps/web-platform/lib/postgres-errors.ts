// Postgres SQLSTATE codes surfaced by @supabase/supabase-js via PostgrestError.
// See https://www.postgresql.org/docs/current/errcodes-appendix.html
export const PG_UNIQUE_VIOLATION = "23505";

/**
 * Extract a Postgres SQLSTATE from an error surfaced by @supabase/supabase-js
 * (`PostgrestError` — `{ message, details, hint, code }`) or node-postgres
 * (a real `Error` carrying `code`). Returns the code only when it matches the
 * canonical SQLSTATE shape — exactly 5 characters from `[0-9A-Z]` (e.g.
 * `"42501"` insufficient_privilege, `"23505"` unique_violation, `"42P01"`
 * undefined_table).
 *
 * The format guard distinguishes a true SQLSTATE from a Node system-error code
 * (`ENOENT`, `EACCES` — 6+ chars), so a filesystem error is never mis-tagged as
 * a database failure.
 *
 * SQLSTATE codes are static error *classes*, never row values, so the result is
 * safe to attach to a Sentry tag (e.g. `pg_code`) for search/aggregation. The
 * accompanying PostgREST `details`/`hint` fields are deliberately NOT extracted
 * here — Postgres embeds offending row values into `details` for constraint
 * violations (e.g. `Key (email)=(...) already exists`), which would leak PII.
 */
export function sqlStateFromError(err: unknown): string | undefined {
  const code = (err as { code?: unknown } | null | undefined)?.code;
  return typeof code === "string" && /^[0-9A-Z]{5}$/.test(code)
    ? code
    : undefined;
}
