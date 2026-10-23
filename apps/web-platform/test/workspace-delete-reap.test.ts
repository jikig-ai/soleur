// #8211 PR-C: deleteWorkspace must reap WORKTREE_ROOT/<id> as well as
// WORKSPACES_ROOT/<id> (Art. 17 erasure of the live working tree). Real
// filesystem, per-test sandbox roots under mkdtemp (never a fixed /tmp path).
import { describe, test, expect, beforeEach, afterEach, vi } from "vitest";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "fs";
import { tmpdir } from "os";
import { join } from "path";

const ID = "11111111-2222-4333-8444-555555555555";

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

    expect(err).toBeInstanceOf(Error);
    expect((err as AggregateError).errors).toHaveLength(1);
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
    expect(String((err as AggregateError).errors[0])).toMatch(/still present/);
    expect(existsSync(b)).toBe(true);
  });

  test("equal roots are deduped: each tree is reaped (and reported) exactly once", async () => {
    process.env.WORKTREE_ROOT = wsRoot; // same as WORKSPACES_ROOT
    seed(wsRoot);
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

    const reaped = info.mock.calls.filter(([, msg]) => msg === "Workspace deleted");
    expect(reaped).toHaveLength(1);
  });

  test("a '/' root throws and removes nothing", async () => {
    const a = seed(wsRoot);
    process.env.WORKTREE_ROOT = "/";
    const { deleteWorkspace } = await import("../server/workspace");

    await expect(deleteWorkspace(ID)).rejects.toThrow(/filesystem root/);
    expect(existsSync(a)).toBe(true);
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
});
