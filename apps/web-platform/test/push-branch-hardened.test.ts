/**
 * #11636 / ADR-309 9b: `pushBranch` with `hardened: true` (the cc push), flow level. Real git and real temp repositories; the
 * git children are observed at the `execFileSync` seam (delegating to the real one), the credential wrapper is replaced by a
 * recorder, and the real isolated-directory creator runs against a private HOME. The real-transport properties (hostile
 * config vectors, shallow, alternates) are in push-branch-isolated-real-git.test.ts.
 */
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { execFileSync as realExec } from "node:child_process";
import {
  existsSync,
  readFileSync,
  mkdtempSync,
  mkdirSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, sep } from "node:path";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

type Rec = { args: string[]; opts: { cwd?: string; env?: NodeJS.ProcessEnv; timeout?: number } };
const h = vi.hoisted(() => ({
  execCalls: [] as unknown[],
  syncCalls: [] as string[][],
  authCalls: [] as Array<{ args: string[]; id: number; opts: { hardened?: { gitDir: string; alternateObjectDirectory: string }; cwd?: string; timeout?: number } }>,
  authImpl: null as null | (() => Promise<Buffer>),
  reports: [] as Array<[unknown, { feature: string; op: string; message?: string; tags?: Record<string, string>; extra?: Record<string, unknown> }]>,
  disposeThrows: false,
  disposeCode: undefined as string | undefined,
  handles: [] as string[],
  /** Fault injection for the async commit check: the callback receives this error instead of running git. */
  execFileFault: null as null | Record<string, unknown>,
  /** Makes the async commit check throw SYNCHRONOUSLY (a bad argument or env value), before any callback exists. */
  execFileThrows: false,
  /** Test seam passed to the real creator (the object-walk entry cap). */
  limits: {} as { objectWalkEntryCap?: number },
  /** Makes the creator refuse with this reason (to exercise a reason push-branch does not know). */
  creatorThrows: null as null | string,
}));

vi.mock("child_process", async () => {
  const actual = await vi.importActual<typeof import("child_process")>("child_process");
  return {
    ...actual,
    execFileSync: (cmd: string, args: string[], opts: Rec["opts"]) => {
      h.execCalls.push({ args, opts });
      h.syncCalls.push(args);
      return actual.execFileSync(cmd, args, { ...opts, env: opts.env ?? gitFixtureEnv(opts.cwd ?? "/") });
    },
    // The hardened commit check is async: observed here the same way (recorded, then delegated to the real execFile).
    execFile: (cmd: string, args: string[], opts: Rec["opts"], cb: (err: unknown) => void) => {
      h.execCalls.push({ args, opts });
      if (h.execFileThrows) throw new TypeError("synchronous execFile failure");
      if (h.execFileFault) {
        const fault = h.execFileFault;
        queueMicrotask(() => cb(Object.assign(new Error("Command failed"), fault)));
        return undefined;
      }
      return actual.execFile(cmd, args, { ...opts, env: opts.env ?? gitFixtureEnv(opts.cwd ?? "/") }, cb as never);
    },
  };
});
vi.mock("../server/git-auth", () => ({
  gitWithInstallationAuth: async (args: string[], id: number, opts: (typeof h.authCalls)[number]["opts"]) => {
    h.authCalls.push({ args, id, opts });
    if (h.authImpl) return h.authImpl();
    return Buffer.from("");
  },
}));
vi.mock("../server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }) }));
vi.mock("../server/observability", () => ({
  reportSilentFallback: (err: unknown, o: { feature: string; op: string; extra?: Record<string, unknown> }) => {
    h.reports.push([err, o]);
  },
  warnSilentFallback: vi.fn(),
}));
vi.mock("../server/git-isolated-push-dir", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../server/git-isolated-push-dir")>();
  return {
    ...actual,
    createIsolatedPushDir: (ws: string) => {
      if (h.creatorThrows) throw new actual.IsolatedPushDirRefusal(h.creatorThrows as never);
      const real = actual.createIsolatedPushDir(ws, h.limits);
      h.handles.push(real.gitDir);
      if (!h.disposeThrows) return real;
      return Object.assign(Object.create(Object.getPrototypeOf(real)), real, {
        dispose: () => {
          real.dispose();
          throw Object.assign(new Error(`EBUSY at ${real.gitDir}`), h.disposeCode ? { code: h.disposeCode } : {});
        },
      });
    },
  };
});

import { ApprovedCommitUnavailableError, pushBranch } from "../server/push-branch";
import { GIT_HARDENING_ARGS } from "../server/inngest/functions/_git-hardening";
import { HARDENED_GIT_ARGS } from "../server/git-hardened-env";

const git = (cwd: string, ...args: string[]): string =>
  realExec("git", args, { cwd, stdio: "pipe", encoding: "utf8", env: gitFixtureEnv(cwd) }).trim();

const STATIC_PLAIN = "Workspace git directory is not a plain repository directory";
const PREPARE_FAILED = "Push could not be prepared (server-side setup problem); nothing was pushed";
const TOO_LARGE =
  "Push could not be prepared: the workspace repository has too many object entries to push from; run git gc in the workspace; nothing was pushed";

/** The exact shape of one hardened-push report: its own static message, the closed enum as a tag AND in extra, no Error object. */
const REFUSED_MESSAGE = "cc-push: the hardened push was refused before it ran; nothing was pushed";
const refusedReport = (reason: string) => [
  null,
  { feature: "cc-push", op: "isolated-dir-refused", message: REFUSED_MESSAGE, tags: { reason }, extra: { reason } },
];
const DISPOSE_MESSAGE = "cc-push: the isolated push directory could not be removed";
const failedReport = (cls: string) => [
  null,
  {
    feature: "cc-push",
    op: "push-failed-after-consume",
    message: "cc-push: the hardened push failed after the Owner's approval was consumed",
    tags: { class: cls },
    extra: { class: cls },
  },
];

describe("pushBranch hardened", () => {
  let root: string;
  let work: string;
  let home: string;
  let sha: string;
  const savedEnv: Record<string, string | undefined> = {};
  const savedGitConfigEnv: Record<string, string | undefined> = {};

  const opts = (extra: Record<string, unknown> = {}) => ({
    installationId: 1,
    owner: "o",
    repo: "r",
    workspacePath: work,
    branch: "feat-x",
    force: false,
    ...extra,
  });
  const hardenedOpts = (extra: Record<string, unknown> = {}) => opts({ commitSha: sha, hardened: true, ...extra });
  const leftovers = (): string[] => {
    const r = join(home, ".soleur-push");
    return existsSync(r) ? readdirSync(r) : [];
  };
  const refusalReports = () => h.reports.filter(([, o]) => o.op === "isolated-dir-refused");

  beforeEach(() => {
    for (const k of Object.keys(process.env)) {
      if (k === "GIT_CONFIG_COUNT" || k === "GIT_CONFIG_PARAMETERS" || /^GIT_CONFIG_(KEY|VALUE)_\d+$/.test(k)) {
        savedGitConfigEnv[k] = process.env[k];
        delete process.env[k];
      }
    }
    for (const k of ["HOME", "TMPDIR", "SOLEUR_TEST_SECRET_CANARY"]) savedEnv[k] = process.env[k];
    h.execCalls.length = 0;
    h.authCalls.length = 0;
    h.reports.length = 0;
    h.handles.length = 0;
    h.authImpl = null;
    h.disposeThrows = false;
    h.disposeCode = undefined;
    h.execFileFault = null;
    h.execFileThrows = false;
    h.limits = {};
    h.creatorThrows = null;
    root = realpathSync(mkdtempSync(join(tmpdir(), "push-hard-")));
    home = join(root, "home");
    mkdirSync(home);
    mkdirSync(join(root, "tmp"));
    process.env.HOME = home;
    process.env.TMPDIR = join(root, "tmp");
    work = join(root, "work");
    realExec("git", ["init", "-q", "-b", "main", work], { env: gitFixtureEnv(root) });
    git(work, "config", "user.name", "t");
    git(work, "config", "user.email", "t@example.invalid");
    git(work, "config", "commit.gpgsign", "false");
    writeFileSync(join(work, "a.txt"), "a\n");
    git(work, "add", ".");
    git(work, "commit", "-q", "-m", "A");
    sha = git(work, "rev-parse", "HEAD");
    h.execCalls.length = 0;
  });

  afterEach(() => {
    rmSync(root, { recursive: true, force: true });
    for (const [k, v] of Object.entries(savedEnv)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
    for (const [k, v] of Object.entries(savedGitConfigEnv)) {
      if (v !== undefined) process.env[k] = v;
      delete savedGitConfigEnv[k];
    }
  });

  describe("the flow", () => {
    test("pushes <sha>:refs/heads/<branch> from the isolated directory (no cwd), after ONE commit check in that directory and NO git config call", async () => {
      process.env.SOLEUR_TEST_SECRET_CANARY = "canary-value";
      await pushBranch(hardenedOpts());
      expect(h.authCalls).toHaveLength(1);
      const call = h.authCalls[0];
      expect(call.args).toEqual(["push", "https://github.com/o/r.git", `${sha}:refs/heads/feat-x`]);
      expect(Object.keys(call.opts).sort()).toEqual(["hardened", "timeout"]);
      expect(call.opts.timeout).toBe(120_000);
      const dir = call.opts.hardened as { gitDir: string; alternateObjectDirectory: string };
      expect(dir.alternateObjectDirectory).toBe(join(work, ".git", "objects"));
      expect(dir.gitDir.startsWith(`${home}${sep}.soleur-push${sep}run-`)).toBe(true);

      const calls = h.execCalls as Rec[];
      expect(calls.map((c) => c.args.filter((a) => ["rev-parse", "cat-file", "config"].includes(a)))).toEqual([["rev-parse"]]);
      const c = calls[0];
      expect(c.args.slice(0, GIT_HARDENING_ARGS.length)).toEqual([...GIT_HARDENING_ARGS]);
      expect(c.args.slice(0, HARDENED_GIT_ARGS.length)).toEqual([...HARDENED_GIT_ARGS]);
      expect(c.args.slice(-4)).toEqual(["rev-parse", "--verify", "--quiet", `${sha}^{commit}`]);
      expect(c.opts.cwd).toBe(dir.gitDir);
      expect(c.opts.timeout).toBe(10_000);
      const env = c.opts.env as NodeJS.ProcessEnv;
      expect(env.SOLEUR_TEST_SECRET_CANARY).toBeUndefined();
      expect(env.GIT_DIR).toBe(dir.gitDir);
      expect(env.GIT_ALTERNATE_OBJECT_DIRECTORIES).toBe(join(work, ".git", "objects"));
      expect(env.HOME).toBe(dir.gitDir);
      expect(env.GIT_ALLOW_PROTOCOL).toBe("https");
      expect(env.GIT_CONFIG_GLOBAL).toBe("/dev/null");
      expect(env.GIT_CONFIG_SYSTEM).toBe("/dev/null");
      expect(env.GIT_NO_REPLACE_OBJECTS).toBe("1");
      expect(env.GIT_COMMON_DIR).toBeUndefined();
      expect(h.reports).toEqual([]);
    });

    test("the commit check is ASYNC (the event loop is not blocked): the hardened path runs no execFileSync at all", async () => {
      h.syncCalls.length = 0;
      await pushBranch(hardenedOpts());
      expect(h.syncCalls).toEqual([]);
      expect((h.execCalls as Rec[]).filter((c) => c.args.includes("rev-parse"))).toHaveLength(1);
    });

    test("EVERY git child of a hardened push runs from the isolated directory, never with the workspace as cwd or GIT_DIR", async () => {
      await pushBranch(hardenedOpts());
      const dir = h.authCalls[0].opts.hardened as { gitDir: string };
      for (const c of h.execCalls as Rec[]) {
        expect(c.opts.cwd).toBe(dir.gitDir);
        expect(c.opts.cwd).not.toBe(work);
        expect(c.opts.env?.GIT_DIR).toBe(dir.gitDir);
        expect(c.opts.env?.GIT_DIR).not.toBe(join(work, ".git"));
      }
      expect(h.authCalls[0].opts.cwd).toBeUndefined();
    });

    test("the pinned sha is pushed, not whatever HEAD became after the approval", async () => {
      writeFileSync(join(work, "b.txt"), "b\n");
      git(work, "add", ".");
      git(work, "commit", "-q", "-m", "B");
      expect(git(work, "rev-parse", "HEAD")).not.toBe(sha);
      await pushBranch(hardenedOpts());
      expect(h.authCalls[0].args[2]).toBe(`${sha}:refs/heads/feat-x`);
    });

    test("force-push, a protected branch and a bad branch name are refused before any directory exists", async () => {
      await expect(pushBranch(hardenedOpts({ force: true }))).rejects.toThrow(/Force-push/);
      await expect(pushBranch(hardenedOpts({ branch: "main" }))).rejects.toThrow(/protected/);
      await expect(pushBranch(hardenedOpts({ branch: "a..b" }))).rejects.toThrow();
      expect(leftovers()).toEqual([]);
      expect(h.authCalls).toHaveLength(0);
    });

    test("legacy (field unset): the original three git calls, no env/timeout option, and the push options carry no hardened key", async () => {
      await pushBranch(opts({ commitSha: sha }));
      const calls = h.execCalls as Rec[];
      expect(calls.map((c) => c.args)).toEqual([
        ["cat-file", "-e", `${sha}^{commit}`],
        ["config", "user.name", "Soleur Agent"],
        ["config", "user.email", "agent@soleur.ai"],
      ]);
      for (const c of calls) {
        expect("env" in c.opts).toBe(false);
        expect("timeout" in c.opts).toBe(false);
        expect(c.opts.cwd).toBe(work);
      }
      expect(h.authCalls[0].opts).toStrictEqual({ cwd: work, timeout: 120_000 });
      expect(leftovers()).toEqual([]);
      expect(h.reports).toEqual([]);
    });

    test("the legacy path does NOT run any isolated-directory check (a .git file still reaches the push)", async () => {
      rmSync(join(work, ".git"), { recursive: true });
      writeFileSync(join(work, ".git"), "gitdir: /nonexistent\n");
      await pushBranch(opts());
      expect(h.authCalls).toHaveLength(1);
    });
  });

  describe("workspace tamper refusals (typed, static text, nothing pushed, nothing left behind, reported with a closed reason)", () => {
    /** Refused as the typed static refusal, with exactly one report carrying only the closed reason. */
    async function expectRefused(reason: string): Promise<void> {
      const p = pushBranch(hardenedOpts());
      await expect(p).rejects.toMatchObject({ name: "ApprovedCommitUnavailableError" });
      await expect(pushBranch(hardenedOpts())).rejects.toThrow(new RegExp(`^${STATIC_PLAIN}$`));
      expect(h.authCalls).toHaveLength(0);
      expect(h.execCalls).toHaveLength(0);
      expect(leftovers()).toEqual([]);
      const reports = refusalReports();
      expect(reports).toHaveLength(2);
      for (const [err, o] of reports) {
        expect(err).toBeNull(); // the Error object is never passed (#8629 class)
        expect([err, o]).toEqual(refusedReport(reason));
        expect(JSON.stringify(o)).not.toContain(root);
        expect(JSON.stringify(o)).not.toContain(sha);
      }
    }

    test("when .git is a FILE", async () => {
      rmSync(join(work, ".git"), { recursive: true });
      writeFileSync(join(work, ".git"), `gitdir: ${join(root, "elsewhere")}\n`);
      await expectRefused("git_dir_not_plain");
    });

    test("when .git is a SYMLINK to a real repository that CONTAINS the approved commit (so only the check, not a missing commit, can refuse)", async () => {
      const real = join(root, "real-git");
      renameSync(join(work, ".git"), real);
      expect(git(work, "--git-dir", real, "cat-file", "-t", sha)).toBe("commit");
      h.execCalls.length = 0;
      symlinkSync(real, join(work, ".git"));
      await expectRefused("git_dir_not_plain");
    });

    test("when .git is missing", async () => {
      rmSync(join(work, ".git"), { recursive: true });
      await expectRefused("git_dir_not_plain");
    });

    test("when .git/objects is a symlink to a complete copy", async () => {
      const aside = join(root, "aside-objects");
      renameSync(join(work, ".git", "objects"), aside);
      symlinkSync(aside, join(work, ".git", "objects"));
      await expectRefused("object_store_redirect");
    });

    test("when .git/objects/pack is a symlink to a complete copy", async () => {
      git(work, "gc", "-q");
      h.execCalls.length = 0; // the fixture's own git calls are not the code under test
      const aside = join(root, "aside-pack");
      renameSync(join(work, ".git", "objects", "pack"), aside);
      symlinkSync(aside, join(work, ".git", "objects", "pack"));
      await expectRefused("object_store_redirect");
    });

    test("when a loose-object fan-out directory .git/objects/<2hex> is a symlink to a complete copy", async () => {
      const fan = sha.slice(0, 2);
      const aside = join(root, "aside-fan");
      renameSync(join(work, ".git", "objects", fan), aside);
      symlinkSync(aside, join(work, ".git", "objects", fan));
      await expectRefused("object_store_redirect");
    });

    test.each(["alternates", "http-alternates"])("when .git/objects/info/%s exists", async (name) => {
      mkdirSync(join(work, ".git", "objects", "info"), { recursive: true });
      writeFileSync(join(work, ".git", "objects", "info", name), `${join(root, "other")}\n`);
      await expectRefused("object_store_redirect");
    });

    test("when .git/shallow is not a list of 40-hex ids", async () => {
      writeFileSync(join(work, ".git", "shallow"), "not-a-sha\n");
      await expectRefused("shallow_invalid");
    });

    test("when the workspace path contains ':'", async () => {
      const colon = join(root, "a:b");
      renameSync(work, colon);
      work = colon;
      await expectRefused("alternate_path_unsafe");
    });
  });

  describe("documented behaviour change: entries the 9a pre-flight refused are now ignored, because nothing reads them", () => {
    const planters: Array<[string, () => void]> = [
      ["config (symlink)", () => symlinkAside("config")],
      ["HEAD (symlink)", () => symlinkAside("HEAD")],
      ["hooks (symlink)", () => symlinkAside("hooks")],
      ["info (symlink)", () => symlinkAside("info")],
      ["index (symlink)", () => symlinkAside("index")],
      ["refs (symlink)", () => symlinkAside("refs")],
      ["packed-refs (planted)", () => writeFileSync(join(work, ".git", "packed-refs"), `${"a".repeat(40)} refs/heads/evil\n`)],
      ["commondir (planted)", () => writeFileSync(join(work, ".git", "commondir"), `${join(root, "other")}\n`)],
      ["config.worktree (planted)", () => writeFileSync(join(work, ".git", "config.worktree"), "[core]\n\tfsmonitor = /bin/false\n")],
      ["info/grafts (planted)", () => writeFileSync(join(work, ".git", "info", "grafts"), `${sha}\n`)],
    ];
    function symlinkAside(entry: string): void {
      const aside = join(root, `aside-${entry}`);
      renameSync(join(work, ".git", entry), aside);
      symlinkSync(aside, join(work, ".git", entry));
    }

    test.each(planters)("%s: the push proceeds, none of it is read, and nothing is reported", async (_label, plant) => {
      plant();
      await pushBranch(hardenedOpts());
      expect(h.authCalls).toHaveLength(1);
      expect(h.reports).toEqual([]);
      expect(leftovers()).toEqual([]);
    });
  });

  describe("the approved commit", () => {
    test.each([
      ["absent", undefined],
      ["a 64-hex (sha256-shaped) id", "a".repeat(64)],
      ["uppercase hex", "A".repeat(40)],
      ["too short", "abc123"],
      ["not hex", "z".repeat(40)],
    ])("%s is refused as ApprovedCommitUnavailableError (reason sha_invalid) before anything is created", async (_label, bad) => {
      const p = pushBranch(opts({ hardened: true, ...(bad === undefined ? {} : { commitSha: bad }) }));
      await expect(p).rejects.toBeInstanceOf(ApprovedCommitUnavailableError);
      await expect(p).rejects.toThrow(/^Approved commit is not a valid full commit sha$/);
      expect(h.reports).toEqual([refusedReport("sha_invalid")]);
      expect(h.authCalls).toHaveLength(0);
      expect(h.execCalls).toHaveLength(0);
      expect(h.handles).toHaveLength(0);
      expect(leftovers()).toEqual([]);
    });

    test("a valid sha that is not in the object store is refused (reason commit_absent) and the directory is removed", async () => {
      await expect(pushBranch(hardenedOpts({ commitSha: "e".repeat(40) }))).rejects.toMatchObject({
        name: "ApprovedCommitUnavailableError",
        message: "Approved commit is not present in the workspace repository",
      });
      expect(h.reports).toEqual([refusedReport("commit_absent")]);
      expect(h.authCalls).toHaveLength(0);
      expect(leftovers()).toEqual([]);
    });
  });

  describe("infrastructure failure is not a tamper refusal", () => {
    test("an unusable HOME is a plain static error (no path, no cause), reported as setup_failed, with no /tmp fallback", async () => {
      delete process.env.HOME;
      let err: unknown;
      try {
        await pushBranch(hardenedOpts());
      } catch (e) {
        err = e;
      }
      expect(err).toBeInstanceOf(Error);
      expect(err).not.toBeInstanceOf(ApprovedCommitUnavailableError);
      expect((err as Error).name).toBe("Error");
      expect((err as Error).message).toBe(PREPARE_FAILED);
      expect((err as Error).cause).toBeUndefined();
      expect(h.reports).toEqual([refusedReport("setup_failed")]);
      expect(h.authCalls).toHaveLength(0);
      expect(readdirSync(join(root, "tmp"))).toEqual([]);
    });

    test("a PATH entry under the workspace is refused as infrastructure (env_path_unsafe), not as a tampered repository", async () => {
      const bin = join(work, "bin");
      mkdirSync(bin);
      const savedPath = process.env.PATH;
      process.env.PATH = `${bin}:${savedPath ?? ""}`;
      try {
        await expect(pushBranch(hardenedOpts())).rejects.toMatchObject({ name: "Error", message: PREPARE_FAILED });
      } finally {
        process.env.PATH = savedPath;
      }
      expect(h.reports).toEqual([refusedReport("env_path_unsafe")]);
    });

    test("an object store above the walk cap is infrastructure (object_store_too_large) with its own static text, not a tamper refusal", async () => {
      h.limits = { objectWalkEntryCap: 3 };
      let err: unknown;
      try {
        await pushBranch(hardenedOpts());
      } catch (e) {
        err = e;
      }
      expect(err).not.toBeInstanceOf(ApprovedCommitUnavailableError);
      expect((err as Error).message).toBe(TOO_LARGE); // its own static text: the model can tell the user what to do (git gc)
      expect((err as Error).message).not.toBe(PREPARE_FAILED);
      expect((err as Error).message).not.toMatch(/\//); // no path
      expect((err as Error).message).not.toContain(root);
      expect(h.reports).toEqual([refusedReport("object_store_too_large")]);
      expect(h.authCalls).toHaveLength(0);
      expect(leftovers()).toEqual([]);
    });

    test("a refusal reason push-branch does not know defaults to the plain infrastructure error (never to 'commit not available')", async () => {
      h.creatorThrows = "some_future_reason";
      let err: unknown;
      try {
        await pushBranch(hardenedOpts());
      } catch (e) {
        err = e;
      }
      expect(err).not.toBeInstanceOf(ApprovedCommitUnavailableError);
      expect((err as Error).message).toBe(PREPARE_FAILED);
      expect(h.reports).toEqual([refusedReport("some_future_reason")]);
    });

    test.each([
      ["a timeout (killed by the 10 s bound)", { killed: true, signal: "SIGTERM", code: null }, "commit_check_timeout"],
      ["git missing from PATH (spawn ENOENT)", { code: "ENOENT" }, "commit_check_failed"],
      ["EMFILE on spawn", { code: "EMFILE" }, "commit_check_failed"],
      ["exit status 128 (a broken object store)", { code: 128 }, "commit_check_failed"],
    ])("the commit check ending in %s is infrastructure, NOT commit_absent: plain error, own reason, directory removed", async (_label, fault, reason) => {
      h.execFileFault = fault;
      let err: unknown;
      try {
        await pushBranch(hardenedOpts());
      } catch (e) {
        err = e;
      }
      expect(err).not.toBeInstanceOf(ApprovedCommitUnavailableError);
      expect((err as Error).message).toBe(PREPARE_FAILED);
      expect(h.reports).toEqual([refusedReport(reason)]);
      expect(h.authCalls).toHaveLength(0);
      expect(existsSync(h.handles[0])).toBe(false);
      expect(leftovers()).toEqual([]);
    });

    test("exit status 1 (git's answer for 'not a valid commit here') IS commit_absent", async () => {
      h.execFileFault = { code: 1 };
      await expect(pushBranch(hardenedOpts())).rejects.toBeInstanceOf(ApprovedCommitUnavailableError);
      expect(h.reports).toEqual([refusedReport("commit_absent")]);
    });

    test("a SYNCHRONOUS throw from the commit check is infrastructure (commit_check_failed), never commit_absent, and the directory is removed", async () => {
      h.execFileThrows = true;
      let err: unknown;
      try {
        await pushBranch(hardenedOpts());
      } catch (e) {
        err = e;
      }
      expect(err).not.toBeInstanceOf(ApprovedCommitUnavailableError);
      expect((err as Error).message).toBe(PREPARE_FAILED);
      expect(h.reports).toEqual([refusedReport("commit_check_failed")]);
      expect(h.authCalls).toHaveLength(0);
      expect(existsSync(h.handles[0])).toBe(false);
      expect(leftovers()).toEqual([]);
    });

    test("an annotated-tag OBJECT sha is not the approved commit: rev-parse peels it to its commit, so the printed sha must equal the approved one (commit_absent)", async () => {
      git(work, "tag", "-a", "-m", "m", "t1");
      const tagObject = git(work, "rev-parse", "refs/tags/t1");
      expect(tagObject).not.toBe(sha); // the premise: a distinct object that peels to the commit
      expect(git(work, "rev-parse", `${tagObject}^{commit}`)).toBe(sha);
      await expect(pushBranch(hardenedOpts({ commitSha: tagObject }))).rejects.toBeInstanceOf(ApprovedCommitUnavailableError);
      expect(h.reports).toEqual([refusedReport("commit_absent")]);
      expect(h.authCalls).toHaveLength(0);
      expect(leftovers()).toEqual([]);
    });

    test("the approved commit itself is present (control for the tag-object test: same repository, the commit sha)", async () => {
      git(work, "tag", "-a", "-m", "m", "t1");
      await pushBranch(hardenedOpts());
      expect(h.authCalls).toHaveLength(1);
      expect(h.reports).toEqual([]);
    });

    test("the commit check's lazy import runs INSIDE the try (a rejected import must not leak the directory: the caller holds no handle yet)", () => {
      // An import() rejection cannot be induced from a test, so the property is pinned on the source text of the one function.
      const src = readFileSync(join(__dirname, "../server/push-branch.ts"), "utf8");
      const body = src.slice(src.indexOf("async function checkCommitPresent("), src.indexOf("async function prepareIsolatedPush("));
      expect(body.length).toBeGreaterThan(200);
      const tryAt = body.indexOf("try {");
      const importAt = body.indexOf('await import("node:child_process")');
      expect(tryAt).toBeGreaterThan(-1);
      expect(importAt).toBeGreaterThan(tryAt);
    });

    test("a REAL spawn failure (git not found on PATH) is commit_check_failed, not commit_absent", async () => {
      const savedPath = process.env.PATH;
      process.env.PATH = join(root, "no-such-bin");
      try {
        await expect(pushBranch(hardenedOpts())).rejects.toMatchObject({ name: "Error", message: PREPARE_FAILED });
      } finally {
        process.env.PATH = savedPath;
      }
      expect(h.reports).toEqual([refusedReport("commit_check_failed")]);
      expect(leftovers()).toEqual([]);
    });
  });

  describe("the isolated directory never outlives the call (except process death)", () => {
    test("removed after success", async () => {
      await pushBranch(hardenedOpts());
      expect(h.handles).toHaveLength(1);
      expect(existsSync(h.handles[0])).toBe(false);
      expect(leftovers()).toEqual([]);
    });

    test("removed after a push failure, and the surfaced text is path-stripped", async () => {
      h.authImpl = async () => {
        throw Object.assign(new Error("failed"), { stderr: Buffer.from(`fatal: unable to access '${home}/.soleur-push/run-x/config': denied`) });
      };
      let err: unknown;
      try {
        await pushBranch(hardenedOpts());
      } catch (e) {
        err = e;
      }
      expect((err as Error).message).toMatch(/^Git push failed: /);
      expect((err as Error).message).not.toContain(home);
      expect(existsSync(h.handles[0])).toBe(false);
      expect(leftovers()).toEqual([]);
    });

    test("removed when the credential wrapper rejects (token mint failure)", async () => {
      h.authImpl = async () => {
        throw new Error("mint failed");
      };
      await expect(pushBranch(hardenedOpts())).rejects.toThrow(/Git push failed/);
      expect(leftovers()).toEqual([]);
    });

    test("removed after a creator refusal and after a cat-file refusal (asserted by path non-existence)", async () => {
      await expect(pushBranch(hardenedOpts({ commitSha: "e".repeat(40) }))).rejects.toBeInstanceOf(ApprovedCommitUnavailableError);
      expect(h.handles).toHaveLength(1);
      expect(existsSync(h.handles[0])).toBe(false);
      expect(leftovers()).toEqual([]);
    });

    test("two concurrent pushes from one workspace get distinct directories and both are removed", async () => {
      await Promise.all([pushBranch(hardenedOpts()), pushBranch(hardenedOpts({ branch: "feat-y" }))]);
      expect(h.handles).toHaveLength(2);
      expect(new Set(h.handles).size).toBe(2);
      for (const d of h.handles) expect(existsSync(d)).toBe(false);
    });

    test("a throwing dispose() does not change the push result and is reported by class name only", async () => {
      h.disposeThrows = true;
      await expect(pushBranch(hardenedOpts())).resolves.toEqual({ branch: "feat-x", pushed: true });
      const r = h.reports.filter(([, o]) => o.op === "isolated-dir-dispose-failed");
      expect(r).toEqual([
        [null, { feature: "cc-push", op: "isolated-dir-dispose-failed", message: DISPOSE_MESSAGE, tags: { class: "unknown" }, extra: { class: "unknown" } }],
      ]);
      expect(JSON.stringify(r)).not.toContain(home);
    });

    test("a throwing dispose() with an errno code is reported by that code (the class name would always be 'Error')", async () => {
      h.disposeThrows = true;
      h.disposeCode = "EBUSY";
      await expect(pushBranch(hardenedOpts())).resolves.toEqual({ branch: "feat-x", pushed: true });
      const r = h.reports.filter(([, o]) => o.op === "isolated-dir-dispose-failed");
      expect(r).toHaveLength(1);
      expect(r[0][1].tags).toEqual({ class: "EBUSY" });
      expect(r[0][1].extra).toEqual({ class: "EBUSY" });
      expect(JSON.stringify(r)).not.toContain(home);
      h.reports.length = 0;
      h.disposeCode = "not an errno /etc/passwd";
      await pushBranch(hardenedOpts());
      expect(h.reports.filter(([, o]) => o.op === "isolated-dir-dispose-failed")[0][1].tags).toEqual({ class: "unknown" });
    });

    test("a throwing dispose() does not mask the push failure either", async () => {
      h.disposeThrows = true;
      h.authImpl = async () => {
        throw Object.assign(new Error("x"), { stderr: Buffer.from("remote: Permission denied") });
      };
      await expect(pushBranch(hardenedOpts())).rejects.toThrow(/^Git push failed: remote: Permission denied$/);
    });
  });

  describe("a push that fails after the approval was consumed", () => {
    const failing = (stderr: string, extra: Record<string, unknown> = {}) => {
      h.authImpl = async () => {
        throw Object.assign(new Error("Command failed"), { stderr: Buffer.from(stderr), ...extra });
      };
    };

    test.each([
      ["unpack", "error: remote unpack failed: eof before pack header"],
      ["unpack", " ! [remote rejected] feat-x -> feat-x (unpacker error)"],
      ["auth", "remote: Invalid username or token. Authentication failed for 'https://github.com/o/r.git/'"],
      ["auth", "fatal: could not read Username for 'https://github.com': terminal prompts disabled"],
      ["non_fast_forward", " ! [rejected]        abc -> feat-x (non-fast-forward)"],
      ["non_fast_forward", " ! [rejected]        abc -> feat-x (fetch first)"],
      ["other", "something unexpected"],
    ])("class %s is reported with the closed enum only", async (cls, stderr) => {
      failing(stderr);
      await expect(pushBranch(hardenedOpts())).rejects.toThrow(/^Git push failed: /);
      const r = h.reports.filter(([, o]) => o.op === "push-failed-after-consume");
      expect(r).toEqual([failedReport(cls)]);
    });

    test("the REAL GitHub 403 (no contents:write) classifies as auth, not other", async () => {
      failing(
        "remote: Permission to o/r.git denied to soleur-app[bot].\nfatal: unable to access 'https://github.com/o/r.git/': The requested URL returned error: 403\n",
      );
      await expect(pushBranch(hardenedOpts())).rejects.toThrow(/^Git push failed: /);
      expect(h.reports.filter(([, o]) => o.op === "push-failed-after-consume")).toEqual([failedReport("auth")]);
    });

    test.each([
      "fatal: unable to access 'https://github.com/o/r.git/': Failed to connect to github.com port 443 after 129000 ms: Connection timed out",
      "fatal: unable to access 'https://github.com/o/r.git/': Connection timed out after 30001 milliseconds",
    ])("a connect timeout (nothing landed) is NOT class timeout and does not say the push MAY HAVE been pushed", async (stderr) => {
      failing(stderr);
      const p = pushBranch(hardenedOpts());
      await expect(p).rejects.toThrow(/^Git push failed: /);
      await expect(p).rejects.not.toThrow(/MAY HAVE been pushed/);
      expect(h.reports.filter(([, o]) => o.op === "push-failed-after-consume")).toEqual([failedReport("other")]);
    });

    test.each([
      ["killed", { killed: true }],
      ["SIGTERM", { signal: "SIGTERM" }],
      ["ETIMEDOUT", { code: "ETIMEDOUT" }],
    ])("class timeout comes from the child (%s), with no stderr at all", async (_label, extra) => {
      failing("", extra);
      await expect(pushBranch(hardenedOpts())).rejects.toThrow(/MAY HAVE been pushed/);
      expect(h.reports.filter(([, o]) => o.op === "push-failed-after-consume")).toEqual([failedReport("timeout")]);
    });

    test.each([
      "remote: error: File timeout exceeded.bin is 120.00 MB; this exceeds GitHub's file size limit",
      "fatal: unable to access 'https://github.com/o/r.git/': timeout exceeded",
    ])("stderr text that says 'timeout exceeded' cannot forge class timeout (Node puts stderr into the error message): %s", async (stderr) => {
      // Node's execFile error message is `Command failed: <cmd>\n<stderr>`, so the stderr text is in `message` as well. A real
      // timeout carries killed/SIGTERM and no such marker.
      failing(stderr, { message: `Command failed: git push\n${stderr}` });
      const p = pushBranch(hardenedOpts());
      await expect(p).rejects.toThrow(/^Git push failed: /);
      await expect(p).rejects.not.toThrow(/MAY HAVE been pushed/);
      expect(h.reports.filter(([, o]) => o.op === "push-failed-after-consume")).toEqual([failedReport("other")]);
    });

    test.each(["a", "e", "r", "o"])(
      "a one-letter branch (%s) does not eat letters out of the git-authored words: 'Authentication failed' stays class auth",
      async (branch) => {
        failing("fatal: Authentication failed for 'https://github.com/o/r.git/'");
        await expect(pushBranch(hardenedOpts({ branch }))).rejects.toThrow(/^Git push failed: /);
        expect(h.reports.filter(([, o]) => o.op === "push-failed-after-consume")).toEqual([failedReport("auth")]);
      },
    );

    test.each([
      ["a one-letter branch against the 'remote:' line prefix", "e", "remote: Permission to o/r.git denied to x."],
      ["the ref spelled refs/heads/<branch> in a host echo", "unpack", "remote: error: GH013: Repository rule violations found for refs/heads/unpack."],
    ])("%s", async (label, branch, stderr) => {
      failing(stderr);
      await expect(pushBranch(hardenedOpts({ branch }))).rejects.toThrow(/^Git push failed: /);
      const cls = label.startsWith("a one-letter") ? "auth" : "other";
      expect(h.reports.filter(([, o]) => o.op === "push-failed-after-consume")).toEqual([failedReport(cls)]);
    });

    test("a repository named like a class cannot forge it through the remote URL echo (owner/repo is removed as a slug)", async () => {
      failing("fatal: repository 'https://github.com/o/unpack.git/' not found");
      await expect(pushBranch(hardenedOpts({ repo: "unpack" }))).rejects.toThrow(/^Git push failed: /);
      expect(h.reports.filter(([, o]) => o.op === "push-failed-after-consume")).toEqual([failedReport("other")]);
    });

    test("removing the slug cannot JOIN its neighbours into a class word ('unp' + 'a/r' + 'ack' must not become 'unpack')", async () => {
      failing("error: remote unpa/rack failed");
      await expect(pushBranch(hardenedOpts({ owner: "a", repo: "r" }))).rejects.toThrow(/^Git push failed: /);
      expect(h.reports.filter(([, o]) => o.op === "push-failed-after-consume")).toEqual([failedReport("other")]);
    });

    test.each([
      ["a branch named like a class in a ref-status line", "unpack-fix", " ! [remote rejected] abcdef0 -> unpack-fix (protected branch hook declined)"],
      ["a branch named non-fast-forward echoed by the host", "non-fast-forward", "remote: error: GH013: Repository rule violations found for refs/heads/non-fast-forward."],
      ["a branch named unpack in the failed-to-push echo and a remote-rejected line", "unpack", "error: failed to push some refs to 'https://github.com/o/r.git'\n ! [remote rejected] abc -> unpack (some other reason)"],
    ])("%s cannot forge the class (agent-chosen names are not matched)", async (_label, branch, stderr) => {
      failing(stderr);
      await expect(pushBranch(hardenedOpts({ branch }))).rejects.toThrow(/^Git push failed: /);
      expect(h.reports.filter(([, o]) => o.op === "push-failed-after-consume")).toEqual([failedReport("other")]);
    });

    test("a timeout says the push MAY have landed (never reads as 'nothing landed') and is reported as class timeout", async () => {
      failing("", { killed: true, signal: "SIGTERM" });
      const p = pushBranch(hardenedOpts());
      await expect(p).rejects.toThrow(/MAY HAVE been pushed/);
      await expect(p).rejects.toThrow(/Ask the user to check the remote branch before asking for a new approval/);
      await expect(p).rejects.toThrow(/^Git push failed: /);
      expect(h.reports.filter(([, o]) => o.op === "push-failed-after-consume")).toEqual([failedReport("timeout")]);
    });

    test("the legacy path reports nothing and keeps its error shape", async () => {
      failing("remote: nope");
      await expect(pushBranch(opts({ commitSha: sha }))).rejects.toThrow(/^Git push failed: remote: nope$/);
      expect(h.reports).toEqual([]);
    });
  });
});
