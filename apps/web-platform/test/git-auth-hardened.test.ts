/**
 * #11636 / ADR-309 9b: the HARDENED form of `gitWithInstallationAuth` (opt-in via `hardened: <isolated push directory>`), with
 * REAL git and real temp repositories. Only the installation-token mint is replaced. The planted-hook tests prove the property
 * that matters: a `pre-push` hook (or a repo-config `core.hooksPath`) the agent planted in its writable workspace does not run
 * on the server-side push. A control with the legacy (unhardened) form proves the hook WOULD have run, so the absence is not
 * vacuous.
 */
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
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
    buildIsolatedGitEnv: (dir: import("../server/git-hardened-env").IsolatedPushDir, extra: Readonly<Record<string, string>> = {}) =>
      // `extra` can no longer override the pinned protocol (A2), so the test-only widening is applied to the RESULT.
      ({ ...actual.buildIsolatedGitEnv(dir, extra), ...(h.allowFile ? { GIT_ALLOW_PROTOCOL: "https:file" } : {}) }),
  };
});

import { gitWithInstallationAuth } from "../server/git-auth";
import { createIsolatedPushDir, type IsolatedPushDirHandle } from "../server/git-isolated-push-dir";

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

  // The LEGACY form inherits `process.env`. `scripts/test-all.sh` exports `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0=core.hooksPath`
  // (the battery ref guard) to its whole process tree, which would displace the planted `.git/hooks/pre-push` and turn every
  // "legacy runs the hook" control red in CI only. Strip the count-indexed env config for the file so the controls measure git,
  // not the runner; the hardened form builds its own environment and never sees it either way.
  const savedGitConfigEnv: Record<string, string | undefined> = {};
  const savedEnv: Record<string, string | undefined> = {};
  let sha: string;
  let iso: IsolatedPushDirHandle | undefined;
  /** The hardened option for `work`: a fresh isolated directory (disposed in afterEach). */
  const isolate = (): IsolatedPushDirHandle => (iso = createIsolatedPushDir(work));
  const ref = (): string => `${sha}:refs/heads/feat-x`;

  beforeEach(() => {
    for (const k of Object.keys(process.env)) {
      if (k === "GIT_CONFIG_COUNT" || k === "GIT_CONFIG_PARAMETERS" || /^GIT_CONFIG_(KEY|VALUE)_\d+$/.test(k)) {
        savedGitConfigEnv[k] = process.env[k];
        delete process.env[k];
      }
    }
    h.allowFile = true;
    h.mint.mockClear();
    for (const k of ["HOME", "TMPDIR"]) savedEnv[k] = process.env[k];
    root = realpathSync(mkdtempSync(join(tmpdir(), "git-hardened-")));
    // The isolated directory lives under HOME (never TMPDIR); both are private to this test.
    mkdirSync(join(root, "home"));
    mkdirSync(join(root, "tmp"));
    process.env.HOME = join(root, "home");
    process.env.TMPDIR = join(root, "tmp");
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
    sha = git(work, "rev-parse", "HEAD");
  });

  afterEach(() => {
    iso?.dispose();
    iso = undefined;
    for (const [k, v] of Object.entries(savedEnv)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
    rmSync(root, { recursive: true, force: true });
    for (const [k, v] of Object.entries(savedGitConfigEnv)) {
      if (v !== undefined) process.env[k] = v;
      delete savedGitConfigEnv[k];
    }
  });

  test("control: the legacy form runs a planted .git/hooks/pre-push", async () => {
    plantHook(join(work, ".git", "hooks"), marker);
    await gitWithInstallationAuth(["push", remote, "HEAD:refs/heads/feat-x"], 1, { cwd: work });
    expect(existsSync(marker)).toBe(true);
  });

  test("hardened: the push succeeds and a planted .git/hooks/pre-push does NOT run", async () => {
    plantHook(join(work, ".git", "hooks"), marker);
    await gitWithInstallationAuth(["push", remote, ref()], 1, { hardened: isolate() });
    expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(git(work, "rev-parse", "HEAD"));
    expect(existsSync(marker)).toBe(false);
  });

  test("hardened: a repo-config core.hooksPath pointing at an attacker directory does NOT run", async () => {
    const evil = join(root, "evil-hooks");
    plantHook(evil, marker);
    git(work, "config", "core.hooksPath", evil);
    await gitWithInstallationAuth(["push", remote, ref()], 1, { hardened: isolate() });
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
    await expect(gitWithInstallationAuth(["push", remote, ref()], 1, { hardened: isolate() })).rejects.toBeTruthy();
    expect(existsSync(marker)).toBe(false);
    expect(() => git(remote, "rev-parse", "refs/heads/feat-x")).toThrow();
  });

  test("hardened: with the production clamp (GIT_ALLOW_PROTOCOL=https) a local-path push is refused, not performed", async () => {
    h.allowFile = false;
    await expect(gitWithInstallationAuth(["push", remote, ref()], 1, { hardened: isolate() })).rejects.toBeTruthy();
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
    await expect(gitWithInstallationAuth(["push", url, ref()], 1, { hardened: isolate() })).rejects.toBeTruthy();
    expect(existsSync(marker)).toBe(false);
  });

  test("control + hardened: a repo-config push.followTags=true sends an annotated tag along in the legacy form, not in the hardened one", async () => {
    git(work, "config", "push.followTags", "true");
    git(work, "tag", "-a", "-m", "t", "v1");
    await gitWithInstallationAuth(["push", remote, "HEAD:refs/heads/feat-x"], 1, { cwd: work });
    expect(git(remote, "tag", "--list")).toBe("v1");
    git(remote, "tag", "-d", "v1");
    git(remote, "branch", "-D", "feat-x");
    await gitWithInstallationAuth(["push", remote, ref()], 1, { hardened: isolate() });
    expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(git(work, "rev-parse", "HEAD"));
    expect(git(remote, "tag", "--list")).toBe("");
  });

  test("hardened with a stray true, or with a caller cwd, refuses BEFORE minting a token or running git", async () => {
    await expect(gitWithInstallationAuth(["push"], 1, { hardened: true } as never)).rejects.toThrow(/isolated push directory/);
    expect(h.mint).not.toHaveBeenCalled();
    await expect(gitWithInstallationAuth(["push"], 1, { hardened: isolate(), cwd: work })).rejects.toThrow(/no cwd/);
    expect(h.mint).not.toHaveBeenCalled();
  });

  test("hardened: the push runs from the isolated directory with the workspace objects only as an alternate (the commit is not in the isolated objects)", async () => {
    const dir = isolate();
    expect(() => execFileSync("git", ["cat-file", "-e", `${sha}^{commit}`], { env: { ...gitFixtureEnv(root), GIT_DIR: dir.gitDir }, stdio: "pipe" })).toThrow();
    await gitWithInstallationAuth(["push", remote, ref()], 1, { hardened: dir });
    expect(git(remote, "rev-parse", "refs/heads/feat-x")).toBe(sha);
  });
});
