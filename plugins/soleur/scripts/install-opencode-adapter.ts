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
 *     `skills` / `instructions` entries and every other key survive — for a config this script
 *     can READ. A config it cannot parse (JSONC comments, a syntax error, a torn write) is
 *     **refused**, not replaced: silently substituting `{}` would discard every key the operator
 *     ever set, and report success. `--force` replaces it after writing a `.bak-<ts>` beside it.
 *   - Writes are temp-file + rename, so an interrupted install cannot leave a half-written
 *     `opencode.json` whose next read takes the unparseable path.
 *   - The hook module (`opencode/plugin.ts`, source rather than a generated stub) is copied
 *     into `<configdir>/plugins/`, OpenCode's plugin discovery directory (measurement §6.6),
 *     with the plugin-root token resolved so the installed copy still reaches the checkout's
 *     guard scripts.
 *
 * `--check` writes nothing: it compares the target against `expectedInstalled` and exits 1
 * on a difference.
 */

import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from "fs";
import { dirname, join, relative, resolve } from "path";
import {
  ADAPTER_DIR,
  ADAPTER_SOURCE_FILES,
  PLUGIN_ROOT_TOKEN,
  configFragmentValues,
  expectedOpenCodeAdapter,
} from "./sync-opencode-adapter";

const PLUGIN_ROOT = resolve(dirname(import.meta.filename), "..");

/**
 * Where a vendored payload lives, target-relative.
 *
 * `<configdir>/soleur/` is already Soleur's exclusive namespace in a config dir (the installed
 * `INSTRUCTIONS.md` lives there and `installedExtras` treats everything under it as ours by
 * name), so the payload joins it rather than opening a second namespace. One directory is also
 * one thing to remove on uninstall.
 */
export const VENDOR_DIR = "soleur";

/**
 * The plugin-root subtrees a vendored payload carries.
 *
 * A vendored payload is the canonical plugin root copied into the config dir. It exists because
 * the npm distribution has **no checkout to point at**: `npx` runs the installer out of an
 * ephemeral cache directory, so a config that named the package path rots the moment that cache
 * is pruned — and the failure is silent, because the `skills` key and the guard scripts simply
 * stop resolving. The copy is the durable root.
 *
 * Each entry is load-bearing: `skills` is what the `skills` key registers, `agents`/`commands`
 * are what the generated stubs name, `hooks` is what the installed hook module spawns its guards
 * from, `scripts` is what the canonical prose calls as `<root>/scripts/<name>.sh` (404 call
 * sites), `lib` is what those scripts import, `opencode` is the generated tree the installer
 * itself reads, and `.claude-plugin` is the identity marker `plugin-version.sh` and
 * `resolve-regenerable-conflicts.sh` resolve the root by.
 */
export const PAYLOAD_DIRS = [
  "skills",
  "agents",
  "commands",
  "hooks",
  "scripts",
  "lib",
  ADAPTER_DIR,
  ".claude-plugin",
] as const;

/**
 * Marker that tells a plugin root apart as a **vendored payload** rather than a checkout.
 *
 * It is what lets the copy's own `scripts/install-opencode-adapter.ts --check` pass: run from
 * `<configdir>/soleur/`, the payload is inside the target, so the extras sweep would otherwise
 * report every one of the ~800 payload files as EXTRA and exit 1 — a correct install graded as
 * broken.
 */
export const VENDOR_MARKER = ".soleur-vendored.json";

/** True when `root` is a payload the installer vendored, not a checkout. */
export function isVendoredRoot(root: string): boolean {
  return existsSync(join(root, VENDOR_MARKER));
}

/**
 * Deterministic marker bytes. No version and no timestamp: the payload's own files carry the
 * version (an upgrade changes them and `--check` reports STALE), and a version here would make
 * the marker flap between the two install modes.
 */
function vendorMarkerContent(): string {
  return `${JSON.stringify({ format: 1, kind: "soleur-opencode-payload", owns: [...PAYLOAD_DIRS] }, null, 2)}\n`;
}

/** Every file under `<root>/<dir>`, keyed `<dir>/<relative path>`, in sorted order. */
function walkPayloadFiles(root: string, dir: string): Array<[string, string]> {
  const found: Array<[string, string]> = [];
  const visit = (relativeDir: string): void => {
    let entries;
    try {
      entries = readdirSync(join(root, relativeDir), { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      const path = `${relativeDir}/${entry.name}`;
      if (entry.isDirectory()) {
        visit(path);
        continue;
      }
      found.push([path, readFileSync(join(root, path), "utf-8")]);
    }
  };
  visit(dir);
  return found;
}

export interface InstallOptions {
  force?: boolean;
  /**
   * Mirror the canonical payload into `<target>/soleur/` and point every installed file at that
   * copy instead of at `pluginRoot`. Used by the npm distribution, which has no checkout.
   *
   * A vendored payload is also recognised without this flag: a root carrying `VENDOR_MARKER`
   * owns its payload wherever it sits inside the target, so the copy's own `--check` agrees
   * with the install that produced it.
   */
  vendorPayload?: boolean;
}

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

/**
 * A config file that exists but cannot be read as a JSON object.
 *
 * This is not a generic parse error: it is the branch that decides between merging into an
 * operator's config and destroying it. It names the path and the remedy because the caller's
 * only sane action is to look at that file.
 */
export class UnparseableConfigError extends Error {
  constructor(
    readonly path: string,
    readonly detail: string,
  ) {
    super(
      `${path} exists but is not a JSON object (${detail}). Refusing to overwrite it — that would replace every key you set with the Soleur fragment alone. Fix the file, move it aside, or re-run with --force (which writes a timestamped backup first).`,
    );
    this.name = "UnparseableConfigError";
  }
}

/**
 * Where each generated file lands in a config dir, with tokens resolved.
 *
 * The plugin module is the one file here that is **source, not a generated stub**: it is
 * hand-written in the generator's namespace (`ADAPTER_SOURCE_FILES`) and installed into
 * OpenCode's plugin discovery directory, `<configdir>/plugins/`, with the plugin-root token
 * resolved so the checkout's guard scripts stay reachable from the installed copy.
 */
export function expectedInstalled(
  targetDir: string,
  pluginRoot = PLUGIN_ROOT,
  config?: Record<string, unknown>,
  options: InstallOptions = {},
): Map<string, string> {
  const expected = new Map<string, string>();
  // Where the installed files POINT, as opposed to where their bytes come from. The two are the
  // same for a checkout install. They differ for a vendored payload, where the bytes come from
  // the package and the pointer must name the copy — the only path that outlives the npm cache.
  const effectiveRoot = options.vendorPayload === true ? join(targetDir, VENDOR_DIR) : pluginRoot;
  for (const [path, content] of expectedOpenCodeAdapter(pluginRoot)) {
    if (path === `${ADAPTER_DIR}/opencode.json`) continue; // merged below, never copied verbatim
    // `opencode/` is the generator's namespace, not a discovery root. INSTRUCTIONS.md keeps a
    // `soleur/` prefix so it cannot collide with anything the operator already has.
    const installed =
      path === `${ADAPTER_DIR}/INSTRUCTIONS.md` ? `soleur/${relative(ADAPTER_DIR, path)}` : relative(ADAPTER_DIR, path);
    expected.set(installed, resolveToken(content, effectiveRoot));
  }
  for (const source of ADAPTER_SOURCE_FILES) {
    if (!source.startsWith(`${ADAPTER_DIR}/`)) continue;
    // Every `*.ts` in `<configdir>/plugins/` loads (measurement §6.6), so the installed name
    // carries the plugin's namespace: a bare `plugin.ts` would collide with an operator's own.
    const installed = `plugins/soleur-${source.slice(ADAPTER_DIR.length + 1)}`;
    expected.set(installed, resolveToken(readFileSync(join(pluginRoot, source), "utf-8"), effectiveRoot));
  }
  for (const [path, content] of payloadExpected(targetDir, pluginRoot, effectiveRoot, options)) {
    expected.set(path, content);
  }
  // One definition of the fragment's shape, shared with the generator: the generator emits it
  // with the token, this resolves the token and unions it into the operator's config.
  const fragment = configFragmentValues(effectiveRoot);
  const merged = mergeFragment(config ?? readConfig(join(targetDir, "opencode.json")), {
    skills: fragment.skills,
    // The installed path (`soleur/`), not the generator's `opencode/` namespace.
    instructions: [join(targetDir, "soleur", "INSTRUCTIONS.md")],
  });
  expected.set("opencode.json", `${JSON.stringify(merged, null, 2)}\n`);
  return expected;
}

/**
 * The payload files this install owns, keyed target-relative.
 *
 * Content always comes from `sourceRoot` and is written under `effectiveRoot`, which is what
 * makes the two install modes one code path: a checkout install has no payload inside the target
 * (the checkout is the root, so `effectiveRoot` is outside it and this returns nothing), while a
 * vendored install has `effectiveRoot` inside the target and mirrors the bytes there.
 *
 * Ownership is the point, not the copy: these paths join `expected`, so the extras sweep — which
 * deletes anything under `soleur/` the installer did not write — keeps them instead of deleting
 * the payload one pass after writing it.
 */
function payloadExpected(
  targetDir: string,
  sourceRoot: string,
  effectiveRoot: string,
  options: InstallOptions,
): Map<string, string> {
  const owned = options.vendorPayload === true || isVendoredRoot(sourceRoot);
  const result = new Map<string, string>();
  if (!owned) return result;
  const prefix = relative(targetDir, effectiveRoot).split("\\").join("/");
  // A root outside the target owns nothing inside it: that is the checkout install.
  if (prefix === "" || prefix.startsWith("..")) return result;
  for (const dir of PAYLOAD_DIRS) {
    for (const [path, content] of walkPayloadFiles(sourceRoot, dir)) {
      result.set(`${prefix}/${path}`, content);
    }
  }
  result.set(`${prefix}/${VENDOR_MARKER}`, vendorMarkerContent());
  return result;
}

/**
 * Read an operator config. A **missing** config is an empty one (a first install); anything
 * else that is not a JSON object throws `UnparseableConfigError`. The two cases were one branch
 * (`catch → {}`), which made "first install" and "operator config with JSONC comments"
 * indistinguishable — and the write path then replaced the second with the fragment alone.
 */
function readConfig(path: string): Record<string, unknown> {
  let raw: string;
  try {
    raw = readFileSync(path, "utf-8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return {};
    throw new UnparseableConfigError(path, `could not be read: ${String(error)}`);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    throw new UnparseableConfigError(path, String(error));
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new UnparseableConfigError(path, `top level is ${Array.isArray(parsed) ? "an array" : parsed === null ? "null" : typeof parsed}`);
  }
  return parsed as Record<string, unknown>;
}

/** Target-relative paths of every file under `dir` (empty when the directory is absent). */
function walkFiles(targetDir: string, dir: string): string[] {
  const found: string[] = [];
  const visit = (relativeDir: string): void => {
    let entries;
    try {
      entries = readdirSync(join(targetDir, relativeDir), { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const path = `${relativeDir}/${entry.name}`;
      if (entry.isDirectory()) visit(path);
      else found.push(path);
    }
  };
  visit(dir);
  return found.sort();
}

/**
 * The generated stubs' own signature. `agents/` and `commands/` are SHARED with the operator, so
 * a file there is only removable when it says, in its own text, that this generator wrote it and
 * that it points at the resolved checkout. Anything else in those roots is not ours.
 */
const STUB_SIGNATURES = ["Stub for the canonical agent `", "Run the canonical `"] as const;

function isGeneratedStub(content: string, pluginRoot: string): boolean {
  return content.includes(pluginRoot) && STUB_SIGNATURES.some((signature) => content.includes(signature));
}

/**
 * Files an install owns but no longer generates. Without this, deleting an agent or renaming a
 * command in the canonical tree leaves its installed stub loading forever — a half-updated
 * install that `--check` would call ok.
 */
export function installedExtras(
  targetDir: string,
  expected: Map<string, string>,
  root = PLUGIN_ROOT,
): string[] {
  const extras: string[] = [];
  // Exclusive namespaces: everything under `soleur/` and `plugins/soleur-*` is ours by name.
  // A vendored payload's own files are in `expected`, so they are not "extras".
  for (const path of walkFiles(targetDir, "soleur")) if (!expected.has(path)) extras.push(path);
  for (const path of walkFiles(targetDir, "plugins")) {
    if (path.startsWith("plugins/soleur-") && !expected.has(path)) extras.push(path);
  }
  // Shared roots: attributed by content, never by location. A stub names the RESOLVED root, so
  // `root` here is the effective root the install wrote into those stubs, not the source.
  for (const root_ of ["agents", "commands"]) {
    for (const path of walkFiles(targetDir, root_)) {
      if (expected.has(path)) continue;
      let content: string;
      try {
        content = readFileSync(join(targetDir, path), "utf-8");
      } catch {
        continue;
      }
      if (isGeneratedStub(content, root)) extras.push(path);
    }
  }
  return extras.sort();
}

/** Write through a sibling temp file and rename, so a reader never sees a partial file. */
function writeAtomic(full: string, content: string): void {
  mkdirSync(dirname(full), { recursive: true });
  const temp = `${full}.soleur-tmp-${process.pid}`;
  writeFileSync(temp, content);
  renameSync(temp, full);
}

export interface InstallResult {
  /** Config-dir-relative files written or updated, sorted. */
  written: string[];
  /** Config-dir-relative files that were already correct, sorted. */
  unchanged: string[];
  /** Config-dir-relative stale files removed, sorted. */
  removed: string[];
}

export function installOpenCodeAdapter(
  targetDir: string,
  pluginRoot = PLUGIN_ROOT,
  options: InstallOptions = {},
): InstallResult {
  const result: InstallResult = { written: [], unchanged: [], removed: [] };
  const configPath = join(targetDir, "opencode.json");
  let config: Record<string, unknown> | undefined;
  try {
    config = readConfig(configPath);
  } catch (error) {
    if (!(error instanceof UnparseableConfigError)) throw error;
    if (options.force !== true) throw error;
    const backup = `${configPath}.bak-${Date.now()}`;
    copyFileSync(configPath, backup);
    console.error(`[soleur] --force: replaced ${configPath}; the previous bytes are at ${backup}`);
    config = {};
  }
  const expected = expectedInstalled(targetDir, pluginRoot, config, options);
  const effectiveRoot = options.vendorPayload === true ? join(targetDir, VENDOR_DIR) : pluginRoot;
  for (const [path, content] of expected) {
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
    writeAtomic(full, content);
    result.written.push(path);
  }
  for (const path of installedExtras(targetDir, expected, effectiveRoot)) {
    rmSync(join(targetDir, path), { force: true });
    result.removed.push(path);
  }
  result.written.sort();
  result.unchanged.sort();
  result.removed.sort();
  return result;
}

/** Read-only: paths the target does not already match. Empty means installed and current. */
export function installProblems(targetDir: string, pluginRoot = PLUGIN_ROOT, options: InstallOptions = {}): string[] {
  const problems: string[] = [];
  const expected = expectedInstalled(targetDir, pluginRoot, undefined, options);
  const effectiveRoot = options.vendorPayload === true ? join(targetDir, VENDOR_DIR) : pluginRoot;
  for (const [path, content] of expected) {
    let current: string | undefined;
    try {
      current = readFileSync(join(targetDir, path), "utf-8");
    } catch {
      current = undefined;
    }
    if (current !== content) problems.push(current === undefined ? `MISSING: ${path}` : `STALE: ${path}`);
  }
  for (const path of installedExtras(targetDir, expected, effectiveRoot)) {
    problems.push(`EXTRA: ${path}`);
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

const USAGE = [
  "Usage: bun plugins/soleur/scripts/install-opencode-adapter.ts [--target DIR] [--plugin-root DIR] [--vendor-payload] [--check] [--force] [--help]",
  "",
  "  --target DIR       config dir to install into (default: $HOME/.config/opencode)",
  "  --plugin-root DIR  checkout (or package) the installed files should point at (default: this checkout)",
  "  --vendor-payload   copy the payload into <target>/soleur/ and point the installed files at that",
  "                     copy; required when there is no checkout to point at (the npm distribution)",
  "  --check            write nothing; report MISSING / STALE / EXTRA",
  "  --force            replace an existing opencode.json that cannot be parsed (backup first)",
  "  --help, -h         print this text and exit 0 without writing",
].join("\n");

/**
 * Unknown arguments are rejected: a typo (`--chek`) otherwise falls through to the WRITE path,
 * which is the direction that changes an operator's machine.
 */
function validateArgs(argv: readonly string[]): void {
  const withValue = new Set(["--target", "--plugin-root"]);
  const known = new Set([...withValue, "--vendor-payload", "--check", "--force", "--help", "-h"]);
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
  const explicitTarget = parseArg(argv, "--target");
  const home = process.env["HOME"];
  if (explicitTarget === undefined && (home === undefined || home === "")) {
    console.error(
      "HOME is not set and --target was not given: refusing to install into a cwd-relative `.config/opencode`. Pass --target DIR.",
    );
    process.exit(2);
  }
  const targetDir = resolve(explicitTarget ?? join(home as string, ".config", "opencode"));
  const pluginRoot = resolve(parseArg(argv, "--plugin-root") ?? PLUGIN_ROOT);
  const options: InstallOptions = {
    force: argv.includes("--force"),
    vendorPayload: argv.includes("--vendor-payload"),
  };
  try {
    if (argv.includes("--check")) {
      const problems = installProblems(targetDir, pluginRoot, options);
      if (problems.length > 0) {
        for (const problem of problems) console.error(problem);
        process.exit(1);
      }
      console.log("opencode-install ok");
      return;
    }
    const result = installOpenCodeAdapter(targetDir, pluginRoot, options);
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

if (import.meta.main) main();
