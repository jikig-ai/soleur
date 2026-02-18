import { readFileSync } from "node:fs";
import { resolve } from "node:path";

export default function () {
  const pluginPath = resolve("plugins/soleur/.claude-plugin/plugin.json");
  return JSON.parse(readFileSync(pluginPath, "utf-8"));
}
