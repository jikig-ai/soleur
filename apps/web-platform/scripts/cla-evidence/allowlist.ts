/**
 * GitHub-Actions bot DB ID. The upstream contributor-assistant/github-action
 * filters this DB-id BEFORE the allowlist check fires (learning #2), so the
 * sidecar must apply the same filter or it would produce false-positive
 * allowlist-bypass evidence records.
 */
export const GITHUB_ACTIONS_BOT_DB_ID = 41898282 as const;

/** Parse the comma-separated `with.allowlist` value from `.github/workflows/cla.yml`. */
export function parseAllowlistFromYaml(raw: string): string[] {
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

/**
 * Decide whether an actor's PR was accepted via allowlist bypass (i.e., merged
 * without a signed CLA because the actor matched the upstream allowlist).
 *
 * - The login must match the allowlist.
 * - The DB-id MUST NOT be 41898282 (`github-actions[bot]`) — defense-in-depth
 *   even if a future operator adds the login back to the allowlist by mistake.
 */
export function isAllowlistBypass(
  login: string,
  dbId: number,
  allowlist: readonly string[],
): boolean {
  if (dbId === GITHUB_ACTIONS_BOT_DB_ID) return false;
  return allowlist.includes(login);
}

/**
 * Parse the `allowlist:` line out of a `.github/workflows/cla.yml` document.
 *
 * PURE by design, and living here rather than in `build-bypass.ts`, so a guard
 * can drive it against the REAL tracked workflow file. `build-bypass.ts` fuses
 * the file read, this expression and a `process.exit(1)` into one function, so
 * importing it to reach the regex kills the test worker instead of failing an
 * assertion — which is why the #7597 class (a format-breaking hand-edit that
 * passes unit tests and then reds a required check for every open PR in the
 * repository) was invisible to the suite.
 *
 * Quoted scalar form only, matching the tracked file. Returns `null` — never a
 * partial or empty list — when the line is absent or not in that form, so the
 * caller decides how loud to be. A `null` here means "the allowlist could not
 * be read", NOT "the allowlist is empty"; conflating those is how a parse
 * failure becomes a silent bypass.
 */
export function parseAllowlistLine(yml: string): string[] | null {
  const m = yml.match(/^\s*allowlist:\s*["']([^"']+)["']\s*$/m);
  if (!m) return null;
  return parseAllowlistFromYaml(m[1]);
}
