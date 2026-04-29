import { existsSync, readdirSync } from "fs";
import { join } from "path";
import { reportSilentFallback } from "./observability";
import { createChildLogger } from "./logger";
import { getPluginPath } from "./plugin-path";

const log = createChildLogger("plugin-mount");

// Latched once per process so the boot-time signal does not flap on repeat
// calls. Test isolation uses `vi.resetModules()` rather than a public reset
// hook so the reset path is not exposed on the production module surface.
let _checked = false;

/**
 * One-shot startup verification that the plugin bind-mount source has been
 * populated by the deploy seed step. Mirrors empty/partial/missing-mount
 * conditions to Sentry via reportSilentFallback so a regression in the deploy
 * seed step is visible in dashboards instead of being a silent feature drop.
 * See #3045.
 *
 * Four differentiated messages let dashboards distinguish:
 * - "plugin-mount path missing": Hetzner volume failed to attach
 * - "plugin-mount empty": deploy seed step skipped or failed
 * - "plugin-mount manifest missing": image shipped without .claude-plugin/
 * - "plugin-mount partial seed": docker cp interrupted (manifest extracted
 *   early but `.seed-complete` sentinel never written)
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

  // The seed sentinel is written by ci-deploy.sh and cloud-init.yml AFTER
  // `docker cp` returns 0. A SIGKILLed cp leaves the manifest (which extracts
  // early in tar order) but no sentinel — without this check, the mount looks
  // healthy and downstream skill loading silently misses files.
  const sentinel = join(pluginPath, ".seed-complete");
  if (!existsSync(sentinel)) {
    reportSilentFallback(null, {
      feature: "plugin-mount",
      op: "discovery",
      message: "plugin-mount partial seed",
      extra: { path: pluginPath, sentinel },
    });
    log.error({ sentinel }, "Plugin mount missing .seed-complete sentinel");
    return;
  }

  log.info({ path: pluginPath, entries: entries.length }, "Plugin mount OK");
}
