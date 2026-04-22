/**
 * Normalize a repository URL to a canonical form so write boundaries,
 * read boundaries, and DB indexes agree on equality. Idempotent.
 *
 * Canonical form:
 *   1. `trim()` leading/trailing whitespace.
 *   2. Lowercase scheme + host only — preserve owner/repo path case
 *      (GitHub path segments are case-insensitive at the API but
 *      case-sensitive for display; the user's typed form is the
 *      display form, so we keep it).
 *   3. Strip trailing `.git` case-insensitively (suffix-anchored so
 *      `bar.git.bak` is left alone).
 *   4. Strip trailing `/` (one or more).
 *
 * Non-URL input passes through as the trimmed + string-only-op'd value.
 * `null`/`undefined`/`""` → `""`.
 *
 * Coupled with the Postgres backfill in
 * `supabase/migrations/031_normalize_repo_url.sql` — any change here
 * must be mirrored in the SQL regex chain (see migration header).
 *
 * See plan:
 *   `knowledge-base/project/plans/2026-04-22-refactor-drain-web-platform-code-review-2775-2776-2777-plan.md`
 */
export function normalizeRepoUrl(raw: string | null | undefined): string {
  if (raw == null) return "";
  const trimmed = raw.trim();
  if (trimmed.length === 0) return "";

  // Try URL parsing to canonicalize scheme + host case.
  // On parse failure (e.g. raw text, non-URL string) fall through to the
  // string-only ops so callers with non-URL inputs still get a stable,
  // idempotent normalization.
  let working = trimmed;
  try {
    const parsed = new URL(trimmed);
    // `parsed.protocol` ends in `:` and is already lowercase; `parsed.host`
    // is already lowercase. Rebuild preserving path case.
    const scheme = parsed.protocol.toLowerCase();
    const host = parsed.host.toLowerCase();
    // `pathname` preserves case; `search` and `hash` are extremely rare
    // for repo URLs but we carry them through for safety.
    working = `${scheme}//${host}${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch {
    // Not a URL — apply string-only ops below.
  }

  // Strip trailing `/` (one or more) — must run BEFORE `.git` strip so
  // `...bar.git/` normalizes via `.../bar.git` → `.../bar`.
  working = working.replace(/\/+$/, "");
  // Strip trailing `.git` (case-insensitive, suffix-anchored).
  working = working.replace(/\.git$/i, "");
  // Strip any trailing `/` the `.git` strip may have exposed (edge case:
  // `...bar.git//` → after slash-strip: `...bar.git` → after git-strip:
  // `...bar` — no further work needed, but a `.git/.git` layered input
  // could technically leave a dangling char; re-running is free).
  working = working.replace(/\/+$/, "");

  return working;
}
