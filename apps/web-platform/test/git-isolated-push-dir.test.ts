/**
 * ADR-309 flip item 9b: `createIsolatedPushDir`, the server-created bare GIT_DIR the approved push runs from. Real git builds the
 * workspaces; the creator itself must spawn nothing. Every refusal test plants the hostile entry against a COMPLETE copy that
 * contains the approved commit, so only the check (never a missing commit) can refuse; every refusal also asserts that nothing
 * was written (the temp directory is created last).
 */
import { execFileSync, spawnSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join, relative, sep } from "node:path";
import { afterAll, afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

const h = vi.hoisted(() => ({
  spawns: 0,
  writes: 0,
  failAt: 0,
  /** Fault injection for the object-store walk: a read of a path ending in `suffix` throws an error with `code`. */
  opendirFault: null as null | { suffix: string; code: string },
  lstatFault: null as null | { suffix: string; code: string },
}));

vi.mock("node:child_process", async () => {
  const actual = await vi.importActual<typeof import("node:child_process")>("node:child_process");
  const count =
    <T extends (...a: never[]) => unknown>(fn: T) =>
    (...a: Parameters<T>) => {
      h.spawns++;
      return fn(...a);
    };
  return {
    ...actual,
    execFile: count(actual.execFile as (...a: never[]) => unknown),
    execFileSync: count(actual.execFileSync as (...a: never[]) => unknown),
    spawn: count(actual.spawn as (...a: never[]) => unknown),
    spawnSync: count(actual.spawnSync as (...a: never[]) => unknown),
  };
});

// A fault-injection seam over the fs WRITE calls only: the Nth write (1-based) throws `ENOSPC`. Reads are untouched, except the two
// walk reads (`opendirSync`, `lstatSync`) that a test can make fail for ONE path to stand in for a concurrent `git gc`.
vi.mock("node:fs", async () => {
  const actual = await vi.importActual<typeof import("node:fs")>("node:fs");
  const inject = (): void => {
    h.writes++;
    if (h.failAt !== 0 && h.writes === h.failAt) {
      throw Object.assign(new Error("ENOSPC: no space left on device, write '/secret/path'"), { code: "ENOSPC" });
    }
  };
  return {
    ...actual,
    mkdirSync: ((...a: Parameters<typeof actual.mkdirSync>) => {
      inject();
      return actual.mkdirSync(...a);
    }) as typeof actual.mkdirSync,
    mkdtempSync: ((...a: Parameters<typeof actual.mkdtempSync>) => {
      inject();
      return actual.mkdtempSync(...a);
    }) as typeof actual.mkdtempSync,
    writeFileSync: ((...a: Parameters<typeof actual.writeFileSync>) => {
      inject();
      return actual.writeFileSync(...a);
    }) as typeof actual.writeFileSync,
    opendirSync: ((...a: Parameters<typeof actual.opendirSync>) => {
      if (h.opendirFault && String(a[0]).endsWith(h.opendirFault.suffix)) {
        throw Object.assign(new Error(`${h.opendirFault.code}: injected`), { code: h.opendirFault.code });
      }
      return actual.opendirSync(...a);
    }) as typeof actual.opendirSync,
    lstatSync: ((...a: Parameters<typeof actual.lstatSync>) => {
      if (h.lstatFault && String(a[0]).endsWith(h.lstatFault.suffix)) {
        throw Object.assign(new Error(`${h.lstatFault.code}: injected`), { code: h.lstatFault.code });
      }
      return actual.lstatSync(...a);
    }) as typeof actual.lstatSync,
  };
});

import { AGENT_SESSION_TMP_ROOT } from "../server/agent-session-tmp";
import {
  IsolatedPushDirRefusal,
  OBJECT_WALK_ENTRY_CAP,
  agentWritableRoots,
  createIsolatedPushDir,
} from "../server/git-isolated-push-dir";
import { isSafeGitPath } from "../server/git-hardened-env";

// A spawn of a non-git program (mkfifo, openssl) reads no git configuration; it still gets an explicit, minimal env.
const NON_GIT_ENV = { PATH: process.env.PATH ?? "" } as unknown as NodeJS.ProcessEnv;

// The chmod-based fixtures cannot make a path unreadable for uid 0 (root bypasses the mode bits), so those tests skip as root.
const isRoot = process.getuid?.() === 0;

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

const ENV_KEYS = ["HOME", "TMPDIR", "PATH", "SSL_CERT_FILE", "SSL_CERT_DIR", "WORKSPACES_ROOT", "WORKTREE_ROOT"] as const;

describe("createIsolatedPushDir", () => {
  let base: string;
  let home: string;
  let tmp: string;
  let ws: string;
  let sha: string;
  const saved: Record<string, string | undefined> = {};

  const soleurRoot = (): string => join(home, ".soleur-push");
  const created = (): string[] => (existsSync(soleurRoot()) ? readdirSync(soleurRoot()) : []);

  function mkRepo(path: string): string {
    mkdirSync(path, { recursive: true });
    git(path, "init", "-q", "-b", "main");
    writeFileSync(join(path, "a.txt"), "a\n");
    git(path, "add", ".");
    git(path, "commit", "-q", "-m", "A");
    return git(path, "rev-parse", "HEAD");
  }

  /** The refusal reason, with the invariant that nothing was written to HOME and no git child ran. */
  function reasonOf(workspace: string = ws): string {
    const spawnsBefore = h.spawns;
    let err: unknown;
    try {
      createIsolatedPushDir(workspace).dispose();
    } catch (e) {
      err = e;
    }
    expect(err, "expected a refusal").toBeInstanceOf(IsolatedPushDirRefusal);
    expect(created(), "a refusal must not leave a directory").toEqual([]);
    expect(h.spawns).toBe(spawnsBefore);
    return (err as IsolatedPushDirRefusal).reason;
  }

  beforeEach(() => {
    for (const k of ENV_KEYS) saved[k] = process.env[k];
    // scripts/test-all.sh injects a count-indexed core.hooksPath env; the fixtures must measure git, not the runner.
    for (const k of Object.keys(process.env)) {
      if (k === "GIT_CONFIG_COUNT" || k === "GIT_CONFIG_PARAMETERS" || /^GIT_CONFIG_(KEY|VALUE)_\d+$/.test(k)) {
        saved[k] = process.env[k];
        delete process.env[k];
      }
    }
    base = realpathSync(mkdtempSync(join(tmpdir(), "iso-dir-")));
    roots.push(base);
    home = join(base, "home");
    tmp = join(base, "tmp");
    mkdirSync(home);
    mkdirSync(tmp);
    ws = join(base, "ws");
    sha = mkRepo(ws);
    process.env.HOME = home;
    process.env.TMPDIR = tmp;
    delete process.env.SSL_CERT_FILE;
    delete process.env.SSL_CERT_DIR;
    delete process.env.WORKSPACES_ROOT;
    delete process.env.WORKTREE_ROOT;
    h.spawns = 0;
    h.writes = 0;
    h.failAt = 0;
    h.opendirFault = null;
    h.lstatFault = null;
  });

  afterEach(() => {
    h.failAt = 0;
    h.opendirFault = null;
    h.lstatFault = null;
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
      delete saved[k];
    }
    try {
      chmodSync(home, 0o755);
    } catch {
      /* already gone */
    }
  });

  describe("a normal workspace", () => {
    test("writes exactly HEAD, config and empty object/ref directories, with the workspace objects as the only alternate", () => {
      const before = h.spawns;
      const dir = createIsolatedPushDir(ws);
      try {
        expect(h.spawns).toBe(before); // no `git init`, no template copy: nothing is spawned
        expect(dir.alternateObjectDirectory).toBe(join(ws, ".git", "objects"));
        expect(dirname2(dir.gitDir)).toBe(soleurRoot());
        expect(statSync(dir.gitDir).mode & 0o777).toBe(0o700);
        expect(statSync(soleurRoot()).mode & 0o777).toBe(0o700);
        expect(readdirSync(dir.gitDir).sort()).toEqual(["HEAD", "config", "objects", "refs"]);
        expect(readFileSync(join(dir.gitDir, "HEAD"), "utf8")).toBe("ref: refs/heads/main\n");
        expect(readFileSync(join(dir.gitDir, "config"), "utf8")).toBe(
          [
            "[core]",
            "\trepositoryformatversion = 0",
            "\tbare = true",
            "\tcommitGraph = false",
            "\tmultiPackIndex = false",
            "[pack]",
            "\tuseBitmaps = false",
            "\treadReverseIndex = false",
            "\tthreads = 1",
            "[gc]",
            "\tauto = 0",
            "",
          ].join("\n"),
        );
        expect(readdirSync(join(dir.gitDir, "objects")).sort()).toEqual(["info", "pack"]);
        expect(readdirSync(join(dir.gitDir, "objects", "pack"))).toEqual([]);
        expect(readdirSync(join(dir.gitDir, "objects", "info"))).toEqual([]);
        expect(readdirSync(join(dir.gitDir, "refs")).sort()).toEqual(["heads", "tags"]);
        // The config the child will read is git-valid, and a commit that exists ONLY in the alternate is visible through it.
        const out = execFileSync("git", ["cat-file", "-t", sha], {
          encoding: "utf8",
          env: { ...gitFixtureEnv(base), GIT_DIR: dir.gitDir, GIT_ALTERNATE_OBJECT_DIRECTORIES: dir.alternateObjectDirectory },
        }).trim();
        expect(out).toBe("commit");
      } finally {
        dir.dispose();
      }
    });

    test("placement: under $HOME/.soleur-push, never under the workspace, TMPDIR (= os.tmpdir() here), the session tmp root or the workspaces root", () => {
      const dir = createIsolatedPushDir(ws);
      try {
        const real = realpathSync(dir.gitDir);
        expect(real.startsWith(`${realpathSync(home)}${sep}.soleur-push${sep}run-`)).toBe(true);
        for (const forbidden of [ws, realpathSync(tmp), tmpdir(), AGENT_SESSION_TMP_ROOT, "/workspaces"]) {
          expect(real === forbidden || real.startsWith(forbidden + sep), forbidden).toBe(false);
        }
        expect(tmpdir()).toBe(tmp); // the premise of the line above: os.tmpdir() follows the TMPDIR set in beforeEach
      } finally {
        dir.dispose();
      }
    });

    test("two creations from one workspace get distinct directories (concurrent pushes)", () => {
      const a = createIsolatedPushDir(ws);
      const b = createIsolatedPushDir(ws);
      try {
        expect(a.gitDir).not.toBe(b.gitDir);
      } finally {
        a.dispose();
        b.dispose();
      }
      expect(created()).toEqual([]);
    });

    test("dispose() removes the directory, is idempotent, and tolerates it already being gone", () => {
      const dir = createIsolatedPushDir(ws);
      writeFileSync(join(dir.gitDir, ".askpass-x.sh"), "x"); // the askpass script lives inside and goes with it
      dir.dispose();
      expect(existsSync(dir.gitDir)).toBe(false);
      expect(() => dir.dispose()).not.toThrow();
      const second = createIsolatedPushDir(ws);
      rmSync(second.gitDir, { recursive: true });
      expect(() => second.dispose()).not.toThrow();
    });

    test("the handle carries a brand the env builder can verify, and a plain object does not", async () => {
      const { assertIsolatedPushDir } = await import("../server/git-hardened-env");
      const dir = createIsolatedPushDir(ws);
      try {
        expect(() => assertIsolatedPushDir(dir)).not.toThrow();
        expect(() => assertIsolatedPushDir({ gitDir: dir.gitDir, alternateObjectDirectory: dir.alternateObjectDirectory })).toThrow();
        expect(() => assertIsolatedPushDir(true)).toThrow();
        expect(() => assertIsolatedPushDir(undefined)).toThrow();
      } finally {
        dir.dispose();
      }
    });
  });

  describe("workspace .git that is not a plain directory", () => {
    test("a symlinked .git to a complete copy", () => {
      const copy = join(base, "real-git");
      renameSync(join(ws, ".git"), copy);
      symlinkSync(copy, join(ws, ".git"));
      expect(git(copy, "--git-dir", copy, "cat-file", "-t", sha)).toBe("commit");
      expect(reasonOf()).toBe("git_dir_not_plain");
    });

    test("a gitdir: file", () => {
      const elsewhere = join(base, "elsewhere");
      renameSync(join(ws, ".git"), elsewhere);
      writeFileSync(join(ws, ".git"), `gitdir: ${elsewhere}\n`);
      expect(reasonOf()).toBe("git_dir_not_plain");
    });

    test("a missing .git is git_dir_not_plain; a missing workspace root is the server's own state (setup_failed)", () => {
      rmSync(join(ws, ".git"), { recursive: true });
      expect(reasonOf()).toBe("git_dir_not_plain");
      expect(reasonOf(join(base, "nowhere"))).toBe("setup_failed");
    });

    test("a relative workspace path is refused even when it EXISTS relative to the current directory", () => {
      expect(reasonOf("relative/ws")).toBe("git_dir_not_plain");
      const rel = relative(process.cwd(), ws);
      expect(isSafeGitPath(rel)).toBe(false);
      expect(realpathSync(rel)).toBe(ws); // the premise: without the absolute-path rule this resolves to a real workspace
      expect(reasonOf(rel)).toBe("git_dir_not_plain");
    });

    test("a workspace reached through a symlinked ancestor is accepted, and the alternate is the REAL path", () => {
      const link = join(base, "link-to-base");
      symlinkSync(base, link);
      const dir = createIsolatedPushDir(join(link, "ws"));
      try {
        expect(dir.alternateObjectDirectory).toBe(join(ws, ".git", "objects"));
      } finally {
        dir.dispose();
      }
    });

    test("no raw fs error, path or cause escapes a refusal", () => {
      rmSync(join(ws, ".git"), { recursive: true });
      let err: unknown;
      try {
        createIsolatedPushDir(ws);
      } catch (e) {
        err = e;
      }
      expect(err).toBeInstanceOf(IsolatedPushDirRefusal);
      const e = err as IsolatedPushDirRefusal;
      expect(e.cause).toBeUndefined();
      expect(e.message).not.toContain(base);
      expect(String(e.stack ?? "").split("\n")[0]).not.toContain(base);
    });
  });

  describe("object store redirection (each target is a complete copy holding the approved commit)", () => {
    test("a symlinked objects directory", () => {
      const aside = join(base, "aside-objects");
      renameSync(join(ws, ".git", "objects"), aside);
      symlinkSync(aside, join(ws, ".git", "objects"));
      expect(reasonOf()).toBe("object_store_redirect");
    });

    test.each(["pack", "info"])("a symlinked objects/%s", (child) => {
      git(ws, "gc", "-q");
      mkdirSync(join(ws, ".git", "objects", "info"), { recursive: true });
      const aside = join(base, `aside-${child}`);
      renameSync(join(ws, ".git", "objects", child), aside);
      symlinkSync(aside, join(ws, ".git", "objects", child));
      expect(reasonOf()).toBe("object_store_redirect");
    });

    test("a symlinked loose-object fan-out directory", () => {
      const fan = sha.slice(0, 2);
      const aside = join(base, "aside-fan");
      renameSync(join(ws, ".git", "objects", fan), aside);
      symlinkSync(aside, join(ws, ".git", "objects", fan));
      expect(reasonOf()).toBe("object_store_redirect");
    });

    test("a symlinked loose OBJECT inside a fan-out directory", () => {
      const fan = sha.slice(0, 2);
      const dir = join(ws, ".git", "objects", fan);
      const name = readdirSync(dir)[0];
      const aside = join(base, "aside-object");
      renameSync(join(dir, name), aside);
      symlinkSync(aside, join(dir, name));
      expect(reasonOf()).toBe("object_store_redirect");
    });

    test("a symlinked pack file", () => {
      git(ws, "gc", "-q");
      const pack = readdirSync(join(ws, ".git", "objects", "pack")).find((f) => f.endsWith(".pack"));
      expect(pack).toBeDefined();
      const aside = join(base, "aside.pack");
      renameSync(join(ws, ".git", "objects", "pack", pack as string), aside);
      symlinkSync(aside, join(ws, ".git", "objects", "pack", pack as string));
      expect(reasonOf()).toBe("object_store_redirect");
    });

    test.each(["alternates", "http-alternates"])("objects/info/%s present (git follows the chain)", (name) => {
      const victim = join(base, "victim");
      mkRepo(victim);
      mkdirSync(join(ws, ".git", "objects", "info"), { recursive: true });
      writeFileSync(join(ws, ".git", "objects", "info", name), `${join(victim, ".git", "objects")}\n`);
      expect(reasonOf()).toBe("object_store_redirect");
    });

    describe("an entry that disappears between the listing and its scan (a concurrent git gc) is gone, not tamper", () => {
      const fanOut = (): string => {
        const name = readdirSync(join(ws, ".git", "objects")).find((n) => /^[0-9a-f]{2}$/.test(n));
        if (!name) throw new Error("fixture has no loose fan-out directory");
        return name;
      };

      test("a fan-out directory that vanishes before its scan is skipped (ENOENT), the creation succeeds", () => {
        h.opendirFault = { suffix: `/objects/${fanOut()}`, code: "ENOENT" };
        createIsolatedPushDir(ws).dispose();
      });

      test("a FIFO entry that vanishes before its lstat is skipped (ENOENT), the creation succeeds; present, it is still a redirect", { timeout: 10_000 }, () => {
        const dir = join(ws, ".git", "objects", fanOut());
        const fifo = join(dir, "f".repeat(38));
        execFileSync("mkfifo", [fifo], { env: NON_GIT_ENV });
        expect(reasonOf()).toBe("object_store_redirect"); // control: the same entry, not vanished
        h.lstatFault = { suffix: `/${"f".repeat(38)}`, code: "ENOENT" };
        createIsolatedPushDir(ws).dispose();
      });

      test("every other errno on that scan stays an infrastructure refusal (setup_failed), and a vanished objects directory itself stays git_dir_not_plain", () => {
        h.opendirFault = { suffix: `/objects/${fanOut()}`, code: "EACCES" };
        expect(reasonOf()).toBe("setup_failed");
        h.opendirFault = { suffix: `/objects/${fanOut()}`, code: "EMFILE" };
        expect(reasonOf()).toBe("setup_failed");
        h.opendirFault = { suffix: "/.git/objects", code: "ENOENT" };
        expect(reasonOf()).toBe("git_dir_not_plain");
      });

      test("the pack and info directories are scanned the same way (a vanished objects/pack is gone too)", () => {
        h.opendirFault = { suffix: "/objects/pack", code: "ENOENT" };
        createIsolatedPushDir(ws).dispose();
        h.opendirFault = { suffix: "/objects/info", code: "ENOENT" };
        createIsolatedPushDir(ws).dispose();
      });
    });

    test("the production entry cap sits far above git's gc.auto thresholds (a legitimate pre-gc store must not dead-end)", () => {
      expect(OBJECT_WALK_ENTRY_CAP).toBeGreaterThanOrEqual(100_000);
    });

    test("an object-store walk above the entry cap is refused as object_store_too_large (not tamper), and a store just under it passes", () => {
      const pack = join(ws, ".git", "objects", "pack");
      mkdirSync(pack, { recursive: true });
      const baseline = (): number => {
        let n = 0;
        for (const top of readdirSync(join(ws, ".git", "objects"))) {
          n++;
          const p = join(ws, ".git", "objects", top);
          if (statSync(p).isDirectory() && (top === "pack" || top === "info" || /^[0-9a-f]{2}$/.test(top))) n += readdirSync(p).length;
        }
        return n;
      };
      for (let i = 0; i < 40; i++) writeFileSync(join(pack, `x${i}`), "");
      const total = baseline();
      const probe = (cap: number): string | "ok" => {
        try {
          createIsolatedPushDir(ws, { objectWalkEntryCap: cap }).dispose();
          return "ok";
        } catch (e) {
          return (e as IsolatedPushDirRefusal).reason;
        }
      };
      expect(probe(total)).toBe("ok");
      expect(probe(total - 1)).toBe("object_store_too_large");
      expect(created()).toEqual([]);
    });

    test("a FIFO at the approved commit's loose-object path is refused (object_store_redirect), never opened", { timeout: 10_000 }, () => {
      const dir = join(ws, ".git", "objects", sha.slice(0, 2));
      const name = readdirSync(dir)[0];
      rmSync(join(dir, name));
      execFileSync("mkfifo", [join(dir, name)], { env: NON_GIT_ENV });
      expect(reasonOf()).toBe("object_store_redirect");
    });

    test("a FIFO named pack-<40hex>.idx is refused (object_store_redirect)", { timeout: 10_000 }, () => {
      git(ws, "gc", "-q");
      execFileSync("mkfifo", [join(ws, ".git", "objects", "pack", `pack-${"a".repeat(40)}.idx`)], { env: NON_GIT_ENV });
      expect(reasonOf()).toBe("object_store_redirect");
    });

    test("a FIFO as the objects/info entry and a unix socket under objects/pack are refused", { timeout: 10_000 }, async () => {
      mkdirSync(join(ws, ".git", "objects", "info"), { recursive: true });
      const fifo = join(ws, ".git", "objects", "info", "commit-graph");
      execFileSync("mkfifo", [fifo], { env: NON_GIT_ENV });
      expect(reasonOf()).toBe("object_store_redirect");
      rmSync(fifo);
      mkdirSync(join(ws, ".git", "objects", "pack"), { recursive: true });
      const sock = join(ws, ".git", "objects", "pack", "s.sock");
      const srv = createServer();
      await new Promise<void>((resolve, reject) => srv.once("error", reject).listen(sock, resolve));
      try {
        expect(reasonOf()).toBe("object_store_redirect");
      } finally {
        await new Promise<void>((resolve) => srv.close(() => resolve()));
      }
    });

    test("a garbage pack .rev in the alternate is not parsed (readReverseIndex off); the same git with it on prints the corruption (control)", () => {
      git(ws, "gc", "-q");
      const packDir = join(ws, ".git", "objects", "pack");
      const idx = readdirSync(packDir).find((f) => f.endsWith(".idx")) as string;
      const rev = join(packDir, idx.replace(/\.idx$/, ".rev"));
      rmSync(rev, { force: true }); // git writes pack side files read-only
      writeFileSync(rev, "garbage-not-a-rev-file");
      const dir = createIsolatedPushDir(ws);
      try {
        const env = { ...gitFixtureEnv(base), GIT_DIR: dir.gitDir, GIT_ALTERNATE_OBJECT_DIRECTORIES: dir.alternateObjectDirectory };
        const run = (...pre: string[]) =>
          spawnSync("git", [...pre, "pack-objects", "--revs", "--stdout"], { input: `${sha}\n`, env, encoding: "latin1" });
        const off = run();
        expect(off.status).toBe(0);
        expect(String(off.stderr)).not.toMatch(/reverse-index/);
        const on = run("-c", "pack.readReverseIndex=true");
        expect(String(on.stderr), "control: the garbage .rev is parsed when the setting is on").toMatch(/reverse-index/);
      } finally {
        dir.dispose();
      }
    });

    test("a workspace path containing ':' (it would split GIT_ALTERNATE_OBJECT_DIRECTORIES)", () => {
      const colon = join(base, "a:b");
      mkRepo(colon);
      expect(isSafeGitPath(join(colon, ".git", "objects"))).toBe(false);
      expect(reasonOf(colon)).toBe("alternate_path_unsafe");
    });
  });

  describe("isSafeGitPath", () => {
    test.each([":", '"', "\\", "\n", "\0"])("refuses a path containing %j", (c) => {
      expect(isSafeGitPath(`/ws/a${c}b/.git/objects`)).toBe(false);
    });
    test("refuses a relative path and accepts an ordinary absolute one", () => {
      expect(isSafeGitPath("ws/.git/objects")).toBe(false);
      expect(isSafeGitPath("")).toBe(false);
      expect(isSafeGitPath("/ws/a b/.git/objects")).toBe(true);
    });
  });

  describe("shallow", () => {
    const shaA = "a".repeat(40);
    const shaB = "b".repeat(40);

    test("a valid shallow file is carried into the directory (mode 0600), nothing else from the workspace", () => {
      writeFileSync(join(ws, ".git", "shallow"), `${shaA}\n${shaB}\n`);
      const dir = createIsolatedPushDir(ws);
      try {
        expect(readFileSync(join(dir.gitDir, "shallow"), "utf8")).toBe(`${shaA}\n${shaB}\n`);
        expect(statSync(join(dir.gitDir, "shallow")).mode & 0o777).toBe(0o600);
      } finally {
        dir.dispose();
      }
    });

    test("no shallow file means no shallow file in the directory", () => {
      const dir = createIsolatedPushDir(ws);
      try {
        expect(existsSync(join(dir.gitDir, "shallow"))).toBe(false);
      } finally {
        dir.dispose();
      }
    });

    test("a FIFO shallow is refused instead of blocking", { timeout: 10_000 }, () => {
      execFileSync("mkfifo", [join(ws, ".git", "shallow")], { env: NON_GIT_ENV });
      expect(reasonOf()).toBe("shallow_invalid");
    });

    test("an empty .git/shallow means a non-shallow workspace: no shallow file is written", () => {
      writeFileSync(join(ws, ".git", "shallow"), "");
      const dir = createIsolatedPushDir(ws);
      try {
        expect(existsSync(join(dir.gitDir, "shallow"))).toBe(false);
      } finally {
        dir.dispose();
      }
    });

    test("a directory as .git/shallow is planted content (shallow_invalid)", () => {
      mkdirSync(join(ws, ".git", "shallow"));
      expect(reasonOf()).toBe("shallow_invalid");
    });

    test.skipIf(isRoot)("(skipped as uid 0) an unreadable .git/shallow (EACCES) says nothing about its content: setup_failed", () => {
      const shallow = join(ws, ".git", "shallow");
      writeFileSync(shallow, `${shaA}\n`);
      chmodSync(shallow, 0);
      expect(() => readFileSync(shallow)).toThrow(); // precondition: the plant is effective for this uid
      try {
        expect(reasonOf()).toBe("setup_failed");
      } finally {
        chmodSync(shallow, 0o644);
      }
    });

    test("an oversized shallow (over 64 KiB), a non-hex line, a short hex line, an uppercase line and a symlinked shallow", () => {
      const shallow = join(ws, ".git", "shallow");
      const oversized = `${shaA}\n`.repeat(1700); // 41 * 1700 = 69 700 bytes
      writeFileSync(shallow, oversized);
      // The size comes from the content written, not from a stat of the path (a stat-then-write on one path is a file-system race to CodeQL).
      expect(Buffer.byteLength(oversized)).toBeGreaterThan(64 * 1024);
      expect(reasonOf()).toBe("shallow_invalid");
      for (const bad of ["not-a-sha\n", `${shaA}\n${"c".repeat(39)}\n`, `${"A".repeat(40)}\n`, `${shaA} extra\n`]) {
        writeFileSync(shallow, bad);
        expect(reasonOf(), JSON.stringify(bad)).toBe("shallow_invalid");
      }
      rmSync(shallow);
      const aside = join(base, "shallow-aside");
      writeFileSync(aside, `${shaA}\n`);
      symlinkSync(aside, shallow);
      expect(reasonOf()).toBe("shallow_invalid");
    });
  });

  describe("environment paths the child will resolve (step 3, before any write)", () => {
    // Every directory the agent can write (or that holds other tenants' trees) is refused for PATH, SSL_CERT_FILE and SSL_CERT_DIR
    // alike: ONE root list serves the env check and the HOME placement check.
    const rootCases = (): Array<[string, string]> => {
      process.env.WORKSPACES_ROOT = join(base, "wsroot");
      process.env.WORKTREE_ROOT = join(base, "wtroot");
      return [
        ["the workspace", join(ws, "bin")],
        ["TMPDIR", join(tmp, "bin")],
        ["the session tmp root", join(AGENT_SESSION_TMP_ROOT, "0123456789abcdef", "bin")],
        ["WORKSPACES_ROOT", join(base, "wsroot", "other-tenant", "bin")],
        ["WORKTREE_ROOT", join(base, "wtroot", "other-tenant", "bin")],
      ];
    };

    test.each(["PATH", "SSL_CERT_FILE", "SSL_CERT_DIR"] as const)("%s under any agent-writable root is refused as env_path_unsafe", (key) => {
      for (const [label, entry] of rootCases()) {
        process.env.PATH = saved.PATH ?? "";
        delete process.env.SSL_CERT_FILE;
        delete process.env.SSL_CERT_DIR;
        process.env[key] = key === "PATH" ? `${entry}:${saved.PATH ?? ""}` : entry;
        expect(reasonOf(), `${key} under ${label}`).toBe("env_path_unsafe");
      }
    });

    test("a PATH entry that is a SYMLINK resolving into a root is refused (the resolved path is what the child runs)", () => {
      mkdirSync(join(ws, "bin"));
      const links = join(base, "links");
      mkdirSync(links);
      symlinkSync(join(ws, "bin"), join(links, "innocent"));
      process.env.PATH = `${join(links, "innocent")}:${saved.PATH ?? ""}`;
      expect(reasonOf()).toBe("env_path_unsafe");
      process.env.PATH = saved.PATH ?? "";
      symlinkSync(join(tmp), join(links, "to-tmp"));
      process.env.SSL_CERT_DIR = join(links, "to-tmp", "certs");
      expect(reasonOf()).toBe("env_path_unsafe");
    });

    test("a root that is itself a symlink: HOME, PATH and SSL_CERT_* under the symlink TARGET and under the LINK path are all refused", () => {
      const target = join(base, "real-wsroot");
      mkdirSync(join(target, "inner"), { recursive: true });
      mkdirSync(join(target, "bin"));
      const link = join(base, "link-wsroot");
      symlinkSync(target, link);
      process.env.WORKSPACES_ROOT = link;
      for (const [label, inner] of [
        ["the target", join(target, "inner")],
        ["the link", join(link, "inner")],
      ]) {
        process.env.HOME = inner;
        expect(reasonOf(), `HOME via ${label}`).toBe("setup_failed");
      }
      process.env.HOME = home;
      for (const key of ["PATH", "SSL_CERT_FILE", "SSL_CERT_DIR"] as const) {
        for (const [label, entry] of [
          ["the target", join(target, "bin")],
          ["the link", join(link, "bin")],
        ]) {
          process.env.PATH = saved.PATH ?? "";
          delete process.env.SSL_CERT_FILE;
          delete process.env.SSL_CERT_DIR;
          process.env[key] = key === "PATH" ? `${entry}:${saved.PATH ?? ""}` : entry;
          expect(reasonOf(), `${key} via ${label}`).toBe("env_path_unsafe");
        }
      }
    });

    test("the same holds for a symlinked WORKTREE_ROOT and a symlinked TMPDIR", () => {
      for (const key of ["WORKTREE_ROOT", "TMPDIR"] as const) {
        const target = join(base, `real-${key}`);
        mkdirSync(join(target, "inner"), { recursive: true });
        symlinkSync(target, join(base, `link-${key}`));
        process.env[key] = join(base, `link-${key}`);
        process.env.HOME = join(target, "inner");
        expect(reasonOf(), `HOME under the target of ${key}`).toBe("setup_failed");
        process.env.HOME = home;
        process.env.PATH = `${join(target, "bin")}:${saved.PATH ?? ""}`;
        expect(reasonOf(), `PATH under the target of ${key}`).toBe("env_path_unsafe");
        process.env.PATH = saved.PATH ?? "";
        process.env.TMPDIR = tmp;
        delete process.env.WORKTREE_ROOT;
      }
    });

    test("a PATH entry INSIDE a root that is a symlink pointing OUTSIDE it is refused (the agent can retarget the link after the check)", () => {
      const outside = join(base, "outside-bin");
      mkdirSync(outside);
      symlinkSync(outside, join(ws, "bin"));
      process.env.PATH = `${join(ws, "bin")}:${saved.PATH ?? ""}`;
      expect(reasonOf()).toBe("env_path_unsafe");
      process.env.PATH = saved.PATH ?? "";
      symlinkSync(outside, join(tmp, "certs"));
      process.env.SSL_CERT_DIR = join(tmp, "certs");
      expect(reasonOf()).toBe("env_path_unsafe");
    });

    test("control: an ordinary PATH and a trust store elsewhere are accepted", () => {
      process.env.SSL_CERT_FILE = join(base, "elsewhere-ca.pem");
      createIsolatedPushDir(ws).dispose();
    });

    test("the mirrored root list contains every sandbox tenant deny root (a ONE-WAY subset check against workspaceTenantDenyRoots)", async () => {
      const { workspaceTenantDenyRoots } = await import("../server/workspace-resolver");
      for (const env of [{}, { WORKSPACES_ROOT: join(base, "wsroot"), WORKTREE_ROOT: join(base, "wtroot") }]) {
        delete process.env.WORKSPACES_ROOT;
        delete process.env.WORKTREE_ROOT;
        Object.assign(process.env, env);
        const mine = agentWritableRoots(ws);
        for (const root of workspaceTenantDenyRoots()) expect(mine, JSON.stringify(env)).toContain(root);
        expect(mine).toContain(ws);
        expect(mine).toContain(AGENT_SESSION_TMP_ROOT);
        expect(mine).toContain(tmp);
      }
    });
  });

  describe("HOME and failure handling", () => {
    test("HOME unset, relative (even when it exists relative to the cwd) or nonexistent refuses as setup_failed", () => {
      delete process.env.HOME;
      expect(reasonOf()).toBe("setup_failed");
      process.env.HOME = "relative/home";
      expect(reasonOf()).toBe("setup_failed");
      const relHome = relative(process.cwd(), home);
      expect(realpathSync(relHome)).toBe(home); // the premise: without the absolute-path rule this resolves
      process.env.HOME = relHome;
      expect(reasonOf()).toBe("setup_failed");
      process.env.HOME = join(base, "no-such-home");
      expect(reasonOf()).toBe("setup_failed");
      expect(readdirSync(tmp)).toEqual([]);
    });

    test.skipIf(isRoot)("(skipped as uid 0) an unwritable HOME refuses as setup_failed and does NOT fall back to the temp directory", () => {
      process.env.HOME = home;
      chmodSync(home, 0o500);
      expect(() => writeFileSync(join(home, "probe"), "x")).toThrow(); // precondition: the plant is effective for this uid
      expect(reasonOf()).toBe("setup_failed");
      chmodSync(home, 0o755);
      expect(readdirSync(tmp)).toEqual([]); // nothing was created under TMPDIR either
    });

    test("a HOME under the workspace, TMPDIR, the session tmp root, WORKSPACES_ROOT or WORKTREE_ROOT refuses as setup_failed and creates nothing", () => {
      process.env.WORKSPACES_ROOT = join(base, "wsroot");
      process.env.WORKTREE_ROOT = join(base, "wtroot");
      const sessionHome = join(AGENT_SESSION_TMP_ROOT, `iso-test-${process.pid}-${Date.now()}`);
      const homes: Array<[string, string]> = [
        ["the workspace", join(ws, "inner-home")],
        ["TMPDIR", join(tmp, "inner-home")],
        ["the session tmp root", sessionHome],
        ["WORKSPACES_ROOT", join(base, "wsroot", "inner-home")],
        ["WORKTREE_ROOT", join(base, "wtroot", "inner-home")],
      ];
      try {
        for (const [label, inner] of homes) {
          mkdirSync(inner, { recursive: true });
          process.env.HOME = inner;
          expect(reasonOf(), label).toBe("setup_failed");
          expect(existsSync(join(inner, ".soleur-push")), label).toBe(false);
        }
      } finally {
        rmSync(sessionHome, { recursive: true, force: true });
      }
    });

    test("a HOME whose real path contains ':' or a double quote refuses as setup_failed (the directory would be an unsafe GIT_DIR)", () => {
      for (const name of ["ho:me", 'ho"me']) {
        const odd = join(base, name);
        mkdirSync(odd);
        process.env.HOME = odd;
        expect(reasonOf(), name).toBe("setup_failed");
        expect(existsSync(join(odd, ".soleur-push")) ? readdirSync(join(odd, ".soleur-push")) : [], name).toEqual([]);
      }
    });

    test("a pre-existing .soleur-push that is a symlink elsewhere refuses as setup_failed and writes nothing through it", () => {
      const elsewhere = join(base, "elsewhere");
      mkdirSync(elsewhere);
      symlinkSync(elsewhere, soleurRoot());
      expect(reasonOf()).toBe("setup_failed");
      expect(readdirSync(elsewhere)).toEqual([]);
    });

    test("an injected write failure at EVERY write step maps to setup_failed, leaves no directory and leaks no path", () => {
      h.writes = 0;
      createIsolatedPushDir(ws).dispose();
      const total = h.writes;
      expect(total).toBeGreaterThanOrEqual(8);
      for (let n = 1; n <= total; n++) {
        h.writes = 0;
        h.failAt = n;
        let err: unknown;
        try {
          createIsolatedPushDir(ws);
        } catch (e) {
          err = e;
        }
        h.failAt = 0;
        expect(err, `write ${n}`).toBeInstanceOf(IsolatedPushDirRefusal);
        const e = err as IsolatedPushDirRefusal;
        expect(e.reason, `write ${n}`).toBe("setup_failed");
        expect(e.cause).toBeUndefined();
        expect(e.message).not.toContain("/secret/path");
        const left = created().filter((name) => name.startsWith("run-"));
        expect(left, `write ${n} left a directory`).toEqual([]);
      }
    });

    test("the chmod'd and FIFO-planted workspace entries the creator never opens do not matter (index, config, HEAD, hooks)", { timeout: 10_000 }, () => {
      for (const f of ["index", "config", "HEAD"]) {
        rmSync(join(ws, ".git", f), { force: true });
        execFileSync("mkfifo", [join(ws, ".git", f)], { env: NON_GIT_ENV });
      }
      createIsolatedPushDir(ws).dispose();
      expect(lstatSync(join(ws, ".git", "config")).isFIFO()).toBe(true);
    });
  });
});

function dirname2(p: string): string {
  return p.slice(0, p.lastIndexOf(sep));
}

