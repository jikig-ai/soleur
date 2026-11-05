/**
 * #11636: `pushBranch` with `hardened: true` (the cc push). Real git and real temp repositories; the git children are observed
 * at the `execFileSync` seam (delegating to the real one) and the credential wrapper is replaced by a recorder.
 */
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { execFileSync as realExec } from "node:child_process";
import { cpSync, mkdtempSync, mkdirSync, renameSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

type Rec = { args: string[]; opts: { cwd?: string; env?: NodeJS.ProcessEnv; timeout?: number } };
const { execCalls, authCalls } = vi.hoisted(() => ({ execCalls: [] as unknown[], authCalls: [] as unknown[] }));

vi.mock("child_process", async () => {
  const actual = await vi.importActual<typeof import("child_process")>("child_process");
  return {
    ...actual,
    execFileSync: (cmd: string, args: string[], opts: Rec["opts"]) => {
      execCalls.push({ args, opts });
      return actual.execFileSync(cmd, args, { ...opts, env: opts.env ?? gitFixtureEnv(opts.cwd ?? "/") });
    },
  };
});
vi.mock("../server/git-auth", () => ({
  gitWithInstallationAuth: async (args: string[], id: number, opts: unknown) => {
    authCalls.push({ args, id, opts });
    return Buffer.from("");
  },
}));
vi.mock("../server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }) }));

import { pushBranch } from "../server/push-branch";
import { GIT_HARDENING_ARGS } from "../server/inngest/functions/_git-hardening";
import { HARDENED_GIT_ARGS } from "../server/git-hardened-env";

const git = (cwd: string, ...args: string[]): string =>
  realExec("git", args, { cwd, stdio: "pipe", encoding: "utf8", env: gitFixtureEnv(cwd) }).trim();

describe("pushBranch hardened", () => {
  let root: string;
  let work: string;
  let sha: string;

  const opts = (extra: Record<string, unknown> = {}) => ({
    installationId: 1,
    owner: "o",
    repo: "r",
    workspacePath: work,
    branch: "feat-x",
    force: false,
    ...extra,
  });

  beforeEach(() => {
    execCalls.length = 0;
    authCalls.length = 0;
    root = mkdtempSync(join(tmpdir(), "push-hard-"));
    work = join(root, "work");
    realExec("git", ["init", "-q", "-b", "main", work], { env: gitFixtureEnv(root) });
    git(work, "config", "user.name", "t");
    git(work, "config", "user.email", "t@example.invalid");
    git(work, "config", "commit.gpgsign", "false");
    writeFileSync(join(work, "a.txt"), "a\n");
    git(work, "add", ".");
    git(work, "commit", "-q", "-m", "A");
    sha = git(work, "rev-parse", "HEAD");
    execCalls.length = 0;
  });

  afterEach(() => {
    rmSync(root, { recursive: true, force: true });
    delete process.env.SOLEUR_TEST_SECRET_CANARY;
  });

  test("hardened: the push call carries hardened:true and the cat-file and config calls get hardening args and an allowlisted env", async () => {
    process.env.SOLEUR_TEST_SECRET_CANARY = "canary-value";
    await pushBranch(opts({ commitSha: sha, hardened: true }));
    expect((authCalls[0] as { opts: unknown }).opts).toEqual({ cwd: work, timeout: 120_000, hardened: true });
    const calls = execCalls as Rec[];
    const verbs = calls.map((c) => c.args.find((a) => ["cat-file", "config"].includes(a)));
    expect(verbs).toEqual(["cat-file", "config", "config"]);
    for (const c of calls) {
      expect(c.args.slice(0, GIT_HARDENING_ARGS.length)).toEqual([...GIT_HARDENING_ARGS]);
      expect(c.args.slice(0, HARDENED_GIT_ARGS.length)).toEqual([...HARDENED_GIT_ARGS]);
      expect(c.args).toContain("http.proxy=");
      expect(c.args).toContain("push.followTags=false");
      expect(c.opts.env?.SOLEUR_TEST_SECRET_CANARY).toBeUndefined();
      expect(c.opts.env?.GIT_DIR).toBe(join(work, ".git"));
      expect(c.opts.env?.GIT_COMMON_DIR).toBe(join(work, ".git"));
      expect(c.opts.env?.GIT_OBJECT_DIRECTORY).toBe(join(work, ".git", "objects"));
      expect(c.opts.env?.GIT_CEILING_DIRECTORIES).toBe(root);
      // The same config isolation on EVERY child (not only the push): no global or system config, no replace objects, https only.
      expect(c.opts.env?.GIT_CONFIG_GLOBAL).toBe("/dev/null");
      expect(c.opts.env?.GIT_CONFIG_SYSTEM).toBe("/dev/null");
      expect(c.opts.env?.GIT_CONFIG_NOSYSTEM).toBe("1");
      expect(c.opts.env?.GIT_NO_REPLACE_OBJECTS).toBe("1");
      expect(c.opts.env?.GIT_ALLOW_PROTOCOL).toBe("https");
      // A FIFO planted in .git must not freeze the server: every synchronous child is bounded.
      expect(c.opts.timeout).toBe(10_000);
    }
  });

  test("legacy (field unset): no hardening args, no env option, and the push options carry no hardened key", async () => {
    await pushBranch(opts({ commitSha: sha }));
    const calls = execCalls as Rec[];
    expect(calls.map((c) => c.args)).toEqual([
      ["cat-file", "-e", `${sha}^{commit}`],
      ["config", "user.name", "Soleur Agent"],
      ["config", "user.email", "agent@soleur.ai"],
    ]);
    for (const c of calls) {
      expect("env" in c.opts).toBe(false);
      expect("timeout" in c.opts).toBe(false);
    }
    expect((authCalls[0] as { opts: object }).opts).toStrictEqual({ cwd: work, timeout: 120_000 });
  });

  /** Every refusal is the typed, static one, attributed to the plain-directory check: the message is asserted and NO git child ran. */
  async function expectPlainDirRefusal(): Promise<void> {
    const p = pushBranch(opts({ commitSha: sha, hardened: true }));
    await expect(p).rejects.toMatchObject({ name: "ApprovedCommitUnavailableError" });
    await expect(pushBranch(opts({ commitSha: sha, hardened: true }))).rejects.toThrow(/^Workspace git directory is not a plain repository directory$/);
    expect(authCalls).toHaveLength(0);
    expect(execCalls).toHaveLength(0);
  }

  test("refuses (typed, static text, nothing pushed) when .git is a FILE", async () => {
    rmSync(join(work, ".git"), { recursive: true });
    writeFileSync(join(work, ".git"), `gitdir: ${join(root, "elsewhere")}\n`);
    await expectPlainDirRefusal();
  });

  test("refuses when .git is a SYMLINK to a real repository that CONTAINS the approved commit (so only the check, not a missing commit, can refuse)", async () => {
    const real = join(root, "real-git");
    cpSync(join(work, ".git"), real, { recursive: true });
    expect(git(work, "--git-dir", real, "cat-file", "-t", sha)).toBe("commit");
    execCalls.length = 0;
    rmSync(join(work, ".git"), { recursive: true });
    symlinkSync(real, join(work, ".git"));
    await expectPlainDirRefusal();
  });

  test("refuses when .git is missing", async () => {
    rmSync(join(work, ".git"), { recursive: true });
    await expectPlainDirRefusal();
  });

  // Entries git reads or writes THROUGH: each moved aside (so the target is a real, complete copy that contains the approved
  // commit) and replaced by a symlink to it. Mirrors GIT_DIR_NO_SYMLINK_ENTRIES in _cron-safe-commit.ts.
  test.each(["config", "HEAD", "objects", "refs", "hooks", "info", "index"])("refuses when .git/%s is a symlink to a complete copy of it", async (entry) => {
    const aside = join(root, `aside-${entry}`);
    renameSync(join(work, ".git", entry), aside);
    symlinkSync(aside, join(work, ".git", entry));
    await expectPlainDirRefusal();
  });

  // Files whose existence redirects where git reads objects, refs or config from. Mirrors GIT_DIR_REDIRECT_FILES (the refusing subset).
  test.each(["commondir", "config.worktree", "objects/info/alternates", "objects/info/http-alternates", "info/grafts"])(
    "refuses when .git/%s exists",
    async (rel) => {
      const file = join(work, ".git", rel);
      mkdirSync(join(file, ".."), { recursive: true });
      writeFileSync(file, `${join(root, "other")}\n`);
      await expectPlainDirRefusal();
    },
  );

  test("a normal repository passes the check (info/exclude, hooks samples and a packed-refs file are not refusals)", async () => {
    git(work, "pack-refs", "--all");
    await pushBranch(opts({ commitSha: sha, hardened: true }));
    expect(authCalls).toHaveLength(1);
  });

  test("the legacy path does NOT run the lstat refusal (a .git file still reaches the push)", async () => {
    rmSync(join(work, ".git"), { recursive: true });
    writeFileSync(join(work, ".git"), "gitdir: /nonexistent\n");
    await pushBranch(opts());
    expect(authCalls).toHaveLength(1);
  });
});
