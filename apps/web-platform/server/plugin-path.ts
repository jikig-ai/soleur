/**
 * Canonical plugin-mount path resolution. Single source of truth for the
 * `SOLEUR_PLUGIN_PATH || /app/shared/plugins/soleur` default — consumed by
 * `workspace.ts` (symlink target for new user workspaces) and
 * `plugin-mount-check.ts` (boot-time integrity probe). See #3045.
 *
 * Defense-in-depth (TR9 PR-5 SECURITY MEDIUM-1): the env override is
 * accepted only when it begins with an allowlisted prefix. Primary
 * mitigation remains Doppler/env-var access control — this guard is a
 * belt-and-suspenders check against a SOLEUR_PLUGIN_PATH typo or a
 * misconfigured Doppler override pointing at an attacker-controlled path
 * (e.g. `/tmp/foo`) that the cron-bug-fixer would otherwise symlink into
 * the spawn cwd. A rejected override falls back to the default and emits
 * a one-line warning to stderr (no Sentry, since this is import-time).
 */

export const SOLEUR_PLUGIN_PATH_DEFAULT = "/app/shared/plugins/soleur";

// Allowlisted prefixes. `/app/` covers the production container; broader
// than `/app/shared/plugins/` to leave room for ops-driven repointing
// (e.g. blue-green plugin rollouts) without code changes. Loosen further
// only when a concrete need arises.
const ALLOWED_PREFIXES = ["/app/"] as const;

export function getPluginPath(): string {
  const override = process.env.SOLEUR_PLUGIN_PATH;
  if (!override) return SOLEUR_PLUGIN_PATH_DEFAULT;
  // Test bypass: vitest / node:test fixtures legitimately point at
  // mkdtemp paths (/tmp/..., /var/folders/...) and would otherwise have
  // to construct fake `/app/*` paths. The prefix guard is a production
  // defense-in-depth check; the production env (NODE_ENV=production,
  // VITEST unset) is where it actually matters.
  if (process.env.VITEST || process.env.NODE_ENV === "test") {
    return override;
  }
  if (ALLOWED_PREFIXES.some((p) => override.startsWith(p))) {
    return override;
  }
  // eslint-disable-next-line no-console -- import-time fallback warning;
  // pino logger isn't bootstrapped this early in some call sites.
  console.warn(
    `[plugin-path] Rejecting SOLEUR_PLUGIN_PATH=${JSON.stringify(override)} ` +
      `(must start with one of: ${ALLOWED_PREFIXES.join(", ")}). ` +
      `Falling back to default ${SOLEUR_PLUGIN_PATH_DEFAULT}.`,
  );
  return SOLEUR_PLUGIN_PATH_DEFAULT;
}
