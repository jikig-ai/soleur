// #12600 (CTO rulings D6, D7, D8; supersede R18's KB exemption and gate placement): `selfHealNonFastForward` runs a
// `reset --keep` only when nothing would be lost - a clean tracked tree (knowledge-base/ included), local commits whose
// content is already upstream, and no untracked or ignored entry in the reset's way (D15a). Every local verb, the
// `symbolic-ref` read included (D15d), runs token-free (D6d); only `pull` and `fetch origin` reach the token-bearing
// `gitWithInstallationAuth`. The three designed holds warn through `mirrorWarnWithDebounce(null, ...)` and the two branch
// aborts stay error through `mirrorWithDebounce(null, ...)`, all keyed on the workspace (D6e, D7, D15e); every emit
// passes a null error and carries its details in tags / extra (D8). The three holds set `held` (D16). Real-git rows:
// test/workspace-sync-self-heal-real-git.test.ts.
// Synthesized data only.
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const { gitSpy, localSpy, reportSpy, warnSpy, mirrorSpy, mirrorWarnSpy, lstatSpy } = vi.hoisted(() => ({
  gitSpy: vi.fn<(args: string[]) => Promise<Buffer>>(),
  /** The D15(a) precheck's on-disk probe; nothing is on disk unless a row says so. */
  lstatSpy: vi.fn<(path: Buffer) => Promise<{ isDirectory: () => boolean }>>(),
  localSpy: vi.fn<(args: string[], opts: { cwd: string; timeout: number }) => Promise<Buffer>>(),
  reportSpy: vi.fn(),
  warnSpy: vi.fn(),
  mirrorSpy: vi.fn(),
  mirrorWarnSpy: vi.fn(),
}));
// D27: the held-commits branch calls the hardened merge (lazily imported); its real-git rows are in
// test/workspace-sync-self-heal-real-git.test.ts. Here it is a seam returning the pull reason a row names.
const H2 = vi.hoisted(() => ({
  mergeSpy: vi.fn<(input: { precheck?: boolean; url?: string; writer: { merge: (t: string) => Promise<string> }; budget?: { remaining(): number; mergeStartMinMs: number } }) => Promise<{ reason: string; remote: unknown }>>(
    async () => ({ reason: "merge_conflict_precheck", remote: null }),
  ),
  disposeSpy: vi.fn(),
  /** The guarded writer the self-heal builds (D37(2)): its args, and the inner merge it wraps. */
  writerSpy: vi.fn(),
  innerMerge: vi.fn(async () => "clean"),
  /** D39(a)/D42: the self-heal's held-count write (frozen signature; WP3 owns the body). */
  heldWriteSpy: vi.fn(async () => ({ total: 0, onRecovered: 0 }) as { total: number; onRecovered: number } | null),
  /** D38(6): the same-host lock (frozen signature; WP1 owns the body). Calls fn by default. */
  lockSpy: vi.fn(async (_p: string, fn: () => Promise<unknown>, _opts?: { waitMs?: number }) => fn()),
  /** R2-B (data-sec P3-2): the autostash pin the self-heal runs first. */
  pinSpy: vi.fn(async (_p: string) => undefined),
  /** The route callers' tenant-scoped repo-URL read. */
  repoUrlSpy: vi.fn(async () => ({ url: "https://github.com/acme/widget.git", owner: "acme", repo: "widget" })),
  /** The count-only path's hardened ls-remote (D42: the pre-call untracked collision). */
  readRemoteSpy: vi.fn(async () => null as unknown),
  /** D43: the system callers' service read. */
  serviceRow: { data: { repo_url: "https://github.com/acme/widget" } as unknown, error: null as unknown },
  serviceCalls: [] as Array<[string, ...unknown[]]>,
  heads: [] as string[],
  isolatedRefusal: null as null | string,
}));
const mergeSpy = H2.mergeSpy;
const disposeSpy = H2.disposeSpy;
vi.mock("@/server/kb-sync-pull", () => ({ mergeVerifiedDefault: H2.mergeSpy }));
vi.mock("@/server/kb-sync-remote", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/kb-sync-remote")>()),
  resolveRepoUrl: H2.repoUrlSpy,
  readRemoteState: H2.readRemoteSpy,
}));
vi.mock("@/server/approval/workspace-head", () => ({
  readWorkspaceHeadRef: () => ({ sha: H2.heads.shift() ?? "a".repeat(40), refName: "refs/heads/main" }),
}));
vi.mock("@/server/git-isolated-push-dir", () => {
  class IsolatedPushDirRefusal extends Error {
    constructor(readonly reason: string) {
      super("refused");
    }
  }
  return {
    IsolatedPushDirRefusal,
    createIsolatedPushDir: () => {
      if (H2.isolatedRefusal) throw new IsolatedPushDirRefusal(H2.isolatedRefusal);
      return { gitDir: "/tmp/iso", dispose: H2.disposeSpy };
    },
  };
});
vi.mock("@/server/connected-repo-git", () => ({
  kbPullWriter: (...a: unknown[]) => {
    H2.writerSpy(...a);
    return { unpack: async () => undefined, setTracking: async () => undefined, casBranch: async () => undefined, merge: H2.innerMerge };
  },
  withWorkspaceGitLock: H2.lockSpy,
  WORKSPACE_GIT_LOCK_TIMEOUT: "lock_timeout",
  pinInterruptedAutostash: H2.pinSpy,
}));
vi.mock("@/server/kb-sync-held-refresh", () => ({ writeHeldFromIsolated: H2.heldWriteSpy }));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => {
    const q = {
      from: (t: string) => (H2.serviceCalls.push(["from", t]), q),
      select: (c: string) => (H2.serviceCalls.push(["select", c]), q),
      eq: (c: string, v: unknown) => (H2.serviceCalls.push(["eq", c, v]), q),
      maybeSingle: async () => (H2.serviceCalls.push(["maybeSingle"]), H2.serviceRow),
    };
    return q;
  },
}));

vi.mock("@/server/git-auth", () => ({ gitWithInstallationAuth: gitSpy }));
vi.mock("@/server/workspace-local-git", () => ({ runWorkspaceLocalGit: localSpy }));
vi.mock("node:fs/promises", async (importOriginal) => ({
  ...(await importOriginal<typeof import("node:fs/promises")>()),
  lstat: lstatSpy,
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSpy,
  warnSilentFallback: warnSpy,
  mirrorWithDebounce: mirrorSpy,
  mirrorWarnWithDebounce: mirrorWarnSpy,
}));

import { syncWorkspace } from "@/server/workspace-sync";

const WS = "/tmp/ws-self-heal";
const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } as never;
const NON_FF = Object.assign(new Error("Command failed: git pull --ff-only"), {
  stderr: "fatal: Not possible to fast-forward, aborting.",
});
const exit = (code: number): Error => Object.assign(new Error(`Command failed (exit ${code})`), { code });

interface Shape {
  status?: string;
  revList?: string;
  headRef?: string;
  /** exit status of `diff --quiet origin/D...HEAD -- . ':(exclude)knowledge-base/'` */
  nonKbDiff?: number;
  /** exit status of `diff --quiet origin/D HEAD -- knowledge-base/` */
  kbDiff?: number;
  statusThrows?: boolean;
  /** stdout of `symbolic-ref refs/remotes/origin/HEAD` */
  symbolicRef?: string;
  /** the error `reset` rejects with */
  resetThrows?: Error;
  /** stdout of the D15(a) precheck's `diff --name-status -z` (default: nothing added or deleted) */
  precheck?: string;
}

function isNonKbDiff(args: string[]): boolean {
  return args[0] === "diff" && args.includes(":(exclude)knowledge-base/");
}
/** The D15(a) collision precheck's path listing. */
function isPrecheckDiff(args: string[]): boolean {
  return args[0] === "diff" && args.includes("--name-status");
}

/** A non-fast-forward default-branch clone; local verbs answer from `s`. */
function script(s: Shape = {}): void {
  const { status = "", revList = "2\n", headRef = "main\n", nonKbDiff = 0, kbDiff = 0 } = s;
  gitSpy.mockImplementation(async (args) => {
    if (args[0] === "pull") throw NON_FF;
    return Buffer.from("");
  });
  localSpy.mockImplementation(async (args) => {
    switch (args[0]) {
      case "symbolic-ref":
        return Buffer.from(s.symbolicRef ?? "refs/remotes/origin/main\n");
      case "reset":
        if (s.resetThrows) throw s.resetThrows;
        return Buffer.from("");
      case "rev-list":
        return Buffer.from(revList);
      case "rev-parse":
        return Buffer.from(headRef);
      case "status":
        if (s.statusThrows) throw new Error("status broke");
        return Buffer.from(status);
      case "diff": {
        if (isPrecheckDiff(args)) return Buffer.from(s.precheck ?? "", "latin1");
        const code = isNonKbDiff(args) ? nonKbDiff : kbDiff;
        if (code !== 0) throw exit(code);
        return Buffer.from("");
      }
      default:
        return Buffer.from("");
    }
  });
}

const run = () => syncWorkspace(1, WS, log, { userId: "u-1", workspaceId: "w-1", op: "push" });
const localVerbs = (): string[] => localSpy.mock.calls.map(([a]) => a[0]);
const tokenVerbs = (): string[] => gitSpy.mock.calls.map(([a]) => a[0]);
const opOf = (call: unknown[]): string => (call[1] as { op?: string }).op ?? "";
const allEmits = (): unknown[][] => [...reportSpy.mock.calls, ...warnSpy.mock.calls, ...mirrorSpy.mock.calls, ...mirrorWarnSpy.mock.calls];
const ALL_SPIES = [gitSpy, localSpy, reportSpy, warnSpy, mirrorSpy, mirrorWarnSpy];
const ENOENT = (): Error => Object.assign(new Error("ENOENT"), { code: "ENOENT" });
const DIR = { isDirectory: () => true };

beforeEach(() => {
  for (const f of ALL_SPIES) f.mockReset();
  lstatSpy.mockReset();
  disposeSpy.mockClear();
  mergeSpy.mockClear();
  for (const f of [H2.writerSpy, H2.innerMerge, H2.heldWriteSpy, H2.lockSpy, H2.repoUrlSpy, H2.readRemoteSpy, H2.pinSpy]) f.mockClear();
  H2.serviceRow = { data: { repo_url: "https://github.com/acme/widget" }, error: null };
  H2.serviceCalls.length = 0;
  H2.heads.length = 0;
  H2.isolatedRefusal = null;
  (log as unknown as Record<string, ReturnType<typeof vi.fn>>).info.mockClear();
  (log as unknown as Record<string, ReturnType<typeof vi.fn>>).warn.mockClear();
  (log as unknown as Record<string, ReturnType<typeof vi.fn>>).error.mockClear();
  lstatSpy.mockImplementation(async () => {
    throw ENOENT();
  });
});

describe("selfHealNonFastForward: dirty tracked tree refuses on both arms (D6a/b)", () => {
  test("a tracked change outside knowledge-base/ with held commits -> no branch-aside, no reset, op self-heal-aborted-dirty-tracked at warning", async () => {
    script({ status: " M src/s.ts\0" });
    const result = await run();
    expect(result).toEqual(expect.objectContaining({ ok: false, errorClass: "non_fast_forward", held: "dirty_tracked" }));
    expect(localVerbs()).not.toContain("reset");
    expect(localVerbs()).not.toContain("branch");
    expect(reportSpy).not.toHaveBeenCalled();
    expect(mirrorWarnSpy).toHaveBeenCalledTimes(1);
    const [err, ctx, key, errorClass] = mirrorWarnSpy.mock.calls[0] as [unknown, { feature: string; op: string; message: string; extra: Record<string, unknown> }, string, string];
    expect(err).toBeNull();
    expect(ctx.feature).toBe("kb-route-helpers");
    expect(ctx.op).toBe("self-heal-aborted-dirty-tracked");
    expect(ctx.extra).toEqual({ userId: "u-1" });
    expect(ctx.message).not.toMatch(/src\/s\.ts/);
    expect(key).toBe(WS);
    expect(errorClass).toBe("self-heal-aborted-dirty-tracked");
  });

  test("only knowledge-base/ changes also refuse (the KB exemption is gone)", async () => {
    script({ status: " M knowledge-base/a.md\0" });
    const result = await run();
    expect(result.ok).toBe(false);
    expect(localVerbs()).not.toContain("reset");
    expect(localVerbs()).not.toContain("branch");
    expect(mirrorWarnSpy.mock.calls.map(opOf)).toEqual(["self-heal-aborted-dirty-tracked"]);
  });

  test("the phantom arm (rev-list 0) with a dirty tracked file refuses too: the gate sits above the commit split", async () => {
    script({ status: " M app/x.ts\0", revList: "0\n" });
    const result = await run();
    expect(result.ok).toBe(false);
    expect(localVerbs()).not.toContain("reset");
    expect(mirrorWarnSpy.mock.calls.map(opOf)).toEqual(["self-heal-aborted-dirty-tracked"]);
    expect(warnSpy.mock.calls.map(opOf)).not.toContain("self-heal-reset");
  });

  test("the status call is untracked-files=no, NUL-separated, and runs before rev-list", async () => {
    script();
    await run();
    const status = localSpy.mock.calls.find(([a]) => a[0] === "status")?.[0];
    expect(status).toEqual(["status", "--porcelain", "-z", "--untracked-files=no"]);
    expect(localVerbs().indexOf("status")).toBeLessThan(localVerbs().indexOf("rev-list"));
  });

  test("a failing status read refuses the reset (fail closed) as self-heal-failed with a null error and extra.errName", async () => {
    script({ statusThrows: true });
    const result = await run();
    expect(result.ok).toBe(false);
    expect(result).not.toHaveProperty("held");
    expect(localVerbs()).not.toContain("reset");
    const failed = reportSpy.mock.calls.filter((c) => opOf(c) === "self-heal-failed");
    expect(failed).toHaveLength(1);
    expect(failed[0][0]).toBeNull();
    // the scripted throw is called synchronously from the self-heal, so its stack's first app frame is the call site (D20)
    expect((failed[0][1] as { extra: Record<string, unknown> }).extra).toEqual({
      userId: "u-1",
      errName: "Error",
      frame: expect.stringMatching(/^server\/workspace-sync\.ts:\d+:\d+$/),
    });
  });
});

describe("selfHealNonFastForward: held commits reset only when their content is upstream (D6c interim)", () => {
  test("held commits whose content is upstream (squash-merged side PR) -> branch-aside + reset, op self-heal-recovered-diverged", async () => {
    script({ nonKbDiff: 0, kbDiff: 0 });
    const result = await run();
    expect(result).toEqual({ ok: true, recovered: true });
    expect(localVerbs()).toEqual(expect.arrayContaining(["branch", "reset"]));
    expect(localVerbs().indexOf("branch")).toBeLessThan(localVerbs().indexOf("reset"));
    expect(warnSpy.mock.calls.map(opOf)).toEqual(["self-heal-recovered-diverged"]);
    const nonKb = localSpy.mock.calls.find(([a]) => isNonKbDiff(a))?.[0];
    // D15(c): the full remote-tracking refname everywhere (a bare `origin/main` DWIMs to refs/heads/origin/main first)
    expect(nonKb).toEqual(["diff", "--quiet", "--no-ext-diff", "--no-textconv", "refs/remotes/origin/main...HEAD", "--", ".", ":(exclude)knowledge-base/"]);
    const kb = localSpy.mock.calls.find(([a]) => a[0] === "diff" && !isNonKbDiff(a) && !isPrecheckDiff(a))?.[0];
    expect(kb).toEqual(["diff", "--quiet", "--no-ext-diff", "--no-textconv", "refs/remotes/origin/main", "HEAD", "--", "knowledge-base/"]);
    expect(localSpy.mock.calls.find(([a]) => a[0] === "rev-list")?.[0]).toEqual(["rev-list", "--count", "refs/remotes/origin/main..HEAD"]);
    // D15(a): the precheck lists A/D paths HEAD -> target, then `reset --keep` (the structural backstop), never --hard
    expect(localSpy.mock.calls.find(([a]) => isPrecheckDiff(a))?.[0]).toEqual(["diff", "--name-status", "-z", "--no-renames", "--no-ext-diff", "--no-textconv", "--diff-filter=AD", "HEAD", "refs/remotes/origin/main", "--"]);
    expect(localSpy.mock.calls.find(([a]) => a[0] === "reset")?.[0]).toEqual(["reset", "--keep", "refs/remotes/origin/main"]);
  });

  test("the precheck runs before the branch-aside, so a refusal never leaves a recovery branch", async () => {
    script({ nonKbDiff: 0, kbDiff: 0 });
    await run();
    const precheckAt = localSpy.mock.calls.findIndex(([a]) => isPrecheckDiff(a));
    const branchAt = localSpy.mock.calls.findIndex(([a]) => a[0] === "branch");
    expect(precheckAt).toBeGreaterThan(-1);
    expect(precheckAt).toBeLessThan(branchAt);
  });

  test("held non-KB commits whose merge pre-check conflicts -> refused, op self-heal-aborted-held-commits, held_kind nonkb, tag reason = the pull reason, no branch-aside, no reset", async () => {
    script({ nonKbDiff: 1 });
    const result = await run();
    expect(mergeSpy).toHaveBeenCalledWith(expect.objectContaining({ precheck: true }));
    expect(disposeSpy).toHaveBeenCalledTimes(1);
    expect(result).toEqual(expect.objectContaining({ ok: false, errorClass: "non_fast_forward", held: "held_commits" }));
    expect(localVerbs()).not.toContain("reset");
    expect(localVerbs()).not.toContain("branch");
    expect(reportSpy).not.toHaveBeenCalled();
    const [err, ctx, key, errorClass] = mirrorWarnSpy.mock.calls[0] as [unknown, { op: string; tags: Record<string, string> }, string, string];
    expect(err).toBeNull();
    expect(ctx.op).toBe("self-heal-aborted-held-commits");
    expect(ctx.tags).toEqual({ held_kind: "nonkb", reason: "merge_conflict_precheck" });
    expect(key).toBe(WS);
    // D20 + obs F2: keyed `<op>:<held_kind>:<reason>`, so a kb hold and a nonkb hold on one workspace are separate
    // debounce classes, and a later reason never hides behind an earlier one's slot
    expect(errorClass).toBe("self-heal-aborted-held-commits:nonkb:merge_conflict_precheck");
  });

  test("D27: held commits whose hardened merge succeeds -> ok, no reset, no branch-aside, no emit", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "merged", remote: null });
    expect(await run()).toEqual({ ok: true });
    expect(localVerbs()).not.toContain("reset");
    expect(localVerbs()).not.toContain("branch");
    expect(allEmits()).toEqual([]);
    expect(disposeSpy).toHaveBeenCalledTimes(1);
  });

  test("held KB-only commits upstream lacks -> refused with held_kind kb (not stranded on a recovery branch)", async () => {
    script({ nonKbDiff: 0, kbDiff: 1 });
    const result = await run();
    expect(result.ok).toBe(false);
    expect(localVerbs()).not.toContain("branch");
    expect(localVerbs()).not.toContain("reset");
    const ctx = mirrorWarnSpy.mock.calls[0][1] as { op: string; tags: Record<string, string> };
    expect(ctx.op).toBe("self-heal-aborted-held-commits");
    expect(ctx.tags.held_kind).toBe("kb");
    expect(mirrorWarnSpy.mock.calls[0][3]).toBe("self-heal-aborted-held-commits:kb:merge_conflict_precheck");
    expect(result).toEqual(expect.objectContaining({ held: "held_commits" }));
  });

  test("a diff that exits neither 0 nor 1 fails closed (self-heal-failed, no reset)", async () => {
    script({ nonKbDiff: 128 });
    const result = await run();
    expect(result.ok).toBe(false);
    expect(localVerbs()).not.toContain("reset");
    expect(reportSpy.mock.calls.map(opOf)).toEqual(["self-heal-failed"]);
  });
});

describe("selfHealNonFastForward: branch checks on both arms (D6f)", () => {
  test("phantom arm on a feature branch -> abort with self-heal-aborted-dirty at error, debounced per workspace (D15e), no reset", async () => {
    script({ revList: "0\n", headRef: "feat\n" });
    const result = await run();
    expect(result.ok).toBe(false);
    expect(result).not.toHaveProperty("held");
    expect(localVerbs()).not.toContain("reset");
    expect(reportSpy).not.toHaveBeenCalled();
    expect(mirrorSpy).toHaveBeenCalledTimes(1);
    const [err, ctx, key, cls] = mirrorSpy.mock.calls[0] as [unknown, { op: string; tags: Record<string, string> }, string, string];
    expect(err).toBeNull();
    expect([ctx.op, ctx.tags, key, cls]).toEqual(["self-heal-aborted-dirty", { head: "non_default" }, WS, "self-heal-aborted-dirty"]);
  });

  test("phantom arm on a detached HEAD -> abort with self-heal-aborted-detached-head at error, debounced per workspace, no reset", async () => {
    script({ revList: "0\n", headRef: "HEAD\n" });
    const result = await run();
    expect(result.ok).toBe(false);
    expect(result).not.toHaveProperty("held");
    expect(localVerbs()).not.toContain("reset");
    expect(reportSpy).not.toHaveBeenCalled();
    const [err, ctx, key, cls] = mirrorSpy.mock.calls[0] as [unknown, { op: string; tags: Record<string, string> }, string, string];
    expect(err).toBeNull();
    expect([ctx.op, ctx.tags, key, cls]).toEqual(["self-heal-aborted-detached-head", { head: "detached" }, WS, "self-heal-aborted-detached-head"]);
  });

  test("an un-countable rev-list on the default branch -> the -dirty slug with tag head=uncountable and its own message", async () => {
    script({ revList: "\n" });
    const result = await run();
    expect(result.ok).toBe(false);
    expect(localVerbs()).not.toContain("reset");
    const [, ctx] = mirrorSpy.mock.calls[0] as [unknown, { op: string; tags: Record<string, string>; message: string }];
    expect(ctx.op).toBe("self-heal-aborted-dirty");
    expect(ctx.tags).toEqual({ head: "uncountable" });
    expect(ctx.message).toMatch(/local-commit count/);
    expect(ctx.message).not.toMatch(/not on the default branch/);
  });

  test("phantom arm on the default branch with a clean tree still resets (op self-heal-reset, null error)", async () => {
    script({ revList: "0\n" });
    const result = await run();
    expect(result).toEqual({ ok: true, recovered: true });
    expect(localVerbs()).toContain("reset");
    expect(localVerbs()).not.toContain("branch");
    expect(warnSpy.mock.calls.map(opOf)).toEqual(["self-heal-reset"]);
    expect(warnSpy.mock.calls[0][0]).toBeNull();
  });
});

describe("selfHealNonFastForward: token-free local verbs (D6d) and null-first emits (D8)", () => {
  test("only pull and fetch reach the token-bearing runner; every local verb, symbolic-ref included (D15d), runs token-free", async () => {
    script({ nonKbDiff: 0, kbDiff: 0 });
    await run();
    expect(new Set(tokenVerbs())).toEqual(new Set(["pull", "fetch"]));
    expect(new Set(localVerbs())).toEqual(new Set(["symbolic-ref", "rev-parse", "status", "rev-list", "diff", "branch", "reset"]));
    for (const [, opts] of localSpy.mock.calls) expect(opts.cwd).toBe(WS);
  });

  test("the default branch comes from the FULL symbolic-ref target, read token-free (D15d)", async () => {
    script({ symbolicRef: "refs/remotes/origin/trunk\n", headRef: "trunk\n", revList: "0\n" });
    const result = await run();
    expect(result).toEqual({ ok: true, recovered: true });
    expect(localSpy.mock.calls.find(([a]) => a[0] === "symbolic-ref")?.[0]).toEqual(["symbolic-ref", "refs/remotes/origin/HEAD"]);
    // D23: an explicit refspec, so D is never a bare argv word git could parse as an option. Forced (`+`), as the clone's
    // configured `+refs/heads/*:refs/remotes/origin/*` was: measured on git 2.56, a non-forced refspec exits 1
    // (`! [rejected] ... (non-fast-forward)`) after an upstream force-push, the phantom divergence this self-heal resets.
    expect(gitSpy.mock.calls.find(([a]) => a[0] === "fetch")?.[0]).toEqual(["fetch", "origin", "+refs/heads/trunk:refs/remotes/origin/trunk"]);
    expect(localSpy.mock.calls.find(([a]) => a[0] === "reset")?.[0]).toEqual(["reset", "--keep", "refs/remotes/origin/trunk"]);
  });

  test.each([
    ["starts with '-' (an option in fetch's argv)", "refs/remotes/origin/--upload-pack=x\n"],
    ["starts with '-' (a CLI override of a config pin)", "refs/remotes/origin/--recurse-submodules=yes\n"],
    ["fails validateBranchFormat ('..')", "refs/remotes/origin/a..b\n"],
    ["fails validateBranchFormat ('.lock')", "refs/remotes/origin/x.lock\n"],
  ])("D23: a default branch from origin/HEAD that %s is unresolvable: the fail-closed `main` fallback, never in argv", async (_why, symbolicRef) => {
    script({ symbolicRef, revList: "0\n" });
    const result = await run();
    expect(result).toEqual({ ok: true, recovered: true });
    const fetch = gitSpy.mock.calls.find(([a]) => a[0] === "fetch")?.[0];
    expect(fetch).toEqual(["fetch", "origin", "+refs/heads/main:refs/remotes/origin/main"]);
    const bad = symbolicRef.trim().slice("refs/remotes/origin/".length);
    for (const [args] of [...gitSpy.mock.calls, ...localSpy.mock.calls]) for (const a of args) expect(a).not.toContain(bad);
    expect(localSpy.mock.calls.find(([a]) => a[0] === "reset")?.[0]).toEqual(["reset", "--keep", "refs/remotes/origin/main"]);
  });

  test("every self-heal emit passes a null error", async () => {
    const shapes: Shape[] = [
      { status: " M a\0" },
      { nonKbDiff: 1 },
      { revList: "0\n", headRef: "feat\n" },
      { revList: "0\n", headRef: "HEAD\n" },
      { revList: "0\n" },
      {},
      { statusThrows: true },
      { revList: "\n" },
    ];
    for (const s of shapes) {
      for (const f of ALL_SPIES) f.mockReset();
      script(s);
      await run();
      expect(allEmits().length).toBeGreaterThan(0);
      for (const call of allEmits()) expect(call[0]).toBeNull();
    }
  });
});

describe("selfHealNonFastForward: self-heal-failed carries a code frame, never the message (D20)", () => {
  test("a throw whose stack runs through server/ gets extra.frame = the first repo-relative server|app|lib file:line", async () => {
    const boom = new Error("fatal: secret-looking /workspaces/u-1 argv");
    boom.stack = [
      "Error: fatal: secret-looking /workspaces/u-1 argv",
      "    at ChildProcess.exithandler (node:child_process:422:12)",
      "    at Object.<anonymous> (/srv/app/node_modules/pkg/index.js:9:3)",
      "    at selfHealNonFastForward (/srv/app/apps/web-platform/server/workspace-sync.ts:347:11)",
      "    at syncWorkspace (/srv/app/apps/web-platform/server/workspace-sync.ts:169:14)",
    ].join("\n");
    script({ revList: "0\n", resetThrows: boom });
    await run();
    const failed = reportSpy.mock.calls.filter((c) => opOf(c) === "self-heal-failed");
    expect(failed).toHaveLength(1);
    const ctx = failed[0][1] as { extra: Record<string, unknown>; message: string };
    expect(ctx.extra).toEqual({ userId: "u-1", errName: "Error", frame: "server/workspace-sync.ts:347:11" });
    expect(String(ctx.extra.frame)).toMatch(/^[\w./-]+:\d+:\d+$/);
    expect(JSON.stringify(failed[0])).not.toContain("secret-looking");
  });

  test("a stack with no server|app|lib frame (node internals, node_modules, tests) omits extra.frame", async () => {
    const boom = new Error("reset broke");
    boom.stack = [
      "Error: reset broke",
      "    at ChildProcess.exithandler (node:child_process:422:12)",
      "    at run (/srv/app/node_modules/vitest/dist/index.js:1:1)",
      "    at fixture (/srv/app/apps/web-platform/test/server/x.test.ts:9:3)",
    ].join("\n");
    script({ revList: "0\n", resetThrows: boom });
    await run();
    const ctx = reportSpy.mock.calls.find((c) => opOf(c) === "self-heal-failed")?.[1] as { extra: Record<string, unknown> };
    expect(ctx.extra).toEqual({ userId: "u-1", errName: "Error" });
  });

  test("a forged `at` line inside the MESSAGE never becomes the frame", async () => {
    const boom = new Error("stderr:\n    at evil (/x/apps/web-platform/server/forged.ts:1:1)");
    boom.stack = `${boom.name}: ${boom.message}\n    at ChildProcess.exithandler (node:child_process:422:12)`;
    script({ revList: "0\n", resetThrows: boom });
    await run();
    const ctx = reportSpy.mock.calls.find((c) => opOf(c) === "self-heal-failed")?.[1] as { extra: Record<string, unknown> };
    expect(ctx.extra).not.toHaveProperty("frame");
  });
});

describe("selfHealNonFastForward: the D15(a) precheck's cost (D23)", () => {
  const z = (...fields: string[]): string => fields.map((f) => `${f}\0`).join("");

  test("leading directories shared by many added paths are lstat'ed once per call (memoised)", async () => {
    script({ revList: "0\n", precheck: z("A", "d/a/x.md", "A", "d/a/y.md", "A", "d/a/z.md", "A", "d/b.md") });
    lstatSpy.mockImplementation(async (p) => {
      const rel = p.toString("latin1").slice(`${WS}/`.length);
      if (rel === "d" || rel === "d/a") return DIR;
      throw ENOENT();
    });
    const result = await run();
    expect(result).toEqual({ ok: true, recovered: true });
    const probes = lstatSpy.mock.calls.map(([p]) => p.toString("latin1").slice(`${WS}/`.length));
    expect(probes.filter((p) => p === "d")).toHaveLength(1);
    expect(probes.filter((p) => p === "d/a")).toHaveLength(1);
    // every added path itself is still probed (shape 1)
    for (const p of ["d/a/x.md", "d/a/y.md", "d/a/z.md", "d/b.md"]) expect(probes).toContain(p);
  });

  test("the memo still refuses: a non-directory at a shared leading directory refuses on the first added path under it", async () => {
    script({ revList: "0\n", precheck: z("A", "docs/a.md", "A", "docs/b.md") });
    lstatSpy.mockImplementation(async (p) => {
      if (p.toString("latin1") === `${WS}/docs`) return { isDirectory: () => false };
      throw ENOENT();
    });
    const result = await run();
    expect(result).toEqual(expect.objectContaining({ ok: false, held: "untracked_collision" }));
    expect(localVerbs()).not.toContain("reset");
  });

  test("shape 3 lists a wholly-untracked subdirectory as ONE entry: `ls-files --others --directory`", async () => {
    script({ revList: "0\n", precheck: z("A", "src", "D", "src/s.ts") });
    lstatSpy.mockImplementation(async (p) => {
      if (p.toString("latin1") === `${WS}/src`) return DIR;
      throw ENOENT();
    });
    const result = await run();
    expect(result).toEqual({ ok: true, recovered: true });
    expect(localSpy.mock.calls.find(([a]) => a[0] === "ls-files")?.[0]).toEqual(["ls-files", "-z", "--others", "--directory", "--", ":(literal)src/"]);
  });
});

// ---------------------------------------------------------------------------------------------------------------------
// Review fix round 1, WP2 (CTO rulings D37 caller side, D38(4), D39(a), D42, D43; obs F2/F4; structural 3a#9).
// ---------------------------------------------------------------------------------------------------------------------

const T_TIP = "b".repeat(40);
const READ_AT = new Date("2026-11-17T10:00:00.000Z");
const REMOTE = { defaultBranch: "main", tip: T_TIP, sideTip: null, readAt: READ_AT };
const runSystem = () => syncWorkspace(1, WS, log, { system: true, workspaceId: "w-1", op: "manual" });
const heldOf = (r: Awaited<ReturnType<typeof run>>): string | undefined => (r.ok ? undefined : r.held);
const warnCtx = (i = 0) => mirrorWarnSpy.mock.calls[i] as [unknown, { op: string; tags: Record<string, string>; extra: Record<string, unknown>; message: string }, string, string];
/** Every KbPullHeldReason, as a Record so a new member fails this file's compile (structural 3a#9). */
const ALL_REASONS: Record<import("@/server/kb-sync-pull").KbPullHeldReason, true> = {
  remote_state: true, fetch_failed: true, isolated_refused: true, tip_mismatch: true, shallow_changed: true, walk_cap: true,
  handover_failed: true, handover_too_large: true, unresolved_merge: true, merge_conflict: true, merge_refused: true,
  autostash_conflict: true, merge_conflict_precheck: true, side_not_kb_only: true, side_pr_unknown: true, up_to_date: true,
  merged: true, non_default_branch: true, side_declined: true, side_pr_created: true, side_linked: true, side_conflict: true,
  untracked_collision: true, merge_unverified: true, pull_deadline: true, side_pr_create_failed: true, pull_unexpected: true,
};

describe("WP2: the self-heal's merge writer and result (D37(2)(3)(4), structural 3a#9)", () => {
  test("D37(2): the writer is the second pinned shape, built with { autostash: false }", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "merged", remote: null });
    await run();
    expect(H2.writerSpy).toHaveBeenCalledTimes(1);
    expect(H2.writerSpy).toHaveBeenCalledWith(WS, { autostash: false });
  });

  test("D37(3), H1: up_to_date (the remote moved between the legacy fetch and the ls-remote) is { ok: true }, no warning", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "up_to_date", remote: REMOTE });
    expect(await run()).toEqual({ ok: true });
    expect(allEmits()).toEqual([]);
    expect(localVerbs()).not.toContain("reset");
  });

  test("D37(1) caller side: a writer that finds an unfinished merge (unresolved_merge) refuses: held, no reset, no branch-aside, no count", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "unresolved_merge", remote: REMOTE });
    const result = await run();
    expect(result).toEqual(expect.objectContaining({ ok: false, errorClass: "non_fast_forward", held: "held_commits" }));
    expect(localVerbs()).not.toContain("reset");
    expect(localVerbs()).not.toContain("branch");
    expect(H2.heldWriteSpy).not.toHaveBeenCalled();
    const [, ctx] = warnCtx();
    expect(ctx.tags).toEqual({ held_kind: "nonkb", reason: "unresolved_merge" });
    // structural 3a#9: the message names what happened, not "local commits hold content upstream lacks"
    expect(ctx.message).toMatch(/unfinished merge|mid-merge/);
  });

  test("structural 3a#9: only merged and up_to_date return ok; every other reason refuses with a hold (the route answers pending)", async () => {
    for (const reason of Object.keys(ALL_REASONS)) {
      script({ nonKbDiff: 1 });
      mirrorWarnSpy.mockClear();
      mergeSpy.mockResolvedValueOnce({ reason, remote: null });
      const result = await run();
      if (reason === "merged" || reason === "up_to_date") {
        expect(result, reason).toEqual({ ok: true });
      } else {
        expect(result.ok, reason).toBe(false);
        expect(heldOf(result), reason).toBe(reason === "untracked_collision" ? "untracked_collision" : "held_commits");
        expect(mirrorWarnSpy, reason).toHaveBeenCalledTimes(1);
      }
    }
  });

  test("structural 3a#9: a conflict the merge left behind, a not-started merge and a remote failure get three different messages", async () => {
    const messageFor = async (reason: string): Promise<string> => {
      script({ nonKbDiff: 1 });
      mirrorWarnSpy.mockClear();
      mergeSpy.mockResolvedValueOnce({ reason, remote: null });
      await run();
      return warnCtx()[1].message;
    };
    const left = await messageFor("merge_conflict");
    const notStarted = await messageFor("merge_conflict_precheck");
    const failed = await messageFor("remote_state");
    expect(new Set([left, notStarted, failed]).size).toBe(3);
    expect(failed).not.toMatch(/upstream lacks/);
  });
});

describe("WP2: observability of the held-commits refusal (obs F2, obs F4)", () => {
  test("obs F2: the pino line names the reason, and the debounce class is `<op>:<held_kind>:<reason>`", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "tip_mismatch", remote: null });
    await run();
    const warnLine = (log as unknown as { warn: ReturnType<typeof vi.fn> }).warn.mock.calls.find(([o]) => (o as { reason?: string }).reason);
    expect(warnLine?.[0]).toEqual(expect.objectContaining({ reason: "tip_mismatch", heldKind: "nonkb" }));
    expect(warnCtx()[3]).toBe("self-heal-aborted-held-commits:nonkb:tip_mismatch");
  });

  test("obs F2: two different reasons on one workspace land in two debounce slots", async () => {
    for (const reason of ["remote_state", "tip_mismatch"]) {
      script({ nonKbDiff: 1 });
      mergeSpy.mockResolvedValueOnce({ reason, remote: null });
      await run();
    }
    expect(mirrorWarnSpy.mock.calls.map((c) => c[3])).toEqual([
      "self-heal-aborted-held-commits:nonkb:remote_state",
      "self-heal-aborted-held-commits:nonkb:tip_mismatch",
    ]);
  });

  test("obs F4: an isolated-dir refusal carries its reason as tag isolated_reason", async () => {
    script({ nonKbDiff: 1 });
    H2.isolatedRefusal = "object_store_too_large";
    const result = await run();
    expect(mergeSpy).not.toHaveBeenCalled();
    expect(heldOf(result)).toBe("held_commits");
    expect(warnCtx()[1].tags).toEqual({ held_kind: "nonkb", reason: "isolated_refused", isolated_reason: "object_store_too_large" });
  });
});

describe("WP2: the self-heal writes the held count and the pull-blocked state (D39(a), D42)", () => {
  test("merged: the count is rewritten on this run's T, the POST-merge HEAD and T's read instant; pullBlocked cleared", async () => {
    script({ nonKbDiff: 1 });
    H2.heads.push("a".repeat(40), "c".repeat(40)); // HEAD before the merge, then the merge commit
    mergeSpy.mockResolvedValueOnce({ reason: "merged", remote: REMOTE });
    expect(await run()).toEqual({ ok: true });
    expect(H2.heldWriteSpy).toHaveBeenCalledTimes(1);
    expect(H2.heldWriteSpy).toHaveBeenCalledWith(
      expect.objectContaining({ workspacePath: WS, workspaceId: "w-1", T: T_TIP, headSha: "c".repeat(40), checkedAt: READ_AT, pullBlocked: null }),
    );
    // the count runs on the isolated dir the merge held, before it is disposed
    expect((H2.heldWriteSpy.mock.calls[0] as unknown as [{ isolated: unknown }])[0].isolated).toEqual(expect.objectContaining({ gitDir: "/tmp/iso" }));
    expect(H2.heldWriteSpy.mock.invocationCallOrder[0]).toBeLessThan(disposeSpy.mock.invocationCallOrder[0]);
  });

  test("up_to_date: the count is written on the unchanged HEAD, pullBlocked cleared", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "up_to_date", remote: REMOTE });
    await run();
    expect(H2.heldWriteSpy).toHaveBeenCalledWith(expect.objectContaining({ T: T_TIP, headSha: "a".repeat(40), pullBlocked: null }));
  });

  test("merge_conflict_precheck sets pullBlocked = merge_conflict_precheck with the count", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "merge_conflict_precheck", remote: REMOTE });
    const result = await run();
    expect(heldOf(result)).toBe("held_commits");
    expect(H2.heldWriteSpy).toHaveBeenCalledWith(expect.objectContaining({ T: T_TIP, headSha: "a".repeat(40), pullBlocked: "merge_conflict_precheck" }));
  });

  test("the writer's untracked_collision (D35) sets pullBlocked = untracked_collision and refuses as the collision hold", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "untracked_collision", remote: REMOTE });
    const result = await run();
    expect(heldOf(result)).toBe("untracked_collision");
    expect(H2.heldWriteSpy).toHaveBeenCalledWith(expect.objectContaining({ pullBlocked: "untracked_collision" }));
    expect(mirrorWarnSpy.mock.calls.map(opOf)).toEqual(["self-heal-aborted-untracked-collision"]);
  });

  test("the pre-call untracked collision on the held arm reads T (count only, no merge) and sets pullBlocked = untracked_collision", async () => {
    script({ nonKbDiff: 1, precheck: "A\0new.txt\0" });
    lstatSpy.mockImplementation(async (p: Buffer) => {
      if (p.toString().endsWith("/new.txt")) return { isDirectory: () => false };
      throw ENOENT();
    });
    H2.readRemoteSpy.mockResolvedValueOnce(REMOTE);
    const result = await run();
    expect(heldOf(result)).toBe("untracked_collision");
    expect(mergeSpy).not.toHaveBeenCalled();
    expect(H2.writerSpy).not.toHaveBeenCalled();
    expect(H2.readRemoteSpy).toHaveBeenCalledTimes(1);
    expect(H2.heldWriteSpy).toHaveBeenCalledWith(expect.objectContaining({ T: T_TIP, headSha: "a".repeat(40), checkedAt: READ_AT, pullBlocked: "untracked_collision" }));
    expect(disposeSpy).toHaveBeenCalledTimes(1);
  });

  test("no remote read (remote_state), or HEAD not on the remote's default branch (X5): no count is attempted, nothing written", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "remote_state", remote: null });
    await run();
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "up_to_date", remote: { ...REMOTE, defaultBranch: "trunk" } });
    await run();
    // the count-only path of the pre-call collision applies the same X5 rule
    script({ nonKbDiff: 1, precheck: "A\0new.txt\0" });
    lstatSpy.mockImplementation(async (p: Buffer) => {
      if (p.toString().endsWith("/new.txt")) return { isDirectory: () => false };
      throw ENOENT();
    });
    H2.readRemoteSpy.mockResolvedValueOnce({ ...REMOTE, defaultBranch: "trunk" });
    expect(heldOf(await run())).toBe("untracked_collision");
    expect(H2.readRemoteSpy).toHaveBeenCalledTimes(1);
    expect(H2.heldWriteSpy).not.toHaveBeenCalled();
  });

  test("a merge that ran and left state (merge_conflict) writes no count (only the four D39(a) outcomes do)", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "merge_conflict", remote: REMOTE });
    await run();
    expect(H2.heldWriteSpy).not.toHaveBeenCalled();
  });
});

describe("WP2: system callers read the repo URL through the service client (D43)", () => {
  test("system: no tenant mint (the tenant repo-URL read is never called); the URL comes from the service read keyed on the job's workspace, ready only", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "merged", remote: null });
    expect(await runSystem()).toEqual({ ok: true });
    expect(H2.repoUrlSpy).not.toHaveBeenCalled();
    expect(H2.serviceCalls).toEqual([
      ["from", "workspaces"],
      ["select", "repo_url"],
      ["eq", "id", "w-1"],
      ["eq", "repo_status", "ready"],
      ["maybeSingle"],
    ]);
    expect(mergeSpy).toHaveBeenCalledWith(expect.objectContaining({ url: "https://github.com/acme/widget.git" }));
  });

  test("system: no ready row (or a read error) is remote_state, with no merge", async () => {
    script({ nonKbDiff: 1 });
    H2.serviceRow = { data: null, error: null };
    const result = await runSystem();
    expect(mergeSpy).not.toHaveBeenCalled();
    expect(heldOf(result)).toBe("held_commits");
    expect(warnCtx()[1].tags).toEqual(expect.objectContaining({ reason: "remote_state" }));
    script({ nonKbDiff: 1 });
    H2.serviceRow = { data: null, error: { code: "57014" } };
    await runSystem();
    expect(mergeSpy).not.toHaveBeenCalled();
  });

  test("system: the pino lines and the mirror extra carry workspaceId, never a userId", async () => {
    script({ nonKbDiff: 1 });
    await runSystem();
    const lines = [...(log as unknown as Record<string, ReturnType<typeof vi.fn>>).info.mock.calls, ...(log as unknown as Record<string, ReturnType<typeof vi.fn>>).warn.mock.calls].map(([o]) => o as Record<string, unknown>);
    expect(lines.length).toBeGreaterThan(0);
    for (const o of lines) {
      expect(o).not.toHaveProperty("userId");
      expect(o.workspaceId).toBe("w-1");
    }
    expect(warnCtx()[1].extra).toEqual(expect.objectContaining({ workspaceId: "w-1" }));
    expect(warnCtx()[1].extra).not.toHaveProperty("userId");
  });

  test("route callers keep the tenant read on (userId, workspaceId) and never touch the service client", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockResolvedValueOnce({ reason: "merged", remote: null });
    await run();
    expect(H2.repoUrlSpy).toHaveBeenCalledWith("u-1", "w-1");
    expect(H2.serviceCalls).toEqual([]);
  });
});

describe("WP2: the self-heal budget gates the merge's start (D38(3)(4)(6))", () => {
  let clock = 0;
  beforeEach(() => {
    clock = 1_000_000;
    vi.spyOn(Date, "now").mockImplementation(() => clock);
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });
  /** The legacy token-bearing fetch takes `ms` (the self-heal's first network step). */
  const slowFetch = (ms: number) => {
    const base = gitSpy.getMockImplementation();
    gitSpy.mockImplementation(async (args) => {
      if (args[0] === "fetch") clock += ms;
      return base!(args);
    });
  };

  test("route caller: the 15 s budget leaves under 5 s before the merge -> pending (held), no merge, no network merge steps", async () => {
    script({ nonKbDiff: 1 });
    slowFetch(11_000);
    const result = await run();
    expect(mergeSpy).not.toHaveBeenCalled();
    expect(heldOf(result)).toBe("held_commits");
    expect(warnCtx()[1].tags).toEqual(expect.objectContaining({ reason: "pull_deadline" }));
  });

  test("route caller: a budget that expires during the merge's network steps stops the merge child from starting (writer gate)", async () => {
    script({ nonKbDiff: 1 });
    mergeSpy.mockImplementationOnce(async (input) => {
      clock += 12_000; // ls-remote + fetch + pre-check took 12 s
      const outcome = await input.writer.merge(T_TIP).catch(() => "refused");
      return { reason: outcome === "clean" ? "merged" : "merge_refused", remote: null };
    });
    const result = await run();
    expect(H2.innerMerge).not.toHaveBeenCalled();
    expect(heldOf(result)).toBe("held_commits");
    expect(warnCtx()[1].tags).toEqual(expect.objectContaining({ reason: "pull_deadline" }));
  });

  test("route caller: with 5 s or more left the merge starts, and a started merge is never cut short", async () => {
    script({ nonKbDiff: 1 });
    H2.innerMerge.mockImplementationOnce(async () => {
      clock += 60_000; // the merge itself runs past the budget: it keeps its own MERGE_TIMEOUT_MS
      return "clean";
    });
    mergeSpy.mockImplementationOnce(async (input) => {
      clock += 9_000;
      const outcome = await input.writer.merge(T_TIP);
      return { reason: outcome === "clean" ? "merged" : "merge_refused", remote: null };
    });
    expect(await run()).toEqual({ ok: true });
    expect(H2.innerMerge).toHaveBeenCalledTimes(1);
  });

  test("background (system) caller: 60 s budget, 20 s merge-start minimum (11 s spent still merges; 41 s spent does not)", async () => {
    script({ nonKbDiff: 1 });
    slowFetch(11_000);
    mergeSpy.mockResolvedValueOnce({ reason: "merged", remote: null });
    expect(await runSystem()).toEqual({ ok: true });
    expect(mergeSpy).toHaveBeenCalledTimes(1);
    script({ nonKbDiff: 1 });
    slowFetch(41_000);
    const late = await runSystem();
    expect(mergeSpy).toHaveBeenCalledTimes(1);
    expect(heldOf(late)).toBe("held_commits");
  });

  test("D38(6): the merge runs under the same-host workspace lock, and the lock wait counts against the budget", async () => {
    script({ nonKbDiff: 1 });
    H2.lockSpy.mockImplementationOnce(async (_p, fn) => {
      clock += 12_000; // another writer held the lock for 12 s
      return fn();
    });
    const result = await run();
    expect(H2.lockSpy).toHaveBeenCalledTimes(1);
    expect(H2.lockSpy.mock.calls[0][0]).toBe(WS);
    expect(mergeSpy).not.toHaveBeenCalled();
    expect(heldOf(result)).toBe("held_commits");
    expect(warnCtx()[1].tags).toEqual(expect.objectContaining({ reason: "pull_deadline" }));
  });

  test("D38(6): the merge itself (not the token-free gate reads) runs inside the lock", async () => {
    script({ nonKbDiff: 1 });
    let inLock = false;
    H2.lockSpy.mockImplementationOnce(async (_p, fn) => {
      inLock = true;
      try {
        return await fn();
      } finally {
        inLock = false;
      }
    });
    mergeSpy.mockImplementationOnce(async () => {
      expect(inLock).toBe(true);
      return { reason: "merged", remote: null };
    });
    expect(await run()).toEqual({ ok: true });
  });

  test("D38(4): the hardened merge's network and isolated children run on the self-heal's clock (route: 15 s total, 5 s merge start)", async () => {
    script({ nonKbDiff: 1 });
    slowFetch(4_000);
    let seen: { remaining: number; min: number } | null = null;
    mergeSpy.mockImplementationOnce(async (input) => {
      seen = { remaining: input.budget?.remaining() ?? Number.NaN, min: input.budget?.mergeStartMinMs ?? Number.NaN };
      return { reason: "merged", remote: null };
    });
    expect(await run()).toEqual({ ok: true });
    expect(seen).toEqual({ remaining: 11_000, min: 5_000 });
  });

  test("D38(4): a system caller's merge runs on its 60 s clock with the 20 s merge start", async () => {
    script({ nonKbDiff: 1 });
    slowFetch(4_000);
    let seen: { remaining: number; min: number } | null = null;
    mergeSpy.mockImplementationOnce(async (input) => {
      seen = { remaining: input.budget?.remaining() ?? Number.NaN, min: input.budget?.mergeStartMinMs ?? Number.NaN };
      return { reason: "merged", remote: null };
    });
    expect(await runSystem()).toEqual({ ok: true });
    expect(seen).toEqual({ remaining: 56_000, min: 20_000 });
  });

  test("D38(4): the pre-call collision's count-only ls-remote is capped at the budget left, and skipped once it is spent", async () => {
    const collide = () => {
      script({ nonKbDiff: 1, precheck: "A\0new.txt\0" });
      lstatSpy.mockImplementation(async (p: Buffer) => {
        if (p.toString().endsWith("/new.txt")) return { isDirectory: () => false };
        throw ENOENT();
      });
    };
    collide();
    slowFetch(4_000);
    H2.readRemoteSpy.mockResolvedValueOnce(REMOTE);
    expect(heldOf(await run())).toBe("untracked_collision");
    expect(H2.readRemoteSpy).toHaveBeenCalledTimes(1);
    expect(H2.readRemoteSpy.mock.calls[0]).toEqual([expect.anything(), 1, "https://github.com/acme/widget.git", { timeoutMs: 11_000 }]);
    H2.readRemoteSpy.mockClear();
    H2.heldWriteSpy.mockClear();
    gitSpy.mockReset();
    collide();
    slowFetch(16_000);
    expect(heldOf(await run())).toBe("untracked_collision"); // the refusal stands; only the display-only count is skipped
    expect(H2.readRemoteSpy).not.toHaveBeenCalled();
    expect(H2.heldWriteSpy).not.toHaveBeenCalled();
  });
});

describe("R2-B: the workspace lock covers every self-heal git step; the pin runs first; recoveries clear pull_blocked", () => {
  beforeEach(() => {
    // a once-implementation a row did not consume must not leak into the next row
    H2.lockSpy.mockReset();
    H2.lockSpy.mockImplementation(async (_p, fn) => fn());
    H2.readRemoteSpy.mockReset();
    H2.readRemoteSpy.mockImplementation(async () => null);
  });
  /** Runs fn with `inLock` set, so a spy can assert where each git step ran. */
  const tracking = () => {
    const where: Record<string, boolean[]> = {};
    let inLock = false;
    H2.lockSpy.mockImplementationOnce(async (_p, fn) => {
      inLock = true;
      try {
        return await fn();
      } finally {
        inLock = false;
      }
    });
    const note = (verb: string) => (where[verb] ??= []).push(inLock);
    const g = gitSpy.getMockImplementation()!;
    gitSpy.mockImplementation(async (args) => (note(args[0]), g(args)));
    const l = localSpy.getMockImplementation()!;
    localSpy.mockImplementation(async (args, opts) => (note(args[0]), l(args, opts)));
    return where;
  };

  test("verify-coverage P3-3/#4: pull --ff-only, the legacy fetch, branch-aside and reset --keep all run under the one lock", async () => {
    script({ revList: "2\n" }); // content upstream: branch-aside + reset
    const where = tracking();
    expect(await run()).toEqual({ ok: true, recovered: true });
    expect(H2.lockSpy).toHaveBeenCalledTimes(1);
    for (const verb of ["pull", "fetch", "branch", "reset"]) expect(where[verb], verb).toEqual([true]);
  });

  test("the ff-only success path runs under the lock too", async () => {
    script();
    gitSpy.mockImplementation(async () => Buffer.from(""));
    const where = tracking();
    expect(await run()).toEqual({ ok: true });
    expect(where.pull).toEqual([true]);
  });

  test("verify-coverage P2-1: the lock wait is bounded by the caller's budget (route 15 s, background 60 s)", async () => {
    script();
    await run();
    expect(H2.lockSpy.mock.calls[0][0]).toBe(WS);
    expect(H2.lockSpy.mock.calls[0][2]).toEqual({ waitMs: 15_000 });
    script();
    await runSystem();
    expect(H2.lockSpy.mock.calls[1][2]).toEqual({ waitMs: 60_000 });
  });

  test("verify-coverage P2-1: a lock that is not free in time -> a hold (the route answers pending); no git ran; one warning", async () => {
    script();
    H2.lockSpy.mockImplementationOnce(async () => "lock_timeout");
    const result = await run();
    expect(result).toEqual(expect.objectContaining({ ok: false, held: "workspace_busy" }));
    expect(gitSpy).not.toHaveBeenCalled();
    expect(localSpy).not.toHaveBeenCalled();
    expect(mirrorWarnSpy.mock.calls.map(opOf)).toEqual(["workspace-sync-lock-timeout"]);
    expect(warnCtx()[1].extra).toEqual({ userId: "u-1" });
    expect(reportSpy).not.toHaveBeenCalled();
  });

  test("the lock wait counts against the self-heal budget (a 12 s wait leaves the route under its 5 s merge start)", async () => {
    let clock = 1_000_000;
    const now = vi.spyOn(Date, "now").mockImplementation(() => clock);
    try {
      script({ nonKbDiff: 1 });
      H2.lockSpy.mockImplementationOnce(async (_p, fn) => {
        clock += 12_000;
        return fn();
      });
      const result = await run();
      expect(mergeSpy).not.toHaveBeenCalled();
      expect(heldOf(result)).toBe("held_commits");
      expect(warnCtx()[1].tags).toEqual(expect.objectContaining({ reason: "pull_deadline" }));
    } finally {
      now.mockRestore();
    }
  });

  test("data-sec P3-2: the autostash pin runs before the dirty-tracked refusal (a cc-only workspace never reaches syncPull)", async () => {
    script({ status: " M src/s.ts\0" });
    const result = await run();
    expect(heldOf(result)).toBe("dirty_tracked");
    expect(H2.pinSpy).toHaveBeenCalledTimes(1);
    expect(H2.pinSpy).toHaveBeenCalledWith(WS);
    const statusOrder = localSpy.mock.invocationCallOrder[localVerbs().indexOf("status")];
    expect(H2.pinSpy.mock.invocationCallOrder[0]).toBeLessThan(statusOrder);
  });

  test("verify-coverage #6: the reset arms (phantom, recovered-diverged) rewrite the count and clear pullBlocked", async () => {
    for (const revList of ["0\n", "2\n"]) {
      script({ revList });
      H2.heldWriteSpy.mockClear();
      H2.readRemoteSpy.mockResolvedValueOnce(REMOTE);
      expect(await run(), revList).toEqual({ ok: true, recovered: true });
      expect(H2.heldWriteSpy, revList).toHaveBeenCalledTimes(1);
      expect(H2.heldWriteSpy, revList).toHaveBeenCalledWith(expect.objectContaining({ T: T_TIP, checkedAt: READ_AT, pullBlocked: null }));
    }
  });

  test("verify-coverage #6: a system fast-forward clears pullBlocked; a route fast-forward adds no remote read", async () => {
    script();
    gitSpy.mockImplementation(async () => Buffer.from(""));
    H2.readRemoteSpy.mockResolvedValueOnce(REMOTE);
    expect(await runSystem()).toEqual({ ok: true });
    expect(H2.heldWriteSpy).toHaveBeenCalledWith(expect.objectContaining({ T: T_TIP, pullBlocked: null }));
    H2.heldWriteSpy.mockClear();
    H2.readRemoteSpy.mockClear();
    script();
    gitSpy.mockImplementation(async () => Buffer.from(""));
    expect(await run()).toEqual({ ok: true });
    expect(H2.readRemoteSpy).not.toHaveBeenCalled();
    expect(H2.heldWriteSpy).not.toHaveBeenCalled();
  });

  test("a recovery off the remote's default branch (X5) or with no remote read writes nothing", async () => {
    script({ revList: "0\n" });
    H2.readRemoteSpy.mockResolvedValueOnce({ ...REMOTE, defaultBranch: "trunk" });
    expect(await run()).toEqual({ ok: true, recovered: true });
    script({ revList: "0\n" });
    expect(await run()).toEqual({ ok: true, recovered: true }); // readRemote: null
    expect(H2.heldWriteSpy).not.toHaveBeenCalled();
  });
});
