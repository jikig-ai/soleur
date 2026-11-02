#!/usr/bin/env node
/**
 * Node shim for `npx @soleur/opencode` / `bunx @soleur/opencode`.
 *
 * The canonical installer is TypeScript (`scripts/install-opencode-adapter.ts`) and OpenCode hooks
 * run under Bun, so this shim locates `bun` and executes `install.js` with it.
 */

import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const packageRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const installer = join(packageRoot, "install.js");

const probe = spawnSync("bun", ["--version"], { stdio: "ignore" });
if (probe.error) {
  console.error(
    "@soleur/opencode requires Bun (`bun` was not found on PATH). Install Bun from https://bun.sh and re-run `npx @soleur/opencode install` (or `bunx @soleur/opencode install`).",
  );
  process.exit(1);
}

const result = spawnSync("bun", [installer, ...process.argv.slice(2)], { stdio: "inherit" });
if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}
process.exit(result.status ?? 1);
