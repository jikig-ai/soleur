import { existsSync, readdirSync } from "fs";
import { join } from "path";
import { reportSilentFallback } from "./observability";
import { createChildLogger } from "./logger";

const log = createChildLogger("plugin-mount");

function getPluginPath(): string {
  return process.env.SOLEUR_PLUGIN_PATH || "/app/shared/plugins/soleur";
}

let _checked = false;

/**
 * One-shot startup verification that the plugin bind-mount source has been
 * populated by the deploy seed step. Mirrors the empty-mount degraded
 * condition to Sentry via reportSilentFallback so a regression in the deploy
 * seed step is visible in dashboards instead of being a silent feature drop.
 * See #3045.
 *
 * Three differentiated messages let dashboards distinguish:
 * - "plugin-mount path missing": Hetzner volume failed to attach
 * - "plugin-mount empty": deploy seed step skipped or failed
 * - "plugin-mount manifest missing": image shipped without .claude-plugin/
 */
export function verifyPluginMountOnce(): void {
  if (_checked) return;
  _checked = true;

  const pluginPath = getPluginPath();

  if (!existsSync(pluginPath)) {
    reportSilentFallback(null, {
      feature: "plugin-mount",
      op: "discovery",
      message: "plugin-mount path missing",
      extra: { path: pluginPath },
    });
    log.error({ path: pluginPath }, "Plugin mount path does not exist");
    return;
  }

  let entries: string[] = [];
  try {
    entries = readdirSync(pluginPath);
  } catch (err) {
    reportSilentFallback(err, {
      feature: "plugin-mount",
      op: "discovery",
      extra: { path: pluginPath },
    });
    log.error({ err, path: pluginPath }, "Plugin mount unreadable");
    return;
  }

  if (entries.length === 0) {
    reportSilentFallback(null, {
      feature: "plugin-mount",
      op: "discovery",
      message: "plugin-mount empty",
      extra: { path: pluginPath },
    });
    log.error({ path: pluginPath }, "Plugin mount is empty");
    return;
  }

  const manifest = join(pluginPath, ".claude-plugin", "plugin.json");
  if (!existsSync(manifest)) {
    reportSilentFallback(null, {
      feature: "plugin-mount",
      op: "discovery",
      message: "plugin-mount manifest missing",
      extra: { path: pluginPath, manifest },
    });
    log.error({ manifest }, "Plugin mount missing .claude-plugin/plugin.json");
    return;
  }

  log.info({ path: pluginPath, entries: entries.length }, "Plugin mount OK");
}

/** Test-only memoization reset. Not exported from server entry. */
export function _resetForTesting(): void {
  _checked = false;
}
