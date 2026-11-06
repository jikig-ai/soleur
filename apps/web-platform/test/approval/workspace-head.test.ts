/**
 * ADR-309 flip item 9b: the gate's workspace-HEAD reader (`readWorkspaceHeadSha`). It reads data and executes no git, so the
 * agent-writable `.git/config`, an inherited `GIT_DIR` and a planted `commondir` cannot change what the gate displays.
 *
 * Real git builds the fixtures and is the oracle for the differential tests; the reader itself is asserted to spawn nothing
 * (a spawn counter over `child_process`) and to import only `node:fs` / `node:path` / `./canonical` (a content test).
 */
import { execFileSync } from "node:child_process";
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { gitFixtureEnv } from "../../../../plugins/soleur/test/lib/git-fixture-env";
import { stripComments } from "./source-scan";

const spawns = vi.hoisted(() => ({ n: 0 }));
vi.mock("node:child_process", async () => {
  const actual = await vi.importActual<typeof import("node:child_process")>("node:child_process");
  return {
    ...actual,
    execFile: (...a: unknown[]) => {
      spawns.n++;
      return (actual.execFile as (...x: unknown[]) => unknown)(...a);
    },
    execFileSync: (...a: unknown[]) => {
      spawns.n++;
      return (actual.execFileSync as (...x: unknown[]) => unknown)(...a);
    },
    spawn: (...a: unknown[]) => {
      spawns.n++;
      return (actual.spawn as (...x: unknown[]) => unknown)(...a);
    },
    spawnSync: (...a: unknown[]) => {
      spawns.n++;
      return (actual.spawnSync as (...x: unknown[]) => unknown)(...a);
    },
  };
});

import { WorkspaceHeadUnreadable, readSmallRegularFile, readWorkspaceHeadSha } from "../../server/approval/workspace-head";

const roots: string[] = [];
afterAll(() => {
  for (const r of roots) rmSync(r, { recursive: true, force: true });
});

const git = (cwd: string, ...args: string[]): string =>
  execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.test", ...args], {
    cwd,
    stdio: "pipe",
    encoding: "utf8",
    env: gitFixtureEnv(cwd),
  }).trim();

function mkRoot(): string {
  const r = mkdtempSync(join(tmpdir(), "ws-head-"));
  roots.push(r);
  return r;
}

function mkRepo(commits = 1): { dir: string; head: string } {
  const dir = join(mkRoot(), "ws");
  mkdirSync(dir);
  git(dir, "init", "-q", "-b", "main");
  for (let i = 0; i < commits; i++) {
    writeFileSync(join(dir, `f${i}.txt`), `content ${i}`);
    git(dir, "add", ".");
    git(dir, "commit", "-q", "-m", `c${i}`);
  }
  return { dir, head: git(dir, "rev-parse", "HEAD") };
}

function mkFifo(path: string): void {
  execFileSync("mkfifo", [path]);
}

/** The reader refused, with a typed error carrying a closed reason. */
function refusal(dir: string): WorkspaceHeadUnreadable {
  try {
    readWorkspaceHeadSha(dir);
  } catch (err) {
    expect(err).toBeInstanceOf(WorkspaceHeadUnreadable);
    return err as WorkspaceHeadUnreadable;
  }
  throw new Error("expected the reader to refuse");
}

let savedGitDir: string | undefined;
const savedGitConfigEnv: Record<string, string | undefined> = {};
beforeEach(() => {
  spawns.n = 0;
  savedGitDir = process.env.GIT_DIR;
  // scripts/test-all.sh injects a count-indexed core.hooksPath env; the fixtures must measure git, not the runner.
  for (const k of Object.keys(process.env)) {
    if (k === "GIT_CONFIG_COUNT" || k === "GIT_CONFIG_PARAMETERS" || /^GIT_CONFIG_(KEY|VALUE)_\d+$/.test(k)) {
      savedGitConfigEnv[k] = process.env[k];
      delete process.env[k];
    }
  }
});
afterEach(() => {
  if (savedGitDir === undefined) delete process.env.GIT_DIR;
  else process.env.GIT_DIR = savedGitDir;
  for (const [k, v] of Object.entries(savedGitConfigEnv)) {
    if (v !== undefined) process.env[k] = v;
    delete savedGitConfigEnv[k];
  }
});

describe("readWorkspaceHeadSha: what it returns", () => {
  test("symbolic HEAD to a loose ref", () => {
    const { dir, head } = mkRepo();
    const before = spawns.n;
    expect(readWorkspaceHeadSha(dir)).toBe(head);
    expect(spawns.n).toBe(before);
  });

  test("detached HEAD (a bare 40-hex body)", () => {
    const { dir, head } = mkRepo(2);
    git(dir, "checkout", "-q", "--detach", "HEAD~1");
    const detached = git(dir, "rev-parse", "HEAD");
    expect(detached).not.toBe(head);
    expect(readFileSync(join(dir, ".git", "HEAD"), "utf8").trim()).toBe(detached);
    expect(readWorkspaceHeadSha(dir)).toBe(detached);
  });

  test("a packed-only branch (git gc --auto style pack-refs --all)", () => {
    const { dir, head } = mkRepo();
    git(dir, "pack-refs", "--all");
    expect(() => readFileSync(join(dir, ".git", "refs", "heads", "main"))).toThrow(); // precondition: no loose file
    expect(readFileSync(join(dir, ".git", "packed-refs"), "utf8")).toContain(`${head} refs/heads/main`);
    expect(readWorkspaceHeadSha(dir)).toBe(head);
  });

  test("a packed-only branch among several packed refs returns the sha of THE NAMED ref, not of the first line", () => {
    const { dir, head } = mkRepo(2);
    git(dir, "branch", "aaa", "HEAD~1");
    const other = git(dir, "rev-parse", "aaa");
    expect(other).not.toBe(head);
    git(dir, "pack-refs", "--all");
    const packed = readFileSync(join(dir, ".git", "packed-refs"), "utf8");
    expect(packed.indexOf(`${other} refs/heads/aaa`)).toBeGreaterThan(-1); // precondition: the other branch is packed too ...
    expect(packed.indexOf(`${other} refs/heads/aaa`)).toBeLessThan(packed.indexOf(`${head} refs/heads/main`)); // ... and listed first
    expect(readWorkspaceHeadSha(dir)).toBe(head);
  });

  test("a loose ref shadows a stale packed entry", () => {
    const { dir, head } = mkRepo();
    git(dir, "pack-refs", "--all");
    writeFileSync(join(dir, "g.txt"), "g");
    git(dir, "add", ".");
    git(dir, "commit", "-q", "-m", "next");
    const next = git(dir, "rev-parse", "HEAD");
    expect(next).not.toBe(head);
    expect(readFileSync(join(dir, ".git", "packed-refs"), "utf8")).toContain(head); // precondition: the stale entry is still there
    expect(readWorkspaceHeadSha(dir)).toBe(next);
  });

  test("packed-refs peeled (^) and header lines are skipped; a tag does not shadow the branch", () => {
    const { dir, head } = mkRepo();
    git(dir, "tag", "-a", "-m", "t", "v1");
    git(dir, "pack-refs", "--all");
    const packed = readFileSync(join(dir, ".git", "packed-refs"), "utf8");
    expect(packed).toMatch(/^#/);
    expect(packed).toMatch(/^\^[0-9a-f]{40}$/m); // precondition: a peeled line exists
    expect(readWorkspaceHeadSha(dir)).toBe(head);
  });

  test("agrees with real git for fixtures built by git (depth-1 clone, gc, pack-refs, detach, shadowed packed ref)", () => {
    const src = mkRepo(3);
    const cloneRoot = mkRoot();
    const clone = join(cloneRoot, "clone");
    execFileSync("git", ["clone", "-q", "--depth", "1", `file://${src.dir}`, clone], {
      stdio: "pipe",
      env: gitFixtureEnv(cloneRoot),
    });
    expect(readWorkspaceHeadSha(clone)).toBe(git(clone, "rev-parse", "HEAD"));
    git(clone, "gc", "-q");
    expect(readWorkspaceHeadSha(clone)).toBe(git(clone, "rev-parse", "HEAD"));
    git(clone, "pack-refs", "--all");
    expect(readWorkspaceHeadSha(clone)).toBe(git(clone, "rev-parse", "HEAD"));
    git(clone, "checkout", "-q", "--detach", "HEAD");
    expect(readWorkspaceHeadSha(clone)).toBe(git(clone, "rev-parse", "HEAD"));
    git(clone, "checkout", "-q", "main");
    writeFileSync(join(clone, "z.txt"), "z");
    git(clone, "add", ".");
    git(clone, "commit", "-q", "-m", "z");
    expect(readWorkspaceHeadSha(clone)).toBe(git(clone, "rev-parse", "HEAD"));
  });
});

describe("readWorkspaceHeadSha: nothing outside the workspace's own HEAD is consulted", () => {
  test("a planted commondir does not redirect it (and real git, pinned the way the old gate was, WAS redirected)", () => {
    const a = mkRepo(1);
    const b = mkRepo(2);
    expect(a.head).not.toBe(b.head);
    writeFileSync(join(a.dir, ".git", "commondir"), `${join(b.dir, ".git")}\n`);
    // Control: the measured failure of the pre-9b pins. If git ever stops following commondir under these pins, this fails loudly.
    const pinned = execFileSync("git", ["rev-parse", "HEAD"], {
      cwd: a.dir,
      encoding: "utf8",
      env: {
        ...gitFixtureEnv(a.dir),
        GIT_DIR: join(a.dir, ".git"),
        GIT_COMMON_DIR: join(a.dir, ".git"),
        GIT_OBJECT_DIRECTORY: join(a.dir, ".git", "objects"),
      },
    }).trim();
    expect(pinned).toBe(b.head);
    const before = spawns.n;
    expect(readWorkspaceHeadSha(a.dir)).toBe(a.head);
    expect(spawns.n).toBe(before);
  });

  test("an inherited process.env.GIT_DIR naming another repository does not redirect it (control: git does)", () => {
    const a = mkRepo(1);
    const b = mkRepo(2);
    process.env.GIT_DIR = join(b.dir, ".git");
    const viaGit = execFileSync("git", ["rev-parse", "HEAD"], {
      cwd: a.dir,
      encoding: "utf8",
      env: { ...gitFixtureEnv(a.dir), GIT_DIR: join(b.dir, ".git") },
    }).trim();
    expect(viaGit).toBe(b.head);
    expect(readWorkspaceHeadSha(a.dir)).toBe(a.head);
  });

  test("a hostile .git/config and an unreadable config (a FIFO) are never opened", { timeout: 10_000 }, () => {
    const { dir, head } = mkRepo();
    const cfg = join(dir, ".git", "config");
    rmSync(cfg);
    mkFifo(cfg);
    expect(readWorkspaceHeadSha(dir)).toBe(head);
    rmSync(cfg);
    writeFileSync(cfg, '[url "https://evil.invalid/"]\n\tinsteadOf = https://github.com/\n[core]\n\tfsmonitor = /bin/false\n');
    expect(readWorkspaceHeadSha(dir)).toBe(head);
  });

  test("the process cwd is irrelevant: the HEAD of THE WORKSPACE PATH is read", () => {
    const a = mkRepo(1);
    const b = mkRepo(2);
    expect(readWorkspaceHeadSha(a.dir)).toBe(a.head);
    expect(readWorkspaceHeadSha(b.dir)).toBe(b.head);
  });
});

describe("readWorkspaceHeadSha: fail-closed refusals (each with a closed reason, none spawning)", () => {
  test("a missing workspace or a missing .git", () => {
    expect(refusal(join(mkRoot(), "nowhere")).reason).toBe("git_dir_not_plain");
    const plain = mkRoot();
    expect(refusal(plain).reason).toBe("git_dir_not_plain");
  });

  test("a worktree-style .git FILE", () => {
    const { dir } = mkRepo();
    const elsewhere = join(mkRoot(), "elsewhere");
    renameSync(join(dir, ".git"), elsewhere);
    writeFileSync(join(dir, ".git"), `gitdir: ${elsewhere}\n`);
    expect(refusal(dir).reason).toBe("git_dir_not_plain");
  });

  test("a SYMLINKED .git to a complete repository (both sides of a later containment compare would resolve to the other repo)", () => {
    const { dir } = mkRepo();
    const copy = join(mkRoot(), "real-git");
    renameSync(join(dir, ".git"), copy);
    symlinkSync(copy, join(dir, ".git"));
    expect(git(dir, "rev-parse", "HEAD")).toMatch(/^[0-9a-f]{40}$/); // precondition: git itself would happily read it
    expect(refusal(dir).reason).toBe("git_dir_not_plain");
  });

  test("a symlinked HEAD", () => {
    const { dir } = mkRepo();
    const aside = join(mkRoot(), "HEAD");
    renameSync(join(dir, ".git", "HEAD"), aside);
    symlinkSync(aside, join(dir, ".git", "HEAD"));
    expect(refusal(dir).reason).toBe("head_unreadable");
  });

  test("a symlinked refs/heads directory (a complete copy holding the same ref)", () => {
    const { dir } = mkRepo();
    const aside = join(mkRoot(), "heads");
    renameSync(join(dir, ".git", "refs", "heads"), aside);
    symlinkSync(aside, join(dir, ".git", "refs", "heads"));
    expect(refusal(dir).reason).toBe("ref_invalid");
  });

  test("a symlinked loose ref FILE", () => {
    const { dir } = mkRepo();
    const loose = join(dir, ".git", "refs", "heads", "main");
    const aside = join(mkRoot(), "main");
    renameSync(loose, aside);
    symlinkSync(aside, loose);
    expect(refusal(dir).reason).toBe("ref_invalid");
  });

  test.each([
    ["traversal", "ref: refs/heads/../../../../etc/passwd"],
    ["dot component", "ref: refs/heads/./main"],
    ["empty component", "ref: refs/heads//main"],
    ["not under refs/", "ref: HEAD"],
    ["a .lock suffix", "ref: refs/heads/main.lock"],
    ["a backslash", "ref: refs/heads/ma\\in"],
    ["a trailing CR", "ref: refs/heads/main\r"],
    ["an empty name", "ref: "],
  ])("a HEAD naming a bad ref (%s) is refused as ref_invalid", (_label, body) => {
    const { dir } = mkRepo();
    writeFileSync(join(dir, ".git", "HEAD"), `${body}\n`);
    expect(refusal(dir).reason).toBe("ref_invalid");
  });

  test("an unborn HEAD", () => {
    const dir = join(mkRoot(), "ws");
    mkdirSync(dir);
    git(dir, "init", "-q", "-b", "main");
    expect(refusal(dir).reason).toBe("ref_unresolvable");
  });

  test("a loose ref in the wrong shape: CRLF, uppercase hex, short hex, garbage", () => {
    const { dir, head } = mkRepo();
    const loose = join(dir, ".git", "refs", "heads", "main");
    writeFileSync(loose, `${head}\r\n`);
    expect(refusal(dir).reason).toBe("ref_invalid");
    writeFileSync(loose, `${head.toUpperCase()}\n`);
    expect(refusal(dir).reason).toBe("ref_invalid");
    writeFileSync(loose, `${head.slice(0, 39)}\n`);
    expect(refusal(dir).reason).toBe("ref_invalid");
    writeFileSync(loose, "not a sha\n");
    expect(refusal(dir).reason).toBe("ref_invalid");
  });

  test("a 64-hex (sha256-shaped) id is never displayed", () => {
    const { dir } = mkRepo();
    writeFileSync(join(dir, ".git", "refs", "heads", "main"), `${"a".repeat(64)}\n`);
    expect(refusal(dir).reason).toBe("not_hex40");
    writeFileSync(join(dir, ".git", "HEAD"), `${"b".repeat(64)}\n`);
    expect(refusal(dir).reason).toBe("not_hex40");
  });

  test("a loose ref that is itself a symref (deeper than the one hop HEAD took)", () => {
    const { dir } = mkRepo();
    writeFileSync(join(dir, ".git", "refs", "heads", "main"), "ref: refs/heads/other\n");
    expect(refusal(dir).reason).toBe("symref_chain");
  });

  test("a reftable repository", () => {
    const { dir } = mkRepo();
    mkdirSync(join(dir, ".git", "reftable"));
    expect(refusal(dir).reason).toBe("reftable");
  });

  test("a FIFO HEAD, a FIFO loose ref and a FIFO packed-refs fail instead of hanging", { timeout: 10_000 }, () => {
    const a = mkRepo();
    rmSync(join(a.dir, ".git", "HEAD"));
    mkFifo(join(a.dir, ".git", "HEAD"));
    expect(refusal(a.dir).reason).toBe("head_unreadable");

    const b = mkRepo();
    const loose = join(b.dir, ".git", "refs", "heads", "main");
    rmSync(loose);
    mkFifo(loose);
    expect(refusal(b.dir)).toBeInstanceOf(WorkspaceHeadUnreadable);

    const c = mkRepo();
    git(c.dir, "pack-refs", "--all");
    rmSync(join(c.dir, ".git", "packed-refs"));
    mkFifo(join(c.dir, ".git", "packed-refs"));
    expect(refusal(c.dir)).toBeInstanceOf(WorkspaceHeadUnreadable);
  });

  test("an oversized HEAD (over 4 KiB) and an unreadable (mode 000) HEAD", () => {
    const a = mkRepo();
    writeFileSync(join(a.dir, ".git", "HEAD"), `ref: refs/heads/${"x".repeat(5000)}\n`);
    expect(refusal(a.dir).reason).toBe("head_unreadable");

    const b = mkRepo();
    const headFile = join(b.dir, ".git", "HEAD");
    chmodSync(headFile, 0);
    expect(() => readFileSync(headFile)).toThrow(); // precondition: the plant is effective for this uid
    try {
      expect(refusal(b.dir).reason).toBe("head_unreadable");
    } finally {
      chmodSync(headFile, 0o644);
    }
  });

  test("no case above spawned a process", () => {
    const { dir } = mkRepo();
    const before = spawns.n;
    readWorkspaceHeadSha(dir);
    try {
      readWorkspaceHeadSha(join(dir, "missing"));
    } catch {
      /* expected */
    }
    expect(spawns.n).toBe(before);
  });
});

describe("readSmallRegularFile", () => {
  test("returns exactly the bytes of a regular file, and distinguishes ENOENT", () => {
    const root = mkRoot();
    writeFileSync(join(root, "a"), "hello");
    expect(readSmallRegularFile(join(root, "a"), 16)).toBe("hello");
    expect(() => readSmallRegularFile(join(root, "missing"), 16)).toThrow(expect.objectContaining({ code: "ENOENT" }));
  });

  test("refuses a symlink final component, a directory, an oversized file and a FIFO (without hanging)", { timeout: 10_000 }, () => {
    const root = mkRoot();
    writeFileSync(join(root, "a"), "x".repeat(32));
    symlinkSync(join(root, "a"), join(root, "link"));
    mkdirSync(join(root, "dir"));
    mkFifo(join(root, "fifo"));
    expect(() => readSmallRegularFile(join(root, "link"), 64)).toThrow();
    expect(() => readSmallRegularFile(join(root, "dir"), 64)).toThrow();
    expect(() => readSmallRegularFile(join(root, "a"), 31)).toThrow();
    expect(() => readSmallRegularFile(join(root, "fifo"), 64)).toThrow();
    expect(readSmallRegularFile(join(root, "a"), 32)).toBe("x".repeat(32));
  });
});

describe("workspace-head.ts: module boundary", () => {
  const src = readFileSync(join(__dirname, "../../server/approval/workspace-head.ts"), "utf8");
  const code = stripComments(src);

  test("imports only node:fs, node:path and ./canonical (so decide-boundary and the dependency rules stay satisfied)", () => {
    const specs = [...code.matchAll(/\bfrom\s*(["'])([^"']+)\1/g)].map((m) => m[2]);
    expect(specs.length).toBeGreaterThan(0);
    for (const s of specs) expect(["node:fs", "node:path", "./canonical"], s).toContain(s);
    expect(code).not.toMatch(/import\s*\(/);
    expect(code).not.toMatch(/\brequire\s*\(/);
  });

  test("names no child_process API and reads no environment variable", () => {
    expect(code).not.toMatch(/child_process|execFile|spawn|\bexec\(/);
    expect(code).not.toMatch(/process\.env|process\.cwd/);
  });
});
