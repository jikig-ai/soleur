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
});
