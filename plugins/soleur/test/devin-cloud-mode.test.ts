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

  test("no Devin env → not-local:no-devin-env (env checked before sentinel)", () => {
    localSentinel(tempDir); // a perfectly valid sentinel must not override the env check
    const result = runDetect(tempDir, { devin: false });
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("not-local:no-devin-env");
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
    // What still works must also be named.
    expect(result.stderr).toContain("skills");
    expect(result.stderr).toContain("AGENTS.md");
    expect(result.stderr).toContain("MCP");
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
});
