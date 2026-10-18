#!/usr/bin/env bun
/**
 * Install the generated OpenCode front door into an OpenCode config directory.
 *
 *   bun plugins/soleur/scripts/install-opencode-adapter.ts                 # ~/.config/opencode
 *   bun plugins/soleur/scripts/install-opencode-adapter.ts --target DIR    # e.g. a project .opencode
 *   bun plugins/soleur/scripts/install-opencode-adapter.ts --check --target DIR
 *
 * Why this exists: the generated tree commits its paths as `__SOLEUR_PLUGIN_ROOT__` rather
 * than absolute ones, because the tree is shared across machines and an absolute path would
 * make `sync-opencode-adapter.ts --check` machine-dependent. OpenCode's `skills` and
 * `instructions` keys take plain paths with no env expansion, and the config schema has no
 * `import` key (measurement §7.1), so something must resolve the token once, on the
 * operator's machine. That is this script.
 *
 * Shapes here are each forced by a measurement:
 *
 *   - `agents/` and `commands/` are copied straight into the config dir, because those are
 *     the roots OpenCode discovers (§3.0, §4.0). Skills are **not** copied — they register
 *     from the canonical tree through the `skills` key (§2.0), so the config points at the
 *     checkout and a second skill tree that could drift is never created.
 *   - The config fragment is merged rather than written, so an operator's existing
 *     `skills` / `instructions` entries and every other key survive.
 *
 * `--check` writes nothing: it compares the target against `expectedInstalled` and exits 1
 * on a difference.
 */

import { mkdirSync, readFileSync, writeFileSync } from "fs";
import { dirname, join, relative, resolve } from "path";
import { ADAPTER_DIR, PLUGIN_ROOT_TOKEN, expectedOpenCodeAdapter } from "./sync-opencode-adapter";

const PLUGIN_ROOT = resolve(dirname(import.meta.filename), "..");

/** `__SOLEUR_PLUGIN_ROOT__` → the real checkout. The only substitution in the whole install. */
function resolveToken(content: string, pluginRoot: string): string {
  return content.split(PLUGIN_ROOT_TOKEN).join(pluginRoot);
}

/** Union a fragment's path arrays into an existing config, preserving every other key. */
export function mergeFragment(
  existing: Record<string, unknown>,
  fragment: { skills: string[]; instructions: string[] },
): Record<string, unknown> {
  const merged: Record<string, unknown> = { ...existing };
  for (const key of ["skills", "instructions"] as const) {
    const present = Array.isArray(existing[key]) ? (existing[key] as unknown[]) : [];
    merged[key] = [...present, ...fragment[key]].filter((value, index, all) => all.indexOf(value) === index);
  }
  return merged;
}

/** Where each generated file lands in a config dir, with tokens resolved. */
export function expectedInstalled(targetDir: string, pluginRoot = PLUGIN_ROOT): Map<string, string> {
  const expected = new Map<string, string>();
  for (const [path, content] of expectedOpenCodeAdapter(pluginRoot)) {
    if (path === `${ADAPTER_DIR}/opencode.json`) continue; // merged below, never copied verbatim
    // `opencode/` is the generator's namespace, not a discovery root. INSTRUCTIONS.md keeps a
    // `soleur/` prefix so it cannot collide with anything the operator already has.
    const installed =
      path === `${ADAPTER_DIR}/INSTRUCTIONS.md` ? `soleur/${relative(ADAPTER_DIR, path)}` : relative(ADAPTER_DIR, path);
    expected.set(installed, resolveToken(content, pluginRoot));
  }
  const merged = mergeFragment(readConfig(join(targetDir, "opencode.json")), {
    skills: [join(pluginRoot, "skills")],
    instructions: [join(targetDir, "soleur", "INSTRUCTIONS.md")],
  });
  expected.set("opencode.json", `${JSON.stringify(merged, null, 2)}\n`);
  return expected;
}

function readConfig(path: string): Record<string, unknown> {
  try {
    const parsed: unknown = JSON.parse(readFileSync(path, "utf-8"));
    return parsed !== null && typeof parsed === "object" ? (parsed as Record<string, unknown>) : {};
  } catch {
    // A missing or unparseable config must not abort an install: the fragment becomes the
    // whole file, and the operator's bytes are replaced only on the write path.
    return {};
  }
}

export interface InstallResult {
  /** Config-dir-relative files written or updated, sorted. */
  written: string[];
  /** Config-dir-relative files that were already correct, sorted. */
  unchanged: string[];
}

export function installOpenCodeAdapter(targetDir: string, pluginRoot = PLUGIN_ROOT): InstallResult {
  const result: InstallResult = { written: [], unchanged: [] };
  for (const [path, content] of expectedInstalled(targetDir, pluginRoot)) {
    const full = join(targetDir, path);
    let current: string | undefined;
    try {
      current = readFileSync(full, "utf-8");
    } catch {
      current = undefined;
    }
    if (current === content) {
      result.unchanged.push(path);
      continue;
    }
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, content);
    result.written.push(path);
  }
  result.written.sort();
  result.unchanged.sort();
  return result;
}

/** Read-only: paths the target does not already match. Empty means installed and current. */
export function installProblems(targetDir: string, pluginRoot = PLUGIN_ROOT): string[] {
  const problems: string[] = [];
  for (const [path, content] of expectedInstalled(targetDir, pluginRoot)) {
    let current: string | undefined;
    try {
      current = readFileSync(join(targetDir, path), "utf-8");
    } catch {
      current = undefined;
    }
    if (current !== content) problems.push(current === undefined ? `MISSING: ${path}` : `STALE: ${path}`);
  }
  return problems.sort();
}

function parseArg(argv: readonly string[], flag: string): string | undefined {
  const index = argv.indexOf(flag);
  if (index === -1) return undefined;
  const value = argv[index + 1];
  if (value === undefined) throw new Error(`${flag} requires a directory`);
  return value;
}

function main(): void {
  const argv = process.argv.slice(2);
  const targetDir = resolve(parseArg(argv, "--target") ?? join(process.env["HOME"] ?? "", ".config", "opencode"));
  const pluginRoot = resolve(parseArg(argv, "--plugin-root") ?? PLUGIN_ROOT);
  if (argv.includes("--check")) {
    const problems = installProblems(targetDir, pluginRoot);
    if (problems.length > 0) {
      for (const problem of problems) console.error(problem);
      process.exit(1);
    }
    console.log("opencode-install ok");
    return;
  }
  const result = installOpenCodeAdapter(targetDir, pluginRoot);
  console.log(
    `opencode-adapter installed into ${targetDir} (${result.written.length} written, ${result.unchanged.length} unchanged)`,
  );
}

if (import.meta.main) main();
