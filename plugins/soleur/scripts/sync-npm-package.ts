#!/usr/bin/env bun
/**
 * Generate the `@soleur/opencode` payload from the canonical tree.
 *
 *   bun plugins/soleur/scripts/sync-npm-package.ts
 *   bun plugins/soleur/scripts/sync-npm-package.ts --check
 *
 * The npm distribution is a **copy** of the plugin root, and this is the only thing that writes
 * that copy. Nothing under `packages/opencode-plugin/` is hand-copied: the package's hand-written
 * files are `package.json`, `README.md`, `install.js` and `bin/`, and everything else is a mirror
 * of a subtree this script owns.
 *
 * Why a copy at all, when ADR-291 has OpenCode register skills straight from the canonical tree
 * with no second tree to drift? Because npm has no checkout to point at. The package has to carry
 * the bytes it installs, so a copy is unavoidable at the boundary; what ADR-245's drift obligation
 * buys us instead is that the copy cannot be *wrong*: `--check` compares it against a fresh walk
 * and exits 1 naming the path, so a canonical skill, agent, script or hook edited without
 * regenerating the package reds in CI rather than shipping stale.
 *
 * `PAYLOAD_DIRS` is imported from the installer rather than restated here: the set the copy
 * carries and the set the installer owns inside a config dir are the same set, and two lists
 * would drift apart silently.
 */

import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "fs";
import { dirname, join, resolve } from "path";
import { PAYLOAD_DIRS } from "./install-opencode-adapter";

/** The canonical plugin root — the copy's source. */
const CANONICAL_ROOT = resolve(dirname(import.meta.filename), "..");

/** Repo-relative location of the npm package. */
const PACKAGE_RELATIVE = "packages/opencode-plugin";

/** Files at the package root that this script does NOT own. */
export const PACKAGE_SOURCE_FILES = ["package.json", "README.md", "install.js", "bin", ".npmignore"] as const;

function packageRoot(repoRoot: string): string {
  return join(repoRoot, PACKAGE_RELATIVE);
}

/** Every file under `<root>/<relativeDir>`, keyed `<relativeDir>/<path>`. */
function walk(root: string, relativeDir: string): Map<string, string> {
  const found = new Map<string, string>();
  const visit = (current: string): void => {
    let entries;
    try {
      entries = readdirSync(join(root, current), { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      const path = `${current}/${entry.name}`;
      if (entry.isDirectory()) {
        visit(path);
        continue;
      }
      found.set(path, readFileSync(join(root, path), "utf-8"));
    }
  };
  visit(relativeDir);
  return found;
}

/** The canonical payload, keyed package-relative — the whole truth `--check` compares against. */
export function expectedPackage(repoRoot: string): Map<string, string> {
  const canonical = join(repoRoot, "plugins", "soleur");
  const expected = new Map<string, string>();
  for (const dir of PAYLOAD_DIRS) {
    for (const [path, content] of walk(canonical, dir)) expected.set(path, content);
  }
  return expected;
}

/** Committed payload files under the package, package-relative. */
function committedPackage(repoRoot: string): string[] {
  const found: string[] = [];
  for (const dir of PAYLOAD_DIRS) {
    for (const path of walk(packageRoot(repoRoot), dir).keys()) found.push(path);
  }
  return found.sort();
}

/** Drift between the committed package and a fresh walk of the canonical tree. Empty means clean. */
export function packageProblems(repoRoot: string): string[] {
  const expected = expectedPackage(repoRoot);
  const root = packageRoot(repoRoot);
  const problems: string[] = [];
  for (const [path, content] of expected) {
    let current: string | undefined;
    try {
      current = readFileSync(join(root, path), "utf-8");
    } catch {
      current = undefined;
    }
    if (current === undefined) problems.push(`MISSING: ${path}`);
    else if (current !== content) problems.push(`DRIFT: ${path}`);
  }
  for (const path of committedPackage(repoRoot)) {
    if (!expected.has(path)) problems.push(`EXTRA: ${path}`);
  }
  // The hand-written files are what makes the mirror a package. Their absence is a defect a
  // payload-only comparison cannot see: a directory of the right bytes with no bin installs
  // nothing.
  for (const path of PACKAGE_SOURCE_FILES) {
    if (!existsSync(join(root, path))) problems.push(`MISSING-SOURCE: ${path}`);
  }
  return problems.sort();
}

/** Write the payload, then report the post-write check (which catches stale extras). */
export function writePackage(repoRoot: string): string[] {
  const root = packageRoot(repoRoot);
  const expected = expectedPackage(repoRoot);
  for (const [path, content] of expected) {
    const full = join(root, path);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, content);
  }
  // A payload file the canonical tree no longer has is not removed by writing it back; drop it
  // so a retired skill cannot keep installing from the package.
  for (const path of committedPackage(repoRoot)) {
    if (!expected.has(path)) rmSync(join(root, path), { force: true });
  }
  return packageProblems(repoRoot);
}

/** Remove generated payload subtrees from `packages/opencode-plugin/`, leaving hand-written source files intact. */
export function cleanPackage(repoRoot: string): void {
  const root = packageRoot(repoRoot);
  for (const dir of PAYLOAD_DIRS) {
    rmSync(join(root, dir), { recursive: true, force: true });
  }
}

function repoRoot(argv: readonly string[]): string {
  const index = argv.indexOf("--repo-root");
  if (index === -1) return resolve(CANONICAL_ROOT, "..", "..");
  const value = argv[index + 1];
  if (value === undefined) throw new Error("--repo-root requires a directory");
  return resolve(value);
}

const USAGE = [
  "Usage: bun plugins/soleur/scripts/sync-npm-package.ts [--repo-root DIR] [--check] [--clean] [--help]",
  "",
  "  --repo-root DIR  repository root containing plugins/soleur and packages/opencode-plugin",
  "                   (default: this checkout)",
  "  --check          compare the materialized package against a fresh walk; write nothing",
  "  --clean          remove generated payload directories from packages/opencode-plugin",
  "  --help, -h       print this text and exit 0 without writing",
].join("\n");

/**
 * Every argument must be known. A silently ignored typo (`--chek`) takes the WRITE path while the
 * operator believes they asked for a check — the direction that overwrites the package.
 */
function validateArgs(argv: readonly string[]): void {
  const withValue = new Set(["--repo-root"]);
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
    if (withValue.has(arg)) i += 1;
  }
}

function main(): void {
  const argv = process.argv.slice(2);
  validateArgs(argv);
  const root = repoRoot(argv);
  if (argv.includes("--clean")) {
    cleanPackage(root);
    return;
  }
  const problems = argv.includes("--check") ? packageProblems(root) : writePackage(root);
  if (problems.length > 0) {
    for (const problem of problems) console.error(problem);
    process.exit(1);
  }
  if (argv.includes("--check")) console.log("npm-package ok");
}

if (import.meta.main) main();
