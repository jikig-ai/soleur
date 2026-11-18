// #12824 — Guards 2 and 3 of the cron spawn-isolation plan
// (knowledge-base/project/plans/archive/20261118-103123-2026-11-17-fix-cron-agent-editable-code-spawn-isolation-plan.md, "Guard Contract").
//
// Guard 2 — chokepoint argv and env. Every claude child receives a HOME no other spawn received, that
// exists with mode 0700 while the child runs and is gone after it exits, and receives
// `--plugin-dir <resolved root>` before any caller flag exactly when `loadPlugin` is true. Uses the
// REAL filesystem under a temp workspace root and mocks only `child_process.spawn` (mocking
// `_cron-spawn-fs.ts` wholesale would test the fake); modes and existence are read INSIDE the fake spawn.
//
// Guard 3 — plugin-root resolver. `resolveCronPluginRoot()` returns a path only when it is the trusted
// absolute root, holds a manifest and a `.seed-complete`, and is not writable by the process; otherwise
// it throws with the reason. Only the W_OK probe is mocked (CI runs as root, where a chmod fixture
// proves nothing); the manifest and sentinel are real files.
//
// Separate file because it `vi.mock`s node:child_process (cron-claude-eval-substrate.test.ts must not).
import { EventEmitter } from "node:events";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve, sep } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const spawnSpy = vi.hoisted(() => vi.fn());
vi.mock("node:child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("node:child_process")>()),
  spawn: spawnSpy,
}));

const reportSpy = vi.hoisted(() => vi.fn());
const warnSpy = vi.hoisted(() => vi.fn());
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: reportSpy,
  warnSilentFallback: warnSpy,
}));
vi.mock("@/server/claude-cost-marker", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/claude-cost-marker")>()),
  emitClaudeCostMarker: vi.fn(),
}));

// Only the W_OK probe is replaced; pathExists / readTextOrNull / createSpawnHome stay real, and removeSpawnHome
// runs the real removal unless a row makes it throw (removeHomeFault).
const probeSpy = vi.hoisted(() => vi.fn());
const removeHomeFault = vi.hoisted(() => ({ err: null as NodeJS.ErrnoException | null }));
vi.mock("@/server/inngest/functions/_cron-spawn-fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/inngest/functions/_cron-spawn-fs")>();
  return {
    ...actual,
    probeWritable: probeSpy,
    removeSpawnHome: (home: string) => {
      if (removeHomeFault.err) throw removeHomeFault.err;
      actual.removeSpawnHome(home);
    },
  };
});

import { NonRetriableError } from "inngest";
import { classifyEvalFatal } from "@/server/inngest/functions/_cron-shared";
import { deriveWriteRoots } from "../../../server/inngest/cron-bash-allowlist-hook.mjs";
import {
  CRON_GIT_HARDENING,
  CronPluginRootError,
  SEED_RETRY_MS,
  buildClaudeArgv,
  resolveCronPluginRoot,
  resolveCronPluginRootOrFail,
  spawnClaudeEval,
} from "@/server/inngest/functions/_cron-claude-eval-substrate";

const noopLogger = { info: () => {}, warn: () => {}, error: () => {} } as unknown as Parameters<
  typeof spawnClaudeEval
>[0]["logger"];

const READ_ONLY = { writable: false, code: "EROFS" };

let scratch: string;
let pluginRoot: string;

function seedPluginRoot(dir: string, { sentinel = true, tag = "v1" } = {}): string {
  mkdirSync(join(dir, ".claude-plugin"), { recursive: true });
  mkdirSync(join(dir, "hooks"), { recursive: true });
  writeFileSync(join(dir, ".claude-plugin", "plugin.json"), '{"name":"soleur"}\n');
  if (sentinel) writeFileSync(join(dir, ".seed-complete"), `seeded 2026-11-17T00:00:00Z tag=${tag}\n`);
  return dir;
}

/** A workspace-shaped spawn cwd: `<scratch>/soleur-<cron>-X/repo`. */
function workspace(): { ephemeralRoot: string; spawnCwd: string } {
  const ephemeralRoot = mkdtempSync(join(scratch, "soleur-cron-bug-fixer-"));
  const spawnCwd = join(ephemeralRoot, "repo");
  mkdirSync(spawnCwd);
  return { ephemeralRoot, spawnCwd };
}

interface Seen {
  argv: string[];
  env: Record<string, string | undefined>;
  homeExisted: boolean;
  homeMode: number | null;
  tmpExisted: boolean;
  tmpMode: number | null;
  // AC8 survivor G2-4b — read just before the child's `exit`, so a HOME removed while the child runs is seen.
  homeAtExit?: boolean;
  tmpAtExit?: boolean;
}
let seen: Seen[];

/** H1: the spy deep-copies the env AT CALL TIME and stats the HOME inside the call. */
function fakeSpawnImpl(onSpawn?: () => void) {
  return (_bin: string, argv: string[], opts: { env: NodeJS.ProcessEnv }) => {
    const env = structuredClone(opts.env) as Record<string, string | undefined>;
    const home = env.HOME ?? "";
    const tmp = env.TMPDIR ?? "";
    const record: Seen = {
      argv: [...argv],
      env,
      homeExisted: home !== "" && existsSync(home),
      homeMode: home !== "" && existsSync(home) ? statSync(home).mode & 0o777 : null,
      tmpExisted: tmp !== "" && existsSync(tmp),
      tmpMode: tmp !== "" && existsSync(tmp) ? statSync(tmp).mode & 0o777 : null,
    };
    seen.push(record);
    onSpawn?.();
    const child = new EventEmitter() as EventEmitter & { stdout: null; stderr: null; pid: number };
    child.stdout = null;
    child.stderr = null;
    child.pid = 4242;
    queueMicrotask(() => {
      child.emit("spawn");
      setImmediate(() => {
        record.homeAtExit = home !== "" && existsSync(home);
        record.tmpAtExit = tmp !== "" && existsSync(tmp);
        child.emit("exit", 0, null);
      });
    });
    return child;
  };
}

function run(spawnCwd: string, extra: Partial<Parameters<typeof spawnClaudeEval>[0]> = {}) {
  return spawnClaudeEval({
    loadPlugin: false,
    spawnCwd,
    installationToken: "tok-test",
    flags: ["--print", "--max-turns", "3", "--"],
    prompt: "/soleur:fix-issue 1",
    maxTurnDurationMs: 60_000,
    cronName: "cron-bug-fixer",
    buildSpawnEnv: (token) => ({ PATH: "/usr/bin", HOME: "/home/soleur", GH_TOKEN: token }) as unknown as NodeJS.ProcessEnv,
    logger: noopLogger,
    ...extra,
  });
}

beforeEach(() => {
  scratch = mkdtempSync(join(tmpdir(), "cron-spawn-isolation-"));
  pluginRoot = seedPluginRoot(join(scratch, "plugin"));
  seen = [];
  spawnSpy.mockReset();
  spawnSpy.mockImplementation(fakeSpawnImpl());
  reportSpy.mockReset();
  warnSpy.mockReset();
  probeSpy.mockReset();
  probeSpy.mockReturnValue(READ_ONLY);
  vi.stubEnv("SOLEUR_PLUGIN_PATH", pluginRoot);
  vi.stubEnv("CLAUDE_BIN", process.execPath); // any existing file: the spawn itself is mocked
  vi.stubEnv("CRON_WORKSPACE_ROOT", scratch);
  vi.spyOn(process, "kill").mockImplementation(() => true);
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
  rmSync(scratch, { recursive: true, force: true });
});

describe("Guard 2 — per-spawn HOME (AC3)", () => {
  it("rows 1/4/5/10/11/12: a fresh 0700 home-* sibling of repo/, TMPDIR=<HOME>/tmp 0700 at spawn, gone after resolve", async () => {
    const { ephemeralRoot, spawnCwd } = workspace();
    await run(spawnCwd);
    expect(seen).toHaveLength(1);
    const { env } = seen[0];
    const home = env.HOME!;
    expect(dirname(home)).toBe(ephemeralRoot);
    expect(basename(home)).toMatch(/^home-/);
    expect(home.startsWith(spawnCwd + sep)).toBe(false);
    expect(seen[0].homeExisted).toBe(true);
    expect(seen[0].homeMode).toBe(0o700);
    expect(env.TMPDIR).toBe(join(home, "tmp"));
    expect(seen[0].tmpExisted).toBe(true);
    expect(seen[0].tmpMode).toBe(0o700);
    expect(seen[0].homeAtExit, "HOME must survive while the child runs").toBe(true);
    // The layout the substrate builds is the one the hook derives its write roots from (repo/ + home-*).
    expect(deriveWriteRoots(spawnCwd, home)).toEqual([spawnCwd, join(home, "tmp")]);
    expect(seen[0].tmpAtExit, "TMPDIR must survive while the child runs").toBe(true);
    expect(existsSync(home), "HOME must be removed after the spawn resolves").toBe(false);
  });

  it("row 2: the substrate's HOME wins over a cron's `HOME: process.env.HOME` (order, not just presence)", async () => {
    const { spawnCwd } = workspace();
    await run(spawnCwd);
    expect(seen[0].env.HOME).not.toBe("/home/soleur");
  });

  it("row 3: two spawns never share a HOME", async () => {
    const a = workspace();
    const b = workspace();
    await run(a.spawnCwd);
    await run(b.spawnCwd, { cronName: "cron-legal-audit" });
    expect(seen).toHaveLength(2);
    expect(seen[0].env.HOME).not.toBe(seen[1].env.HOME);
  });

  it("a server-cwd spawn (no workspace) gets a soleur-home-* dir under the workspace root, swept by the GC prefix", async () => {
    await run(process.cwd(), { cronName: "cron-daily-triage" });
    const home = seen[0].env.HOME!;
    expect(dirname(home)).toBe(scratch);
    expect(basename(home)).toMatch(/^soleur-home-/);
    expect(existsSync(home)).toBe(false);
  });

  it("a failed HOME create reports cron-spawn-home-create and never spawns", async () => {
    vi.stubEnv("CRON_WORKSPACE_ROOT", join(scratch, "does-not-exist"));
    await expect(run(process.cwd(), { cronName: "cron-daily-triage" })).rejects.toThrow();
    expect(spawnSpy).not.toHaveBeenCalled();
    const call = reportSpy.mock.calls.find((c) => c[1]?.op === "cron-spawn-home-create");
    expect(call).toBeDefined();
    // #8629 — an Error first arg is captured untagged under pino-mirror and the tagged capture is deduped away.
    expect(call![0]).toBeNull();
    expect(call![1].tags).toEqual({ cron: "cron-daily-triage" });
    // #12847 escalation (observability P3) — the errno code only: the error message names the HOME path.
    expect(call![1].extra).toEqual({ cron: "cron-daily-triage", code: "ENOENT" });
    expect(JSON.stringify(call![1])).not.toContain(scratch);
  });

  it("a failed HOME removal warns cron-spawn-home-teardown with the errno code only, never the path", async () => {
    const { spawnCwd } = workspace();
    const err = Object.assign(new Error(`EBUSY: resource busy, rmdir '${scratch}/x/home-abc/tmp/agent-named.md'`), {
      code: "EBUSY",
    });
    removeHomeFault.err = err;
    try {
      const result = await run(spawnCwd);
      expect(result.ok).toBe(true);
    } finally {
      removeHomeFault.err = null;
    }
    const call = warnSpy.mock.calls.find((c) => c[1]?.op === "cron-spawn-home-teardown");
    expect(call).toBeDefined();
    expect(call![0]).toBeNull();
    expect(call![1].tags).toEqual({ cron: "cron-bug-fixer" });
    expect(call![1].extra).toEqual({ cron: "cron-bug-fixer", code: "EBUSY" });
    expect(JSON.stringify(call![1])).not.toContain(scratch);
  });

  it("M16: the hardening triple wins over a cron env that sets its own GIT_CONFIG_COUNT", async () => {
    const { spawnCwd } = workspace();
    await run(spawnCwd, {
      buildSpawnEnv: (token) =>
        ({ PATH: "/usr/bin", GH_TOKEN: token, GIT_CONFIG_COUNT: "0", GIT_CONFIG_KEY_0: "core.pager" }) as unknown as NodeJS.ProcessEnv,
    });
    expect(seen[0].env.GIT_CONFIG_COUNT).toBe("3");
    expect(seen[0].env.GIT_CONFIG_KEY_0).toBe("core.hooksPath");
  });

  it("AC3/AC21: the git pin still lands, after the S5 hardening triple", async () => {
    const { spawnCwd } = workspace();
    await run(spawnCwd);
    const { env } = seen[0];
    expect(env.GIT_CONFIG_NOSYSTEM).toBe("1");
    expect(env.GIT_CONFIG_GLOBAL).toBeTruthy();
    expect(env.GIT_CONFIG_COUNT).toBe("3");
    const pairs = [0, 1, 2].map((i) => `${env[`GIT_CONFIG_KEY_${i}`]}=${env[`GIT_CONFIG_VALUE_${i}`]}`);
    expect(pairs).toEqual(["core.hooksPath=/dev/null", "core.fsmonitor=false", "safe.bareRepository=explicit"]);
    for (const [k, v] of Object.entries(CRON_GIT_HARDENING)) expect(env[k]).toBe(v);
  });
});

describe("Guard 2 — --plugin-dir is substrate-owned (AC2)", () => {
  it.each([
    ["--plugin-dir", "plugins/soleur"],
    ["--plugin-dir=plugins/soleur"],
  ])("row 6: a caller flag %s is refused before any spawn", async (...form) => {
    const { spawnCwd } = workspace();
    await expect(run(spawnCwd, { flags: ["--print", ...form, "--"] })).rejects.toThrow(/must not carry --plugin-dir/);
    expect(spawnSpy).not.toHaveBeenCalled();
  });

  it("row 7: loadPlugin:true puts --plugin-dir <resolved root> before every caller flag and before --", async () => {
    const { spawnCwd } = workspace();
    await run(spawnCwd, { loadPlugin: true });
    const { argv } = seen[0];
    const i = argv.indexOf("--plugin-dir");
    expect(i).toBeGreaterThan(-1);
    expect(argv[i + 1]).toBe(pluginRoot);
    expect(i).toBeLessThan(argv.indexOf("--print"));
    expect(i).toBeLessThan(argv.lastIndexOf("--"));
    expect(argv.filter((a) => a === "--plugin-dir")).toHaveLength(1);
  });

  it("row 8 (runtime half): a call with no boolean loadPlugin, or loadPlugin:true for a cron outside CRON_PLUGIN_LOADERS, rejects", async () => {
    const { spawnCwd } = workspace();
    await expect(run(spawnCwd, { loadPlugin: undefined as unknown as boolean })).rejects.toBeInstanceOf(NonRetriableError);
    await expect(run(spawnCwd, { loadPlugin: true, cronName: "cron-roadmap-review" })).rejects.toThrow(/CRON_PLUGIN_LOADERS/);
    expect(spawnSpy).not.toHaveBeenCalled();
  });

  it("H2: loadPlugin:false carries no --plugin-dir", async () => {
    const { spawnCwd } = workspace();
    await run(spawnCwd);
    expect(seen[0].argv.some((a) => a.startsWith("--plugin-dir"))).toBe(false);
  });

  it("row 8: loadPlugin is a required field (no default)", () => {
    const args = {
      spawnCwd: "/x",
      installationToken: "t",
      flags: [],
      prompt: "p",
      maxTurnDurationMs: 1,
      cronName: "cron-bug-fixer",
      buildSpawnEnv: () => ({}) as unknown as NodeJS.ProcessEnv,
      logger: noopLogger,
    };
    // @ts-expect-error -- #12824: omitting loadPlugin must not typecheck (tsc --noEmit enforces this line).
    const omitted: Parameters<typeof spawnClaudeEval>[0] = args;
    expect(omitted).toBeDefined();
  });

  it("buildClaudeArgv is pure: the root goes right after the system-prompt append, none for null", () => {
    const withRoot = buildClaudeArgv("/app/shared/plugins/soleur", { flags: ["--print", "--"], prompt: "p", budget: [] });
    expect(withRoot.slice(3, 5)).toEqual(["--plugin-dir", "/app/shared/plugins/soleur"]);
    expect(buildClaudeArgv(null, { flags: ["--print", "--"], prompt: "p", budget: [] })).not.toContain("--plugin-dir");
  });
});

describe("Guard 3 — resolveCronPluginRoot (AC1)", () => {
  const noSleep = { sleep: vi.fn(async () => {}) };
  beforeEach(() => noSleep.sleep.mockClear());

  it("H2: manifest + sentinel + an EROFS probe → the root and its seed tag", async () => {
    await expect(resolveCronPluginRoot(pluginRoot, noSleep)).resolves.toEqual({
      root: pluginRoot,
      seedTag: "v1",
      seedLine: "seeded 2026-11-17T00:00:00Z tag=v1",
    });
    expect(probeSpy.mock.calls.map((c) => c[0])).toEqual([pluginRoot, join(pluginRoot, "hooks")]);
  });

  it("EACCES also proves read-only", async () => {
    probeSpy.mockReturnValue({ writable: false, code: "EACCES" });
    await expect(resolveCronPluginRoot(pluginRoot, noSleep)).resolves.toMatchObject({ root: pluginRoot });
  });

  it("row 1 / H1: a writable root is refused", async () => {
    probeSpy.mockReturnValue({ writable: true, code: null });
    await expect(resolveCronPluginRoot(pluginRoot, noSleep)).rejects.toMatchObject({ reason: "writable" });
  });

  it.each(["EPERM", "ENOENT", null])("row 3: a probe error %s is not proof of read-only", async (code) => {
    probeSpy.mockReturnValue({ writable: false, code });
    await expect(resolveCronPluginRoot(pluginRoot, noSleep)).rejects.toMatchObject({ reason: "writable" });
  });

  it("row 5: a read-only root with a writable hooks/ is refused", async () => {
    probeSpy.mockImplementation((p: string) =>
      p.endsWith(`${sep}hooks`) ? { writable: true, code: null } : READ_ONLY,
    );
    await expect(resolveCronPluginRoot(pluginRoot, noSleep)).rejects.toMatchObject({ reason: "writable" });
  });

  it("a missing manifest is refused", async () => {
    rmSync(join(pluginRoot, ".claude-plugin"), { recursive: true });
    await expect(resolveCronPluginRoot(pluginRoot, noSleep)).rejects.toMatchObject({ reason: "manifest-missing" });
  });

  it("a half-deleted tree (reseed in progress: no sentinel AND no manifest) waits once before refusing", async () => {
    rmSync(join(pluginRoot, ".claude-plugin"), { recursive: true });
    rmSync(join(pluginRoot, ".seed-complete"));
    const sleep = vi.fn(async () => {
      seedPluginRoot(pluginRoot, { tag: "v3" }); // the copy finishes during the wait
    });
    await expect(resolveCronPluginRoot(pluginRoot, { sleep })).resolves.toEqual({
      root: pluginRoot,
      seedTag: "v3",
      seedLine: "seeded 2026-11-17T00:00:00Z tag=v3",
    });
    expect(sleep).toHaveBeenCalledTimes(1);
  });

  it("rows 2/6: a sentinel that never appears throws seed-incomplete after exactly ONE wait", async () => {
    rmSync(join(pluginRoot, ".seed-complete"));
    await expect(resolveCronPluginRoot(pluginRoot, noSleep)).rejects.toMatchObject({ reason: "seed-incomplete" });
    expect(noSleep.sleep).toHaveBeenCalledTimes(1);
    expect(noSleep.sleep).toHaveBeenCalledWith(SEED_RETRY_MS);
  });

  it("row 6: a sentinel written during the wait passes on the single retry", async () => {
    rmSync(join(pluginRoot, ".seed-complete"));
    const sleep = vi.fn(async () => {
      writeFileSync(join(pluginRoot, ".seed-complete"), "seeded tag=v2\n");
    });
    await expect(resolveCronPluginRoot(pluginRoot, { sleep })).resolves.toEqual({ root: pluginRoot, seedTag: "v2", seedLine: "seeded tag=v2" });
    expect(sleep).toHaveBeenCalledTimes(1);
  });

  it("row 4 neighbour: outside the test env, a non-/app/ candidate is untrusted-path (fed directly)", async () => {
    vi.stubEnv("VITEST", "");
    vi.stubEnv("NODE_ENV", "production");
    await expect(resolveCronPluginRoot("/tmp/evil-plugin", noSleep)).rejects.toMatchObject({ reason: "untrusted-path" });
    await expect(resolveCronPluginRoot("/app/../workspaces/x", noSleep)).rejects.toMatchObject({ reason: "untrusted-path" });
  });

  it("row 4: a refusal reports cron-plugin-root-untrusted ONCE and throws NonRetriableError, never a fallback path", async () => {
    probeSpy.mockReturnValue({ writable: true, code: null });
    const err = await resolveCronPluginRootOrFail("cron-bug-fixer").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(NonRetriableError);
    expect((err as NonRetriableError).cause).toBeInstanceOf(CronPluginRootError);
    const ops = reportSpy.mock.calls.filter((c) => c[1]?.op === "cron-plugin-root-untrusted");
    expect(ops).toHaveLength(1);
    expect(ops[0][0], "#8629: null first arg keeps the op/cron/reason tags").toBeNull();
    expect(ops[0][1].tags).toEqual({ cron: "cron-bug-fixer", reason: "writable" });
  });

  it("a refused root at spawn time throws before any spawn and before any HOME is created", async () => {
    probeSpy.mockReturnValue({ writable: true, code: null });
    const { ephemeralRoot, spawnCwd } = workspace();
    await expect(run(spawnCwd, { loadPlugin: true })).rejects.toBeInstanceOf(NonRetriableError);
    expect(spawnSpy).not.toHaveBeenCalled();
    expect(readdirNames(ephemeralRoot)).toEqual(["repo"]);
  });

  it("row 7: a seed tag that changes while the child runs reports plugin-reseeded-mid-run", async () => {
    spawnSpy.mockImplementation(
      fakeSpawnImpl(() => writeFileSync(join(pluginRoot, ".seed-complete"), "seeded tag=v9\n")),
    );
    const { spawnCwd } = workspace();
    const result = await run(spawnCwd, { loadPlugin: true });
    const reseed = reportSpy.mock.calls.filter((c) => c[1]?.op === "plugin-reseeded-mid-run");
    expect(reseed).toHaveLength(1);
    expect(reseed[0][1].extra).toMatchObject({ seedTagAtSpawn: "v1", seedTagAtExit: "v9" });
    // The verdict is downgraded, so classifyEvalFatal flips a best-effort cron's heartbeat red.
    expect(result.ok).toBe(false);
    expect(result.pluginReseeded).toBe(true);
    expect(classifyEvalFatal(result)).toMatchObject({ fatal: true, fatalClass: "plugin-reseeded" });
  });

  it("row 7b: a cron that runs plugin scripts without loading the plugin (community-monitor) is also downgraded", async () => {
    spawnSpy.mockImplementation(
      fakeSpawnImpl(() => writeFileSync(join(pluginRoot, ".seed-complete"), "seeded tag=v9\n")),
    );
    const { spawnCwd } = workspace();
    const result = await run(spawnCwd, { cronName: "cron-community-monitor", loadPlugin: false });
    expect(reportSpy.mock.calls.filter((c) => c[1]?.op === "plugin-reseeded-mid-run")).toHaveLength(1);
    expect(result.ok).toBe(false);
    expect(result.pluginReseeded).toBe(true);
  });

  it("row 7c: a cron that neither loads the plugin nor runs its scripts has no reseed baseline", async () => {
    spawnSpy.mockImplementation(
      fakeSpawnImpl(() => writeFileSync(join(pluginRoot, ".seed-complete"), "seeded tag=v9\n")),
    );
    const { spawnCwd } = workspace();
    const result = await run(spawnCwd, { cronName: "cron-roadmap-review", loadPlugin: false });
    expect(reportSpy.mock.calls.filter((c) => c[1]?.op === "plugin-reseeded-mid-run")).toHaveLength(0);
    expect(result.ok).toBe(true);
  });

  it("row 7d: a sentinel removed while the child runs counts as a reseed (fail closed)", async () => {
    spawnSpy.mockImplementation(fakeSpawnImpl(() => rmSync(join(pluginRoot, ".seed-complete"))));
    const { spawnCwd } = workspace();
    const result = await run(spawnCwd, { loadPlugin: true });
    expect(result.pluginReseeded).toBe(true);
    expect(result.ok).toBe(false);
  });

  it("row 7e: a failing reseed report still leaves the run not-ok", async () => {
    spawnSpy.mockImplementation(
      fakeSpawnImpl(() => writeFileSync(join(pluginRoot, ".seed-complete"), "seeded tag=v9\n")),
    );
    reportSpy.mockImplementation((_e: unknown, o: { op?: string }) => {
      if (o?.op === "plugin-reseeded-mid-run") throw new Error("sentry down");
    });
    const { spawnCwd } = workspace();
    const result = await run(spawnCwd, { loadPlugin: true });
    expect(result.ok).toBe(false);
    expect(result.pluginReseeded).toBe(true);
  });

  it("row 7f: community-monitor spawned while the sentinel is absent (a reseed under way) is downgraded", async () => {
    rmSync(join(pluginRoot, ".seed-complete"));
    const { spawnCwd } = workspace();
    const result = await run(spawnCwd, { cronName: "cron-community-monitor", loadPlugin: false });
    expect(result.pluginReseeded).toBe(true);
    expect(result.ok).toBe(false);
  });

  // #12847 escalation (architecture + data-integrity P3) — ci-deploy.sh deletes and recopies the tree on every
  // deploy and writes a fresh `seeded <timestamp> tag=<tag>` line, so a same-tag redeploy is a reseed too.
  it("row 7g: a same-tag reseed (new timestamp) while the child runs is detected", async () => {
    spawnSpy.mockImplementation(
      fakeSpawnImpl(() => writeFileSync(join(pluginRoot, ".seed-complete"), "seeded 2026-11-17T09:30:00Z tag=v1\n")),
    );
    const { spawnCwd } = workspace();
    const result = await run(spawnCwd, { loadPlugin: true });
    const reseed = reportSpy.mock.calls.filter((c) => c[1]?.op === "plugin-reseeded-mid-run");
    expect(reseed).toHaveLength(1);
    expect(reseed[0][1].extra).toMatchObject({ seedTagAtSpawn: "v1", seedTagAtExit: "v1" });
    expect(result.ok).toBe(false);
    expect(result.pluginReseeded).toBe(true);
  });

  it("row 7g control: the same sentinel line rewritten byte-for-byte (trailing whitespace aside) is no reseed", async () => {
    spawnSpy.mockImplementation(
      fakeSpawnImpl(() => writeFileSync(join(pluginRoot, ".seed-complete"), "seeded 2026-11-17T00:00:00Z tag=v1  \n\n")),
    );
    const { spawnCwd } = workspace();
    const result = await run(spawnCwd, { loadPlugin: true });
    expect(reportSpy.mock.calls.filter((c) => c[1]?.op === "plugin-reseeded-mid-run")).toHaveLength(0);
    expect(result.ok).toBe(true);
  });

  it("row 7 control: an unchanged tag reports nothing and keeps the verdict", async () => {
    const { spawnCwd } = workspace();
    const result = await run(spawnCwd, { loadPlugin: true });
    expect(reportSpy.mock.calls.filter((c) => c[1]?.op === "plugin-reseeded-mid-run")).toHaveLength(0);
    expect(result.ok).toBe(true);
    expect(result.pluginReseeded).toBeUndefined();
  });

  it("M22: the real probeWritable reports a writable temp dir as writable and a missing path as ENOENT", async () => {
    const real = await vi.importActual<typeof import("@/server/inngest/functions/_cron-spawn-fs")>(
      "@/server/inngest/functions/_cron-spawn-fs",
    );
    expect(real.probeWritable(scratch)).toEqual({ writable: true, code: null });
    expect(real.probeWritable(join(scratch, "no-such-dir"))).toEqual({ writable: false, code: "ENOENT" });
  });
});

describe("Phase 0 pin", () => {
  it("the CLI pin matches the version measurements.md was taken on (re-run the Phase 0 probe on a bump)", () => {
    const pkg = JSON.parse(readFileSync(resolve(__dirname, "../../../package.json"), "utf-8"));
    const pin = pkg.dependencies?.["@anthropic-ai/claude-code"] ?? pkg.devDependencies?.["@anthropic-ai/claude-code"];
    // knowledge-base/project/specs/archive/20261118-103123-feat-one-shot-12824-cron-spawn-isolation/measurements.md
    expect(pin).toBe("2.1.321");
  });
});

function readdirNames(dir: string): string[] {
  return readdirSync(dir).sort();
}
