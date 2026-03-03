import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import github from "./github.js";

export default async function () {
  const plugin = JSON.parse(
    readFileSync(resolve("plugins/soleur/.claude-plugin/plugin.json"), "utf-8")
  );
  const data = await github();
  if (data.version) plugin.version = data.version;
  return plugin;
}
