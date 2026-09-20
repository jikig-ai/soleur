import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { join, resolve } from "path";
import { tmpdir } from "os";
import { gitFixtureEnv } from "./lib/git-fixture-env";

// devin-cloud-mode.test.ts — Guard Contract 1 for Soleur Cloud Mode:
//   "No Devin session is classified `local` without positive this-host,
//    plugin-sourced local-session evidence."
// The classifier under test is plugins/soleur/scripts/cloud-detect.sh, the ONE
// classifier (TR1); SKILL.mds never re-implement detection.

const SCRIPT = join(import.meta.dir, "../scripts/cloud-detect.sh");
const HOOK = join(import.meta.dir, "../hooks/devin-session-start.sh");
const PLUGIN_ROOT = resolve(import.meta.dir, "..");
const SENTINEL_REL = join(".devin", "soleur-local-session");
const DEVIN_ENV_VARS = ["DEVIN", "DEVIN_HOME", "DEVIN_PROJECT_DIR", "DEVIN_PLUGIN_ROOT", "DEVIN_DIR"];

function createTempGitRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), "devin-cloud-mode-"));
  Bun.spawnSync(["git", "init", dir], {
    env: gitFixtureEnv(dir),
    stdout: "ignore",
    stderr: "ignore",
  });
  return dir;
}

// The host string the classifier compares against is resolved through the same
// `hostname` invocation the script uses — not os.hostname() — so a hostname(1)
// quirk cannot desync fixture and implementation.
function currentHost(): string {
  // env bound (fixture-env-adoption guard) but minimal: hostname needs PATH only.
  return Bun.spawnSync(["hostname"], { env: { PATH: process.env.PATH ?? "" } })
    .stdout.toString().trim();
}

// Child env for the classifier/hook subprocesses: the fixture git env with ALL
// DEVIN* markers removed, then `DEVIN=1` added back for Devin-session arms.
// process.env is never mutated — the child env is explicit.
function childEnv(cwd: string, devin = true): Record<string, string> {
  const env = gitFixtureEnv(cwd) as Record<string, string>;
  for (const key of DEVIN_ENV_VARS) delete env[key];
  if (devin) env.DEVIN = "1";
  return env;
}

function runDetect(
  cwd: string,
  opts: { devin?: boolean; args?: string[]; env?: Record<string, string> } = {},
): { exitCode: number; stdout: string; stderr: string } {
  const env = childEnv(cwd, opts.devin ?? true);
  Object.assign(env, opts.env ?? {});
  const result = Bun.spawnSync(["bash", SCRIPT, ...(opts.args ?? [])], {
    cwd,
    env,
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    exitCode: result.exitCode,
    stdout: result.stdout.toString().trim(),
    stderr: result.stderr.toString(),
  };
}

function writeSentinel(repo: string, body: string | Record<string, string>): void {
  mkdirSync(join(repo, ".devin"), { recursive: true });
  writeFileSync(join(repo, SENTINEL_REL), typeof body === "string" ? body : JSON.stringify(body));
}

function localSentinel(repo: string, overrides: Record<string, string> = {}): void {
  writeSentinel(repo, {
    host: currentHost(),
    ts: "2026-09-14T00:00:00Z",
    hook_source: "plugin",
    ...overrides,
  });
}

describe("cloud-detect.sh classification", () => {
  let tempDir: string;
  let savedEnv: Record<string, string | undefined>;

  beforeEach(() => {
    tempDir = createTempGitRepo();
    // bun shares one process env across test files and has no stubEnv — snapshot
    // so afterEach can restore even if a case adds a mutation later.
    savedEnv = { ...process.env };
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
    for (const key of Object.keys(process.env)) {
      if (!(key in savedEnv)) delete process.env[key];
    }
    Object.assign(process.env, savedEnv);
  });

  test("Devin env + matching-host plugin sentinel → local, exit 0", () => {
    localSentinel(tempDir);
    const result = runDetect(tempDir);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("local");
  });

  test("no Devin env + valid plugin sentinel → local (sentinel carries the verdict)", () => {
    // Measured 2026-09-15: local Devin exec shells expose ZERO DEVIN* vars, so
    // env presence can never gate `local`. The sentinel is the evidence.
    localSentinel(tempDir);
    const result = runDetect(tempDir, { devin: false });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("local");
  });

  test("priority: no env + absent sentinel → no-devin-env, not sentinel-absent", () => {
    const result = runDetect(tempDir, { devin: false });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:no-devin-env");
  });

  test("Devin env + git repo without sentinel → not-local:sentinel-absent", () => {
    const result = runDetect(tempDir);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:sentinel-absent");
  });

  test("Devin env + cwd outside any git repo → not-local:sentinel-absent", () => {
    const plain = mkdtempSync(join(tmpdir(), "devin-cloud-nogit-"));
    try {
      const result = runDetect(plain);
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toBe("not-local:sentinel-absent");
    } finally {
      rmSync(plain, { recursive: true, force: true });
    }
  });

  test("sentinel with invalid JSON → not-local:malformed", () => {
    writeSentinel(tempDir, "this is not json at all");
    const result = runDetect(tempDir);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:malformed");
  });

  test("sentinel missing hook_source field → not-local:malformed", () => {
    writeSentinel(tempDir, { host: currentHost(), ts: "2026-09-14T00:00:00Z" });
    const result = runDetect(tempDir);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:malformed");
  });

  test("sentinel missing host field → not-local:malformed", () => {
    writeSentinel(tempDir, { ts: "2026-09-14T00:00:00Z", hook_source: "plugin" });
    const result = runDetect(tempDir);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:malformed");
  });

  test("foreign-host sentinel → not-local:foreign-host", () => {
    localSentinel(tempDir, { host: "other-host" });
    const result = runDetect(tempDir);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:foreign-host");
  });

  test("priority: foreign-host + repo hook_source → foreign-host, not non-plugin-source", () => {
    localSentinel(tempDir, { host: "other-host", hook_source: "repo" });
    const result = runDetect(tempDir);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:foreign-host");
  });

  test("repo-sourced sentinel (hook_source=repo) → not-local:non-plugin-source", () => {
    localSentinel(tempDir, { hook_source: "repo" });
    const result = runDetect(tempDir);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:non-plugin-source");
  });

  test("unrecognized hook_source value → not-local:non-plugin-source", () => {
    localSentinel(tempDir, { hook_source: "fork" });
    const result = runDetect(tempDir);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:non-plugin-source");
  });

  test("measured cloud env shape: DEVIN_DIR-only + no sentinel → sentinel-absent", () => {
    // The exact env the probe measured on a cloud VM exec shell: DEVIN_DIR set,
    // every other DEVIN* var absent. It must NOT classify no-devin-env.
    const result = runDetect(tempDir, {
      env: { DEVIN: "", DEVIN_DIR: "/opt/.devin" },
    });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:sentinel-absent");
  });

  test("conflicting-evidence: valid plugin sentinel on a cloud-marked VM → not-local", () => {
    // Upstream-convergence arm (#8160): if plugin-hook dispatch ever lands in
    // cloud before plugin subagents, the hook writes a valid this-host sentinel
    // while the capability gap persists. DEVIN_DIR is the measured cloud-only
    // marker — its presence must override the sentinel's local claim.
    localSentinel(tempDir);
    const result = runDetect(tempDir, {
      env: { DEVIN_DIR: "/opt/.devin" },
    });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:conflicting-evidence");
  });

  test("conflicting-evidence via DEVIN_DISABLE_HISTEXPAND (second cloud-only marker)", () => {
    localSentinel(tempDir);
    const result = runDetect(tempDir, {
      env: { DEVIN: "", DEVIN_DISABLE_HISTEXPAND: "1" },
    });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:conflicting-evidence");
  });

  test("priority: conflicting-evidence fires after foreign-host and non-plugin-source", () => {
    localSentinel(tempDir, { host: "other-host" });
    const result = runDetect(tempDir, { env: { DEVIN_DIR: "/opt/.devin" } });
    expect(result.stdout).toBe("not-local:foreign-host");
    localSentinel(tempDir, { hook_source: "repo" });
    const r2 = runDetect(tempDir, { env: { DEVIN_DIR: "/opt/.devin" } });
    expect(r2.stdout).toBe("not-local:non-plugin-source");
  });

  test("truncated JSON (no closing brace) → not-local:malformed", () => {
    writeSentinel(tempDir, `{"host":"${currentHost()}","hook_source":"plugin"`);
    const result = runDetect(tempDir);
    expect(result.stdout).toBe("not-local:malformed");
  });

  test("field-like substrings outside a JSON object → not-local:malformed", () => {
    writeSentinel(tempDir, `garbage "host":"${currentHost()}" "hook_source":"plugin"`);
    const result = runDetect(tempDir);
    expect(result.stdout).toBe("not-local:malformed");
  });

  test("classifier run from a repo SUBDIRECTORY still finds the sentinel", () => {
    localSentinel(tempDir);
    const sub = join(tempDir, "sub", "dir");
    mkdirSync(sub, { recursive: true });
    // env built against the fixture ROOT — gitFixtureEnv's discovery ceiling is
    // the argument's parent, so passing the subdir would cap the walk below the
    // repo. cwd is the subdirectory; env belongs to the fixture.
    const env = childEnv(tempDir, true);
    const result = Bun.spawnSync(["bash", SCRIPT], {
      cwd: sub,
      env,
      stdout: "pipe",
      stderr: "pipe",
    });
    expect(result.exitCode).toBe(0);
    expect(result.stdout.toString().trim()).toBe("local");
  });

  test("host near-miss (prefix match) → not-local:foreign-host", () => {
    localSentinel(tempDir, { host: `${currentHost()}-suffix` });
    const result = runDetect(tempDir);
    expect(result.stdout).toBe("not-local:foreign-host");
  });

  test("never-value: valid local sentinel + --banner emits NOTHING on stderr", () => {
    localSentinel(tempDir);
    const result = runDetect(tempDir, { args: ["--banner"] });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("local");
    expect(result.stderr).toBe("");
  });

  test("not-local + --banner names the absent surfaces and the reason on stderr", () => {
    const result = runDetect(tempDir, { args: ["--banner"] }); // sentinel-absent
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:sentinel-absent");
    expect(result.stderr).toContain("sentinel-absent");
    // Absent surfaces named explicitly — silence is the bug this feature kills.
    expect(result.stderr).toContain("subagent");
    expect(result.stderr).toContain("SessionStart");
    expect(result.stderr).toContain("SessionEnd");
    // The load-bearing disclosure lines: degrade path + secrets gate.
    expect(result.stderr).toContain("sequential-fallback");
    expect(result.stderr).toContain("Secrets/prod");
    // What still works must also be named.
    expect(result.stderr).toContain("skills");
    expect(result.stderr).toContain("AGENTS.md");
    expect(result.stderr).toContain("MCP");
  });

  test("--banner is suppressed on no-devin-env (not a Devin session — no false claim)", () => {
    const result = runDetect(tempDir, { devin: false, args: ["--banner"] });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:no-devin-env");
    expect(result.stderr).toBe("");
  });
});

describe("devin-session-start.sh sentinel write", () => {
  let tempDir: string;
  let savedEnv: Record<string, string | undefined>;

  function runHook(
    cwd: string,
    extraEnv: Record<string, string> = {},
  ): { exitCode: number; stdout: string; stderr: string } {
    const env = childEnv(cwd, true);
    delete env.CLAUDE_PLUGIN_ROOT;
    delete env.SOLEUR_HOOK_SOURCE;
    Object.assign(env, extraEnv);
    const result = Bun.spawnSync(["bash", HOOK], {
      cwd,
      env,
      stdout: "pipe",
      stderr: "pipe",
      stdin: Buffer.from("{}"),
    });
    return {
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    };
  }

  beforeEach(() => {
    tempDir = createTempGitRepo();
    savedEnv = { ...process.env };
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
    for (const key of Object.keys(process.env)) {
      if (!(key in savedEnv)) delete process.env[key];
    }
    Object.assign(process.env, savedEnv);
  });

  test("writes content-bearing sentinel under Devin env; context JSON still emitted", () => {
    const result = runHook(tempDir);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("hookSpecificOutput");
    const sentinelPath = join(tempDir, SENTINEL_REL);
    expect(existsSync(sentinelPath)).toBe(true);
    const sentinel = JSON.parse(readFileSync(sentinelPath, "utf8"));
    expect(sentinel.host).toBe(currentHost());
    expect(sentinel.hook_source).toBe("repo"); // no plugin registration in the child env
    expect(sentinel.ts).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
  });

  test("hook_source=plugin when invoked path resolves under CLAUDE_PLUGIN_ROOT", () => {
    const result = runHook(tempDir, { CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT });
    expect(result.exitCode).toBe(0);
    const sentinel = JSON.parse(readFileSync(join(tempDir, SENTINEL_REL), "utf8"));
    expect(sentinel.hook_source).toBe("plugin");
  });

  test("SOLEUR_HOOK_SOURCE env override wins over path inference", () => {
    const result = runHook(tempDir, { SOLEUR_HOOK_SOURCE: "plugin" });
    expect(result.exitCode).toBe(0);
    const sentinel = JSON.parse(readFileSync(join(tempDir, SENTINEL_REL), "utf8"));
    expect(sentinel.hook_source).toBe("plugin");
  });

  test("outside a git repo: hook still exits 0 and emits context JSON, no sentinel", () => {
    const plain = mkdtempSync(join(tmpdir(), "devin-hook-nogit-"));
    try {
      const result = runHook(plain);
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("hookSpecificOutput");
      expect(existsSync(join(plain, SENTINEL_REL))).toBe(false);
    } finally {
      rmSync(plain, { recursive: true, force: true });
    }
  });

  test("sentinel write failure is isolated: context JSON still emitted, exit 0", () => {
    // .devin exists as a regular FILE, so mkdir -p and the redirect both fail —
    // the failure must never kill the hook or suppress additionalContext.
    writeFileSync(join(tempDir, ".devin"), "not a directory");
    const result = runHook(tempDir);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("hookSpecificOutput");
  });

  test("dual registration: repo-sourced write never masks an existing plugin sentinel", () => {
    // Plugin registration wrote first; the repo registration fires second.
    writeSentinel(tempDir, {
      host: currentHost(),
      ts: "2026-09-14T00:00:00Z",
      hook_source: "plugin",
    });
    const result = runHook(tempDir); // resolves hook_source=repo (no CLAUDE_PLUGIN_ROOT)
    expect(result.exitCode).toBe(0);
    const sentinel = JSON.parse(readFileSync(join(tempDir, SENTINEL_REL), "utf8"));
    expect(sentinel.hook_source).toBe("plugin");
  });

  test("dual registration: plugin-sourced write overwrites a repo sentinel", () => {
    // Repo registration wrote first; the plugin registration fires second.
    writeSentinel(tempDir, {
      host: currentHost(),
      ts: "2026-09-14T00:00:00Z",
      hook_source: "repo",
    });
    const result = runHook(tempDir, { CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT });
    expect(result.exitCode).toBe(0);
    const sentinel = JSON.parse(readFileSync(join(tempDir, SENTINEL_REL), "utf8"));
    expect(sentinel.hook_source).toBe("plugin");
  });

  test("silent outside Devin env: no output, no sentinel", () => {
    const env = childEnv(tempDir, false);
    delete env.CLAUDE_PLUGIN_ROOT;
    delete env.SOLEUR_HOOK_SOURCE;
    const result = Bun.spawnSync(["bash", HOOK], {
      cwd: tempDir,
      env,
      stdout: "pipe",
      stderr: "pipe",
      stdin: Buffer.from("{}"),
    });
    expect(result.exitCode).toBe(0);
    expect(result.stdout.toString()).toBe("");
    expect(existsSync(join(tempDir, SENTINEL_REL))).toBe(false);
  });

  test("two real invocations: plugin-then-repo ordering preserves plugin sentinel", () => {
    const r1 = runHook(tempDir, { CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT });
    expect(r1.exitCode).toBe(0);
    const r2 = runHook(tempDir); // repo-sourced second write
    expect(r2.exitCode).toBe(0);
    const sentinel = JSON.parse(readFileSync(join(tempDir, SENTINEL_REL), "utf8"));
    expect(sentinel.hook_source).toBe("plugin");
  });

  test("two real invocations: repo-then-plugin ordering ends plugin-sourced", () => {
    const r1 = runHook(tempDir);
    expect(r1.exitCode).toBe(0);
    const r2 = runHook(tempDir, { CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT });
    expect(r2.exitCode).toBe(0);
    const sentinel = JSON.parse(readFileSync(join(tempDir, SENTINEL_REL), "utf8"));
    expect(sentinel.hook_source).toBe("plugin");
  });
});

// Marker-set drift pin: the cloud-mode marker block is a replicated literal
// across the union set (spawn-site ∪ secrets/prod ∪ pipeline skills ∪ devin
// shims). Replicated literals need a parity guard — a new union member that
// omits the block, or a copy that drifts, must fail this test.
describe("soleur-cloud-mode marker fleet", () => {
  const SKILLS_DIR = join(PLUGIN_ROOT, "skills");
  const DEVIN_SKILLS_DIR = join(PLUGIN_ROOT, "devin", "skills");
  const MARKER_START = "<!-- soleur-cloud-mode:start -->";
  const MARKER_END = "<!-- soleur-cloud-mode:end -->";

  // The skills whose contract genuinely needs the marker: spawn sites, the
  // FR4 secrets/prod union, the pipeline skills, and the devin entry shims.
  // Adding a union member means adding it HERE AND marking its SKILL.md —
  // the two halves of this test pin both directions of drift.
  const UNION = [
    "admin-ip-refresh", "cf-token-scope", "deploy", "flag-create",
    "flag-delete", "flag-list", "flag-set-role", "incident", "operator-digest",
    "postmerge", "provision-cloudflare", "provision-doppler",
    "provision-github", "provision-hetzner", "qa", "reproduce-bug",
    "test-browser", "trigger-cron", "user-set-role", "ux-audit",
  ];

  function markerBlock(path: string): string | null {
    const text = readFileSync(path, "utf8");
    const m = text.match(
      /<!-- soleur-cloud-mode:start -->[\s\S]*?<!-- soleur-cloud-mode:end -->/,
    );
    return m ? m[0] : null;
  }

  test("every marked SKILL.md carries exactly one byte-identical block", () => {
    const { readdirSync } = require("fs");
    const canonical = markerBlock(join(SKILLS_DIR, "work", "SKILL.md"));
    expect(canonical).not.toBeNull();
    const marked: string[] = [];
    for (const dir of [SKILLS_DIR, DEVIN_SKILLS_DIR]) {
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (!entry.isDirectory()) continue;
        const p = join(dir, entry.name, "SKILL.md");
        if (!existsSync(p)) continue;
        const text = readFileSync(p, "utf8");
        const count = text.split(MARKER_START).length - 1;
        if (count === 0) continue;
        marked.push(`${dir === SKILLS_DIR ? "skills" : "devin"}/${entry.name}`);
        expect(count).toBe(1);
        expect(text.split(MARKER_END).length - 1).toBe(1);
        expect(markerBlock(p)).toBe(canonical);
      }
    }
    // 64 plugin skills + 3 devin shims.
    expect(marked.length).toBe(67);
  });

  test("every FR4 union member is marked", () => {
    for (const name of UNION) {
      const p = join(SKILLS_DIR, name, "SKILL.md");
      expect(existsSync(p)).toBe(true);
      expect(markerBlock(p)).not.toBeNull();
    }
  });

  // SET IDENTITY, alongside the cardinality (#8402).
  //
  // `expect(marked.length).toBe(67)` is a stored value, and any `== N` floor survives every
  // substitution that keeps N — an add-one-delete-one diff satisfies it exactly. So the
  // sorted member list is pinned too: swapping one member for another has to edit a list a
  // reviewer reads.
  //
  // A DERIVED form was specified instead of this list ("assert every
  // plugins/soleur/skills/*/SKILL.md is marked") and is NOT implemented, because measuring
  // it falsified its premise: 64 of 100 skills carry the block, not 100 of 100. Membership
  // is a curated union — spawn sites, the FR4 secrets/prod set, the pipeline skills and the
  // devin shims — not a property of being a skill, so no derivation over the directory can
  // reproduce it. Asserting the universal would red a correct tree.
  test("the marked set is pinned by identity, not only by cardinality", () => {
    const { readdirSync } = require("fs");
    const marked: string[] = [];
    for (const dir of [SKILLS_DIR, DEVIN_SKILLS_DIR]) {
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (!entry.isDirectory()) continue;
        const p = join(dir, entry.name, "SKILL.md");
        if (!existsSync(p)) continue;
        if (!readFileSync(p, "utf8").includes(MARKER_START)) continue;
        marked.push(`${dir === SKILLS_DIR ? "skills" : "devin"}/${entry.name}`);
      }
    }
    expect(marked.sort()).toEqual(MARKED_SET);
    // Cross-check against the cardinality the sibling test pins, so the two cannot drift
    // apart into a pair that each pass while disagreeing about the population.
    expect(marked.length).toBe(67);
  });
});

// ===========================================================================================
// #8402 — one cloud-cache recipe across the shipped cohort.
//
// PROPERTY: no file shipped under `plugins/soleur/` instructs an agent to locate an
// executable in the Devin plugin cache BY FILENAME. Every such instruction selects by
// `.claude-plugin/plugin.json` identity, `[ -d ]`-gated, over both documented cache paths.
//
// ASSEMBLY — and this is the part that matters. The 67-member marker list is a SNAPSHOT, not
// the population. The property quantifies over every file under `plugins/soleur/` that names
// a Devin plugin-cache path, DERIVED at test time. Measured today that is 71 files: the 67
// marker blocks plus `devin/INSTRUCTIONS.md`, `commands/go.md`, `test/go-session-gates.test.sh`
// and THIS FILE — four sites the marker-block test structurally cannot see, because it only
// opens `*/SKILL.md`. That membership is NOT the one an earlier draft of this comment carried:
// `AGENTS.md` LEFT the population when its rule body became a pointer (asserted positively in
// the harness row below), and this file ENTERED it by naming both cache paths as fragments.
// Two changes that cancelled in the total — which is the argument for deriving the total
// rather than asserting it. The existing byte-identity + cardinality test is a
// sub-guard over one SUBSET; this is the guard over the population. Both ship.
//
// SCOPE NOTE, stated so this is not read as more than it is: the identity preflight is a
// SHAPE CHECK, not authentication. A planted directory containing `{"name":"soleur"}` passes
// it (ADR-179 A11, and `go-session-gates.test.sh` row R6b is a MUST-PASS row asserting
// exactly that limitation). This guard buys consistency and defence-in-depth. It does not
// prevent executing an untrusted script, and nothing derived from it may say that it does.
// ===========================================================================================
describe("devin cache recipe: identity-selected, never basename-selected", () => {
  const { readdirSync } = require("fs");

  // The two documented cache paths, as REGEX FRAGMENTS. Assembled at runtime rather than
  // written as one literal so that this guard's own body never contains the forbidden
  // shape it searches for. That is what removes the need for an allowlist — and an
  // allowlist is the thing that would quietly grow into the hole the guard exists to close.
  const CACHE_FRAGMENTS = ["/opt/\\.devin/plugins", "devin/cli/plugins/cache"];
  // `-name`/`-iname` with ANY basename argument. The property is "selects a Devin-cache
  // executable by filename", and one specific script name is a single member of that set:
  // a literal-only scan is a universal negative over one spelling.
  const SELECTOR = "-i?name";
  const FIND = "\\bfind\\b";

  /** Every file under plugins/soleur/ that NAMES a Devin plugin-cache path. */
  function deriveCachePathFiles(): string[] {
    const cacheRe = new RegExp(CACHE_FRAGMENTS.join("|"));
    const out: string[] = [];
    const walk = (dir: string) => {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        if (e.name === "node_modules" || e.name === ".git") continue;
        const full = join(dir, e.name);
        if (e.isDirectory()) { walk(full); continue; }
        if (!e.isFile()) continue;
        let text: string;
        try { text = readFileSync(full, "utf8"); } catch { continue; }
        if (cacheRe.test(text)) out.push(full);
      }
    };
    walk(PLUGIN_ROOT);
    return out.sort();
  }

  /**
   * Lines where a `find` rooted at (or arguments containing) a Devin cache path selects by
   * basename. Both operand orders are matched: `find <cache> -name X` and the rarer
   * `find -name X <cache>`.
   */
  function basenameSelectionHits(text: string): string[] {
    const cache = CACHE_FRAGMENTS.join("|");
    const forward = new RegExp(`${FIND}[^\n|]*(?:${cache})[^\n|]*${SELECTOR}\\s`, "g");
    const reverse = new RegExp(`${FIND}[^\n|]*${SELECTOR}\\s[^\n|]*(?:${cache})`, "g");
    return text
      .split("\n")
      .filter((l) => {
        forward.lastIndex = 0; reverse.lastIndex = 0;
        return forward.test(l) || reverse.test(l);
      })
      .map((l) => l.trim());
  }

  /**
   * The SAME property, over the shape `basenameSelectionHits` structurally cannot see.
   *
   * That detector is LINE-SCOPED: both its regexes require the cache fragment and the
   * `-name` on one line. But the sanctioned recipe — and therefore the shape a regression
   * would be written in — is a multi-line `for d in <cacheA> <cacheB>; do … find "$d" … done`,
   * where the cache paths are on the `for` line and the selector is two lines below. Every
   * one of the three non-marker members of the derived population (`commands/go.md`,
   * `devin/INSTRUCTIONS.md`, `test/go-session-gates.test.sh`) is written that way, so the
   * line-scoped scan could not have flagged any of them. A guard that cannot reach the files
   * it enumerates is a guard that reports clean for a reason unrelated to the tree.
   *
   * Block scope, not a fixed lookahead: a `for` line naming a cache path opens a window that
   * closes at its `done` (or at end of text). Inside it, any `find` carrying `-name`/`-iname`
   * is a hit regardless of whether the path literal is on that line — the loop variable IS
   * the cache path. `-path` selection is untouched, which is the whole point: identity
   * selection over the same directory must keep passing.
   */
  function blockScopedSelectionHits(text: string): string[] {
    const cacheRe = new RegExp(CACHE_FRAGMENTS.join("|"));
    const selectorRe = new RegExp(`${FIND}[^\n|]*${SELECTOR}\\s`);
    const lines = text.split("\n");
    const out: string[] = [];
    let depth = 0;
    for (const line of lines) {
      if (depth > 0) {
        if (/\bdone\b/.test(line)) { depth -= 1; continue; }
        if (selectorRe.test(line)) out.push(line.trim());
        continue;
      }
      // Open a window only on a `for`-style line that itself names a cache path; a bare
      // mention elsewhere in the file opens nothing, so this adds no reach beyond loops.
      if (/\bfor\s+\w+\s+in\b/.test(line) && cacheRe.test(line)) depth = 1;
    }
    return out;
  }

  // HARNESS ROW — planted-positive self-test. A detector whose pattern cannot match reports
  // a clean sweep, which is byte-identical to a healthy run. Before reading ANY verdict
  // below, prove the detector fires on an input it must flag. The planted string is
  // assembled from the same fragments, so it is synthesized rather than quoted and needs no
  // exemption of its own.
  test("HARNESS: the detector reports a planted positive", () => {
    // SYNTHESIZED, never quoted. Writing the forbidden shape as a literal would put it in
    // this file, which the derived scan then reports as an offender — and the obvious repair
    // (an allowlist entry for this path) is precisely the hole the guard exists to close,
    // which is why the allowlist was cut rather than added. Concatenation keeps the two
    // halves on either side of a `+` so no source line carries the contiguous shape.
    const OPT = "/opt/" + ".devin/plugins";
    const HOME_CACHE = "$HOME/.local/share/" + "devin/cli/plugins/cache";
    const N = "-" + "name";
    const IN = "-i" + "name";
    const planted = `GUARD="$(find ${OPT} ${N} precommit-guard.sh 2>/dev/null | head -1)"`;
    expect(basenameSelectionHits(planted).length).toBe(1);
    const plantedHome = `X="$(find "${HOME_CACHE}" ${N} cloud-detect.sh | head -1)"`;
    expect(basenameSelectionHits(plantedHome).length).toBe(1);
    // Variant spellings of the SAME mechanism must be caught, or the scan is a universal
    // negative over one member of a set: `-iname`, a glob argument, and a third script name
    // are all "selects a Devin-cache executable by filename".
    expect(basenameSelectionHits(`find ${OPT} ${IN} 'cloud-detect*' | head -1`).length).toBe(1);
    expect(basenameSelectionHits(`find ${OPT} ${N} some-other-script.sh`).length).toBe(1);
    // must-PASS input that is NOT the canonical: naming the directory is permitted; only
    // SELECTING BY BASENAME is forbidden. devin/INSTRUCTIONS.md does exactly this.
    const pathOnly = `the lock file is \`${OPT}/lock.json\``;
    expect(basenameSelectionHits(pathOnly).length).toBe(0);
    // Identity selection over the same directory must PASS.
    const identity =
      "MANIFEST=\"$(find \"$d\" -path '*/.claude-plugin/plugin.json' -exec grep -l soleur {} + | head -1)\"";
    expect(basenameSelectionHits(identity).length).toBe(0);

    // BLOCK-SCOPED detector, planted both ways. The offending form is the one the shipped
    // fences are written in, so a detector that misses it reports clean about the files it
    // enumerates. Assembled from the same fragments — no source line carries the shape.
    const loopBad = [
      `for d in "$HOME/.local/share/${"devin/cli/plugins/cache"}" ${OPT}; do`,
      '  [ -d "$d" ] || continue',
      `  X="$(find "$d" ${N} cloud-detect.sh 2>/dev/null | head -1)"`,
      "done",
    ].join("\n");
    expect(blockScopedSelectionHits(loopBad).length).toBe(1);
    // …and the LINE-scoped detector is blind to exactly this, which is why both ship.
    expect(basenameSelectionHits(loopBad).length).toBe(0);
    // The sanctioned identity loop must stay clean under the new detector too.
    const loopGood = [
      `for d in "$HOME/.local/share/${"devin/cli/plugins/cache"}" ${OPT}; do`,
      '  [ -d "$d" ] || continue',
      "  MANIFEST=\"$(find \"$d\" -path '*/.claude-plugin/plugin.json' -exec grep -l soleur {} + | head -1)\"",
      "done",
    ].join("\n");
    expect(blockScopedSelectionHits(loopGood).length).toBe(0);
    // A selector AFTER the loop closes is out of scope — the window must not leak.
    expect(blockScopedSelectionHits(loopGood + `\nfind /tmp ${N} x.sh`).length).toBe(0);
  });

  // HARNESS ROW — non-vacuity. A derived population that comes back empty (a moved root, a
  // typo'd fragment) would make every assertion below pass while measuring nothing.
  test("HARNESS: the derived population is non-empty and covers the non-marker sites", () => {
    const files = deriveCachePathFiles();
    expect(files.length).toBeGreaterThanOrEqual(67);
    // Sites the marker-block test structurally cannot see — it only ever opens `*/SKILL.md`.
    // These are the whole reason the assembly is DERIVED rather than a member list.
    //
    // `AGENTS.md` is deliberately NOT in this list. It was a member before #8402 and is the
    // witness that the derived scan reaches what the marker test cannot (it carried the
    // basename recipe and only this scan could see it). Its rule body is now a POINTER to
    // devin/INSTRUCTIONS.md §Detection, because a multi-line identity recipe cannot live
    // legibly on one line in a customer-shipped, always-loaded rules file — so it no longer
    // names a cache path at all and correctly leaves the population. Requiring it to stay
    // would pin the defect's shape rather than the property. Its treatment is asserted
    // positively in the next test instead.
    for (const rel of [
      "devin/INSTRUCTIONS.md",
      "commands/go.md",
      "test/go-session-gates.test.sh",
    ]) {
      expect(
        files.some((f) => f.endsWith(rel)),
        `${rel} names a Devin cache path but fell out of the derived population — the scan no longer reaches the non-marker sites`,
      ).toBe(true);
    }
  });

  // The pointer treatment, pinned positively. AGENTS.md leaves the derived population by
  // becoming a pointer, so no absence-based assertion can distinguish "correctly a pointer"
  // from "the rule was deleted" — and an absence that reads as safety is the failure mode
  // this suite exists for.
  test("the AGENTS.md rule points at the identity recipe rather than carrying one", () => {
    const agents = readFileSync(join(PLUGIN_ROOT, "AGENTS.md"), "utf8");
    const rule = agents
      .split("\n")
      .find((l) => l.includes("[id: cloud-detect-before-pipeline]"));
    expect(rule, "the cloud-detect-before-pipeline rule is missing entirely").toBeDefined();
    const r = rule as string;
    // Still tells the agent to run the classifier.
    expect(r).toContain("scripts/cloud-detect.sh");
    // Points at where the recipe lives, and forbids the basename shortcut by name.
    expect(r).toContain("devin/INSTRUCTIONS.md");
    expect(r).toMatch(/identity/i);
    expect(r).toMatch(/never by the script's basename/i);
    // Carries no cache path of its own — that is what took it out of the derived population.
    expect(basenameSelectionHits(r).length).toBe(0);
  });

  test("no shipped file selects a Devin-cache executable by filename", () => {
    const offenders: string[] = [];
    for (const f of deriveCachePathFiles()) {
      const text = readFileSync(f, "utf8");
      const hits = [...basenameSelectionHits(text), ...blockScopedSelectionHits(text)];
      if (hits.length) offenders.push(`${f.slice(PLUGIN_ROOT.length + 1)}: ${hits[0]}`);
    }
    expect(
      offenders,
      `these files locate a Devin-cache executable by basename; select by .claude-plugin/plugin.json identity instead:\n${offenders.join("\n")}`,
    ).toEqual([]);
  });

  test("the canonical block carries the full identity recipe", () => {
    const canonical = readFileSync(join(PLUGIN_ROOT, "skills", "work", "SKILL.md"), "utf8")
      .match(/<!-- soleur-cloud-mode:start -->[\s\S]*?<!-- soleur-cloud-mode:end -->/)?.[0];
    expect(canonical).toBeDefined();
    const c = canonical as string;
    // Both documented cache paths.
    expect(c).toContain("/opt/.devin/plugins");
    expect(c).toContain("devin/cli/plugins/cache");
    // Identity, not basename.
    expect(c).toContain(".claude-plugin/plugin.json");
    expect(c).toContain('"name"[[:space:]]*:[[:space:]]*"soleur"');
    // `[ -d ]`-gated, so a non-Devin box searches nothing.
    expect(c).toMatch(/\[ -d /);
    // One resolution, two consumers.
    expect(c).toContain("scripts/cloud-detect.sh");
    expect(c).toContain("scripts/precommit-guard.sh");
    // The scope note must travel WITH the recipe: this is where a reader forms the belief
    // that the check is stronger than it is.
    expect(c).toMatch(/shape check, not authentication/i);
    // And it must not overstate. CPO-C3: downstream copy generators read this text.
    expect(c).not.toMatch(/\b(prevents|protects against|secures)\b/i);
  });
});

// The marked cohort, pinned by identity. See the set-identity test above for why this is a
// committed list rather than a derivation over the skills directory.
const MARKED_SET: string[] = [
  "devin/go", "devin/help", "devin/sync", "skills/admin-ip-refresh",
  "skills/agent-native-architecture", "skills/agent-native-audit", "skills/atdd-developer",
  "skills/brainstorm", "skills/cf-token-scope", "skills/code-to-prd", "skills/community",
  "skills/competitive-analysis", "skills/compound", "skills/compound-capture",
  "skills/content-writer", "skills/deepen-plan", "skills/deploy",
  "skills/drain-labeled-backlog", "skills/drain-prs", "skills/eval-harness",
  "skills/fix-issue", "skills/flag-create", "skills/flag-delete", "skills/flag-list",
  "skills/flag-set-role", "skills/frontend-design", "skills/gdpr-gate", "skills/go",
  "skills/growth", "skills/incident", "skills/legal-audit", "skills/legal-generate",
  "skills/merge-pr", "skills/model-launch-review", "skills/one-shot", "skills/operator-digest",
  "skills/pencil-setup", "skills/plan", "skills/plan-review", "skills/postmerge",
  "skills/preflight", "skills/product-roadmap", "skills/provision-cloudflare",
  "skills/provision-doppler", "skills/provision-github", "skills/provision-hetzner",
  "skills/qa", "skills/rclone", "skills/reproduce-bug", "skills/resolve-parallel",
  "skills/resolve-pr-parallel", "skills/resolve-todo-parallel", "skills/review",
  "skills/schedule", "skills/seo-aeo", "skills/ship", "skills/skill-security-scan",
  "skills/spec-templates", "skills/sync", "skills/test-browser", "skills/test-fix-loop",
  "skills/triage", "skills/trigger-cron", "skills/user-set-role", "skills/ux-audit",
  "skills/work", "skills/xcode-test",
];
