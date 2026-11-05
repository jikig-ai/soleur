/**
 * #11636: `pushBranch` with `hardened: true` (the cc push). Real git and real temp repositories; the git children are observed
 * at the `execFileSync` seam (delegating to the real one) and the credential wrapper is replaced by a recorder.
 */
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { execFileSync as realExec } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

type Rec = { args: string[]; opts: { cwd?: string; env?: NodeJS.ProcessEnv } };
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
      expect(c.args).toContain("http.proxy=");
      expect(c.opts.env?.SOLEUR_TEST_SECRET_CANARY).toBeUndefined();
      expect(c.opts.env?.GIT_DIR).toBe(join(work, ".git"));
      expect(c.opts.env?.GIT_CEILING_DIRECTORIES).toBe(root);
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
    for (const c of calls) expect("env" in c.opts).toBe(false);
    expect((authCalls[0] as { opts: object }).opts).toStrictEqual({ cwd: work, timeout: 120_000 });
  });

  test("refuses (typed, static text, nothing pushed) when .git is a FILE", async () => {
    rmSync(join(work, ".git"), { recursive: true });
    writeFileSync(join(work, ".git"), `gitdir: ${join(root, "elsewhere")}\n`);
    const p = pushBranch(opts({ commitSha: sha, hardened: true }));
    await expect(p).rejects.toMatchObject({ name: "ApprovedCommitUnavailableError" });
    await expect(pushBranch(opts({ commitSha: sha, hardened: true }))).rejects.toThrow(/not a plain repository directory/);
    expect(authCalls).toHaveLength(0);
    expect(execCalls).toHaveLength(0);
  });

  test("refuses when .git is a SYMLINK to a real repository", async () => {
    const real = join(root, "real-git");
    realExec("git", ["init", "-q", "-b", "main", real], { env: gitFixtureEnv(root) });
    rmSync(join(work, ".git"), { recursive: true });
    symlinkSync(join(real, ".git"), join(work, ".git"));
    await expect(pushBranch(opts({ commitSha: sha, hardened: true }))).rejects.toMatchObject({ name: "ApprovedCommitUnavailableError" });
    expect(authCalls).toHaveLength(0);
  });

  test("refuses when .git is missing", async () => {
    rmSync(join(work, ".git"), { recursive: true });
    await expect(pushBranch(opts({ commitSha: sha, hardened: true }))).rejects.toMatchObject({ name: "ApprovedCommitUnavailableError" });
  });

  test("refuses when objects/info/alternates exists", async () => {
    mkdirSync(join(work, ".git", "objects", "info"), { recursive: true });
    writeFileSync(join(work, ".git", "objects", "info", "alternates"), `${join(root, "other-objects")}\n`);
    await expect(pushBranch(opts({ commitSha: sha, hardened: true }))).rejects.toThrow(/not a plain repository directory/);
    expect(authCalls).toHaveLength(0);
  });

  test("the legacy path does NOT run the lstat refusal (a .git file still reaches the push)", async () => {
    rmSync(join(work, ".git"), { recursive: true });
    writeFileSync(join(work, ".git"), "gitdir: /nonexistent\n");
    await pushBranch(opts());
    expect(authCalls).toHaveLength(1);
  });
});
