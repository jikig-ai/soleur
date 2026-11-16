// #12600 (CTO rulings D6, D7, D8; supersede R18's KB exemption and gate placement): `selfHealNonFastForward` runs a
// `reset --keep` only when nothing would be lost - a clean tracked tree (knowledge-base/ included), local commits whose
// content is already upstream, and no untracked or ignored entry in the reset's way (D15a). Every local verb, the
// `symbolic-ref` read included (D15d), runs token-free (D6d); only `pull` and `fetch origin` reach the token-bearing
// `gitWithInstallationAuth`. The three designed holds warn through `mirrorWarnWithDebounce(null, ...)` and the two branch
// aborts stay error through `mirrorWithDebounce(null, ...)`, all keyed on the workspace (D6e, D7, D15e); every emit
// passes a null error and carries its details in tags / extra (D8). The three holds set `held` (D16). Real-git rows:
// test/workspace-sync-self-heal-real-git.test.ts.
// Synthesized data only.
import { beforeEach, describe, expect, test, vi } from "vitest";

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

const run = () => syncWorkspace(1, WS, log, { userId: "u-1", op: "push" });
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
    expect(localSpy.mock.calls.find(([a]) => isPrecheckDiff(a))?.[0]).toEqual(["diff", "--name-status", "-z", "--no-renames", "--diff-filter=AD", "HEAD", "refs/remotes/origin/main", "--"]);
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

  test("held non-KB commits -> refused, op self-heal-aborted-held-commits, held_kind nonkb, no branch-aside, no reset", async () => {
    script({ nonKbDiff: 1 });
    const result = await run();
    expect(result).toEqual(expect.objectContaining({ ok: false, errorClass: "non_fast_forward", held: "held_commits" }));
    expect(localVerbs()).not.toContain("reset");
    expect(localVerbs()).not.toContain("branch");
    expect(reportSpy).not.toHaveBeenCalled();
    const [err, ctx, key, errorClass] = mirrorWarnSpy.mock.calls[0] as [unknown, { op: string; tags: Record<string, string> }, string, string];
    expect(err).toBeNull();
    expect(ctx.op).toBe("self-heal-aborted-held-commits");
    expect(ctx.tags).toEqual({ held_kind: "nonkb", reason: "merge_not_attempted" });
    expect(key).toBe(WS);
    // D20: keyed `<op>:<held_kind>`, so a kb hold and a nonkb hold on one workspace are separate debounce classes
    expect(errorClass).toBe("self-heal-aborted-held-commits:nonkb");
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
    expect(mirrorWarnSpy.mock.calls[0][3]).toBe("self-heal-aborted-held-commits:kb");
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
