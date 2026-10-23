// #8211 PR-C: deleteWorkspace must reap WORKTREE_ROOT/<id> as well as
// WORKSPACES_ROOT/<id> (Art. 17 erasure of the live working tree). Real
// filesystem, per-test sandbox roots under mkdtemp (never a fixed /tmp path).
import { describe, test, expect, beforeEach, afterEach, vi } from "vitest";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { REAP_RECHECK_DELAY_MS } from "../server/workspace";

// Contains hex LETTERS: an all-digit id is its own upper-case form and proves nothing.
const ID = "abcdef01-2222-4333-8444-5555555555ab";

let sandbox: string;
let wsRoot: string;
let wtRoot: string;
const saved = { ws: process.env.WORKSPACES_ROOT, wt: process.env.WORKTREE_ROOT };

function seed(root: string, id = ID): string {
  const dir = join(root, id);
  mkdirSync(join(dir, "sub"), { recursive: true });
  writeFileSync(join(dir, "sub", "f.txt"), "x");
  return dir;
}

beforeEach(() => {
  sandbox = mkdtempSync(join(tmpdir(), "soleur-reap-"));
  wsRoot = join(sandbox, "workspaces");
  wtRoot = join(sandbox, "worktrees");
  mkdirSync(wsRoot);
  mkdirSync(wtRoot);
  process.env.WORKSPACES_ROOT = wsRoot;
  process.env.WORKTREE_ROOT = wtRoot;
});

afterEach(() => {
  vi.resetModules();
  vi.doUnmock("child_process");
  vi.doUnmock("fs");
  vi.doUnmock("../server/logger");
  vi.doUnmock("../server/workspace-resolver");
  if (saved.ws === undefined) delete process.env.WORKSPACES_ROOT;
  else process.env.WORKSPACES_ROOT = saved.ws;
  if (saved.wt === undefined) delete process.env.WORKTREE_ROOT;
  else process.env.WORKTREE_ROOT = saved.wt;
  rmSync(sandbox, { recursive: true, force: true });
});

describe("deleteWorkspace reaps every tenant root", () => {
  test("removes BOTH WORKSPACES_ROOT/<id> and WORKTREE_ROOT/<id>", async () => {
    const a = seed(wsRoot);
    const b = seed(wtRoot);
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID);

    expect(existsSync(a)).toBe(false);
    expect(existsSync(b)).toBe(false);
  });

  test("reaps the worktree tree even when the flag is off (post-rollback leftovers)", async () => {
    delete process.env.GIT_DATA_STORE_ENABLED;
    const b = seed(wtRoot);
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID);

    expect(existsSync(b)).toBe(false);
  });

  test("leaves other workspaces' trees in both roots untouched", async () => {
    const other = "99999999-2222-4333-8444-555555555555";
    const keepA = seed(wsRoot, other);
    const keepB = seed(wtRoot, other);
    seed(wsRoot);
    seed(wtRoot);
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID);

    expect(existsSync(keepA)).toBe(true);
    expect(existsSync(keepB)).toBe(true);
  });

  test("an absent dir in every root is a no-op", async () => {
    const { deleteWorkspace } = await import("../server/workspace");
    await expect(deleteWorkspace(ID)).resolves.toBeUndefined();
  });

  test("only one root populated: the other absent root does not throw", async () => {
    const b = seed(wtRoot);
    const { deleteWorkspace } = await import("../server/workspace");
    await expect(deleteWorkspace(ID)).resolves.toBeUndefined();
    expect(existsSync(b)).toBe(false);
  });

  test("a non-UUID id throws BEFORE any rm", async () => {
    const a = seed(wsRoot, "not-a-uuid");
    const calls: string[] = [];
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: (cmd: string, ...rest: unknown[]) => {
          calls.push(cmd);
          return (actual.execFileSync as (...a: unknown[]) => unknown)(cmd, ...rest);
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    await expect(deleteWorkspace("not-a-uuid")).rejects.toThrow(/Invalid workspaceId/);
    await expect(deleteWorkspace("../../etc")).rejects.toThrow(/Invalid workspaceId/);

    expect(calls).toEqual([]);
    expect(existsSync(a)).toBe(true);
  });

  test("a symlinked <root>/<id> is unlinked and its target is never followed", async () => {
    const target = join(sandbox, "precious");
    mkdirSync(target);
    writeFileSync(join(target, "keep.txt"), "keep");
    symlinkSync(target, join(wtRoot, ID));
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID);

    // The link is gone (lstat, not existsSync: a dangling link must not survive).
    expect(() => lstatSync(join(wtRoot, ID))).toThrow(/ENOENT/);
    expect(readFileSync(join(target, "keep.txt"), "utf8")).toBe("keep");
  });

  test("a DANGLING symlink at <root>/<id> is removed too", async () => {
    symlinkSync(join(sandbox, "does-not-exist"), join(wtRoot, ID));
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID);

    expect(() => lstatSync(join(wtRoot, ID))).toThrow(/ENOENT/);
  });

  test("a failure on the first root still attempts the second, then throws an aggregate", async () => {
    const a = seed(wsRoot);
    const b = seed(wtRoot);
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: (cmd: string, args: string[], ...rest: unknown[]) => {
          // Make EVERY phase fail for the workspaces-root tree only.
          if (args.some((p) => typeof p === "string" && p.startsWith(wsRoot))) {
            throw new Error("Permission denied");
          }
          return (actual.execFileSync as (...x: unknown[]) => unknown)(cmd, args, ...rest);
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    const err = await deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    );

    expect(err).toBeInstanceOf(AggregateError);
    expect((err as AggregateError).errors).toHaveLength(1);
    expect((err as { failures: unknown[] }).failures).toEqual([{ root: "workspaces", kind: "error" }]);
    // "N of M": one failure out of the two reap targets (the tree under each root).
    expect((err as Error).message).toBe("deleteWorkspace: 1 of 2 reap targets could not be reaped");
    // The second root was still reaped despite the first root's failure.
    expect(existsSync(b)).toBe(false);
    expect(existsSync(a)).toBe(true);
  });

  test("verifies each dir is gone: a dir that survives rm is reported, not swallowed", async () => {
    const b = seed(wtRoot);
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        // rm "succeeds" without removing anything.
        execFileSync: () => Buffer.alloc(0),
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    const err = await deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    );
    expect(err).toBeInstanceOf(AggregateError);
    expect(String((err as AggregateError).errors[0])).toMatch(/survived/);
    expect(existsSync(b)).toBe(true);
  });

  test("equal roots are deduped: each tree is reaped (and reported) exactly once", async () => {
    process.env.WORKTREE_ROOT = wsRoot; // same as WORKSPACES_ROOT
    seed(wsRoot);
    const info = vi.fn();
    const execCalls: string[] = [];
    vi.doMock("../server/logger", async () => {
      const actual = await vi.importActual<typeof import("../server/logger")>("../server/logger");
      return {
        ...actual,
        createChildLogger: () => ({ info, warn: vi.fn(), error: vi.fn(), debug: vi.fn() }),
      };
    });
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: (cmd: string, ...rest: unknown[]) => {
          execCalls.push(cmd);
          return (actual.execFileSync as (...x: unknown[]) => unknown)(cmd, ...rest);
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID);

    const reaped = info.mock.calls.filter(([, msg]) => msg === "Workspace deleted");
    expect(reaped).toHaveLength(1);
    // The REAL subprocess count: one rm for the single tree, none for the duplicate root.
    expect(execCalls).toEqual(["rm"]);
  });

  test("a '/' WORKTREE_ROOT: the legacy reap still runs, the resolver failure is reported, wtRoot is untouched", async () => {
    const a = seed(wsRoot);
    const wtKeep = seed(wtRoot); // a tree under the (now overridden) real worktree dir
    process.env.WORKTREE_ROOT = "/";
    const { deleteWorkspace } = await import("../server/workspace");

    const err = await deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    );

    expect((err as { failures: unknown[] }).failures).toEqual([{ root: "resolver", kind: "error", label: "worktree" }]);
    expect(existsSync(a)).toBe(false); // legacy reap NOT skipped by the resolver throw
    expect(existsSync(wtKeep)).toBe(true);
  });

  test.each([
    ["relative", "relative/worktrees"],
    ["dotdot", "/tmp/../etc"],
  ])("a %s WORKTREE_ROOT is a resolver failure, never a path join", async (_n, value) => {
    const a = seed(wsRoot);
    process.env.WORKTREE_ROOT = value;
    const { deleteWorkspace } = await import("../server/workspace");

    const err = await deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    );

    expect((err as { failures: { root: string }[] }).failures.map((f) => f.root)).toEqual(["resolver"]);
    expect(existsSync(a)).toBe(false);
  });

  test("an EMPTY WORKTREE_ROOT falls back to the default, not to '' or cwd", async () => {
    const a = seed(wsRoot);
    process.env.WORKTREE_ROOT = "";
    const { workspaceReapRoots } = await import("../server/workspace-resolver");
    expect(workspaceReapRoots().roots.map((r) => r.root)).toEqual([wsRoot, "/var/lib/soleur/worktrees"]);
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID);

    expect(existsSync(a)).toBe(false);
  });

  test("WORKTREE_ROOT nested inside WORKSPACES_ROOT: both trees reaped, other ids untouched", async () => {
    const nested = join(wsRoot, "wt");
    mkdirSync(nested);
    process.env.WORKTREE_ROOT = nested;
    const a = seed(wsRoot);
    const b = seed(nested);
    const other = seed(nested, "99999999-2222-4333-8444-555555555555");
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID);

    expect(existsSync(a)).toBe(false);
    expect(existsSync(b)).toBe(false);
    expect(existsSync(other)).toBe(true);
  });

  test("an UPPERCASE id reaps the lowercase on-disk tree (case-sensitive FS)", async () => {
    const a = seed(wsRoot);
    const b = seed(wtRoot);
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID.toUpperCase());

    expect(existsSync(a)).toBe(false);
    expect(existsSync(b)).toBe(false);
  });

  test("a symlinked root and its target are one reap target: counted once, reaped once", async () => {
    const real = join(sandbox, "real-wt");
    mkdirSync(real);
    rmSync(wtRoot, { recursive: true });
    symlinkSync(real, wtRoot);
    seed(real);
    const info = vi.fn();
    vi.doMock("../server/logger", async () => {
      const actual = await vi.importActual<typeof import("../server/logger")>("../server/logger");
      return {
        ...actual,
        createChildLogger: () => ({ info, warn: vi.fn(), error: vi.fn(), debug: vi.fn() }),
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID);

    expect(existsSync(join(real, ID))).toBe(false);
    expect(info.mock.calls.filter(([, m]) => m === "Workspace deleted")).toHaveLength(1);
  });

  test("a move-aside (rm/chmod/find fail, mv works) is an erasure FAILURE and the orphan is reported", async () => {
    const b = seed(wtRoot);
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: (cmd: string, args: string[], ...rest: unknown[]) => {
          if (cmd === "rm" || cmd === "chmod" || cmd === "find" || cmd === "rmdir") {
            throw new Error("Permission denied");
          }
          return (actual.execFileSync as (...x: unknown[]) => unknown)(cmd, args, ...rest); // real mv
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    const err = await deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    );

    expect(err).toBeInstanceOf(AggregateError);
    expect((err as { failures: unknown[] }).failures).toEqual([{ root: "worktree", kind: "moved-aside" }]);
    // The original path is gone, but the tree still exists as an orphan: that is why it fails.
    expect(existsSync(b)).toBe(false);
    expect(readdirSync(wtRoot).some((n) => n.startsWith(`${ID}.orphaned-`))).toBe(true);
  });

  // Error objects serialise to {} under plain JSON.stringify, which would hide a path-bearing
  // `err` handed to a log call. Expand them (name, message, stack, code) so it cannot.
  const ser = (v: unknown) =>
    JSON.stringify(v, (_k, x) =>
      x instanceof Error ? { name: x.name, message: x.message, stack: x.stack, code: (x as { code?: string }).code } : x,
    );
  const stubLogger = (logged: unknown[][]) =>
    vi.doMock("../server/logger", async () => {
      const actual = await vi.importActual<typeof import("../server/logger")>("../server/logger");
      const rec = (...a: unknown[]) => void logged.push(a);
      return { ...actual, createChildLogger: () => ({ info: rec, warn: rec, error: rec, debug: rec }) };
    });

  test("rm failure: the thrown error and every log call carry no path and no raw id", async () => {
    seed(wtRoot);
    const logged: unknown[][] = [];
    stubLogger(logged);
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: () => {
          throw new Error(`rm: cannot remove '${wtRoot}/${ID}': Permission denied`);
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    const err = (await deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    )) as AggregateError;

    expect(err).toBeInstanceOf(AggregateError);
    const blob = ser([err.message, err.stack, err.errors, logged]);
    expect(blob).not.toContain(ID);
    expect(blob).not.toContain(sandbox);
    expect(logged.length).toBeGreaterThan(0);
  });

  test("lstat failure (path-bearing EACCES): the raw error object never reaches a log call or the thrown error", async () => {
    seed(wtRoot);
    const target = join(wtRoot, ID);
    const logged: unknown[][] = [];
    stubLogger(logged);
    vi.doMock("fs", async () => {
      const actual = await vi.importActual<typeof import("fs")>("fs");
      return {
        ...actual,
        lstatSync: Object.assign(
          (p: string, ...rest: unknown[]) => {
            if (p === target) {
              throw Object.assign(new Error(`EACCES: permission denied, lstat '${p}'`), { code: "EACCES" });
            }
            return (actual.lstatSync as (...a: unknown[]) => unknown)(p, ...rest);
          },
          actual.lstatSync,
        ),
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    const err = (await deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    )) as AggregateError & { failures: unknown[] };

    expect(err.failures).toEqual([{ root: "worktree", kind: "error", code: "EACCES" }]);
    const blob = ser([err.message, err.stack, err.errors, logged]);
    expect(blob).not.toContain(ID);
    expect(blob).not.toContain(sandbox);
    expect(blob).toContain("EACCES"); // the code survives; the path does not
    vi.doUnmock("fs");
  });

  test("the legacy volume root is reaped BEFORE the worktree root (order of removal, not just labels)", async () => {
    seed(wsRoot);
    seed(wtRoot);
    const rmTargets: string[] = [];
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: (cmd: string, args: string[], ...rest: unknown[]) => {
          if (cmd === "rm") rmTargets.push(args[args.length - 1]);
          return (actual.execFileSync as (...x: unknown[]) => unknown)(cmd, args, ...rest);
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    await deleteWorkspace(ID);

    expect(rmTargets).toEqual([join(wsRoot, ID), join(wtRoot, ID)]);
  });

  test("a RELATIVE WORKSPACES_ROOT is refused, never resolved against the cwd; the worktree root is still reaped", async () => {
    const cwdTree = join(sandbox, "rel", ID);
    mkdirSync(cwdTree, { recursive: true });
    const b = seed(wtRoot);
    process.env.WORKSPACES_ROOT = "rel";
    const prev = process.cwd();
    process.chdir(sandbox);
    try {
      const { deleteWorkspace } = await import("../server/workspace");
      const err = await deleteWorkspace(ID).then(
        () => null,
        (e: unknown) => e,
      );
      expect((err as { failures: unknown[] }).failures).toEqual([
        { root: "resolver", kind: "error", label: "workspaces" },
      ]);
      expect((err as Error).message).toBe("deleteWorkspace: 1 of 2 reap targets could not be reaped");
    } finally {
      process.chdir(prev);
    }
    expect(existsSync(cwdTree)).toBe(true);
    expect(existsSync(b)).toBe(false);
  });

  test("an EMPTY WORKSPACES_ROOT falls back to /workspaces (not '' and not the cwd)", async () => {
    process.env.WORKSPACES_ROOT = "";
    const b = seed(wtRoot);
    const { deleteWorkspace } = await import("../server/workspace");
    await expect(deleteWorkspace(ID)).resolves.toBeUndefined();
    expect(existsSync(b)).toBe(false);
  });

  test("REAP_RECHECK_DELAY_MS is exactly 250 ms", async () => {
    const { REAP_RECHECK_DELAY_MS: d } = await import("../server/workspace");
    expect(d).toBe(250);
  });

  describe("orphan siblings (<id>.orphaned-<ts>)", () => {
    const ts = "1760000000000";

    test("an orphan of THIS id is removed under EVERY root; another tenant's orphan survives", async () => {
      const mine = [join(wsRoot, `${ID}.orphaned-${ts}`), join(wtRoot, `${ID}.orphaned-${ts}`)];
      const theirs = [
        join(wsRoot, `99999999-2222-4333-8444-555555555555.orphaned-${ts}`),
        join(wtRoot, `99999999-2222-4333-8444-555555555555.orphaned-${ts}`),
      ];
      for (const d of [...mine, ...theirs]) mkdirSync(join(d, "sub"), { recursive: true });
      const { deleteWorkspace } = await import("../server/workspace");

      await deleteWorkspace(ID);

      for (const d of mine) expect(existsSync(d)).toBe(false);
      for (const d of theirs) expect(existsSync(d)).toBe(true);
    });

    test("the match is STRICT: near-miss names are never touched", async () => {
      const near = [
        `${ID}.orphaned-abc`,
        `${ID}.orphaned-`,
        `${ID}.orphaned-${ts}.orphaned-${ts}`,
        `${ID}x.orphaned-${ts}`,
        `${ID}.orphaned-12`,
        `X${ID}.orphaned-${ts}`,
        `${ID}-backup`,
      ].map((n) => join(wtRoot, n));
      for (const d of near) mkdirSync(d);
      const { deleteWorkspace } = await import("../server/workspace");

      await deleteWorkspace(ID);

      for (const d of near) expect(existsSync(d)).toBe(true);
    });

    test("an uppercase id reaps the lowercase orphan", async () => {
      const o = join(wtRoot, `${ID}.orphaned-${ts}`);
      mkdirSync(o);
      const { deleteWorkspace } = await import("../server/workspace");
      await deleteWorkspace(ID.toUpperCase());
      expect(existsSync(o)).toBe(false);
    });

    test("an orphan that survives is a FAILURE and counts in the total", async () => {
      const o = join(wtRoot, `${ID}.orphaned-${ts}`);
      mkdirSync(o);
      vi.doMock("child_process", async () => {
        const actual = await vi.importActual<typeof import("child_process")>("child_process");
        return {
          ...actual,
          execFileSync: (cmd: string) => {
            if (cmd === "rm" || cmd === "chmod" || cmd === "find" || cmd === "rmdir" || cmd === "mv") {
              throw new Error("Permission denied");
            }
            return Buffer.alloc(0);
          },
        };
      });
      const { deleteWorkspace } = await import("../server/workspace");

      const err = await deleteWorkspace(ID).then(
        () => null,
        (e: unknown) => e,
      );

      expect((err as { failures: unknown[] }).failures).toEqual([{ root: "worktree", kind: "error" }]);
      // 2 roots x (tree) + 1 orphan = 3 targets.
      expect((err as Error).message).toBe("deleteWorkspace: 1 of 3 reap targets could not be reaped");
      expect(existsSync(o)).toBe(true);
    });

    test("a provision-time move-aside leaves an orphan that a later delete reaps", async () => {
      const dir = seed(wtRoot, ID);
      process.env.WORKTREE_ROOT = wtRoot;
      vi.doMock("child_process", async () => {
        const actual = await vi.importActual<typeof import("child_process")>("child_process");
        return {
          ...actual,
          execFileSync: (cmd: string, args: string[], ...rest: unknown[]) => {
            if (cmd === "rm" || cmd === "chmod" || cmd === "find" || cmd === "rmdir") throw new Error("denied");
            return (actual.execFileSync as (...x: unknown[]) => unknown)(cmd, args, ...rest);
          },
        };
      });
      const { removeWorkspaceDir } = await import("../server/workspace");
      expect(removeWorkspaceDir(dir, [wtRoot])).toBe("moved-aside"); // what provision does and ignores
      expect(readdirSync(wtRoot).filter((n) => n.startsWith(`${ID}.orphaned-`))).toHaveLength(1);

      vi.resetModules();
      vi.doUnmock("child_process");
      const { deleteWorkspace } = await import("../server/workspace");
      await deleteWorkspace(ID);

      expect(readdirSync(wtRoot)).toEqual([]);
    });
  });

  test("provisionWorkspaceWithRepo also builds the LOWERCASE path (clone target)", async () => {
    let cloneTarget = "";
    vi.doMock("../server/github-app", async () => {
      const actual = await vi.importActual<typeof import("../server/github-app")>("../server/github-app");
      return {
        ...actual,
        generateInstallationToken: async () => "tok",
        checkRepoAccess: async () => "ok",
      };
    });
    vi.doMock("../server/git-auth", async () => {
      const actual = await vi.importActual<typeof import("../server/git-auth")>("../server/git-auth");
      return {
        ...actual,
        gitWithInstallationAuth: async (args: string[]) => {
          cloneTarget = args[args.length - 1];
          throw new Error("stop after recording the clone target");
        },
      };
    });
    const { provisionWorkspaceWithRepo } = await import("../server/workspace");

    await expect(
      provisionWorkspaceWithRepo(ID.toUpperCase(), "https://github.com/o/r", 1),
    ).rejects.toThrow();

    expect(cloneTarget).toBe(join(wsRoot, ID));
    vi.doUnmock("../server/github-app");
    vi.doUnmock("../server/git-auth");
  });

  test("a mixed-case id provisions to, and deletes from, the SAME lowercase directory", async () => {
    process.env.SOLEUR_PLUGIN_PATH = "/nonexistent";
    const { provisionWorkspace, deleteWorkspace } = await import("../server/workspace");

    const path = await provisionWorkspace(ID.toUpperCase());

    expect(path).toBe(join(wsRoot, ID));
    expect(readdirSync(wsRoot)).toEqual([ID]);

    await deleteWorkspace(ID.toUpperCase());
    expect(readdirSync(wsRoot)).toEqual([]);
  });

  test("a file recreated by a straggler after the reap is caught by the re-check", async () => {
    const b = seed(wtRoot);
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: (cmd: string, args: string[], ...rest: unknown[]) => {
          const out = (actual.execFileSync as (...x: unknown[]) => unknown)(cmd, args, ...rest);
          if (cmd === "rm" && args[args.length - 1] === b) {
            // The straggling writer lands just inside the re-check delay (a shorter delay misses it).
            setTimeout(() => mkdirSync(b), REAP_RECHECK_DELAY_MS - 30);
          }
          return out;
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    const err = await deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    );

    expect((err as { failures: unknown[] }).failures).toEqual([{ root: "worktree", kind: "recreated" }]);
  });
});

describe("removeWorkspaceDir allowed-roots guard", () => {
  test("default still refuses a path outside getWorkspacesRoot()", async () => {
    const b = seed(wtRoot);
    const { removeWorkspaceDir } = await import("../server/workspace");

    expect(() => removeWorkspaceDir(b)).toThrow(/outside workspace root/);
    expect(existsSync(b)).toBe(true);
  });

  test("an explicit allowed root admits its own children only", async () => {
    const b = seed(wtRoot);
    const { removeWorkspaceDir } = await import("../server/workspace");

    expect(() => removeWorkspaceDir(wtRoot, [wtRoot])).toThrow(/outside workspace root/);
    expect(() => removeWorkspaceDir(join(sandbox, "x"), [wtRoot])).toThrow(/outside workspace root/);
    removeWorkspaceDir(b, [wtRoot]);
    expect(existsSync(b)).toBe(false);
  });

  test("a '/' allowed root is refused", async () => {
    const { removeWorkspaceDir } = await import("../server/workspace");
    expect(() => removeWorkspaceDir("/etc/passwd-nonexistent", ["/"])).toThrow(
      /outside workspace root/,
    );
  });

  test("an explicit root does not admit a SIBLING that merely shares its prefix", async () => {
    const evil = `${wtRoot}-evil`;
    mkdirSync(join(evil, "x"), { recursive: true });
    const { removeWorkspaceDir } = await import("../server/workspace");

    expect(() => removeWorkspaceDir(join(evil, "x"), [wtRoot])).toThrow(/outside workspace root/);
    expect(existsSync(join(evil, "x"))).toBe(true);
  });

  test("the DEFAULT allowed roots stay the single workspaces root (widening it to an outside root must fail this)", async () => {
    // An outside tree that a widened default (e.g. [getWorkspacesRoot(), "/var"], or the
    // worktree root) would admit.
    const outside = seed(wtRoot);
    const { removeWorkspaceDir } = await import("../server/workspace");

    expect(() => removeWorkspaceDir(outside)).toThrow(/outside workspace root/);
    expect(() => removeWorkspaceDir("/var/lib/soleur-nonexistent-x/y")).toThrow(/outside workspace root/);
    expect(existsSync(outside)).toBe(true);
  });

  test("returns the outcome; a move-aside is reported, not thrown (provision caller semantics unchanged)", async () => {
    const dir = seed(wsRoot, "provision-me");
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFileSync: (cmd: string, args: string[], ...rest: unknown[]) => {
          if (cmd === "rm" || cmd === "chmod" || cmd === "find" || cmd === "rmdir") {
            throw new Error("Permission denied");
          }
          return (actual.execFileSync as (...x: unknown[]) => unknown)(cmd, args, ...rest);
        },
      };
    });
    const { removeWorkspaceDir } = await import("../server/workspace");

    expect(removeWorkspaceDir(dir)).toBe("moved-aside");
    expect(existsSync(dir)).toBe(false); // path freed for re-provisioning
  });

  test("outcomes: removed / absent / unlinked", async () => {
    const { removeWorkspaceDir } = await import("../server/workspace");
    const dir = seed(wsRoot, "o1");
    expect(removeWorkspaceDir(dir)).toBe("removed");
    expect(removeWorkspaceDir(dir)).toBe("absent");
    const target = join(sandbox, "t");
    mkdirSync(target);
    symlinkSync(target, join(wsRoot, "lnk"));
    expect(removeWorkspaceDir(join(wsRoot, "lnk"))).toBe("unlinked");
    expect(existsSync(target)).toBe(true);
  });
});
