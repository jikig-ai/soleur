import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
import github from "./github.js";

export default async function () {
  const plugin = JSON.parse(
    readFileSync(join(__dirname, "..", "..", ".claude-plugin", "plugin.json"), "utf-8")
  );
  const data = await github();
  if (data.version) plugin.version = data.version;
  return plugin;
}
