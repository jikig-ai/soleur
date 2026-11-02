#!/usr/bin/env bun
/**
 * Entry point for `npx @soleur/opencode install` / `bunx @soleur/opencode install`.
 *
 * Delegates directly to `runCli` in `./scripts/install-opencode-adapter.ts` with
 * `defaultVendorPayload = true` so the payload is mirrored into `<target>/soleur/` and every
 * installed reference points at that durable copy rather than an ephemeral npx/bunx cache directory.
 */

import { dirname, resolve } from "path";
import { fileURLToPath } from "url";
import { runCli } from "./scripts/install-opencode-adapter";

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

runCli(process.argv.slice(2), PACKAGE_ROOT, true, USAGE);
