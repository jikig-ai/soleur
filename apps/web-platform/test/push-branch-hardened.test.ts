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
  authCalls: [] as Array<{ args: string[]; id: number; opts: { hardened?: { gitDir: string; alternateObjectDirectory: string }; cwd?: string; timeout?: number } }>,
  authImpl: null as null | (() => Promise<Buffer>),
  reports: [] as Array<[unknown, { feature: string; op: string; extra?: Record<string, unknown> }]>,
  disposeThrows: false,
  handles: [] as string[],
}));

vi.mock("child_process", async () => {
  const actual = await vi.importActual<typeof import("child_process")>("child_process");
  return {
    ...actual,
    execFileSync: (cmd: string, args: string[], opts: Rec["opts"]) => {
      h.execCalls.push({ args, opts });
      return actual.execFileSync(cmd, args, { ...opts, env: opts.env ?? gitFixtureEnv(opts.cwd ?? "/") });
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
      const real = actual.createIsolatedPushDir(ws);
      h.handles.push(real.gitDir);
      if (!h.disposeThrows) return real;
      return Object.assign(Object.create(Object.getPrototypeOf(real)), real, {
        dispose: () => {
          real.dispose();
          throw new Error(`EBUSY at ${real.gitDir}`);
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
    test("pushes <sha>:refs/heads/<branch> from the isolated directory (no cwd), after ONE cat-file in that directory and NO git config call", async () => {
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
      expect(calls.map((c) => c.args.filter((a) => ["cat-file", "config"].includes(a)))).toEqual([["cat-file"]]);
      const c = calls[0];
      expect(c.args.slice(0, GIT_HARDENING_ARGS.length)).toEqual([...GIT_HARDENING_ARGS]);
      expect(c.args.slice(0, HARDENED_GIT_ARGS.length)).toEqual([...HARDENED_GIT_ARGS]);
      expect(c.args.slice(-3)).toEqual(["cat-file", "-e", `${sha}^{commit}`]);
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
        expect(o).toEqual({ feature: "cc-push", op: "isolated-dir-refused", extra: { reason } });
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
      expect(h.reports).toEqual([[null, { feature: "cc-push", op: "isolated-dir-refused", extra: { reason: "sha_invalid" } }]]);
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
      expect(h.reports).toEqual([[null, { feature: "cc-push", op: "isolated-dir-refused", extra: { reason: "commit_absent" } }]]);
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
      expect((err as Error).message).toBe("Push could not be prepared");
      expect((err as Error).cause).toBeUndefined();
      expect(h.reports).toEqual([[null, { feature: "cc-push", op: "isolated-dir-refused", extra: { reason: "setup_failed" } }]]);
      expect(h.authCalls).toHaveLength(0);
      expect(readdirSync(join(root, "tmp"))).toEqual([]);
    });

    test("a PATH entry under the workspace is refused as infrastructure (env_path_unsafe), not as a tampered repository", async () => {
      const bin = join(work, "bin");
      mkdirSync(bin);
      const savedPath = process.env.PATH;
      process.env.PATH = `${bin}:${savedPath ?? ""}`;
      try {
        await expect(pushBranch(hardenedOpts())).rejects.toMatchObject({ name: "Error", message: "Push could not be prepared" });
      } finally {
        process.env.PATH = savedPath;
      }
      expect(h.reports).toEqual([[null, { feature: "cc-push", op: "isolated-dir-refused", extra: { reason: "env_path_unsafe" } }]]);
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
      expect(r).toEqual([[null, { feature: "cc-push", op: "isolated-dir-dispose-failed", extra: { class: "Error" } }]]);
      expect(JSON.stringify(r)).not.toContain(home);
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
      expect(r).toEqual([[null, { feature: "cc-push", op: "push-failed-after-consume", extra: { class: cls } }]]);
    });

    test("a timeout says the push MAY have landed (never reads as 'nothing landed') and is reported as class timeout", async () => {
      failing("", { killed: true, signal: "SIGTERM" });
      const p = pushBranch(hardenedOpts());
      await expect(p).rejects.toThrow(/MAY have landed/);
      await expect(p).rejects.toThrow(/^Git push failed: /);
      expect(h.reports.filter(([, o]) => o.op === "push-failed-after-consume")).toEqual([
        [null, { feature: "cc-push", op: "push-failed-after-consume", extra: { class: "timeout" } }],
      ]);
    });

    test("the legacy path reports nothing and keeps its error shape", async () => {
      failing("remote: nope");
      await expect(pushBranch(opts({ commitSha: sha }))).rejects.toThrow(/^Git push failed: remote: nope$/);
      expect(h.reports).toEqual([]);
    });
  });
});
