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
