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
 *   5. Re-trim whitespace a suffix strip can expose (`foo .git` →
 *      `foo `): the function's idempotence contract requires the
 *      output to be trim-stable. Defect found by the fast-check
 *      property suite (test/lib/repo-url.property.test.ts).
 *
 *   6. Repeat 1-5 to a fixpoint (see `normalizeRepoUrl`): a strip can expose a
 *      dot-segment (`/..git.git` -> `/.`) the next call's URL parse resolves.
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
function normalizeRepoUrlOnce(raw: string | null | undefined): string {
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
  // Strip trailing `.git` (case-insensitive, suffix-anchored). Match one or
  // more repetitions of `.git` so `bar.git.git` collapses to `bar` in a
  // single pass — otherwise the normalizer would be non-idempotent at
  // read boundaries (DB stores `bar.git`, next read returns `bar`, scoping
  // drifts). Still suffix-anchored: `bar.git.bak` is untouched.
  working = working.replace(/(\.git)+$/i, "");
  // Strip any trailing `/` the `.git` strip may have exposed.
  working = working.replace(/\/+$/, "");
  // Re-trim: a `/` or `.git` strip can expose whitespace it was shielding
  // ("foo .git" -> "foo ", "x /" -> "x "), and an output with trailing
  // whitespace is not a fixpoint — the next call's input trim() would
  // move the value again, breaking the documented idempotence contract.
  working = working.trim();

  return working;
}

/**
 * Public entry: run the single-pass pipeline to a FIXPOINT so the documented
 * idempotence holds for every input. One pass is not enough: a suffix strip
 * can expose a dot-segment (`/..git.git` -> `/.`) that the next call's URL
 * parse resolves (`/.` -> `/`), so `f(f(x)) !== f(x)` for one pass. Each pass
 * only shortens or leaves the value, so this converges in a handful of
 * rounds; the cap is a fail-safe, not an expected path.
 */
export function normalizeRepoUrl(raw: string | null | undefined): string {
  let current = normalizeRepoUrlOnce(raw);
  for (let i = 0; i < 8; i++) {
    const next = normalizeRepoUrlOnce(current);
    if (next === current) return current;
    current = next;
  }
  return current;
}
