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

// `allowFile`: these tests push to a LOCAL bare remote (the file transport), which the production clamp
// (`GIT_ALLOW_PROTOCOL=https`) forbids by design. The wrapper below adds `file` to the allowed set for the tests that need a real
// transport and leaves the production value untouched when `allowFile` is false (the clamp tests).
const h = vi.hoisted(() => ({ mint: vi.fn(async () => `ghs_${"a".repeat(40)}`), allowFile: true }));
vi.mock("../server/github-app", () => ({ generateInstallationToken: h.mint }));
vi.mock("../server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }) }));
vi.mock("../server/git-hardened-env", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../server/git-hardened-env")>();
  return {
    ...actual,
    buildHardenedGitEnv: (workspacePath: string, extra: Readonly<Record<string, string>> = {}) =>
      actual.buildHardenedGitEnv(workspacePath, h.allowFile ? { ...extra, GIT_ALLOW_PROTOCOL: "https:file" } : extra),
  };
});

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
    h.allowFile = true;
    h.mint.mockClear();
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

  /** A bare remote whose `pre-receive` rejects every push: the transport connects, the local `pre-push` hook is reached, the push fails. */
  function rejectingRemote(): void {
    const hook = join(remote, "hooks", "pre-receive");
    writeFileSync(hook, "#!/bin/sh\necho rejected >&2\nexit 1\n");
    chmodSync(hook, 0o755);
  }

  test("control: the legacy form, pushing to a remote that REJECTS the push, fails AND runs the planted pre-push hook", async () => {
    rejectingRemote();
    plantHook(join(work, ".git", "hooks"), marker);
    await expect(gitWithInstallationAuth(["push", remote, "HEAD:refs/heads/feat-x"], 1, { cwd: work })).rejects.toBeTruthy();
    expect(existsSync(marker)).toBe(true);
  });

  test("hardened: pushing to a remote that REJECTS the push fails and the planted pre-push hook does NOT run", async () => {
    rejectingRemote();
    plantHook(join(work, ".git", "hooks"), marker);
    await expect(gitWithInstallationAuth(["push", remote, "HEAD:refs/heads/feat-x"], 1, { cwd: work, hardened: true })).rejects.toBeTruthy();
    expect(existsSync(marker)).toBe(false);
    expect(() => git(remote, "rev-parse", "refs/heads/feat-x")).toThrow();
  });

  test("hardened: with the production clamp (GIT_ALLOW_PROTOCOL=https) a local-path push is refused, not performed", async () => {
    h.allowFile = false;
    await expect(gitWithInstallationAuth(["push", remote, "HEAD:refs/heads/feat-x"], 1, { cwd: work, hardened: true })).rejects.toBeTruthy();
    expect(() => git(remote, "rev-parse", "refs/heads/feat-x")).toThrow();
  });

  test("control + hardened: a repo-config protocol.ext.allow=always does not let an ext:: URL run a command under the hardened form", async () => {
    git(work, "config", "protocol.ext.allow", "always");
    const url = `ext::touch ${marker}`;
    // Control: the legacy form honours the repo config and runs the command, so the absence below is meaningful.
    await expect(gitWithInstallationAuth(["push", url, "HEAD:refs/heads/feat-x"], 1, { cwd: work })).rejects.toBeTruthy();
    expect(existsSync(marker)).toBe(true);
    rmSync(marker);
    h.allowFile = false;
    await expect(gitWithInstallationAuth(["push", url, "HEAD:refs/heads/feat-x"], 1, { cwd: work, hardened: true })).rejects.toBeTruthy();
    expect(existsSync(marker)).toBe(false);
  });

  test("control + hardened: a repo-config push.followTags=true sends an annotated tag along in the legacy form, not in the hardened one", async () => {
    git(work, "config", "push.followTags", "true");
    git(work, "tag", "-a", "-m", "t", "v1");
    await gitWithInstallationAuth(["push", remote, "HEAD:refs/heads/feat-x"], 1, { cwd: work });
    expect(git(remote, "tag", "--list")).toBe("v1");
    git(remote, "tag", "-d", "v1");
    git(remote, "branch", "-D", "feat-x");
    await gitWithInstallationAuth(["push", remote, "HEAD:refs/heads/feat-x"], 1, { cwd: work, hardened: true });
    expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(git(work, "rev-parse", "HEAD"));
    expect(git(remote, "tag", "--list")).toBe("");
  });

  test("hardened without a cwd refuses BEFORE minting a token or running git", async () => {
    await expect(gitWithInstallationAuth(["push"], 1, { hardened: true })).rejects.toThrow(/requires the workspace cwd/);
    expect(h.mint).not.toHaveBeenCalled();
  });
});
