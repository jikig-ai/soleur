#!/usr/bin/env bun
/**
 * harness-discovery-smoke — prove Codex, Devin and OpenCode DISCOVER the skill set
 * their manifests declare, by installing the plugin hermetically from this checkout and
 * asking the vendor CLI what it registered (ADR-245; the unfiled item 6 of #8390's
 * bundle).
 *
 * WHAT THIS PROVES, AND WHAT IT DOES NOT.
 *   - It proves REGISTRATION: the name is in the harness's skill list. It does not
 *     prove INVOCABILITY (ADR-236: `codex exec` ignores `disable-model-invocation`,
 *     and `devin skills list` reports `[user]` vs `[user,model]`), and it does not
 *     prove WHICH copy was loaded — for `go`/`help`/`sync` the shim body differs
 *     from the canonical skill, and a single listing cannot distinguish them.
 *   - It proves nothing about UNIQUENESS. A newly added `codex/skills/plan/` is
 *     legitimately k=2 and passes here by construction; cross-root collision policy
 *     stays with `components.test.ts` (ADR-224 decision 5, ACKED_CROSS_ROOT_DUPES).
 *
 * OPENCODE IS A DIFFERENT SHAPE, and the differences are each forced by a measurement
 * (§11.0): ids are BARE directory basenames with no namespace, so `plan` names both this
 * plugin's skill and the operator's own — the arm keys on the absolute `path`, not the id.
 * The listing also requires a live session: `GET /api/skill` answers an empty array until
 * one exists, so the arm opens one rather than reading a listing that would be a false
 * alarm about a correct install.
 *
 * The pure functions below are exported and unit-tested offline against synthesized
 * fixtures (`plugins/soleur/test/harness-discovery-smoke.test.ts`); the CLI-driving
 * half is the same code under a real binary. NOTE: importing this module binds a
 * per-process scratch session (`ensureScratchSession()` at load, below) — importers
 * of the pure functions get the environment mutation too; it is a no-op nested under
 * an already-bound root.
 *
 * `scripts/codex-plugin-smoke.mjs` is deliberately UNTOUCHED: it is the operator-local
 * check of an already-installed plugin and its hooks, and needs `~/.codex` state this
 * gate refuses to depend on.
 */

import { execFileSync, spawn, spawnSync } from "child_process";
import { randomBytes } from "crypto";
import {
  closeSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "fs";
import { tmpdir } from "os";
import { dirname, isAbsolute, join, relative, resolve, sep } from "path";
import { ensureScratchSession } from "../test/lib/scratch-session";
import { gitCleanEnv } from "../test/lib/git-clean-env";
import { PLUGIN_ROOT_TOKEN } from "./sync-opencode-adapter";

// Bind a per-process scratch session root (#7004, ADR-250) BEFORE anything
// allocates: this script runs via `bun <file>` (ci.yml), where the bunfig
// [test].preload does NOT run, so this statement IS the adoption — scratchDir()
// below then lands every harness-discovery-* home/repo under an owned
// soleur-run.<pid>.* root the reapers can attribute when a run is SIGKILLed
// (clean exits were already covered by SCRATCH[]/cleanupScratch()). A nested
// run under a runner inherits the parent's root and never deletes it.
ensureScratchSession();

export const REPO_ROOT = resolve(import.meta.dir, "../../..");
const PLUGIN_ROOT = resolve(REPO_ROOT, "plugins/soleur");

/** Per-call wall-clock cap. A vendor CLI that hangs must not hold the CI job open. */
export const CLI_TIMEOUT_MS = 90_000;

export type Harness = "codex" | "devin" | "opencode";

/**
 * Scratch directories this process created, removed on the way out.
 *
 * `mkdtempSync` has no owner otherwise: a CI runner is thrown away so nothing shows there, but
 * the same script run locally (which is how the parsers get debugged) leaves a fresh `CODEX_HOME`
 * and a scratch git repo in `$TMPDIR` on every invocation. Registered rather than removed inline
 * because every arm below can return early, including the throwing ones.
 */
const SCRATCH: string[] = [];
function scratchDir(prefix: string): string {
  const d = mkdtempSync(join(tmpdir(), prefix));
  SCRATCH.push(d);
  return d;
}
function cleanupScratch(): void {
  for (const d of SCRATCH.splice(0)) {
    try {
      rmSync(d, { recursive: true, force: true });
    } catch {
      // Best effort: a leaked scratch dir must never change this gate's verdict.
    }
  }
}

export interface Verdict {
  missing: string[];
  extra: string[];
  badMultiplicity: string[];
  /** Which multiplicity mode the run exhibited, once inferred. */
  mode: "dedup" | "additive" | "single" | "indeterminate";
}

/**
 * The expectation, derived from the manifest's own `skills` roots.
 *
 * Keyed on the DIRECTORY BASENAME, never on frontmatter `name:`: a skill that loses
 * its `name:` must still appear in the expected set, so the CLI omitting it reads as
 * MISSING rather than as a shrunken expectation that quietly agrees.
 *
 * The value is the number of declared roots containing that name — its `k`. The
 * Codex `go`/`help`/`sync` duplication is therefore DERIVED from the manifest rather
 * than acked by hand, so the allowance expires on its own when #8236 deletes a root.
 */
export function expectedSkills(manifestPath: string, pluginRoot = PLUGIN_ROOT): Map<string, number> {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as { skills?: string[] };
  const roots = manifest.skills ?? [];
  if (roots.length === 0) throw new Error(`${manifestPath} declares no skills roots`);
  const counts = new Map<string, number>();
  for (const root of roots) {
    const dir = resolve(pluginRoot, root);
    // THROW, never `continue`. A typo'd or deleted root silently contributing
    // zero is the "shrunken expectation that quietly agrees" this function's
    // header refuses one level down (at the skill-NAME level): the manifest
    // declares the root, so its absence is a defect in the thing under test,
    // not a reason to expect less of it. Measured consequence of the old form:
    // `"skills": ["./skilz", …]` collapsed the expectation to the 3 shim stems,
    // all 3 were discovered, and the gate exited 0 on a 99-skill loss.
    if (!existsSync(dir)) {
      throw new Error(`${manifestPath}: declared skills root '${root}' does not exist at ${dir}`);
    }
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      if (!existsSync(join(dir, entry.name, "SKILL.md"))) continue;
      const name = `soleur:${entry.name}`;
      counts.set(name, (counts.get(name) ?? 0) + 1);
    }
  }
  // Roots that exist but hold no skill. Same argument as the throw above, one
  // level out: an empty expectation makes `verdict()` trivially clean and the
  // whole gate exits 0 having compared nothing against nothing.
  if (counts.size === 0) {
    throw new Error(`${manifestPath}: declared roots ${JSON.stringify(roots)} contain no SKILL.md`);
  }
  return counts;
}

/**
 * Canonicalise a path for comparison: symlinked scratch roots (`/var` → `/private/var`
 * on macOS, a linked worktree anywhere) make the server's reported `path` and this
 * process's `PLUGIN_ROOT` differ as STRINGS while denoting the same file.
 */
function canonical(p: string): string {
  try {
    return realpathSync(p);
  } catch {
    return resolve(p);
  }
}

/**
 * A path relative to the plugin root, with `/` separators, or `undefined` when it lies
 * outside. Returning `undefined` rather than a `../…` string is what EXCLUDES global
 * leakage: an operator's `~/.claude/skills/plan/SKILL.md` and the harness's own
 * `/builtin/opencode.md` both carry ids this plugin also uses, so counting anything the
 * declaration did not place under the plugin root would report them as registrations.
 */
function pluginRelative(pluginRoot: string, p: string): string | undefined {
  const rel = relative(canonical(pluginRoot), canonical(p));
  if (rel === "" || rel.startsWith("..") || isAbsolute(rel)) return undefined;
  return rel.split(sep).join("/");
}

/**
 * The expectation for the OpenCode arm, derived from the generated fragment's own
 * `skills` roots (measurement §11.0). Keyed on the plugin-relative `path`, because the
 * server's ids are bare basenames that collide across roots (§2.3).
 *
 * The `__SOLEUR_PLUGIN_ROOT__` sentinel is resolved here with the same substitution the
 * installer performs (D6): the committed fragment is machine-independent, and the arm
 * must judge the bytes a user would actually install.
 */
export function expectedOpenCodeSkillFiles(manifestPath: string, pluginRoot = PLUGIN_ROOT): Map<string, number> {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as { skills?: string[] };
  const roots = manifest.skills ?? [];
  if (roots.length === 0) throw new Error(`${manifestPath} declares no skills roots`);
  const counts = new Map<string, number>();
  for (const root of roots) {
    const dir = resolve(pluginRoot, root.split(PLUGIN_ROOT_TOKEN).join(pluginRoot));
    // THROW, never `continue` — the same argument as `expectedSkills()` above: a
    // declared root the installer would have written is an assertion, and a typo'd
    // one silently shrinking the expectation is how a 103-skill loss reads green.
    if (!existsSync(dir)) {
      throw new Error(`${manifestPath}: declared skills root '${root}' does not exist at ${dir}`);
    }
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const file = join(dir, entry.name, "SKILL.md");
      if (!existsSync(file)) continue;
      const rel = pluginRelative(pluginRoot, file);
      if (rel) counts.set(rel, 1);
    }
  }
  if (counts.size === 0) {
    throw new Error(`${manifestPath}: declared roots ${JSON.stringify(roots)} contain no SKILL.md`);
  }
  return counts;
}

/**
 * `GET /api/skill` returns `{location, data: [{id, name, description, path, content}]}`
 * (measurement §11.4), one record per registration — and `content` is the skill's full
 * text, so the payload runs to megabytes and must be read from a FILE, never a pipe.
 *
 * Keyed on `path`, not `id`: ids are bare basenames with no namespace, so the same id
 * is carried by this plugin's skill and by any operator-level copy. Counting is by
 * relative path, so a duplicate registration of the SAME file still shows up.
 *
 * Unreadable input yields an EMPTY MAP rather than a throw: whether the bytes were a
 * listing at all is `isStructurallyParseable()`'s question, and folding the two together
 * is what would let a dead server grade as a set mismatch.
 */
export function parseOpenCodeSkillList(raw: string, pluginRoot = PLUGIN_ROOT): Map<string, number> {
  const counts = new Map<string, number>();
  let payload: { data?: unknown };
  try {
    payload = JSON.parse(raw) as { data?: unknown };
  } catch {
    return counts;
  }
  if (!Array.isArray(payload?.data)) return counts;
  for (const entry of payload.data as Array<{ path?: unknown }>) {
    if (typeof entry?.path !== "string") continue;
    const rel = pluginRelative(pluginRoot, entry.path);
    if (!rel) continue;
    counts.set(rel, (counts.get(rel) ?? 0) + 1);
  }
  return counts;
}

/**
 * `codex debug prompt-input` emits the skills list inside an ESCAPED JSON STRING —
 * `\n`, not real newlines — so a line-anchored regex over the raw bytes returns zero.
 * Decoding first is the whole reason this is a function rather than a grep.
 */
export function parseCodexPromptInput(raw: string): Map<string, number> {
  let text = raw;
  const decoded = raw.replace(/\\n/g, "\n");
  if (decoded !== raw) text = decoded;
  const counts = new Map<string, number>();
  for (const m of text.matchAll(/^\s*-\s+(soleur:[a-z0-9-]+):/gm)) {
    counts.set(m[1], (counts.get(m[1]) ?? 0) + 1);
  }
  return counts;
}

/** `devin skills list` prints `  /soleur:<name>  …` one per registration. */
export function parseDevinSkillsList(raw: string): Map<string, number> {
  const counts = new Map<string, number>();
  for (const m of raw.matchAll(/^\s+\/(soleur:[a-z0-9-]+)(?:\s|$)/gm)) {
    counts.set(m[1], (counts.get(m[1]) ?? 0) + 1);
  }
  return counts;
}

/** Did the listing carry the structure a parse depends on, at all? */
export function isStructurallyParseable(harness: Harness, raw: string, discovered: Map<string, number>): boolean {
  if (discovered.size > 0) return true;
  if (harness === "codex") return /<skills_instructions>/.test(raw);
  if (harness === "opencode") {
    // The marker is the payload's `data` array. An empty one is a READING, not an
    // outage: a correct install answers `{location, data: []}` before a session
    // exists (measurement §11.1), and a total loss must grade exit 1 naming the
    // missing skills rather than `unparseable-output` (exit 3, UNRESOLVED) — the
    // same AP-021 inversion the Devin arm below refuses.
    try {
      const payload = JSON.parse(raw) as { data?: unknown };
      return Array.isArray(payload?.data);
    } catch {
      return false;
    }
  }
  // Devin has a structural marker too, and using it is what keeps the two arms
  // honest. Without it, "the CLI answered and listed NOTHING" — a total loss of
  // all 102 registrations, the worst regression this gate exists to catch —
  // graded `unparseable-output` (exit 3, UNRESOLVED) on Devin while the
  // identical Codex regression graded exit 1 with the names listed. That is the
  // AP-021 inversion the exit taxonomy below forbids in the other direction,
  // and it would have been the triage signal for #8574's soak.
  return /^\s*Available skills:/m.test(raw);
}

/**
 * ONE MODE PER HARNESS RUN.
 *
 * A name found in k declared roots may be listed once (the harness dedups) or k times
 * (it is additive) — but not a MIXTURE. Checking "1 or k" per name independently would
 * pass a listing with `go` twice and `help` once, which is exactly the loader ambiguity
 * ADR-224 decision 5 exists to detect. So the mode is INFERRED across every multi-root
 * name, and a mixture goes to badMultiplicity.
 *
 * Measured 2026-09-23: Codex 0.156.1 is additive (go/help/sync twice, 105 entries for
 * 102 names); Devin 3000.11.1 dedups (102 entries, each once).
 */
export function verdict(expected: Map<string, number>, discovered: Map<string, number>): Verdict {
  const missing: string[] = [];
  const extra: string[] = [];
  const badMultiplicity: string[] = [];

  for (const name of discovered.keys()) if (!expected.has(name)) extra.push(name);

  const multiRoot = [...expected.entries()].filter(([, k]) => k >= 2);
  let mode: Verdict["mode"] = "indeterminate";
  if (multiRoot.length === 0) {
    // No name is declared by more than one root, so there is no cross-root
    // multiplicity to infer and `indeterminate` would read as a defect. This is
    // the OpenCode shape: one canonical tree, no shim roots.
    mode = "single";
  } else {
    // `n === 0` is MISSING, and is reported as such below. Feeding it into the
    // mode inference too makes an ordinary omission arrive as "3 missing, 0
    // extra, 3 bad-multiplicity" — a bogus multiplicity story layered over the
    // real cause, which is the operator's first read of a red run.
    const observed = multiRoot
      .map(([name, k]) => ({ name, k, n: discovered.get(name) ?? 0 }))
      .filter((o) => o.n > 0);
    const allOne = observed.every((o) => o.n === 1);
    const allK = observed.every((o) => o.n === o.k);
    if (allOne) mode = "dedup";
    else if (allK) mode = "additive";
    else {
      mode = "indeterminate";
      for (const o of observed) {
        if (o.n !== 1 && o.n !== o.k) {
          badMultiplicity.push(`${o.name}: listed ${o.n} times, expected 1 (dedup) or ${o.k} (additive)`);
        }
      }
      if (badMultiplicity.length === 0) {
        badMultiplicity.push(
          `mixed multiplicity mode across multi-root names: ${observed
            .map((o) => `${o.name}=${o.n}/k${o.k}`)
            .join(", ")} — a harness must dedup consistently or be additive consistently`,
        );
      }
    }
  }

  for (const [name, k] of expected) {
    const n = discovered.get(name) ?? 0;
    if (n === 0) {
      missing.push(name);
      continue;
    }
    const allowed = mode === "dedup" ? [1] : mode === "additive" ? [k] : [1, k];
    if (!allowed.includes(n)) {
      badMultiplicity.push(`${name}: listed ${n} times, expected ${allowed.join(" or ")}`);
    }
  }

  return { missing, extra, badMultiplicity, mode };
}

export interface ExitInput {
  cliPresent: boolean;
  installFailed?: boolean;
  /** The probe command itself failed (non-zero, or killed at CLI_TIMEOUT_MS). */
  probeFailed?: boolean;
  version?: string;
  pin?: string;
  parseable: boolean;
  verdict?: Verdict;
}

export interface ExitResult {
  code: 0 | 1 | 3;
  reason: string;
}

/**
 * The exit decision, PURE and exported — the two rows carrying the whole "never exit 0
 * on an empty or unparsed listing" contract are decided in the CLI-driving path
 * otherwise, where no unit test can reach them.
 *
 * ADR-177 taxonomy. Exit 3 is UNRESOLVED and is reserved for a listing that is
 * STRUCTURALLY unreadable — no `<skills_instructions>` marker, or zero `soleur:` lines.
 * A listing that PARSED but is missing names is a real partial loss and exits 1 naming
 * them: mapping "discovered < 100" to exit 3 would report a 60-skill regression as
 * "could not check", which names a cause the gate did not measure (AP-021).
 */
export function resolveExit(input: ExitInput): ExitResult {
  if (!input.cliPresent) return { code: 3, reason: "cli-missing" };
  // "Could not read the version" is NOT "the version is fine". `cliVersion()`
  // returns undefined whenever `--version` exits non-zero or prints no semver,
  // and the old `pin && version && …` form skipped the comparison entirely in
  // exactly that case — so `--pin` failed OPEN on an unreadable binary, which
  // is the one mapping the ADR-177 taxonomy exists to forbid.
  if (input.pin && !input.version) return { code: 3, reason: "version-unknown" };
  if (input.pin && input.version && input.version !== input.pin) {
    return { code: 3, reason: `version-mismatch:${input.version}!=${input.pin}` };
  }
  if (input.installFailed) return { code: 3, reason: "install-failed" };
  // A probe that died (timeout, crash, non-zero) yields PARTIAL output, and a
  // partial listing parses. Without this, a CLI that printed 40 of 102 names
  // and then hung reported "set-mismatch: 62 missing" — an authoritative claim
  // of a regression that did not happen, from a run that could not measure one.
  if (input.probeFailed) return { code: 3, reason: "probe-failed" };
  if (!input.parseable) return { code: 3, reason: "unparseable-output" };
  const v = input.verdict;
  if (!v) return { code: 3, reason: "unparseable-output" };
  const problems = v.missing.length + v.extra.length + v.badMultiplicity.length;
  if (problems > 0) {
    return {
      code: 1,
      reason: `set-mismatch: ${v.missing.length} missing, ${v.extra.length} extra, ${v.badMultiplicity.length} bad-multiplicity`,
    };
  }
  return { code: 0, reason: `ok (mode=${v.mode})` };
}

/**
 * Neutralise text before it reaches a GitHub Actions log.
 *
 * WHY THIS IS NOT PARANOIA. GitHub parses a WORKFLOW COMMAND from any log line whose first
 * non-whitespace characters are `::` — `::error::`, `::add-mask::`, `::set-output` and, worst,
 * `::stop-commands::`. Everything this script prints on a red path is derived from two places a
 * pull request can write to:
 *
 *   - the vendor CLI's raw output, which ECHOES skill names, and
 *   - `verdict()`'s `missing` / `extra` / `badMultiplicity` arrays, whose members are built from
 *     `readdirSync` over `plugins/soleur/skills/` — i.e. from DIRECTORY NAMES in the checkout.
 *
 * A directory name may contain `:`, and on a fork PR the checkout is the fork's. So a fork could
 * add `skills/<name-containing-a-newline-and-::error::…>/SKILL.md` and have this job emit
 * annotations, mask arbitrary strings out of the log, or issue `::stop-commands::` and silence
 * every real annotation after it. The job is advisory and cannot gate a merge, but a log that can
 * be authored by the thing under test is not evidence.
 *
 * TWO LAYERS, because either alone has a hole:
 *
 *   1. Per-line neutralisation. A line that would start a command gets one leading space, which
 *      GitHub does NOT trim back into a command. Applied after normalising `\r`, since a lone CR
 *      also begins a new line on a terminal.
 *   2. A `::stop-commands::<token>` fence around the whole block, with a 128-bit random token.
 *      Layer 1 is what makes the fence safe: without it, untrusted text containing the resume
 *      token would end the fence early, and with it no untrusted line can be a command at all.
 *
 * C0 control characters other than `\n` and `\t` are dropped outright — they carry no
 * information here and are how a name hides what it really is in a terminal.
 */
export function sanitizeForLog(text: string): string {
  return text
    .replace(/\r\n?/g, "\n")
    // eslint-disable-next-line no-control-regex -- the C0 set is the subject, not a typo (cq-regex-unicode-separators-escape-only)
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .split("\n")
    .map((line) => (/^\s*::/.test(line) ? ` ${line}` : line))
    .join("\n");
}

/** Write untrusted text to stderr inside a random-token workflow-command fence. */
function writeUntrusted(text: string): void {
  const token = randomBytes(16).toString("hex");
  process.stderr.write(`::stop-commands::${token}\n`);
  process.stderr.write(sanitizeForLog(text));
  if (!text.endsWith("\n")) process.stderr.write("\n");
  process.stderr.write(`::${token}::\n`);
}

function run(cmd: string, args: string[], env: Record<string, string>, cwd = REPO_ROOT): { ok: boolean; out: string } {
  try {
    const out = execFileSync(cmd, args, {
      cwd,
      env,
      encoding: "utf8",
      timeout: CLI_TIMEOUT_MS,
      maxBuffer: 32 * 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
    });
    return { ok: true, out };
  } catch (e) {
    const err = e as { stdout?: string; stderr?: string; message?: string };
    return { ok: false, out: `${err.stdout ?? ""}\n${err.stderr ?? ""}\n${err.message ?? ""}` };
  }
}

function have(bin: string): boolean {
  try {
    execFileSync("command", ["-v", bin], { shell: "/bin/bash", stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function cliVersion(bin: string, env: Record<string, string> = { PATH: process.env.PATH ?? "" }): string | undefined {
  const r = run(bin, ["--version"], env);
  if (!r.ok) return undefined;
  const m = r.out.match(/\d+\.\d+\.\d+/);
  return m ? m[0] : undefined;
}

function driveCodex(pin?: string): { input: ExitInput; raw: string } {
  if (!have("codex")) return { input: { cliPresent: false, parseable: false }, raw: "" };
  const home = scratchDir("harness-discovery-codex-");
  const env = { PATH: process.env.PATH ?? "", HOME: home, CODEX_HOME: home };
  const version = cliVersion("codex");
  if (pin && version && version !== pin) {
    return { input: { cliPresent: true, parseable: false, version, pin }, raw: "" };
  }
  const add = run("codex", ["plugin", "marketplace", "add", REPO_ROOT], env);
  const install = run("codex", ["plugin", "add", "soleur@soleur"], env);
  if (!add.ok || !install.ok) {
    return { input: { cliPresent: true, installFailed: true, parseable: false, version, pin }, raw: `${add.out}\n${install.out}` };
  }
  const probe = run("codex", ["debug", "prompt-input"], env);
  const discovered = parseCodexPromptInput(probe.out);
  const parseable = isStructurallyParseable("codex", probe.out, discovered);
  const expected = expectedSkills(resolve(PLUGIN_ROOT, ".codex-plugin/plugin.json"));
  const usable = probe.ok && parseable;
  return {
    input: {
      cliPresent: true,
      probeFailed: !probe.ok,
      parseable,
      version,
      pin,
      verdict: usable ? verdict(expected, discovered) : undefined,
    },
    raw: probe.out,
  };
}

function driveDevin(pin?: string): { input: ExitInput; raw: string } {
  if (!have("devin")) return { input: { cliPresent: false, parseable: false }, raw: "" };
  const home = scratchDir("harness-discovery-devin-");
  const scratch = scratchDir("harness-discovery-devin-repo-");
  const env = {
    PATH: process.env.PATH ?? "",
    HOME: home,
    XDG_CONFIG_HOME: join(home, "config"),
    XDG_DATA_HOME: join(home, "data"),
  };
  const version = cliVersion("devin");
  if (pin && version && version !== pin) {
    return { input: { cliPresent: true, parseable: false, version, pin }, raw: "" };
  }
  const init = run("git", ["init", "-q", scratch], env, scratch);
  if (!init.ok) {
    // Otherwise the scratch dir is not a repo, Devin reads no config, and the
    // empty listing grades `unparseable-output` — naming a cause we did not
    // measure when the real one is right here.
    return { input: { cliPresent: true, installFailed: true, parseable: false, version, pin }, raw: init.out };
  }
  mkdirSync(join(scratch, ".devin"), { recursive: true });
  writeFileSync(
    join(scratch, ".devin/config.json"),
    // The repo-scoped local source: `devin plugins install` requires auth, this does not.
    JSON.stringify({ requiredPlugins: [{ source: "local", path: PLUGIN_ROOT }] }, null, 2),
  );
  const probe = run("devin", ["skills", "list"], env, scratch);
  const discovered = parseDevinSkillsList(probe.out);
  const parseable = isStructurallyParseable("devin", probe.out, discovered);
  const expected = expectedSkills(resolve(PLUGIN_ROOT, ".devin-plugin/plugin.json"));
  const usable = probe.ok && parseable;
  return {
    input: {
      cliPresent: true,
      probeFailed: !probe.ok,
      parseable,
      version,
      pin,
      verdict: usable ? verdict(expected, discovered) : undefined,
    },
    raw: probe.out,
  };
}

/** Synchronous sleep, so the server-poll loop keeps this file's all-sync shape. */
function sleepMs(ms: number): void {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

/** How long a spawned `opencode serve` has to announce its port and password. */
export const SERVER_BOOT_TIMEOUT_MS = 60_000;

/**
 * How long the location has to finish SCANNING its skill roots before the reading is
 * taken. Measured §11.6: the scan is asynchronous and the first read is always empty;
 * a hermetic install settles to all 103 canonical skills in **~2 s**, and the poll exits
 * the moment the expected population is reached. The cap is therefore a ceiling on a
 * failure, not a per-run cost.
 */
export const SKILL_SETTLE_TIMEOUT_MS = 120_000;

/**
 * The absolute path to a binary.
 *
 * `opencode` on PATH is almost always a version-manager shim, and a shim resolves its
 * install through `$HOME` — which this arm redirects for hermeticity, and which makes the
 * shim try to REINSTALL (measured: the run hangs, then dies with `Disk quota exceeded`).
 * `readlink -f` follows the shim chain to the real launcher, which needs no HOME at all.
 */
export function resolveBin(bin: string): string | undefined {
  const r = run(
    "bash",
    ["-c", 'p=$(command -v "$1") || exit 1; r=$(readlink -f "$p" 2>/dev/null) || r="$p"; [ -n "$r" ] || r="$p"; printf "%s" "$r"', "bash", bin],
    { PATH: process.env.PATH ?? "" },
  );
  const out = r.out.trim();
  return r.ok && out !== "" ? out : undefined;
}

/**
 * Run a command with its stdout going straight to a FILE.
 *
 * `run()`'s pipe is NOT safe for this payload. `execFileSync` silently truncates a large
 * stdout — observed at ~800 kB and ~946 kB, different each run — and still reports
 * SUCCESS, so the JSON arrives with an unclosed string and `JSON.parse` fails, which
 * grades a correct install UNRESOLVED (measurement §11.6). The same call through a file
 * descriptor yields all 3,069,017 bytes, valid. Hence the file, and hence not `run()`.
 */
function runToFile(
  cmd: string,
  args: string[],
  env: Record<string, string>,
  cwd: string,
  outPath: string,
): { ok: boolean; err: string } {
  const fd = openSync(outPath, "w");
  try {
    const r = spawnSync(cmd, args, {
      cwd,
      env,
      stdio: ["ignore", fd, "pipe"],
      timeout: CLI_TIMEOUT_MS,
      encoding: "utf8",
    });
    return { ok: r.status === 0, err: r.stderr ?? "" };
  } finally {
    closeSync(fd);
  }
}

/**
 * Drive a real `opencode serve` and read `GET /api/skill` from it.
 *
 * Every step is forced by the measured recipe (measurement §11.0/§11.6):
 *
 *   - `serve` is a LONG-RUNNING process, so this is the one arm that is not a single
 *     `execFileSync`. It is spawned detached into a log file and polled; the log is also
 *     where the port and password come from.
 *   - `--port 0` lets the OS pick, and the banner names the chosen port, so two CI jobs
 *     cannot race for a fixed one.
 *   - Every `/api/*` route is `UnauthorizedError` without that password, and `opencode
 *     api` calls `GET /api/info` first.
 *   - The listing is built by an ASYNCHRONOUS scan of the location's skill roots, so the
 *     first read is always empty and a single read reports a correct install as a total
 *     loss. The poll below is the whole reason this is not a single call.
 *   - The listing is read from a FILE, never from `run()`'s pipe — see `runToFile`.
 *
 * Deliberately NOT part of the recipe: `POST /api/session` (measured unnecessary — an
 * idle boot settles) and `POST /api/location/reload` (measured to CLEAR the listing
 * before rebuilding it, which would make the poll race its own reset).
 */
/**
 * Is a child pid still alive? The `error`/`exit` events cannot fire while the boot loop blocks
 * the thread, so liveness is asked synchronously instead of awaited: `kill(pid, 0)` performs no
 * signal and throws `ESRCH` for a process that is gone.
 */
function processAlive(pid: number | undefined): boolean {
  if (pid === undefined) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function openCodeSkillProbe(
  bin: string,
  project: string,
  env: Record<string, string>,
  expected: Map<string, number>,
): { ok: boolean; raw: string } {
  const logPath = join(project, "serve.log");
  const fd = openSync(logPath, "w");
  const child = spawn(bin, ["serve", "--port", "0", "--hostname", "127.0.0.1"], {
    cwd: project,
    env,
    stdio: ["ignore", fd, fd],
    detached: true,
  });
  let spawnError: Error | undefined;
  child.on("error", (e: Error) => {
    spawnError = e;
  });
  child.unref();
  closeSync(fd);

  const readLog = (): string => {
    try {
      return readFileSync(logPath, "utf8");
    } catch {
      return "";
    }
  };

  try {
    let url: string | undefined;
    let password: string | undefined;
    const bootDeadline = Date.now() + SERVER_BOOT_TIMEOUT_MS;
    while (Date.now() < bootDeadline && !(url && password)) {
      const text = readLog();
      url ??= text.match(/server listening on (http:\/\/[^\s]+)/)?.[1];
      password ??= text.match(/server password (\S+)/)?.[1];
      if (url && password) break;
      sleepMs(250);
    }
    if (!url || !password) {
      // `spawnError` is set by the child's `error` event, and no event handler can run while
      // this loop blocks the thread in `Atomics.wait` (`sleepMs`) — so the check is HERE, after
      // the loop, where it is reachable. A child that never spawned (no pid) or already
      // exited is a DEAD PROBE (UNRESOLVED), not a slow boot: grading it as "did not announce
      // itself" would report a correct install as a set mismatch.
      if (spawnError !== undefined || !processAlive(child.pid)) {
        const why = spawnError?.message ?? `process ${String(child.pid)} is not running`;
        return { ok: false, raw: `server failed to start: ${why}\n${readLog().slice(0, 4096)}` };
      }
      return {
        ok: false,
        raw: `server did not announce itself within ${SERVER_BOOT_TIMEOUT_MS}ms:\n${readLog().slice(0, 4096)}`,
      };
    }

    const apiEnv = { ...env, OPENCODE_PASSWORD: password };
    const outPath = join(project, "skills.json");
    const deadline = Date.now() + SKILL_SETTLE_TIMEOUT_MS;
    let last = "";
    let failures = 0;
    for (;;) {
      const listing = runToFile(bin, ["api", "--server", url, "GET", "/api/skill"], apiEnv, project, outPath);
      let text = "";
      try {
        text = readFileSync(outPath, "utf8");
      } catch {
        text = "";
      }
      if (listing.ok) {
        failures = 0;
        last = text;
        if (parseOpenCodeSkillList(last).size >= expected.size) break;
      } else {
        last = `listing failed (status != 0): ${listing.err}\n--- partial payload ---\n${text.slice(0, 2048)}`;
        // A transport that keeps failing is a dead probe, not an empty listing: five
        // consecutive failures end the arm as UNRESOLVED rather than as a set mismatch.
        if (++failures >= 5) return { ok: false, raw: last };
      }
      if (Date.now() >= deadline) break;
      sleepMs(1000);
    }
    return { ok: true, raw: last };
  } finally {
    // Detached, so the child leads its own process group: signalling the group also
    // reaps anything the server forked, and leaves no listener behind on a red run.
    if (child.pid) {
      try {
        process.kill(-child.pid, "SIGTERM");
      } catch {
        try {
          child.kill("SIGTERM");
        } catch {
          // Already gone — nothing to clean up.
        }
      }
    }
  }
}

function driveOpenCode(pin?: string): { input: ExitInput; raw: string } {
  if (!have("opencode")) return { input: { cliPresent: false, parseable: false }, raw: "" };
  const home = scratchDir("harness-discovery-opencode-");
  const project = scratchDir("harness-discovery-opencode-repo-");
  const configDir = join(home, ".config", "opencode");
  // A fully hermetic HOME + XDG set: the operator's own config, and the `~/.claude/skills`
  // / `~/.agents/skills` trees this harness also reads, are then out of reach — measured
  // §11.4 to be the only control needed for the reading to be this plugin's 103 skills
  // plus the harness's own 2 built-ins, with no "other" bucket at all. The absolute
  // binary (`resolveBin`) is what makes a hermetic HOME safe: a PATH shim resolves its
  // install THROUGH `$HOME` and reinstalls into the scratch dir without one.
  const env = gitCleanEnv({
    HOME: home,
    PATH: process.env.PATH ?? "",
    XDG_CONFIG_HOME: join(home, ".config"),
    XDG_DATA_HOME: join(home, ".local", "share"),
    XDG_STATE_HOME: join(home, ".local", "state"),
  });
  const bin = resolveBin("opencode") ?? "opencode";
  const version = cliVersion(bin, env);
  if (pin && version && version !== pin) {
    return { input: { cliPresent: true, parseable: false, version, pin }, raw: "" };
  }
  const init = run("git", ["init", "-q", project], env, project);
  if (!init.ok) {
    // `opencode serve` opens a project, and the scratch dir must be a repo for that to
    // mean anything. A failure here is install-shaped, not a parse one.
    return { input: { cliPresent: true, installFailed: true, parseable: false, version, pin }, raw: init.out };
  }
  // The user-facing installer, not a hand-rolled copy of what it does: the arm must
  // judge the bytes an operator actually gets, sentinel and all.
  const install = run(
    process.execPath,
    [resolve(PLUGIN_ROOT, "scripts/install-opencode-adapter.ts"), "--target", configDir],
    env,
  );
  if (!install.ok) {
    return { input: { cliPresent: true, installFailed: true, parseable: false, version, pin }, raw: install.out };
  }
  const expected = expectedOpenCodeSkillFiles(resolve(PLUGIN_ROOT, "opencode/opencode.json"));
  const probe = openCodeSkillProbe(bin, project, env, expected);
  const discovered = parseOpenCodeSkillList(probe.raw);
  const parseable = isStructurallyParseable("opencode", probe.raw, discovered);
  const usable = probe.ok && parseable;
  return {
    input: {
      cliPresent: true,
      probeFailed: !probe.ok,
      parseable,
      version,
      pin,
      verdict: usable ? verdict(expected, discovered) : undefined,
    },
    raw: probe.raw,
  };
}

const USAGE = "usage: harness-discovery-smoke.ts --harness codex|devin|opencode [--pin <version>]\n";

/**
 * Argument parsing, PURE and exported so the fail-open cases below are reachable from a unit test.
 *
 * Both of them were live, and both fail in the direction that reports a green:
 *
 *   - `argv[argv.indexOf("--harness") + 1]` reads `argv[0]` when the flag is ABSENT, because
 *     `indexOf` returns -1 and -1 + 1 is 0. `harness-discovery-smoke.ts codex` therefore ran the
 *     Codex arm with no flag at all, and any other bare first argument silently selected nothing.
 *   - `--pin` with no value yields `undefined`, which is indistinguishable from "no pin given", so
 *     a typo'd flag SKIPS the version comparison entirely. A pin that silently does not apply is
 *     worse than no pin: the job still prints its reassuring pin in the log.
 *
 * A flag-shaped value (`--pin --harness`) is likewise a mistake, never a version.
 */
export function parseArgs(argv: readonly string[]): { harness: Harness; pin?: string } | { error: string } {
  const hIdx = argv.indexOf("--harness");
  if (hIdx === -1) return { error: "missing --harness" };
  const harness = argv[hIdx + 1];
  if (harness !== "codex" && harness !== "devin" && harness !== "opencode") {
    return { error: `--harness must be codex, devin or opencode, got ${JSON.stringify(harness ?? null)}` };
  }
  const pIdx = argv.indexOf("--pin");
  if (pIdx === -1) return { harness };
  const pin = argv[pIdx + 1];
  if (pin === undefined || pin.startsWith("--")) {
    return { error: `--pin requires a version, got ${JSON.stringify(pin ?? null)}` };
  }
  return { harness, pin };
}

function main(): void {
  const parsed = parseArgs(process.argv.slice(2));
  if ("error" in parsed) {
    process.stderr.write(`harness-discovery: ${parsed.error}\n${USAGE}`);
    process.exit(2);
  }
  const { harness, pin } = parsed;

  let result: ExitResult;
  let input: ExitInput;
  let raw: string;
  try {
    const arms = { codex: driveCodex, devin: driveDevin, opencode: driveOpenCode } as const;
    ({ input, raw } = arms[harness](pin));
    result = resolveExit(input);
  } finally {
    // Before the writes below, and before any exit: `process.exit()` runs no `finally`.
    cleanupScratch();
  }

  if (input.verdict) {
    // Untrusted: `missing`/`extra` members come from directory names in the checkout.
    writeUntrusted(JSON.stringify({ harness, ...input.verdict }, null, 2));
  }
  // Trusted: every field here is produced by this file.
  process.stderr.write(`harness-discovery[${harness}]: exit=${result.code} reason=${result.reason}\n`);
  if (result.code !== 0) {
    // The first 4 KB of raw vendor output, so a red job is diagnosable from the log
    // itself and needs no artifact upload. Untrusted — see `sanitizeForLog`.
    process.stderr.write(`--- raw ${harness} output (first 4 KB) ---\n`);
    writeUntrusted(raw.slice(0, 4096));
  }
  process.exit(result.code);
}

if (import.meta.main) main();
