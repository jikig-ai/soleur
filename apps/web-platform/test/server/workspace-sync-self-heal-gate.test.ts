// #12600 (CTO rulings D6, D7, D8; supersede R18's KB exemption and gate placement): `selfHealNonFastForward` runs a
// `reset --hard` only when nothing would be lost - a clean tracked tree (knowledge-base/ included) AND, with local commits
// on the default branch, local commits whose content is already upstream. Every local verb runs token-free (D6d); only
// `pull`, `fetch origin` and `symbolic-ref` reach the token-bearing `gitWithInstallationAuth`. The two refusals emit at
// warning level through `mirrorWarnWithDebounce(null, ...)` keyed on the workspace (D6e, D7); every emit passes a null
// error and carries its details in tags / extra (D8). Real-git rows: test/workspace-sync-self-heal-real-git.test.ts.
// Synthesized data only.
import { beforeEach, describe, expect, test, vi } from "vitest";

const { gitSpy, localSpy, reportSpy, warnSpy, mirrorWarnSpy } = vi.hoisted(() => ({
  gitSpy: vi.fn<(args: string[]) => Promise<Buffer>>(),
  localSpy: vi.fn<(args: string[], opts: { cwd: string; timeout: number }) => Promise<Buffer>>(),
  reportSpy: vi.fn(),
  warnSpy: vi.fn(),
  mirrorWarnSpy: vi.fn(),
}));

vi.mock("@/server/git-auth", () => ({ gitWithInstallationAuth: gitSpy }));
vi.mock("@/server/workspace-local-git", () => ({ runWorkspaceLocalGit: localSpy }));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSpy,
  warnSilentFallback: warnSpy,
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
}

function isNonKbDiff(args: string[]): boolean {
  return args[0] === "diff" && args.includes(":(exclude)knowledge-base/");
}

/** A non-fast-forward default-branch clone; local verbs answer from `s`. */
function script(s: Shape = {}): void {
  const { status = "", revList = "2\n", headRef = "main\n", nonKbDiff = 0, kbDiff = 0 } = s;
  gitSpy.mockImplementation(async (args) => {
    if (args[0] === "pull") throw NON_FF;
    if (args[0] === "symbolic-ref") return Buffer.from("origin/main\n");
    return Buffer.from("");
  });
  localSpy.mockImplementation(async (args) => {
    switch (args[0]) {
      case "rev-list":
        return Buffer.from(revList);
      case "rev-parse":
        return Buffer.from(headRef);
      case "status":
        if (s.statusThrows) throw new Error("status broke");
        return Buffer.from(status);
      case "diff": {
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
const allEmits = (): unknown[][] => [...reportSpy.mock.calls, ...warnSpy.mock.calls, ...mirrorWarnSpy.mock.calls];

beforeEach(() => {
  for (const f of [gitSpy, localSpy, reportSpy, warnSpy, mirrorWarnSpy]) f.mockReset();
});

describe("selfHealNonFastForward: dirty tracked tree refuses on both arms (D6a/b)", () => {
  test("a tracked change outside knowledge-base/ with held commits -> no branch-aside, no reset, op self-heal-aborted-dirty-tracked at warning", async () => {
    script({ status: " M src/s.ts\0" });
    const result = await run();
    expect(result).toEqual(expect.objectContaining({ ok: false, errorClass: "non_fast_forward" }));
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
    expect(localVerbs()).not.toContain("reset");
    const failed = reportSpy.mock.calls.filter((c) => opOf(c) === "self-heal-failed");
    expect(failed).toHaveLength(1);
    expect(failed[0][0]).toBeNull();
    expect((failed[0][1] as { extra: Record<string, unknown> }).extra).toEqual({ userId: "u-1", errName: "Error" });
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
    expect(nonKb).toEqual(["diff", "--quiet", "--no-ext-diff", "--no-textconv", "origin/main...HEAD", "--", ".", ":(exclude)knowledge-base/"]);
    const kb = localSpy.mock.calls.find(([a]) => a[0] === "diff" && !isNonKbDiff(a))?.[0];
    expect(kb).toEqual(["diff", "--quiet", "--no-ext-diff", "--no-textconv", "origin/main", "HEAD", "--", "knowledge-base/"]);
  });

  test("held non-KB commits -> refused, op self-heal-aborted-held-commits, held_kind nonkb, no branch-aside, no reset", async () => {
    script({ nonKbDiff: 1 });
    const result = await run();
    expect(result).toEqual(expect.objectContaining({ ok: false, errorClass: "non_fast_forward" }));
    expect(localVerbs()).not.toContain("reset");
    expect(localVerbs()).not.toContain("branch");
    expect(reportSpy).not.toHaveBeenCalled();
    const [err, ctx, key, errorClass] = mirrorWarnSpy.mock.calls[0] as [unknown, { op: string; tags: Record<string, string> }, string, string];
    expect(err).toBeNull();
    expect(ctx.op).toBe("self-heal-aborted-held-commits");
    expect(ctx.tags).toEqual({ held_kind: "nonkb", reason: "merge_not_attempted" });
    expect(key).toBe(WS);
    expect(errorClass).toBe("self-heal-aborted-held-commits");
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
  test("phantom arm on a feature branch -> abort with self-heal-aborted-dirty, no reset", async () => {
    script({ revList: "0\n", headRef: "feat\n" });
    const result = await run();
    expect(result.ok).toBe(false);
    expect(localVerbs()).not.toContain("reset");
    expect(reportSpy.mock.calls.map(opOf)).toEqual(["self-heal-aborted-dirty"]);
    expect(reportSpy.mock.calls[0][0]).toBeNull();
  });

  test("phantom arm on a detached HEAD -> abort with self-heal-aborted-detached-head, no reset", async () => {
    script({ revList: "0\n", headRef: "HEAD\n" });
    const result = await run();
    expect(result.ok).toBe(false);
    expect(localVerbs()).not.toContain("reset");
    expect(reportSpy.mock.calls.map(opOf)).toEqual(["self-heal-aborted-detached-head"]);
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
  test("only pull, symbolic-ref and fetch reach the token-bearing runner; every local verb runs token-free", async () => {
    script({ nonKbDiff: 0, kbDiff: 0 });
    await run();
    expect(new Set(tokenVerbs())).toEqual(new Set(["pull", "symbolic-ref", "fetch"]));
    expect(new Set(localVerbs())).toEqual(new Set(["rev-parse", "status", "rev-list", "diff", "branch", "reset"]));
    for (const [, opts] of localSpy.mock.calls) expect(opts.cwd).toBe(WS);
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
    ];
    for (const s of shapes) {
      for (const f of [gitSpy, localSpy, reportSpy, warnSpy, mirrorWarnSpy]) f.mockReset();
      script(s);
      await run();
      expect(allEmits().length).toBeGreaterThan(0);
      for (const call of allEmits()) expect(call[0]).toBeNull();
    }
  });
});
