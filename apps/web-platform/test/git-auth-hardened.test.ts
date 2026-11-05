/**
 * #11636: the HARDENED form of `gitWithInstallationAuth` (opt-in via `hardened: true`), with REAL git and real temp
 * repositories. Only the installation-token mint is replaced. The planted-hook tests prove the property that matters: a
 * `pre-push` hook (or a repo-config `core.hooksPath`) the agent planted in its writable workspace does not run on the
 * server-side push. A control with the legacy (unhardened) form proves the hook WOULD have run, so the absence is not vacuous.
 */
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

vi.mock("../server/github-app", () => ({ generateInstallationToken: async () => `ghs_${"a".repeat(40)}` }));
vi.mock("../server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }) }));

import { gitWithInstallationAuth } from "../server/git-auth";

const git = (cwd: string, ...args: string[]): string =>
  execFileSync("git", args, { cwd, stdio: "pipe", encoding: "utf8", env: gitFixtureEnv(cwd) }).trim();

function plantHook(dir: string, marker: string): void {
  mkdirSync(dir, { recursive: true });
  const hook = join(dir, "pre-push");
  writeFileSync(hook, `#!/bin/sh\necho ran > '${marker}'\nexit 0\n`);
  chmodSync(hook, 0o755);
}

describe("gitWithInstallationAuth hardened (real git)", () => {
  let root: string;
  let work: string;
  let remote: string;
  let marker: string;

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "git-hardened-"));
    remote = join(root, "remote.git");
    work = join(root, "work");
    marker = join(root, "marker");
    execFileSync("git", ["init", "--bare", "-q", remote], { env: gitFixtureEnv(root) });
    execFileSync("git", ["init", "-q", "-b", "main", work], { env: gitFixtureEnv(root) });
    git(work, "config", "user.name", "t");
    git(work, "config", "user.email", "t@example.invalid");
    git(work, "config", "commit.gpgsign", "false");
    writeFileSync(join(work, "a.txt"), "a\n");
    git(work, "add", ".");
    git(work, "commit", "-q", "-m", "A");
  });

  afterEach(() => rmSync(root, { recursive: true, force: true }));

  test("control: the legacy form runs a planted .git/hooks/pre-push", async () => {
    plantHook(join(work, ".git", "hooks"), marker);
    await gitWithInstallationAuth(["push", remote, "HEAD:refs/heads/feat-x"], 1, { cwd: work });
    expect(existsSync(marker)).toBe(true);
  });

  test("hardened: the push succeeds and a planted .git/hooks/pre-push does NOT run", async () => {
    plantHook(join(work, ".git", "hooks"), marker);
    await gitWithInstallationAuth(["push", remote, "HEAD:refs/heads/feat-x"], 1, { cwd: work, hardened: true });
    expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(git(work, "rev-parse", "HEAD"));
    expect(existsSync(marker)).toBe(false);
  });

  test("hardened: a repo-config core.hooksPath pointing at an attacker directory does NOT run", async () => {
    const evil = join(root, "evil-hooks");
    plantHook(evil, marker);
    git(work, "config", "core.hooksPath", evil);
    await gitWithInstallationAuth(["push", remote, "HEAD:refs/heads/feat-x"], 1, { cwd: work, hardened: true });
    expect(existsSync(marker)).toBe(false);
  });

  test("hardened: pushing to an unreachable URL fails and no planted hook ran", async () => {
    plantHook(join(work, ".git", "hooks"), marker);
    await expect(
      gitWithInstallationAuth(["push", "https://127.0.0.1:9/o/r.git", "HEAD:refs/heads/feat-x"], 1, {
        cwd: work,
        hardened: true,
        timeout: 20_000,
      }),
    ).rejects.toBeTruthy();
    expect(existsSync(marker)).toBe(false);
  });

  test("hardened without a cwd refuses before minting anything or running git", async () => {
    await expect(gitWithInstallationAuth(["push"], 1, { hardened: true })).rejects.toThrow(/requires the workspace cwd/);
  });
});
