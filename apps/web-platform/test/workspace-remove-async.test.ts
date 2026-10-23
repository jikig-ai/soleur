// #8211: the erasure path must not block the event loop (a node_modules-heavy live clone), must
// bound every child, and must behave exactly like the sync remover the provision path keeps.
import { describe, test, expect, beforeEach, afterEach, vi } from "vitest";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, symlinkSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { mockChildProcess } from "./helpers/mock-child-process";

const ID = "abcdef01-2222-4333-8444-5555555555ab";
let sandbox: string;
let wsRoot: string;
let wtRoot: string;
const saved = { ws: process.env.WORKSPACES_ROOT, wt: process.env.WORKTREE_ROOT };

function seed(root: string, id = ID): string {
  const d = join(root, id);
  mkdirSync(join(d, "sub"), { recursive: true });
  writeFileSync(join(d, "sub", "f.txt"), "x");
  return d;
}

beforeEach(() => {
  sandbox = mkdtempSync(join(tmpdir(), "soleur-async-"));
  wsRoot = join(sandbox, "workspaces");
  wtRoot = join(sandbox, "worktrees");
  mkdirSync(wsRoot);
  mkdirSync(wtRoot);
  process.env.WORKSPACES_ROOT = wsRoot;
  process.env.WORKTREE_ROOT = wtRoot;
});
afterEach(() => {
  vi.doUnmock("child_process");
  vi.resetModules();
  if (saved.ws === undefined) delete process.env.WORKSPACES_ROOT;
  else process.env.WORKSPACES_ROOT = saved.ws;
  if (saved.wt === undefined) delete process.env.WORKTREE_ROOT;
  else process.env.WORKTREE_ROOT = saved.wt;
  rmSync(sandbox, { recursive: true, force: true });
});

const failures = (e: unknown) => (e as { failures: unknown[] }).failures;

describe("deleteWorkspace does not block the event loop", () => {
  test("timers keep firing while a slow child removes the tree", async () => {
    const dir = seed(wtRoot);
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      const busy = (ms: number) => {
        const end = Date.now() + ms;
        while (Date.now() < end) {
          /* a SYNC child blocks the loop for its whole duration */
        }
      };
      return {
        ...actual,
        // A sync rm blocks the loop the whole time; the async one yields.
        execFileSync: (cmd: string, args: string[], ...rest: unknown[]) => {
          if (cmd === "rm") busy(150);
          return (actual.execFileSync as (...x: unknown[]) => unknown)(cmd, args, ...rest);
        },
        execFile: (cmd: string, args: string[], opts: unknown, cb: (...a: unknown[]) => void) => {
          if (cmd !== "rm") return (actual.execFile as (...x: unknown[]) => unknown)(cmd, args, opts, cb);
          setTimeout(() => {
            rmSync(args[args.length - 1], { recursive: true, force: true });
            cb(null, "", "");
          }, 150);
          return undefined;
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    let ticks = 0;
    const timer = setInterval(() => void ticks++, 10);
    await deleteWorkspace(ID);
    clearInterval(timer);

    expect(existsSync(dir)).toBe(false);
    // 150 ms of child time at a 10 ms tick: a blocked loop fires at most ~1 timer.
    expect(ticks).toBeGreaterThanOrEqual(5);
  });
});

describe("per-child time limits", () => {
  test("the limits are the documented ones", async () => {
    const { REAP_CMD_TIMEOUT_MS } = await import("../server/workspace");
    expect(REAP_CMD_TIMEOUT_MS).toEqual({ rm: 60_000, chmod: 30_000, find: 60_000, rmdir: 10_000, mv: 10_000 });
  });

  test("every async child is started with its own timeout", async () => {
    seed(wtRoot);
    const seen: Record<string, unknown> = {};
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFile: (cmd: string, args: string[], opts: { timeout?: number }, cb: (...a: unknown[]) => void) => {
          seen[cmd] = opts.timeout;
          // Fail rm/chmod/find/rmdir so every phase runs; let mv really move it aside.
          if (cmd !== "mv") {
            setImmediate(() => cb(Object.assign(new Error("denied"), { code: 1 })));
            return undefined;
          }
          return (actual.execFile as (...x: unknown[]) => unknown)(cmd, args, opts, cb);
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID).catch(() => undefined);

    expect(seen).toEqual({ rm: 60_000, chmod: 30_000, find: 60_000, rmdir: 10_000, mv: 10_000 });
  });

  test.each([
    ["rm (phase 1)", ["rm"]],
    ["find (phase 2)", ["rm", "chmod", "find"]],
    ["mv (phase 3)", ["rm", "chmod", "find", "rmdir", "mv"]],
  ])("a child killed at its limit (%s) is a `timeout` failure; the other root is still reaped", async (_n, failBefore) => {
    seed(wsRoot);
    seed(wtRoot);
    const last = failBefore[failBefore.length - 1];
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFile: (cmd: string, args: string[], opts: unknown, cb: (...a: unknown[]) => void) => {
          if (args.some((a) => typeof a === "string" && a.startsWith(wtRoot)) && failBefore.includes(cmd)) {
            const killed = cmd === last;
            setImmediate(() =>
              cb(Object.assign(new Error("Command failed"), killed ? { killed: true, signal: "SIGKILL" } : { code: 1 })),
            );
            return undefined;
          }
          return (actual.execFile as (...x: unknown[]) => unknown)(cmd, args, opts, cb);
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    const err = await deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    );

    expect(failures(err)).toEqual([{ root: "worktree", kind: "timeout", code: "ETIMEDOUT" }]);
    expect(existsSync(join(wsRoot, ID))).toBe(false);
  });

  test("a timeout message carries no path and no id", async () => {
    seed(wtRoot);
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFile: (_c: string, _a: string[], _o: unknown, cb: (...a: unknown[]) => void) => {
          setImmediate(() => cb(Object.assign(new Error(`Command failed: rm -rf ${wtRoot}/${ID}`), { killed: true })));
          return undefined;
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");
    const err = (await deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    )) as AggregateError;
    expect(JSON.stringify([err.message, err.errors.map((e) => e.message)])).not.toContain(ID);
  });
});

describe("sync / async parity (one step generator, two runners)", () => {
  type Fixture = {
    name: string;
    handler?: (cmd: string) => void;
    prepare: (root: string) => string;
  };
  const dirFixture = (root: string) => {
    const d = join(root, "tree");
    mkdirSync(join(d, "sub"), { recursive: true });
    writeFileSync(join(d, "sub", "f"), "x");
    return d;
  };
  const failFour = (cmd: string) => {
    if (["rm", "chmod", "find", "rmdir"].includes(cmd)) throw new Error("denied");
  };
  const fixtures: Fixture[] = [
    { name: "plain directory", prepare: dirFixture },
    { name: "absent", prepare: (root) => join(root, "nope") },
    {
      name: "symlink to a directory",
      prepare: (root) => {
        const target = join(root, "..", `target-${Math.random()}`);
        mkdirSync(target);
        symlinkSync(target, join(root, "link"));
        return join(root, "link");
      },
    },
    { name: "dangling symlink", prepare: (root) => (symlinkSync(join(root, "gone"), join(root, "dl")), join(root, "dl")) },
    { name: "undeletable tree: moved aside", handler: failFour, prepare: dirFixture },
    {
      name: "undeletable and mv fails too: throws",
      handler: (cmd) => {
        if (["rm", "chmod", "find", "rmdir", "mv"].includes(cmd)) throw new Error("denied");
      },
      prepare: dirFixture,
    },
    { name: "rm fails, find/rmdir finish it (phase 2)", handler: (cmd) => { if (cmd === "rm") throw new Error("denied"); }, prepare: dirFixture },
  ];

  async function run(kind: "sync" | "async", f: Fixture) {
    vi.resetModules();
    vi.doUnmock("child_process");
    if (f.handler) {
      const h = f.handler;
      mockChildProcess((cmd) => h(cmd));
    }
    const root = mkdtempSync(join(sandbox, `${kind}-`));
    const target = f.prepare(root);
    const m = await import("../server/workspace");
    let outcome: string;
    try {
      outcome = kind === "sync" ? m.removeWorkspaceDir(target, [root]) : await m.removeWorkspaceDirAsync(target, [root]);
    } catch (e) {
      outcome = `throws: ${(e as Error).message}`;
    }
    // Normalise the orphan timestamp; compare what is left on disk.
    const left = readdirSync(root)
      .map((n) => n.replace(/\.orphaned-\d+$/, ".orphaned-TS"))
      .sort();
    return { outcome, left };
  }

  test.each(fixtures.map((f) => [f.name, f] as const))("%s: same outcome and same end state", async (_n, f) => {
    const a = await run("sync", f);
    const b = await run("async", f);
    expect(b).toEqual(a);
  });

  test.each([
    ["outside the allowed root", (root: string) => join(root, "..", "elsewhere"), /outside workspace root/],
    ["the root itself", (root: string) => root, /outside workspace root/],
    ["a prefix-sharing sibling", (root: string) => `${root}-evil/x`, /outside workspace root/],
  ])("guard parity: %s is refused by both", async (_n, pathFor, re) => {
    vi.resetModules();
    const m = await import("../server/workspace");
    const root = mkdtempSync(join(sandbox, "g-"));
    expect(() => m.removeWorkspaceDir(pathFor(root), [root])).toThrow(re);
    await expect(m.removeWorkspaceDirAsync(pathFor(root), [root])).rejects.toThrow(re);
  });

  test("the sync remover has NO time limit and never reports a timeout (provision behaviour unchanged)", async () => {
    const opts: unknown[] = [];
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: (cmd: string, args: string[], o: unknown) => {
          opts.push(o);
          return (actual.execFileSync as (...x: unknown[]) => unknown)(cmd, args, o);
        },
      };
    });
    const m = await import("../server/workspace");
    const root = mkdtempSync(join(sandbox, "p-"));
    const d = dirFixtureAt(root);
    expect(m.removeWorkspaceDir(d, [root])).toBe("removed");
    expect(opts).toEqual([{ stdio: "pipe" }]);

    function dirFixtureAt(r: string) {
      const x = join(r, "t");
      mkdirSync(x);
      return x;
    }
  });
});
