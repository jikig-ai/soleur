// #5426 — KB-sync protected-branch fallback: the op and alert contract of `syncPush` (#12600 plan task 4.5).
//
// Since #12600 the fallback runs entirely in the isolated GIT_DIR (`runSideFallback` in server/kb-sync-publish.ts): no
// workspace checkout, commit or reset. Its git behaviour (side parents, the side push, the local branch, the dirty file
// kept) is asserted on real git in test/session-sync-kb-only-push-real-git.test.ts (matrix 10, 12, 13, 16, 20). The
// classifier lives in test/server/classify-push-error.test.ts. What stays here is the mapping from the publish result to
// the Sentry ops the issue alert keys on (`kb-sync.protected-fallback-failed`, `kb-sync.push-protected-fallback`), the
// closed `fallback_reason` tag, and "bookkeeping only after a delivered push". Synthesized data only.

import { describe, test, expect, vi, beforeEach } from "vitest";
import { stripHostGitBlock } from "../helpers/host-git-block";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY ??= "test-service-role-key";

const { reportSilentFallbackSpy, warnSilentFallbackSpy, publishSpy, writeRepoColsSpy } = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
  warnSilentFallbackSpy: vi.fn(),
  publishSpy: vi.fn(),
  writeRepoColsSpy: vi.fn(async () => undefined),
}));

// execFileSync (connected-repo wrapper): `remote -v` returns a remote so hasRemote() passes; `rev-list` returns 1 so
// hasLocalCommits() says yes; `status -z` is clean (no auto-commit).
vi.mock("child_process", () => ({
  execFileSync: vi.fn((_cmd: string, rawArgs: string[]) => {
    const args = stripHostGitBlock(rawArgs);
    if (args[0] === "remote") return Buffer.from("origin\tgit@github.com:acme/widgets.git (fetch)\n");
    if (args[0] === "rev-list") return Buffer.from("1\n");
    return Buffer.from("");
  }),
}));

vi.mock("fs", () => ({
  readdirSync: vi.fn(() => []),
  lstatSync: vi.fn(() => {
    throw Object.assign(new Error("ENOENT"), { code: "ENOENT" }); // no .git, no MERGE_HEAD
  }),
}));

vi.mock("@supabase/supabase-js", () => ({ createClient: vi.fn() }));

vi.mock("@/lib/supabase/tenant", () => {
  class FakeRuntimeAuthError extends Error {}
  const chain: Record<string, unknown> = {};
  chain.eq = () => chain;
  chain.maybeSingle = async () => ({ data: { id: "user-1" }, error: null });
  return {
    getFreshTenantClient: vi.fn(async () => ({ from: () => ({ select: () => chain }), rpc: async () => ({ error: null }) })),
    RuntimeAuthError: FakeRuntimeAuthError,
  };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: warnSilentFallbackSpy,
  mirrorWarnWithDebounce: vi.fn(),
  hashUserId: (s: string) => `hash-${s}`,
}));

// The token-bearing arm is never reached here (`publishKbOnly` is the seam); mocked so its module graph loads.
vi.mock("../../server/git-auth", () => ({ gitWithInstallationAuth: vi.fn() }));
vi.mock("../../server/resolve-installation-id", () => ({ resolveInstallationId: async () => 42 }));
vi.mock("../../server/workspace-repo-mirror", () => ({ writeRepoColsToWorkspace: writeRepoColsSpy }));
vi.mock("../../server/approval/workspace-head", () => ({
  readWorkspaceHeadRef: () => ({ sha: "a".repeat(40), refName: "refs/heads/main" }),
}));
vi.mock("../../server/kb-sync-publish", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../server/kb-sync-publish")>()),
  publishKbOnly: publishSpy,
}));
vi.mock("../../server/logger", () => {
  const l = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() };
  return { default: l, createChildLogger: () => l };
});

import { syncPush } from "@/server/session-sync";
import { KbSyncError } from "../../server/kb-sync-publish";

const STUB_SERVICE = {} as never;
const run = () => syncPush("user-1", "/tmp/ws-fallback", STUB_SERVICE, "ws-1");
const opsOf = (spy: typeof reportSilentFallbackSpy, op: string) =>
  spy.mock.calls.filter(([, ctx]) => (ctx as { op?: string }).op === op);
const gh006 = () => new KbSyncError("push_rejected", "protected_branch");

beforeEach(() => {
  for (const f of [reportSilentFallbackSpy, warnSilentFallbackSpy, publishSpy, writeRepoColsSpy]) f.mockReset();
});

describe("syncPush — protected-branch fallback op contract (#5426, #12600)", () => {
  test("the publish receives the frozen HEAD and an injected workspace writer", async () => {
    publishSpy.mockResolvedValue({ kind: "pushed" });
    await run();
    expect(publishSpy).toHaveBeenCalledTimes(1);
    const input = publishSpy.mock.calls[0][0] as Record<string, unknown>;
    expect(input).toEqual(
      expect.objectContaining({ userId: "user-1", workspaceId: "ws-1", installationId: 42, headSha: "a".repeat(40), refName: "refs/heads/main" }),
    );
    expect(Object.keys(input.writer as object).sort()).toEqual(["casBranch", "setTracking", "unpack"]);
  });

  test("fallback delivered -> warn kb-sync.push-protected-fallback with PR url + commit count, bookkeeping runs", async () => {
    publishSpy.mockResolvedValue({ kind: "fallback", prUrl: "https://github.com/acme/widgets/pull/7", commitCount: 1 });
    await run();
    const warned = opsOf(warnSilentFallbackSpy, "kb-sync.push-protected-fallback");
    expect(warned).toHaveLength(1);
    expect(warned[0][1]).toEqual(
      expect.objectContaining({
        feature: "session-sync",
        extra: expect.objectContaining({ prUrl: "https://github.com/acme/widgets/pull/7", commitCount: 1 }),
      }),
    );
    expect(opsOf(reportSilentFallbackSpy, "kb-sync.protected-fallback-failed")).toHaveLength(0);
    expect(writeRepoColsSpy).toHaveBeenCalledTimes(1);
  });

  test("fallback failed -> kb-sync.protected-fallback-failed, reason fallback_failed, closed fallback_reason tag, no bookkeeping", async () => {
    for (const fallbackReason of ["side_fetch_failed", "side_hash_mismatch", "side_guard_failed", "side_push_rejected", "pr_failed"]) {
      reportSilentFallbackSpy.mockReset();
      publishSpy.mockResolvedValue({ kind: "fallback_failed", fallbackReason, pushErr: gh006() });
      await run();
      const failed = opsOf(reportSilentFallbackSpy, "kb-sync.protected-fallback-failed");
      expect(failed).toHaveLength(1);
      const ctx = failed[0][1] as { extra?: { reason?: string }; tags?: Record<string, string>; message?: string };
      expect(ctx.extra?.reason).toBe("fallback_failed");
      expect(ctx.tags?.fallback_reason).toBe(fallbackReason);
      expect(ctx.message).toMatch(/fallback failed/);
    }
    expect(writeRepoColsSpy).not.toHaveBeenCalled();
  });

  test("persistent_other (shallow) -> kb-sync.protected-fallback-failed with reason persistent_other, not op syncPush", async () => {
    publishSpy.mockRejectedValue(new KbSyncError("push_rejected", "persistent_other"));
    await run();
    const failed = opsOf(reportSilentFallbackSpy, "kb-sync.protected-fallback-failed");
    expect(failed).toHaveLength(1);
    expect((failed[0][1] as { extra?: { reason?: string } }).extra?.reason).toBe("persistent_other");
    expect(opsOf(reportSilentFallbackSpy, "syncPush")).toHaveLength(0);
    expect(writeRepoColsSpy).not.toHaveBeenCalled();
  });

  test("other (auth / network) -> outer catch op:syncPush with the closed reason tag, no fallback op", async () => {
    publishSpy.mockRejectedValue(new KbSyncError("push_transient", "other"));
    await run();
    const outer = opsOf(reportSilentFallbackSpy, "syncPush");
    expect(outer).toHaveLength(1);
    expect((outer[0][1] as { tags?: Record<string, string> }).tags?.reason).toBe("push_transient");
    expect(opsOf(reportSilentFallbackSpy, "kb-sync.protected-fallback-failed")).toHaveLength(0);
  });

  test("held or nothing to sync -> no fallback op, no bookkeeping", async () => {
    for (const result of [{ kind: "held", reason: "side_ahead" }, { kind: "noop" }]) {
      publishSpy.mockResolvedValue(result);
      await run();
    }
    expect(warnSilentFallbackSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    expect(writeRepoColsSpy).not.toHaveBeenCalled();
  });
});
