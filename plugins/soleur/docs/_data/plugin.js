import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import github from "./github.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

export default async function () {
  const plugin = JSON.parse(
    readFileSync(join(__dirname, "..", "..", ".claude-plugin", "plugin.json"), "utf-8")
  );
  const data = await github();
  // Unconditional overwrite, NOT a fallback tier: plugin.json no longer carries
  // a `version` key (the `0.0.0-dev` frozen sentinel is gone), so there is no
  // manifest value to fall back to. `github()` is the only source, and it has
  // three paths that yield null — the SOLEUR_DOCS_OFFLINE hatch, the fetch
  // `catch` arm, and the no-release `?? null`. All three land on "unknown",
  // which is the string the CLI itself records for a keyless manifest.
  // Without this, `plugin.version` is `undefined` and base.njk's
  // `{{ plugin.version | jsonLdSafe | safe }}` throws mid-build.
  plugin.version = data.version ?? "unknown";
  return plugin;
}
