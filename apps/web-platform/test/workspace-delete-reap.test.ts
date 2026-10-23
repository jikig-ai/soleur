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

    expect((err as { failures: unknown[] }).failures).toEqual([{ root: "resolver", kind: "error" }]);
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
    expect(workspaceReapRoots().map((r) => r.root)).toEqual([wsRoot, "/var/lib/soleur/worktrees"]);
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

  test("the thrown error and every log call carry no path and no raw id", async () => {
    seed(wtRoot);
    const logged: unknown[][] = [];
    vi.doMock("../server/logger", async () => {
      const actual = await vi.importActual<typeof import("../server/logger")>("../server/logger");
      const rec = (...a: unknown[]) => void logged.push(a);
      return { ...actual, createChildLogger: () => ({ info: rec, warn: rec, error: rec, debug: rec }) };
    });
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
    const blob = JSON.stringify([err.message, err.errors.map((e) => e.message), logged]);
    expect(blob).not.toContain(ID);
    expect(blob).not.toContain(sandbox);
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
            // The straggling writer wins the race right after the rm.
            setTimeout(() => mkdirSync(b), 20);
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
