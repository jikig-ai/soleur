#!/usr/bin/env bun
import { installOpenCodeAdapter } from "./install-opencode-adapter.js";
import { resolve, join, dirname } from "path";
import { fileURLToPath } from "url";
import { existsSync } from "fs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const packageRoot = resolve(__dirname, "..");

const PLUGIN_ROOT = packageRoot; // In npm package, this is the package root

const argv = process.argv.slice(2);
const home = process.env["HOME"];

const explicitTarget = parseArg(argv, "--target");
if (explicitTarget === undefined && (home === undefined || home === "")) {
  console.error("HOME is not set and --target was not given");
  process.exit(2);
}

const targetDir = resolve(explicitTarget ?? join(home, ".config", "opencode"));

try {
  if (argv.includes("--check")) {
    const { installProblems } = await import("./install-opencode-adapter.js");
    const problems = installProblems(targetDir, PLUGIN_ROOT);
    if (problems.length > 0) {
      problems.forEach((p) => console.error(p));
      process.exit(1);
    }
    console.log("opencode-install ok");
    process.exit(0);
  }
  const result = installOpenCodeAdapter(targetDir, PLUGIN_ROOT, {
    force: argv.includes("--force"),
  });
  console.log(
    `opencode-adapter installed into ${targetDir} (${result.written.length} written, ${result.unchanged.length} unchanged, ${result.removed.length} removed)`,
  );
} catch (error) {
  console.error(error);
  process.exit(1);
}

function parseArg(argv, flag) {
  const index = argv.indexOf(flag);
  if (index === -1) return undefined;
  const value = argv[index + 1];
  if (value === undefined) throw new Error(`${flag} requires a directory`);
  return value;
}
