/**
 * ADR-309 flip item 9b: `createIsolatedPushDir`, the server-created bare GIT_DIR the approved push runs from. Real git builds the
 * workspaces; the creator itself must spawn nothing. Every refusal test plants the hostile entry against a COMPLETE copy that
 * contains the approved commit, so only the check (never a missing commit) can refuse; every refusal also asserts that nothing
 * was written (the temp directory is created last).
 */
import { execFileSync } from "node:child_process";
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
import { tmpdir } from "node:os";
import { join, sep } from "node:path";
import { afterAll, afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

const h = vi.hoisted(() => ({ spawns: 0, writes: 0, failAt: 0 }));

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

// A fault-injection seam over the fs WRITE calls only: the Nth write (1-based) throws `ENOSPC`. Reads are untouched.
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
  };
});

import { AGENT_SESSION_TMP_ROOT } from "../server/agent-session-tmp";
import { IsolatedPushDirRefusal, createIsolatedPushDir } from "../server/git-isolated-push-dir";
import { isSafeGitPath } from "../server/git-hardened-env";

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

const ENV_KEYS = ["HOME", "TMPDIR", "PATH", "SSL_CERT_FILE", "SSL_CERT_DIR", "WORKSPACES_ROOT"] as const;

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
    h.spawns = 0;
    h.writes = 0;
    h.failAt = 0;
  });

  afterEach(() => {
    h.failAt = 0;
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

    test("a missing .git, a missing workspace and a relative path", () => {
      rmSync(join(ws, ".git"), { recursive: true });
      expect(reasonOf()).toBe("git_dir_not_plain");
      expect(reasonOf(join(base, "nowhere"))).toBe("git_dir_not_plain");
      expect(reasonOf("relative/ws")).toBe("git_dir_not_plain");
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

    test("an object-store walk above the entry cap is refused, not run unbounded", () => {
      const pack = join(ws, ".git", "objects", "pack");
      mkdirSync(pack, { recursive: true });
      for (let i = 0; i < 10_001; i++) writeFileSync(join(pack, `x${i}`), "");
      expect(reasonOf()).toBe("object_store_redirect");
    }, 30_000);

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
      execFileSync("mkfifo", [join(ws, ".git", "shallow")]);
      expect(reasonOf()).toBe("shallow_invalid");
    });

    test("an oversized shallow (over 64 KiB), a non-hex line, a short hex line, an uppercase line and a symlinked shallow", () => {
      const shallow = join(ws, ".git", "shallow");
      writeFileSync(shallow, `${shaA}\n`.repeat(1700)); // 41 * 1700 = 69 700 bytes
      expect(statSync(shallow).size).toBeGreaterThan(64 * 1024);
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

  describe("environment paths the child will resolve (step 0, before any write)", () => {
    test("PATH containing a directory under the workspace or under TMPDIR", () => {
      const inWs = join(ws, "bin");
      mkdirSync(inWs);
      process.env.PATH = `${inWs}:${saved.PATH ?? ""}`;
      expect(reasonOf()).toBe("env_path_unsafe");
      const inTmp = join(tmp, "bin");
      mkdirSync(inTmp);
      process.env.PATH = `${inTmp}:${saved.PATH ?? ""}`;
      expect(reasonOf()).toBe("env_path_unsafe");
    });

    test("SSL_CERT_FILE / SSL_CERT_DIR under the workspace or TMPDIR", () => {
      process.env.SSL_CERT_FILE = join(ws, "ca.pem");
      expect(reasonOf()).toBe("env_path_unsafe");
      delete process.env.SSL_CERT_FILE;
      process.env.SSL_CERT_DIR = join(tmp, "certs");
      expect(reasonOf()).toBe("env_path_unsafe");
    });

    test("control: an ordinary PATH and a trust store elsewhere are accepted", () => {
      process.env.SSL_CERT_FILE = join(base, "elsewhere-ca.pem");
      createIsolatedPushDir(ws).dispose();
    });
  });

  describe("HOME and failure handling", () => {
    test("HOME unset, relative or unwritable refuses as setup_failed and does NOT fall back to the temp directory", () => {
      delete process.env.HOME;
      expect(reasonOf()).toBe("setup_failed");
      process.env.HOME = "relative/home";
      expect(reasonOf()).toBe("setup_failed");
      process.env.HOME = home;
      chmodSync(home, 0o500);
      expect(() => writeFileSync(join(home, "probe"), "x")).toThrow(); // precondition: the plant is effective for this uid
      expect(reasonOf()).toBe("setup_failed");
      chmodSync(home, 0o755);
      expect(readdirSync(tmp)).toEqual([]); // nothing was created under TMPDIR either
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
        execFileSync("mkfifo", [join(ws, ".git", f)]);
      }
      createIsolatedPushDir(ws).dispose();
      expect(lstatSync(join(ws, ".git", "config")).isFIFO()).toBe(true);
    });
  });
});

function dirname2(p: string): string {
  return p.slice(0, p.lastIndexOf(sep));
}

