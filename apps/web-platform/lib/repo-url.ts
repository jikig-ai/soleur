/**
 * Strip any trailing mix of `/` and `.git` (case-insensitive) in O(n):
 * walk an end index backwards and slice once. `bar.git.bak` is untouched.
 */
function stripTrailingSlashAndGit(s: string): string {
  let end = s.length;
  for (;;) {
    if (end > 0 && s.charCodeAt(end - 1) === 47 /* "/" */) {
      end--;
    } else if (end >= 4 && s.slice(end - 4, end).toLowerCase() === ".git") {
      end -= 4;
    } else {
      return s.slice(0, end);
    }
  }
}

/** One normalization pass (steps 1-5 of `normalizeRepoUrl`). */
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

  // Strip trailing `/` and case-insensitive `.git` (suffix-anchored, in any
  // interleaving: `bar.git/`, `bar.git.git`, `bar/.git`). Linear scan rather
  // than the former `/\/+$/` and `/(\.git)+$/i` regexes, which are quadratic
  // on a long run followed by a non-matching character.
  working = stripTrailingSlashAndGit(working);
  // Re-trim: a `/` or `.git` strip can expose whitespace it was shielding
  // ("foo .git" -> "foo ", "x /" -> "x "), and an output with trailing
  // whitespace is not a fixpoint — the next call's input trim() would
  // move the value again, breaking the documented idempotence contract.
  working = working.trim();

  return working;
}

/** Fail-safe bound on extra passes; convergence takes at most 2 in practice. */
const MAX_EXTRA_PASSES = 32;

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
 *   6. Repeat 1-5 until the value stops changing: a strip can expose a
 *      dot-segment (`/..git.git` -> `/.`) that the next call's URL parse
 *      resolves (`/.` -> `/`), so a single pass is not a fixpoint. Passes
 *      are not strictly length-decreasing (a string that failed URL parsing
 *      can become parseable and gain `//` or `%20`), so convergence is
 *      empirical (at most 2 extra rounds over 300k fuzz inputs); the cap is a
 *      fail-safe, not an expected path.
 *
 * Non-URL input passes through as the trimmed + string-only-op'd value.
 * `null`/`undefined`/`""` → `""`.
 *
 * Coupled with a Postgres twin of this chain: any change here must follow the
 * sync-sites registry in `test/repo-url-sql-parity.test.ts` (ports, golden
 * table, and a NEW migration plus verify file — an applied migration is never
 * edited). Step 6 and URL path resolution (dot-segments, `%2e`, userinfo/port)
 * have no SQL equivalent: parity holds for URL-clean inputs only.
 *
 * See plan:
 *   `knowledge-base/project/plans/2026-04-22-refactor-drain-web-platform-code-review-2775-2776-2777-plan.md`
 */
export function normalizeRepoUrl(raw: string | null | undefined): string {
  let current = normalizeRepoUrlOnce(raw);
  for (let i = 0; i < MAX_EXTRA_PASSES; i++) {
    const next = normalizeRepoUrlOnce(current);
    if (next === current) return current;
    current = next;
  }
  return current;
}
