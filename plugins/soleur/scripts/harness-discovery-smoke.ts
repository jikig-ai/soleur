#!/usr/bin/env bun
/**
 * harness-discovery-smoke — prove Codex and Devin DISCOVER the skill set their
 * manifests declare, by installing the plugin hermetically from this checkout and
 * asking the vendor CLI what it registered (ADR-240; the unfiled item 6 of #8390's
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
 * The pure functions below are exported and unit-tested offline against synthesized
 * fixtures (`plugins/soleur/test/harness-discovery-smoke.test.ts`); the CLI-driving
 * half is the same code under a real binary.
 *
 * `scripts/codex-plugin-smoke.mjs` is deliberately UNTOUCHED: it is the operator-local
 * check of an already-installed plugin and its hooks, and needs `~/.codex` state this
 * gate refuses to depend on.
 */

import { execFileSync } from "child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join, resolve } from "path";

export const REPO_ROOT = resolve(import.meta.dir, "../../..");
const PLUGIN_ROOT = resolve(REPO_ROOT, "plugins/soleur");

/** Per-call wall-clock cap. A vendor CLI that hangs must not hold the CI job open. */
export const CLI_TIMEOUT_MS = 90_000;

export type Harness = "codex" | "devin";

export interface Verdict {
  missing: string[];
  extra: string[];
  badMultiplicity: string[];
  /** Which multiplicity mode the run exhibited, once inferred. */
  mode: "dedup" | "additive" | "indeterminate";
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
    if (!existsSync(dir)) continue;
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      if (!existsSync(join(dir, entry.name, "SKILL.md"))) continue;
      const name = `soleur:${entry.name}`;
      counts.set(name, (counts.get(name) ?? 0) + 1);
    }
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
  return false;
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
  if (multiRoot.length > 0) {
    const observed = multiRoot.map(([name, k]) => ({ name, k, n: discovered.get(name) ?? 0 }));
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
  if (input.pin && input.version && input.version !== input.pin) {
    return { code: 3, reason: `version-mismatch:${input.version}!=${input.pin}` };
  }
  if (input.installFailed) return { code: 3, reason: "install-failed" };
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

function cliVersion(bin: string): string | undefined {
  const r = run(bin, ["--version"], { PATH: process.env.PATH ?? "" });
  if (!r.ok) return undefined;
  const m = r.out.match(/\d+\.\d+\.\d+/);
  return m ? m[0] : undefined;
}

function driveCodex(pin?: string): { input: ExitInput; raw: string } {
  if (!have("codex")) return { input: { cliPresent: false, parseable: false }, raw: "" };
  const home = mkdtempSync(join(tmpdir(), "harness-discovery-codex-"));
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
  return {
    input: { cliPresent: true, parseable, version, pin, verdict: parseable ? verdict(expected, discovered) : undefined },
    raw: probe.out,
  };
}

function driveDevin(pin?: string): { input: ExitInput; raw: string } {
  if (!have("devin")) return { input: { cliPresent: false, parseable: false }, raw: "" };
  const home = mkdtempSync(join(tmpdir(), "harness-discovery-devin-"));
  const scratch = mkdtempSync(join(tmpdir(), "harness-discovery-devin-repo-"));
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
  run("git", ["init", "-q", scratch], env, scratch);
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
  return {
    input: { cliPresent: true, parseable, version, pin, verdict: parseable ? verdict(expected, discovered) : undefined },
    raw: probe.out,
  };
}

function main(): void {
  const argv = process.argv.slice(2);
  const harness = (argv[argv.indexOf("--harness") + 1] ?? "") as Harness;
  const pinIdx = argv.indexOf("--pin");
  const pin = pinIdx === -1 ? undefined : argv[pinIdx + 1];
  if (harness !== "codex" && harness !== "devin") {
    process.stderr.write("usage: harness-discovery-smoke.ts --harness codex|devin [--pin <version>]\n");
    process.exit(2);
  }

  const { input, raw } = harness === "codex" ? driveCodex(pin) : driveDevin(pin);
  const result = resolveExit(input);

  if (input.verdict) {
    process.stderr.write(`${JSON.stringify({ harness, ...input.verdict }, null, 2)}\n`);
  }
  process.stderr.write(`harness-discovery[${harness}]: exit=${result.code} reason=${result.reason}\n`);
  if (result.code !== 0) {
    // The first 4 KB of raw vendor output, so a red job is diagnosable from the log
    // itself and needs no artifact upload.
    process.stderr.write(`--- raw ${harness} output (first 4 KB) ---\n${raw.slice(0, 4096)}\n`);
  }
  process.exit(result.code);
}

if (import.meta.main) main();
