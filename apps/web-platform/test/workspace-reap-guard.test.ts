// #8211: deleteWorkspace's rm runs async (up to a minute per child). A re-provision of the same
// <root>/<id> in that window must be refused, not have its new tree deleted underneath; two
// concurrent deletes of one id are ONE reap; the guard always releases.
import { describe, test, expect, beforeEach, afterEach, vi } from "vitest";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

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

/** Mock async execFile so `rm` HOLDS until released; everything else (and sync) is real. */
function holdRm() {
  const held: { run: () => void }[] = [];
  const rmCalls: string[][] = [];
  vi.doMock("child_process", async () => {
    const actual = await vi.importActual<typeof import("child_process")>("child_process");
    return {
      ...actual,
      execFile: (cmd: string, args: string[], opts: unknown, cb: (...a: unknown[]) => void) => {
        if (cmd !== "rm") return (actual.execFile as (...x: unknown[]) => unknown)(cmd, args, opts, cb);
        rmCalls.push(args);
        held.push({
          run: () => {
            rmSync(args[args.length - 1], { recursive: true, force: true });
            cb(null, "", "");
          },
        });
        return undefined;
      },
    };
  });
  return { held, rmCalls, releaseAll: () => held.splice(0).forEach((h) => h.run()) };
}

beforeEach(() => {
  sandbox = mkdtempSync(join(tmpdir(), "soleur-guard-"));
  wsRoot = join(sandbox, "workspaces");
  wtRoot = join(sandbox, "worktrees");
  mkdirSync(wsRoot);
  mkdirSync(wtRoot);
  process.env.WORKSPACES_ROOT = wsRoot;
  process.env.WORKTREE_ROOT = wtRoot;
  process.env.SOLEUR_PLUGIN_PATH = "/nonexistent";
});
afterEach(() => {
  vi.useRealTimers();
  vi.doUnmock("child_process");
  vi.resetModules();
  if (saved.ws === undefined) delete process.env.WORKSPACES_ROOT;
  else process.env.WORKSPACES_ROOT = saved.ws;
  if (saved.wt === undefined) delete process.env.WORKTREE_ROOT;
  else process.env.WORKTREE_ROOT = saved.wt;
  rmSync(sandbox, { recursive: true, force: true });
});

const tick = () => new Promise((r) => setTimeout(r, 20));

describe("provision during a slow reap", () => {
  test("provisionWorkspace is REFUSED (typed) and the reaped tree is not touched; after the reap it succeeds", async () => {
    const dir = seed(wtRoot);
    const { releaseAll } = holdRm();
    const { deleteWorkspace, provisionWorkspace, WorkspaceReapInProgressError } = await import("../server/workspace");

    const reaping = deleteWorkspace(ID);
    await tick();

    await expect(provisionWorkspace(ID)).rejects.toBeInstanceOf(WorkspaceReapInProgressError);
    await expect(provisionWorkspace(ID.toUpperCase())).rejects.toBeInstanceOf(WorkspaceReapInProgressError);
    // Nothing was created in either root, and the tree being reaped is exactly as it was.
    expect(readdirSync(wsRoot)).toEqual([]);
    expect(readdirSync(dir)).toEqual(["sub"]);

    releaseAll();
    await reaping;
    expect(existsSync(dir)).toBe(false);

    const path = await provisionWorkspace(ID);
    expect(path).toBe(join(wsRoot, ID));
    expect(existsSync(join(wsRoot, ID))).toBe(true);
  });

  test("provisionWorkspaceWithRepo is refused at entry, before any token / removal / clone", async () => {
    seed(wtRoot);
    const { releaseAll } = holdRm();
    const token = vi.fn();
    vi.doMock("../server/github-app", async () => {
      const actual = await vi.importActual<typeof import("../server/github-app")>("../server/github-app");
      return { ...actual, generateInstallationToken: token, checkRepoAccess: vi.fn() };
    });
    const { deleteWorkspace, provisionWorkspaceWithRepo, WorkspaceReapInProgressError } = await import("../server/workspace");

    const reaping = deleteWorkspace(ID);
    await tick();
    await expect(provisionWorkspaceWithRepo(ID, "https://github.com/o/r", 1)).rejects.toBeInstanceOf(
      WorkspaceReapInProgressError,
    );
    expect(token).not.toHaveBeenCalled();

    releaseAll();
    await reaping;
    vi.doUnmock("../server/github-app");
  });

  test("a reap that starts during the TOKEN await is caught before the preflight / any removal", async () => {
    const { runExclusiveReap } = await import("../server/workspace-reap-guard");
    const dir = seed(wsRoot);
    let release!: () => void;
    const preflight = vi.fn();
    const cloned = vi.fn();
    vi.doMock("../server/github-app", async () => {
      const actual = await vi.importActual<typeof import("../server/github-app")>("../server/github-app");
      return {
        ...actual,
        generateInstallationToken: async () => {
          void runExclusiveReap(ID, () => new Promise<void>((r) => (release = r)));
          return "tok";
        },
        checkRepoAccess: async () => (preflight(), "ok"),
      };
    });
    vi.doMock("../server/git-auth", async () => {
      const actual = await vi.importActual<typeof import("../server/git-auth")>("../server/git-auth");
      return { ...actual, gitWithInstallationAuth: async () => void cloned() };
    });
    const { provisionWorkspaceWithRepo, WorkspaceReapInProgressError } = await import("../server/workspace");

    await expect(provisionWorkspaceWithRepo(ID, "https://github.com/o/r", 1)).rejects.toBeInstanceOf(
      WorkspaceReapInProgressError,
    );

    // Refused BEFORE the parallel cleanup + preflight: the existing tree was not removed either.
    expect(preflight).not.toHaveBeenCalled();
    expect(existsSync(dir)).toBe(true);
    expect(cloned).not.toHaveBeenCalled();
    release();
    vi.doUnmock("../server/github-app");
    vi.doUnmock("../server/git-auth");
  });

  test("a reap that starts during the PREFLIGHT await is caught before the clone", async () => {
    const { runExclusiveReap } = await import("../server/workspace-reap-guard");
    let release!: () => void;
    const cloned = vi.fn();
    vi.doMock("../server/github-app", async () => {
      const actual = await vi.importActual<typeof import("../server/github-app")>("../server/github-app");
      return {
        ...actual,
        generateInstallationToken: async () => "tok",
        checkRepoAccess: async () => {
          void runExclusiveReap(ID, () => new Promise<void>((r) => (release = r)));
          return "ok";
        },
      };
    });
    vi.doMock("../server/git-auth", async () => {
      const actual = await vi.importActual<typeof import("../server/git-auth")>("../server/git-auth");
      return { ...actual, gitWithInstallationAuth: async () => void cloned() };
    });
    const { provisionWorkspaceWithRepo, WorkspaceReapInProgressError } = await import("../server/workspace");

    await expect(provisionWorkspaceWithRepo(ID, "https://github.com/o/r", 1)).rejects.toBeInstanceOf(
      WorkspaceReapInProgressError,
    );

    expect(cloned).not.toHaveBeenCalled();
    release();
    vi.doUnmock("../server/github-app");
    vi.doUnmock("../server/git-auth");
  });

  test("ensureWorkspaceRepoCloned returns `failed` (honest-blocking) while the id is being reaped", async () => {
    const { runExclusiveReap } = await import("../server/workspace-reap-guard");
    let release!: () => void;
    const p = runExclusiveReap(ID, () => new Promise<void>((r) => (release = r)));
    const { ensureWorkspaceRepoCloned } = await import("../server/ensure-workspace-repo");

    const out = await ensureWorkspaceRepoCloned({
      userId: ID,
      workspacePath: join(wtRoot, ID),
      installationId: 1,
      repoUrl: "https://github.com/o/r",
    });

    expect(out).toBe("failed");
    expect(existsSync(join(wtRoot, ID))).toBe(false); // no mkdir / clone happened
    release();
    await p;
  });
});

describe("one reap per id", () => {
  test("two concurrent deletes of the same id run the steps ONCE and settle identically", async () => {
    seed(wtRoot);
    const { held, rmCalls, releaseAll } = holdRm();
    const { deleteWorkspace } = await import("../server/workspace");

    const a = deleteWorkspace(ID);
    const b = deleteWorkspace(ID.toUpperCase());
    await tick();
    expect(rmCalls).toHaveLength(1);
    expect(held).toHaveLength(1);

    releaseAll();
    await expect(Promise.all([a, b])).resolves.toEqual([undefined, undefined]);
    expect(rmCalls).toHaveLength(1);
  });

  test("a FAILING shared reap rejects both callers with the same error object (one report, no double page)", async () => {
    seed(wtRoot);
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFile: (_c: string, _a: string[], _o: unknown, cb: (...x: unknown[]) => void) => {
          setImmediate(() => cb(Object.assign(new Error("denied"), { code: 1 })));
          return undefined;
        },
      };
    });
    const { deleteWorkspace } = await import("../server/workspace");

    const [ra, rb] = await Promise.allSettled([deleteWorkspace(ID), deleteWorkspace(ID)]);

    expect(ra.status).toBe("rejected");
    expect(rb.status).toBe("rejected");
    expect((ra as PromiseRejectedResult).reason).toBe((rb as PromiseRejectedResult).reason);
  });

  test("different ids reap independently, in parallel", async () => {
    const other = "99999999-2222-4333-8444-555555555555";
    seed(wtRoot);
    seed(wtRoot, other);
    const { rmCalls, releaseAll } = holdRm();
    const { deleteWorkspace } = await import("../server/workspace");

    const a = deleteWorkspace(ID);
    const b = deleteWorkspace(other);
    await tick();
    expect(rmCalls).toHaveLength(2);
    releaseAll();
    await Promise.all([a, b]);
  });
});

describe("the guard is released in `finally`", () => {
  test("after SUCCESS", async () => {
    const { isWorkspaceBeingReaped } = await import("../server/workspace-reap-guard");
    seed(wtRoot);
    const { deleteWorkspace } = await import("../server/workspace");
    await deleteWorkspace(ID);
    expect(isWorkspaceBeingReaped(ID)).toBe(false);
  });

  test("after FAILURE, and a re-provision then works", async () => {
    const { isWorkspaceBeingReaped } = await import("../server/workspace-reap-guard");
    seed(wtRoot);
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFile: (_c: string, _a: string[], _o: unknown, cb: (...x: unknown[]) => void) => {
          setImmediate(() => cb(Object.assign(new Error("denied"), { code: 1 })));
          return undefined;
        },
      };
    });
    const { deleteWorkspace, provisionWorkspace } = await import("../server/workspace");
    await expect(deleteWorkspace(ID)).rejects.toBeInstanceOf(AggregateError);
    expect(isWorkspaceBeingReaped(ID)).toBe(false);
    await expect(provisionWorkspace(ID)).resolves.toBe(join(wsRoot, ID));
  });

  test("after a hard-stopped child (TIMEOUT): the reap is over, but the id stays held by the abandoned child (see the hold tests below)", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "Date"] });
    const { isWorkspaceBeingReaped } = await import("../server/workspace-reap-guard");
    seed(wtRoot);
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        // The child never answers and ignores SIGKILL.
        execFile: () => undefined,
      };
    });
    const { deleteWorkspace, REAP_CMD_TIMEOUT_MS, REAP_HARD_STOP_GRACE_MS } = await import("../server/workspace");

    const p = deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    );
    await vi.advanceTimersByTimeAsync(REAP_CMD_TIMEOUT_MS.rm + REAP_HARD_STOP_GRACE_MS + 10);
    const err = await p;

    expect((err as { failures: unknown[] }).failures).toEqual([{ root: "worktree", kind: "timeout", code: "ETIMEDOUT" }]);
    expect(isWorkspaceBeingReaped(ID)).toBe(true);
  });
});

describe("an abandoned (hard-stopped) child keeps the id blocked until it actually exits", () => {
  /** rm calls: the first HANGS (callback captured), later ones complete and remove the tree. */
  function hangFirstRm() {
    const hung: ((...a: unknown[]) => void)[] = [];
    let n = 0;
    vi.doMock("child_process", async () => {
      const actual = await vi.importActual<typeof import("child_process")>("child_process");
      return {
        ...actual,
        execFile: (cmd: string, args: string[], opts: unknown, cb: (...a: unknown[]) => void) => {
          if (cmd !== "rm") return (actual.execFile as (...x: unknown[]) => unknown)(cmd, args, opts, cb);
          n += 1;
          if (n === 1) {
            hung.push(cb);
            return undefined;
          }
          rmSync(args[args.length - 1], { recursive: true, force: true });
          setImmediate(() => cb(null, "", ""));
          return undefined;
        },
      };
    });
    return hung;
  }
  const FAKE = { toFake: ["setTimeout", "clearTimeout", "Date"] as ("setTimeout" | "clearTimeout" | "Date")[] };

  test("the reap reports the timeout at once, but provisioning stays refused until the child's callback fires", async () => {
    vi.useFakeTimers(FAKE);
    seed(wtRoot);
    const hung = hangFirstRm();
    const guard = await import("../server/workspace-reap-guard");
    const { deleteWorkspace, provisionWorkspace, REAP_CMD_TIMEOUT_MS, REAP_HARD_STOP_GRACE_MS, WorkspaceReapInProgressError } =
      await import("../server/workspace");

    const p = deleteWorkspace(ID).then(
      () => null,
      (e: unknown) => e,
    );
    await vi.advanceTimersByTimeAsync(REAP_CMD_TIMEOUT_MS.rm + REAP_HARD_STOP_GRACE_MS + 10);
    const err = await p;

    // deleteWorkspace's own result is unchanged: the unit is a timeout failure, immediately.
    expect((err as { failures: unknown[] }).failures).toEqual([{ root: "worktree", kind: "timeout", code: "ETIMEDOUT" }]);
    // ...but the abandoned rm may still be alive: the id is NOT free.
    expect(guard.isWorkspaceBeingReaped(ID)).toBe(true);
    await expect(provisionWorkspace(ID)).rejects.toBeInstanceOf(WorkspaceReapInProgressError);

    hung[0](null, "", ""); // the child finally exits
    expect(guard.isWorkspaceBeingReaped(ID)).toBe(false);
    await expect(provisionWorkspace(ID)).resolves.toBe(join(wsRoot, ID));
  });

  test("the hold has a CEILING: a child that never exits releases the id after 10 min, with one hashed breadcrumb", async () => {
    vi.useFakeTimers(FAKE);
    seed(wtRoot);
    hangFirstRm();
    const logged: unknown[][] = [];
    vi.doMock("../server/logger", async () => {
      const actual = await vi.importActual<typeof import("../server/logger")>("../server/logger");
      const rec = (...a: unknown[]) => void logged.push(a);
      return { ...actual, createChildLogger: () => ({ info: rec, warn: rec, error: rec, debug: rec }) };
    });
    const guard = await import("../server/workspace-reap-guard");
    const { deleteWorkspace, REAP_CMD_TIMEOUT_MS, REAP_HARD_STOP_GRACE_MS } = await import("../server/workspace");

    const p = deleteWorkspace(ID).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(REAP_CMD_TIMEOUT_MS.rm + REAP_HARD_STOP_GRACE_MS + 10);
    await p;
    expect(guard.isWorkspaceBeingReaped(ID)).toBe(true);

    await vi.advanceTimersByTimeAsync(guard.REAP_CHILD_HOLD_CEILING_MS - REAP_CMD_TIMEOUT_MS.rm - REAP_HARD_STOP_GRACE_MS - 20);
    expect(guard.isWorkspaceBeingReaped(ID)).toBe(true); // just short of the ceiling
    await vi.advanceTimersByTimeAsync(100);
    expect(guard.isWorkspaceBeingReaped(ID)).toBe(false);

    const crumbs = logged.filter(([, m]) => /hold ceiling/.test(String(m)));
    expect(crumbs).toHaveLength(1);
    expect(JSON.stringify(crumbs)).not.toContain(ID);
    expect(crumbs[0][0]).toHaveProperty("workspaceIdHash");
  });

  test("overlapping reaps of one id count children: a later reap finishing does not release the abandoned one's hold", async () => {
    vi.useFakeTimers(FAKE);
    seed(wtRoot);
    const hung = hangFirstRm();
    const guard = await import("../server/workspace-reap-guard");
    const { deleteWorkspace, REAP_CMD_TIMEOUT_MS, REAP_HARD_STOP_GRACE_MS } = await import("../server/workspace");

    const first = deleteWorkspace(ID).catch(() => undefined);
    await vi.advanceTimersByTimeAsync(REAP_CMD_TIMEOUT_MS.rm + REAP_HARD_STOP_GRACE_MS + 10);
    await first;

    // A SECOND reap of the same id runs and completes while the first child is still alive.
    seed(wtRoot);
    let settled = false;
    const second = deleteWorkspace(ID).then(() => void (settled = true));
    for (let i = 0; i < 50 && !settled; i++) {
      await new Promise((r) => setImmediate(r)); // let the (real) child callback run
      await vi.advanceTimersByTimeAsync(300); // then the re-check delay
    }
    await second;
    expect(guard.isWorkspaceBeingReaped(ID)).toBe(true); // still held by the first, abandoned child

    hung[0](null, "", "");
    expect(guard.isWorkspaceBeingReaped(ID)).toBe(false);
  });

  test("guard unit: holds are counted, release is idempotent and never underflows", async () => {
    const guard = await import("../server/workspace-reap-guard");
    const a = guard.beginReapChild(ID);
    const b = guard.beginReapChild(ID.toUpperCase());
    expect(guard.isWorkspaceBeingReaped(ID)).toBe(true);
    a();
    a(); // double release must not drop b's hold
    expect(guard.isWorkspaceBeingReaped(ID)).toBe(true);
    b();
    expect(guard.isWorkspaceBeingReaped(ID)).toBe(false);
    expect(() => guard.assertWorkspaceNotBeingReaped(ID)).not.toThrow();
    // another id is never affected
    const c = guard.beginReapChild(ID);
    expect(guard.isWorkspaceBeingReaped("99999999-2222-4333-8444-555555555555")).toBe(false);
    c();
  });
});
