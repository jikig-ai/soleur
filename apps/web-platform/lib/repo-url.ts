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
 *   6. Repeat 1-5 until the output stops changing (the loop in the exported
 *      function): a strip can expose a dot-segment (`/..git/` -> `/.`) that
 *      the next call's URL parse resolves away, so a single pass is not a
 *      fixpoint. Found by the same suite (merge_group run 39400877769).
 *
 * Non-URL input passes through as the trimmed + string-only-op'd value.
 * `null`/`undefined`/`""` → `""`.
 *
 * Coupled with the Postgres backfill in
 * `supabase/migrations/031_normalize_repo_url.sql` — steps 1-5 on string
 * input must be mirrored in the SQL regex chain (see migration header).
 * Step 6 and the `new URL()` rewrites (dot-segments, opaque paths) have no SQL
 * twin: the migration is a one-time backfill that never parses a URL, so the
 * two already diverge on those inputs; realistic stored values
 * (`https://github.com/<owner>/<repo>`) contain none. The missing SQL re-trim
 * is tracked separately in #10633.
 *
 * See plan:
 *   `knowledge-base/project/plans/2026-04-22-refactor-drain-web-platform-code-review-2775-2776-2777-plan.md`
 */
function normalizeRepoUrlPass(raw: string | null | undefined): string {
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
  // The `.git` strip can also expose a trailing dot-segment: `a/..git` →
  // `a/..`. URL parsing collapses `..` on the NEXT normalize() call, so
  // leaving it in place breaks idempotence — strip exposed trailing `/.`/`..`
  // segments to the same fixpoint URL normalization would reach. (#10716)
  working = working.replace(/(\/\.{1,2})+$/, "");
  working = working.replace(/\/+$/, "");
  // Re-trim: a `/` or `.git` strip can expose whitespace it was shielding
  // ("foo .git" -> "foo ", "x /" -> "x "), and an output with trailing
  // whitespace is not a fixpoint — the next call's input trim() would
  // move the value again, breaking the documented idempotence contract.
  working = working.trim();

  return working;
}

export function normalizeRepoUrl(raw: string | null | undefined): string {
  // Run the pass to a fixpoint: one pass is not enough, because a suffix strip
  // can expose a dot-segment (`/..git/` -> `/.`) or an opaque path that the
  // next call's URL parse rewrites, and each such rewrite needs another pass.
  // The cap is derived from the input length so a long peel chain still
  // converges (a fixed small cap leaves it non-idempotent); every other pass
  // shortens the value, so the loop terminates well inside it.
  let current: string = normalizeRepoUrlPass(raw);
  const cap = (raw?.length ?? 0) + 3;
  for (let i = 0; i < cap; i++) {
    const next = normalizeRepoUrlPass(current);
    if (next === current) return current;
    current = next;
  }
  return current;
}
