#!/usr/bin/env bun
/**
 * Materialize and verify the `@soleur/opencode` npm package payload from the canonical tree.
 *
 *   bun plugins/soleur/scripts/sync-npm-package.ts
 *   bun plugins/soleur/scripts/sync-npm-package.ts --check
 *   bun plugins/soleur/scripts/sync-npm-package.ts --out-dir DIR
 *
 * The npm distribution carries a materialized copy of `PAYLOAD_DIRS` because `npm publish` packs
 * files from the package directory. To avoid duplicating ~800 files in git, the generated payload
 * subtrees under `packages/opencode-plugin/` are gitignored and materialized at build/publish time
 * by this script. `PAYLOAD_DIRS` and `expectedPayloadEntries` are imported from
 * `install-opencode-adapter.ts` so the package builder and the vendored installer share one
 * definition of the payload and preserve executable file bits (`0755`).
 */

import { chmodSync, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "fs";
import { dirname, join, resolve } from "path";
import { PAYLOAD_DIRS, expectedPayloadEntries, walkPayloadFiles } from "./install-opencode-adapter";

/** The canonical plugin root — the copy's source. */
const CANONICAL_ROOT = resolve(dirname(import.meta.filename), "..");

/** Repo-relative location of the npm package. */
const PACKAGE_RELATIVE = "packages/opencode-plugin";

/** Hand-written source files at the package root that this script does NOT own. */
export const PACKAGE_SOURCE_FILES = ["package.json", "README.md", "install.js", "bin"] as const;

function defaultPackageRoot(repoRoot: string): string {
  return join(repoRoot, PACKAGE_RELATIVE);
}

/** The canonical payload, keyed package-relative — the truth `--check` compares against. */
export function expectedPackage(repoRoot: string): Map<string, string> {
  const canonical = join(repoRoot, "plugins", "soleur");
  const expected = new Map<string, string>();
  for (const [path, entry] of expectedPayloadEntries(canonical)) {
    expected.set(path, entry.content);
  }
  return expected;
}

/** Materialized payload files under `pkgRoot`, package-relative. */
function materializedPackage(pkgRoot: string): string[] {
  const found: string[] = [];
  for (const dir of PAYLOAD_DIRS) {
    for (const [path] of walkPayloadFiles(pkgRoot, dir)) found.push(path);
  }
  return found.sort();
}

/** Drift between a materialized package root and a fresh walk of the canonical tree. */
export function packageProblems(repoRoot: string, outDir?: string): string[] {
  const canonical = join(repoRoot, "plugins", "soleur");
  const expected = expectedPayloadEntries(canonical);
  const root = outDir ?? defaultPackageRoot(repoRoot);
  const problems: string[] = [];
  for (const [path, entry] of expected) {
    const full = join(root, path);
    let current: string | undefined;
    let currentExec = false;
    try {
      current = readFileSync(full, "utf-8");
      currentExec = (statSync(full).mode & 0o111) !== 0;
    } catch {
      current = undefined;
    }
    if (current === undefined) problems.push(`MISSING: ${path}`);
    else if (current !== entry.content || (entry.executable && !currentExec)) problems.push(`DRIFT: ${path}`);
  }
  for (const path of materializedPackage(root)) {
    if (!expected.has(path)) problems.push(`EXTRA: ${path}`);
  }
  for (const path of PACKAGE_SOURCE_FILES) {
    if (!existsSync(join(root, path))) problems.push(`MISSING-SOURCE: ${path}`);
  }
  return problems.sort();
}

/** Write the payload into `outDir` (default: `packages/opencode-plugin`), preserving executable bits. */
export function writePackage(repoRoot: string, outDir?: string): string[] {
  const canonical = join(repoRoot, "plugins", "soleur");
  const root = outDir ?? defaultPackageRoot(repoRoot);
  const expected = expectedPayloadEntries(canonical);
  for (const [path, entry] of expected) {
    const full = join(root, path);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, entry.content);
    if (entry.executable) chmodSync(full, 0o755);
  }
  for (const path of materializedPackage(root)) {
    if (!expected.has(path)) rmSync(join(root, path), { force: true });
  }
  return packageProblems(repoRoot, root);
}

/** Remove generated payload subtrees from `outDir` (default: `packages/opencode-plugin`). */
export function cleanPackage(repoRoot: string, outDir?: string): void {
  const root = outDir ?? defaultPackageRoot(repoRoot);
  for (const dir of PAYLOAD_DIRS) {
    rmSync(join(root, dir), { recursive: true, force: true });
  }
}

function parseArg(argv: readonly string[], flag: string): string | undefined {
  const index = argv.indexOf(flag);
  if (index === -1) return undefined;
  return argv[index + 1];
}

const USAGE = [
  "Usage: bun plugins/soleur/scripts/sync-npm-package.ts [--repo-root DIR] [--out-dir DIR] [--check] [--clean] [--help]",
  "",
  "  --repo-root DIR  repository root containing plugins/soleur and packages/opencode-plugin",
  "                   (default: this checkout)",
  "  --out-dir DIR    package root to materialize/check (default: <repo-root>/packages/opencode-plugin)",
  "  --check          compare the materialized package against a fresh walk; write nothing",
  "  --clean          remove generated payload directories from the package root",
  "  --help, -h       print this text and exit 0 without writing",
].join("\n");

function validateArgs(argv: readonly string[]): void {
  const withValue = new Set(["--repo-root", "--out-dir"]);
  const known = new Set([...withValue, "--check", "--clean", "--help", "-h"]);
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      console.log(USAGE);
      process.exit(0);
    }
    if (!known.has(arg)) {
      console.error(`unknown argument: ${arg}\n${USAGE}`);
      process.exit(2);
    }
    if (withValue.has(arg)) {
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("-")) {
        console.error(`${arg} requires a directory\n${USAGE}`);
        process.exit(2);
      }
      i += 1;
    }
  }
}

function main(): void {
  const argv = process.argv.slice(2);
  validateArgs(argv);
  const root = resolve(parseArg(argv, "--repo-root") ?? resolve(CANONICAL_ROOT, "..", ".."));
  const explicitOut = parseArg(argv, "--out-dir");
  const outDir = explicitOut !== undefined ? resolve(explicitOut) : undefined;
  if (argv.includes("--clean")) {
    cleanPackage(root, outDir);
    return;
  }
  const problems = argv.includes("--check") ? packageProblems(root, outDir) : writePackage(root, outDir);
  if (problems.length > 0) {
    for (const problem of problems) console.error(problem);
    process.exit(1);
  }
  if (argv.includes("--check")) console.log("npm-package ok");
}

if (import.meta.main) main();
