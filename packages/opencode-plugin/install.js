#!/usr/bin/env bun
/**
 * Entry point for `npx @soleur/opencode install` / `bunx @soleur/opencode install`.
 *
 * Delegates to the canonical installer (`./scripts/install-opencode-adapter.ts`) with
 * `vendorPayload: true` so the payload is mirrored into `<target>/soleur/` and every installed
 * reference points at that durable copy rather than an ephemeral npx/bunx cache directory.
 */

import { dirname, join, resolve } from "path";
import { fileURLToPath } from "url";
import {
  UnparseableConfigError,
  installOpenCodeAdapter,
  installProblems,
} from "./scripts/install-opencode-adapter";

const PACKAGE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)));

const USAGE = [
  "Usage: npx @soleur/opencode [install] [--target DIR] [--check] [--force] [--help]",
  "",
  "Commands:",
  "  install        Install Soleur into an OpenCode config directory (default)",
  "",
  "Options:",
  "  --target DIR   Config dir to install into (default: $HOME/.config/opencode)",
  "  --check        Verify the installed tree without writing",
  "  --force        Replace an existing opencode.json that cannot be parsed (writes backup first)",
  "  --help, -h     Show this help message and exit 0",
].join("\n");

function parseArg(argv, flag) {
  const index = argv.indexOf(flag);
  if (index === -1) return undefined;
  const value = argv[index + 1];
  if (value === undefined) {
    console.error(`${flag} requires a directory\n${USAGE}`);
    process.exit(2);
  }
  return value;
}

function main() {
  const rawArgs = process.argv.slice(2);
  const subcommand = rawArgs[0] && !rawArgs[0].startsWith("-") ? rawArgs[0] : "install";
  const argv = rawArgs[0] && !rawArgs[0].startsWith("-") ? rawArgs.slice(1) : rawArgs;

  if (subcommand === "help" || argv.includes("--help") || argv.includes("-h")) {
    console.log(USAGE);
    process.exit(0);
  }

  if (subcommand !== "install" && subcommand !== "setup") {
    console.error(`unknown command: ${subcommand}\n${USAGE}`);
    process.exit(2);
  }

  const withValue = new Set(["--target"]);
  const known = new Set([...withValue, "--check", "--force", "--help", "-h"]);
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!known.has(arg)) {
      console.error(`unknown argument: ${arg}\n${USAGE}`);
      process.exit(2);
    }
    if (withValue.has(arg)) i += 1;
  }

  const explicitTarget = parseArg(argv, "--target");
  const home = process.env["HOME"];
  if (explicitTarget === undefined && (home === undefined || home === "")) {
    console.error(
      "HOME is not set and --target was not given: refusing to install into a cwd-relative `.config/opencode`. Pass --target DIR.",
    );
    process.exit(2);
  }

  const targetDir = resolve(explicitTarget ?? join(home, ".config", "opencode"));
  const options = {
    force: argv.includes("--force"),
    vendorPayload: true,
  };

  try {
    if (argv.includes("--check")) {
      const problems = installProblems(targetDir, PACKAGE_ROOT, options);
      if (problems.length > 0) {
        for (const problem of problems) console.error(problem);
        process.exit(1);
      }
      console.log("opencode-install ok");
      return;
    }
    const result = installOpenCodeAdapter(targetDir, PACKAGE_ROOT, options);
    console.log(
      `opencode-adapter installed into ${targetDir} (${result.written.length} written, ${result.unchanged.length} unchanged, ${result.removed.length} removed)`,
    );
  } catch (error) {
    if (error instanceof UnparseableConfigError) {
      console.error(error.message);
      process.exit(1);
    }
    throw error;
  }
}

main();
