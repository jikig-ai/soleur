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
 *     the roots OpenCode discovers (§3.0, §4.0). Skills are **not** copied on a checkout
 *     install — they register from the canonical tree through the `skills` key (§2.0), so the
 *     config points at the checkout and a second skill tree that could drift is never created.
 *   - On an npm install (`--vendor-payload`), the canonical payload is mirrored into
 *     `<configdir>/soleur/` so every installed reference points at a durable directory that
 *     survives `npx` / `bunx` cache eviction.
 *   - The config fragment is merged rather than written, so an operator's existing
 *     `skills` / `instructions` entries and every other key survive — for a config this script
 *     can READ. A config it cannot parse (JSONC comments, a syntax error, a torn write) is
 *     **refused**, not replaced: silently substituting `{}` would discard every key the operator
 *     ever set, and report success. `--force` replaces it after writing a `.bak-<ts>` beside it.
 *   - Writes are temp-file + rename, so an interrupted install cannot leave a half-written
 *     `opencode.json` whose next read takes the unparseable path.
 *   - The hook module (`opencode/plugin.ts`, source rather than a generated stub) is copied
 *     into `<configdir>/plugins/`, OpenCode's plugin discovery directory (measurement §6.6),
 *     with the plugin-root token resolved so the installed copy still reaches the guard scripts.
 *
 * `--check` writes nothing: it compares the target against `expectedInstalled` and exits 1
 * on a difference.
 */

import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "fs";
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

function vendorMarkerContent(): string {
  return `${JSON.stringify({ format: 1, kind: "soleur-opencode-payload", owns: [...PAYLOAD_DIRS] }, null, 2)}\n`;
}

export interface PayloadEntry {
  content: string;
  executable: boolean;
}

/**
 * Every regular file under `<root>/<dir>`, keyed `<dir>/<relative path>`, in sorted order.
 * Symlinks are refused so a stray symlink in the source tree can never be dereferenced into
 * the published npm tarball or vendored config directory.
 */
export function walkPayloadFiles(root: string, dir: string): Array<[string, PayloadEntry]> {
  const found: Array<[string, PayloadEntry]> = [];
  const visit = (relativeDir: string): void => {
    let entries;
    try {
      entries = readdirSync(join(root, relativeDir), { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      const path = `${currentPath(relativeDir, entry.name)}`;
      if (entry.isSymbolicLink()) {
        throw new Error(`Refusing symbolic link in payload tree: ${join(root, path)}`);
      }
      if (entry.isDirectory()) {
        visit(path);
        continue;
      }
      if (!entry.isFile()) continue;
      const full = join(root, path);
      const executable = (statSync(full).mode & 0o111) !== 0;
      found.push([path, { content: readFileSync(full, "utf-8"), executable }]);
    }
  };
  visit(dir);
  return found;
}

function currentPath(dir: string, name: string): string {
  return `${dir}/${name}`;
}

/** Full payload map for `root`, shared with `sync-npm-package.ts`. */
export function expectedPayloadEntries(root: string): Map<string, PayloadEntry> {
  const expected = new Map<string, PayloadEntry>();
  for (const dir of PAYLOAD_DIRS) {
    for (const [path, entry] of walkPayloadFiles(root, dir)) {
      expected.set(path, entry);
    }
  }
  return expected;
}

export interface InstallOptions {
  force?: boolean;
  /**
   * Mirror the canonical payload into `<target>/soleur/` and point every installed file at that
   * copy instead of at `pluginRoot`. Used by the npm distribution, which has no checkout.
   */
  vendorPayload?: boolean;
}

function resolveEffectiveRoot(targetDir: string, pluginRoot: string, options: InstallOptions): string {
  return options.vendorPayload === true ? join(targetDir, VENDOR_DIR) : pluginRoot;
}

/** `__SOLEUR_PLUGIN_ROOT__` → the resolved root. The only substitution in the whole install. */
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

export function expectedInstalled(
  targetDir: string,
  pluginRoot = PLUGIN_ROOT,
  config?: Record<string, unknown>,
  options: InstallOptions = {},
): Map<string, string> {
  const expected = new Map<string, string>();
  const effectiveRoot = resolveEffectiveRoot(targetDir, pluginRoot, options);
  for (const [path, content] of expectedOpenCodeAdapter(pluginRoot)) {
    if (path === `${ADAPTER_DIR}/opencode.json`) continue;
    const installed =
      path === `${ADAPTER_DIR}/INSTRUCTIONS.md` ? `soleur/${relative(ADAPTER_DIR, path)}` : relative(ADAPTER_DIR, path);
    expected.set(installed, resolveToken(content, effectiveRoot));
  }
  for (const source of ADAPTER_SOURCE_FILES) {
    if (!source.startsWith(`${ADAPTER_DIR}/`)) continue;
    const installed = `plugins/soleur-${source.slice(ADAPTER_DIR.length + 1)}`;
    expected.set(installed, resolveToken(readFileSync(join(pluginRoot, source), "utf-8"), effectiveRoot));
  }
  for (const [path, entry] of payloadExpected(targetDir, pluginRoot, effectiveRoot, options)) {
    expected.set(path, entry.content);
  }
  const fragment = configFragmentValues(effectiveRoot);
  const merged = mergeFragment(config ?? readConfig(join(targetDir, "opencode.json")), {
    skills: fragment.skills,
    instructions: [join(targetDir, "soleur", "INSTRUCTIONS.md")],
  });
  expected.set("opencode.json", `${JSON.stringify(merged, null, 2)}\n`);
  return expected;
}

function payloadExpected(
  targetDir: string,
  sourceRoot: string,
  effectiveRoot: string,
  options: InstallOptions,
): Map<string, PayloadEntry> {
  const owned = options.vendorPayload === true || isVendoredRoot(sourceRoot);
  const result = new Map<string, PayloadEntry>();
  if (!owned) return result;
  const prefix = relative(targetDir, effectiveRoot).split("\\").join("/");
  if (prefix === "" || prefix.startsWith("..")) return result;
  for (const [path, entry] of expectedPayloadEntries(sourceRoot)) {
    result.set(`${prefix}/${path}`, entry);
  }
  result.set(`${prefix}/${VENDOR_MARKER}`, { content: vendorMarkerContent(), executable: false });
  return result;
}

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
    throw new UnparseableConfigError(
      path,
      `top level is ${Array.isArray(parsed) ? "an array" : parsed === null ? "null" : typeof parsed}`,
    );
  }
  return parsed as Record<string, unknown>;
}

/** Target-relative paths of every regular file under `dir` (skips symlinks; empty when absent). */
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
      if (entry.isSymbolicLink()) continue;
      const path = `${relativeDir}/${entry.name}`;
      if (entry.isDirectory()) visit(path);
      else if (entry.isFile()) found.push(path);
    }
  };
  visit(dir);
  return found.sort();
}

const STUB_SIGNATURES = ["Stub for the canonical agent `", "Run the canonical `"] as const;

function isGeneratedStub(content: string, pluginRoot: string): boolean {
  return content.includes(pluginRoot) && STUB_SIGNATURES.some((signature) => content.includes(signature));
}

export function installedExtras(
  targetDir: string,
  expected: Map<string, string>,
  root = PLUGIN_ROOT,
): string[] {
  const extras: string[] = [];
  for (const path of walkFiles(targetDir, "soleur")) if (!expected.has(path)) extras.push(path);
  for (const path of walkFiles(targetDir, "plugins")) {
    if (path.startsWith("plugins/soleur-") && !expected.has(path)) extras.push(path);
  }
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

/** Write through a sibling temp file and rename, preserving executable mode when needed. */
function writeAtomic(full: string, content: string, executable = false): void {
  mkdirSync(dirname(full), { recursive: true });
  const temp = `${full}.soleur-tmp-${process.pid}`;
  writeFileSync(temp, content);
  if (executable) chmodSync(temp, 0o755);
  renameSync(temp, full);
}

export interface InstallResult {
  written: string[];
  unchanged: string[];
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
  const effectiveRoot = resolveEffectiveRoot(targetDir, pluginRoot, options);
  const payload = payloadExpected(targetDir, pluginRoot, effectiveRoot, options);
  const expected = expectedInstalled(targetDir, pluginRoot, config, options);
  for (const [path, content] of expected) {
    const full = join(targetDir, path);
    const wantExec = payload.get(path)?.executable === true;
    let current: string | undefined;
    let currentExec = false;
    try {
      current = readFileSync(full, "utf-8");
      currentExec = (statSync(full).mode & 0o111) !== 0;
    } catch {
      current = undefined;
    }
    if (current === content && (!wantExec || currentExec)) {
      result.unchanged.push(path);
      continue;
    }
    writeAtomic(full, content, wantExec);
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

export function installProblems(targetDir: string, pluginRoot = PLUGIN_ROOT, options: InstallOptions = {}): string[] {
  const problems: string[] = [];
  const effectiveRoot = resolveEffectiveRoot(targetDir, pluginRoot, options);
  const payload = payloadExpected(targetDir, pluginRoot, effectiveRoot, options);
  const expected = expectedInstalled(targetDir, pluginRoot, undefined, options);
  for (const [path, content] of expected) {
    const full = join(targetDir, path);
    const wantExec = payload.get(path)?.executable === true;
    let current: string | undefined;
    let currentExec = false;
    try {
      current = readFileSync(full, "utf-8");
      currentExec = (statSync(full).mode & 0o111) !== 0;
    } catch {
      current = undefined;
    }
    if (current === undefined) problems.push(`MISSING: ${path}`);
    else if (current !== content || (wantExec && !currentExec)) problems.push(`STALE: ${path}`);
  }
  for (const path of installedExtras(targetDir, expected, effectiveRoot)) {
    problems.push(`EXTRA: ${path}`);
  }
  return problems.sort();
}

function parseArg(argv: readonly string[], flag: string): string | undefined {
  const index = argv.indexOf(flag);
  if (index === -1) return undefined;
  return argv[index + 1];
}

const USAGE = [
  "Usage: bun plugins/soleur/scripts/install-opencode-adapter.ts [install] [--target DIR] [--plugin-root DIR] [--vendor-payload] [--check] [--force] [--help]",
  "",
  "  --target DIR       config dir to install into (default: $HOME/.config/opencode)",
  "  --plugin-root DIR  checkout (or package) the installed files should point at (default: this checkout)",
  "  --vendor-payload   copy the payload into <target>/soleur/ and point the installed files at that",
  "                     copy; required when there is no checkout to point at (the npm distribution)",
  "  --check            write nothing; report MISSING / STALE / EXTRA",
  "  --force            replace an existing opencode.json that cannot be parsed (backup first)",
  "  --help, -h         print this text and exit 0 without writing",
].join("\n");

function validateArgs(argv: readonly string[], usage = USAGE): void {
  const withValue = new Set(["--target", "--plugin-root"]);
  const known = new Set([...withValue, "--vendor-payload", "--check", "--force", "--help", "-h"]);
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      console.log(usage);
      process.exit(0);
    }
    if (!known.has(arg)) {
      console.error(`unknown argument: ${arg}\n${usage}`);
      process.exit(2);
    }
    if (withValue.has(arg)) {
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("-")) {
        console.error(`${arg} requires a directory\n${usage}`);
        process.exit(2);
      }
      i += 1;
    }
  }
}

export function runCli(
  rawArgv: readonly string[],
  defaultPluginRoot = PLUGIN_ROOT,
  defaultVendorPayload = false,
  usage = USAGE,
): void {
  const argv = rawArgv[0] === "install" ? rawArgv.slice(1) : rawArgv;
  validateArgs(argv, usage);
  const explicitTarget = parseArg(argv, "--target");
  const home = process.env["HOME"];
  if (explicitTarget === undefined && (home === undefined || home === "")) {
    console.error(
      "HOME is not set and --target was not given: refusing to install into a cwd-relative `.config/opencode`. Pass --target DIR.",
    );
    process.exit(2);
  }
  const targetDir = resolve(explicitTarget ?? join(home as string, ".config", "opencode"));
  const pluginRoot = resolve(parseArg(argv, "--plugin-root") ?? defaultPluginRoot);
  const options: InstallOptions = {
    force: argv.includes("--force"),
    vendorPayload: defaultVendorPayload || argv.includes("--vendor-payload"),
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

if (import.meta.main) runCli(process.argv.slice(2));
