// #12600 (CTO ruling R18): the default-branch arm of `selfHealNonFastForward` must not `reset --hard` over a tracked
// code edit. Held foreign commits are the steady state after #12600, so without this gate every upstream push to the
// default branch would erase a member's uncommitted edits outside knowledge-base/. The real-git rows are matrix 21 and the
// R18 positive control in test/session-sync-kb-only-push-real-git.test.ts. Synthesized data only.
import { beforeEach, describe, expect, test, vi } from "vitest";

const { gitSpy, reportSpy, warnSpy } = vi.hoisted(() => ({
  gitSpy: vi.fn<(args: string[]) => Promise<Buffer>>(),
  reportSpy: vi.fn(),
  warnSpy: vi.fn(),
}));

vi.mock("@/server/git-auth", () => ({ gitWithInstallationAuth: gitSpy }));
vi.mock("@/server/observability", () => ({ reportSilentFallback: reportSpy, warnSilentFallback: warnSpy }));

import { syncWorkspace } from "@/server/workspace-sync";

const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } as never;
const NON_FF = Object.assign(new Error("Command failed: git pull --ff-only"), {
  stderr: "fatal: Not possible to fast-forward, aborting.",
});

/** A diverged default-branch clone with 2 un-pushed commits; `status` answers with the given porcelain -z bytes. */
function script(status: string): void {
  gitSpy.mockImplementation(async (args) => {
    switch (args[0]) {
      case "pull":
        throw NON_FF;
      case "symbolic-ref":
        return Buffer.from("origin/main\n");
      case "rev-list":
        return Buffer.from("2\n");
      case "rev-parse":
        return Buffer.from("main\n");
      case "status":
        return Buffer.from(status);
      default:
        return Buffer.from("");
    }
  });
}
const verbs = (): string[] => gitSpy.mock.calls.map(([a]) => a[0]);
const ops = (spy: typeof reportSpy): string[] => spy.mock.calls.map(([, o]) => (o as { op?: string }).op ?? "");

beforeEach(() => {
  for (const f of [gitSpy, reportSpy, warnSpy]) f.mockReset();
});

describe("selfHealNonFastForward R18 gate (#12600)", () => {
  test("a tracked change outside knowledge-base/ -> no branch-aside, no reset, op self-heal-aborted-dirty-nonkb, non_fast_forward", async () => {
    script(" M src/s.ts\0");
    const result = await syncWorkspace(1, "/tmp/ws-r18", log, { userId: "u-1", op: "push" });
    expect(result).toEqual(expect.objectContaining({ ok: false, errorClass: "non_fast_forward" }));
    expect(verbs()).not.toContain("reset");
    expect(verbs()).not.toContain("branch");
    expect(ops(reportSpy)).toEqual(["self-heal-aborted-dirty-nonkb"]);
    const ctx = reportSpy.mock.calls[0][1] as { feature: string; message: string; extra: Record<string, unknown> };
    expect(ctx.feature).toBe("kb-route-helpers");
    expect(ctx.extra).toEqual({ userId: "u-1" });
    expect(ctx.message).not.toMatch(/src\/s\.ts/);
  });

  test("the status call is untracked-files=no and NUL-separated", async () => {
    script(" M src/s.ts\0");
    await syncWorkspace(1, "/tmp/ws-r18", log, { userId: "u-1", op: "push" });
    const status = gitSpy.mock.calls.find(([a]) => a[0] === "status")?.[0];
    expect(status).toEqual(["status", "--porcelain", "-z", "--untracked-files=no"]);
  });

  test("a rename whose SOURCE is outside knowledge-base/ also refuses", async () => {
    script("R  knowledge-base/new.md\0src/old.ts\0");
    const result = await syncWorkspace(1, "/tmp/ws-r18", log, { userId: "u-1", op: "push" });
    expect(result.ok).toBe(false);
    expect(verbs()).not.toContain("reset");
  });

  test("only knowledge-base/ changes (or a clean tree) -> the recovery still runs (branch-aside + reset)", async () => {
    for (const status of [" M knowledge-base/a.md\0", ""]) {
      gitSpy.mockReset();
      reportSpy.mockReset();
      script(status);
      const result = await syncWorkspace(1, "/tmp/ws-r18", log, { userId: "u-1", op: "push" });
      expect(result).toEqual({ ok: true, recovered: true });
      expect(verbs()).toEqual(expect.arrayContaining(["branch", "reset"]));
      expect(ops(reportSpy)).not.toContain("self-heal-aborted-dirty-nonkb");
    }
  });

  test("a failing status read refuses the reset (fail closed)", async () => {
    gitSpy.mockImplementation(async (args) => {
      if (args[0] === "status") throw new Error("status broke");
      if (args[0] === "pull") throw NON_FF;
      if (args[0] === "symbolic-ref") return Buffer.from("origin/main\n");
      if (args[0] === "rev-list") return Buffer.from("2\n");
      if (args[0] === "rev-parse") return Buffer.from("main\n");
      return Buffer.from("");
    });
    const result = await syncWorkspace(1, "/tmp/ws-r18", log, { userId: "u-1", op: "push" });
    expect(result.ok).toBe(false);
    expect(verbs()).not.toContain("reset");
  });
});
