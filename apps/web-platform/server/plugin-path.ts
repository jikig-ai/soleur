/**
 * Canonical plugin-mount path resolution. Single source of truth for the
 * `SOLEUR_PLUGIN_PATH || /app/shared/plugins/soleur` default — consumed by
 * `workspace.ts` (symlink target for new user workspaces) and
 * `plugin-mount-check.ts` (boot-time integrity probe). See #3045.
 */

export const SOLEUR_PLUGIN_PATH_DEFAULT = "/app/shared/plugins/soleur";

export function getPluginPath(): string {
  return process.env.SOLEUR_PLUGIN_PATH || SOLEUR_PLUGIN_PATH_DEFAULT;
}
