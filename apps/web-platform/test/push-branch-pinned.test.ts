/**
 * #4672 R1 (CTO ruling 1): `pushBranch` with a pinned `commitSha` pushes exactly the approved commit, even when HEAD
 * moved while the approval was pending. Real git, real temp repositories (a workspace and a bare "remote"); only the
 * credential-injecting wrapper is replaced by a plain `git <args>` run against the local bare repository.
 */
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const { state } = vi.hoisted(() => ({ state: { remote: "" } }));

vi.mock("../server/git-auth", () => ({
  // Swap the github URL for the local bare repository; everything else (refspec) is exactly what production passes.
  gitWithInstallationAuth: async (args: string[], _id: number, opts: { cwd: string }) => {
    const rewritten = args.map((a) => (a.startsWith("https://github.com/") ? state.remote : a));
    return execFileSync("git", rewritten, { cwd: opts.cwd, stdio: "pipe" });
  },
}));
vi.mock("../server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }) }));

import { pushBranch } from "../server/push-branch";

const git = (cwd: string, ...args: string[]): string =>
  execFileSync("git", args, { cwd, stdio: "pipe", encoding: "utf8" }).trim();

describe("pushBranch pinned commit (real git)", () => {
  let root: string;
  let work: string;
  let shaA: string;
  let shaB: string;

  const opts = (extra: Partial<Parameters<typeof pushBranch>[0]> = {}) => ({
    installationId: 1,
    owner: "o",
    repo: "r",
    workspacePath: work,
    branch: "feat-x",
    force: false,
    ...extra,
  });

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "push-pin-"));
    state.remote = join(root, "remote.git");
    work = join(root, "work");
    execFileSync("git", ["init", "--bare", "-q", state.remote]);
    execFileSync("git", ["init", "-q", "-b", "main", work]);
    git(work, "config", "user.name", "t");
    git(work, "config", "user.email", "t@example.invalid");
    git(work, "config", "commit.gpgsign", "false");
    writeFileSync(join(work, "a.txt"), "approved\n");
    git(work, "add", ".");
    git(work, "commit", "-q", "-m", "A");
    shaA = git(work, "rev-parse", "HEAD");
    // The commit made while the approval was pending (an agent background process).
    writeFileSync(join(work, "b.txt"), "NOT approved\n");
    git(work, "add", ".");
    git(work, "commit", "-q", "-m", "B");
    shaB = git(work, "rev-parse", "HEAD");
  });

  afterEach(() => rmSync(root, { recursive: true, force: true }));

  test("approve at A, HEAD moves to B: the remote branch ends at A, not B", async () => {
    expect(shaA).not.toBe(shaB);
    await pushBranch(opts({ commitSha: shaA }));
    expect(git(state.remote, "rev-parse", "refs/heads/feat-x")).toBe(shaA);
    expect(() => git(state.remote, "cat-file", "-e", `${shaB}^{commit}`)).toThrow();
  });

  test("without a pin the legacy behaviour pushes HEAD (B)", async () => {
    await pushBranch(opts());
    expect(git(state.remote, "rev-parse", "refs/heads/feat-x")).toBe(shaB);
  });

  test("a sha that is absent from the repository throws and the remote branch is not created", async () => {
    await expect(pushBranch(opts({ commitSha: "c".repeat(40) }))).rejects.toThrow(/not present/);
    expect(() => git(state.remote, "rev-parse", "refs/heads/feat-x")).toThrow();
  });

  test("an invalid sha throws", async () => {
    await expect(pushBranch(opts({ commitSha: "HEAD" }))).rejects.toThrow(/valid full commit sha/);
  });
});
