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

const { reportSilentFallbackSpy, warnSilentFallbackSpy, mirrorWithDebounceSpy, publishSpy, writeRepoColsSpy } = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
  mirrorWithDebounceSpy: vi.fn(),
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
  mirrorWithDebounce: mirrorWithDebounceSpy,
  mirrorWarnWithDebounce: vi.fn(),
  hashUserId: (s: string) => `hash-${s}`,
}));

// The token-bearing arm is never reached here (`publishKbOnly` is the seam); mocked so its module graph loads.
vi.mock("../../server/git-auth", () => ({ gitWithInstallationAuth: vi.fn() }));
vi.mock("../../server/resolve-installation-id", () => ({ resolveInstallationId: async () => 42 }));
vi.mock("../../server/workspace-repo-mirror", () => ({ writeRepoColsToWorkspace: writeRepoColsSpy }));
vi.mock("../../server/approval/workspace-head", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../server/approval/workspace-head")>()),
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
  for (const f of [reportSilentFallbackSpy, warnSilentFallbackSpy, mirrorWithDebounceSpy, publishSpy, writeRepoColsSpy]) f.mockReset();
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

  test("D13: the injected workspace writers run their git child with a timeout (a stalled .lock cannot wedge the turn)", async () => {
    publishSpy.mockResolvedValue({ kind: "noop" });
    await run();
    const writer = publishSpy.mock.calls[0][0].writer as { unpack(b: Buffer): void; casBranch(b: string, n: string, p: string): void; setTracking(b: string, s: string): void };
    const { execFileSync } = await import("child_process");
    const spy = vi.mocked(execFileSync);
    spy.mockClear();
    writer.unpack(Buffer.from("PACK"));
    writer.casBranch("main", "a".repeat(40), "b".repeat(40));
    writer.setTracking("main", "c".repeat(40));
    expect(spy).toHaveBeenCalledTimes(3);
    for (const call of spy.mock.calls) {
      const opts = call[2] as { timeout?: number };
      expect(opts.timeout).toBeGreaterThan(0);
      expect(opts.timeout).toBeLessThanOrEqual(60_000);
    }
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

  test("fallback failed -> kb-sync.protected-fallback-failed, null err, closed fallback_reason + push_class tags, debounced per workspace and reason, no bookkeeping", async () => {
    for (const fallbackReason of ["side_hash_mismatch", "side_guard_failed", "side_push_rejected", "pr_failed"]) {
      mirrorWithDebounceSpy.mockReset();
      publishSpy.mockResolvedValue({ kind: "fallback_failed", fallbackReason, pushErr: gh006() });
      await run();
      // D8: the Error path loses the tags to the pino-mirror capture (#8629), so the emit is null-first and debounced (R16).
      expect(opsOf(reportSilentFallbackSpy, "kb-sync.protected-fallback-failed")).toHaveLength(0);
      const failed = opsOf(mirrorWithDebounceSpy, "kb-sync.protected-fallback-failed");
      expect(failed, fallbackReason).toHaveLength(1);
      const [err, ctx, key, errorClass] = failed[0] as [unknown, { extra?: Record<string, unknown>; tags?: Record<string, string>; message?: string }, string, string];
      expect(err).toBeNull();
      expect(ctx.extra).toEqual({ userId: "user-1", reason: "fallback_failed" });
      expect(ctx.tags).toEqual({ reason: "fallback_failed", fallback_reason: fallbackReason, push_class: "protected_branch" });
      expect(ctx.message).toMatch(/fallback failed/);
      expect(key).toBe("ws-1");
      expect(errorClass).toBe(`kb-sync-fallback-failed:${fallbackReason}`);
    }
    expect(writeRepoColsSpy).not.toHaveBeenCalled();
  });

  test("persistent_other (shallow) -> kb-sync.protected-fallback-failed with null err and tag reason persistent_other, not op syncPush", async () => {
    publishSpy.mockRejectedValue(new KbSyncError("push_rejected", "persistent_other"));
    await run();
    const failed = opsOf(reportSilentFallbackSpy, "kb-sync.protected-fallback-failed");
    expect(failed).toHaveLength(1);
    const [err, ctx] = failed[0] as [unknown, { extra?: Record<string, unknown>; tags?: Record<string, string> }];
    expect(err).toBeNull();
    expect(ctx.extra).toEqual({ userId: "user-1", reason: "persistent_other" });
    expect(ctx.tags).toEqual({ reason: "persistent_other", push_class: "persistent_other" });
    expect(opsOf(reportSilentFallbackSpy, "syncPush")).toHaveLength(0);
    expect(writeRepoColsSpy).not.toHaveBeenCalled();
  });

  test("other (auth / network) -> outer catch op:syncPush, null err, closed reason + push_class tags, no fallback op", async () => {
    publishSpy.mockRejectedValue(new KbSyncError("push_transient", "other"));
    await run();
    const outer = opsOf(reportSilentFallbackSpy, "syncPush");
    expect(outer).toHaveLength(1);
    const [err, ctx] = outer[0] as [unknown, { extra?: Record<string, unknown>; tags?: Record<string, string> }];
    expect(err).toBeNull();
    expect(ctx.tags).toEqual({ reason: "push_transient", push_class: "other" });
    expect(ctx.extra).toEqual({ userId: "user-1" });
    expect(opsOf(reportSilentFallbackSpy, "kb-sync.protected-fallback-failed")).toHaveLength(0);
  });

  test("a non-KbSyncError -> op:syncPush with reason unclassified and extra.errName only, never err.message (argv)", async () => {
    class GitChildError extends Error {}
    publishSpy.mockRejectedValue(Object.assign(new GitChildError("Command failed: git push https://github.com/acme/widgets.git abc:main"), { name: "GitChildError" }));
    await run();
    const outer = opsOf(reportSilentFallbackSpy, "syncPush");
    expect(outer).toHaveLength(1);
    const [err, ctx] = outer[0] as [unknown, { extra?: Record<string, unknown>; tags?: Record<string, string>; message?: string }];
    expect(err).toBeNull();
    expect(ctx.tags).toEqual({ reason: "unclassified", push_class: "none" });
    expect(ctx.extra).toEqual({ userId: "user-1", errName: "GitChildError" });
    expect(JSON.stringify(outer)).not.toMatch(/github\.com|Command failed/);
  });

  test("D20: a non-KbSyncError carries extra.frame = its first server/app/lib stack frame as file:line, never the message", async () => {
    // the message itself holds an `at` line naming an app path: only the frames AFTER the header may be read
    const err = new TypeError("Cannot read https://github.com/acme/widgets.git\n    at forged (/srv/app/apps/web-platform/server/evil.ts:1:1)");
    err.stack = [
      `TypeError: ${err.message}`,
      "    at Object.next (node:internal/streams/x:10:3)",
      "    at helper (/srv/app/node_modules/pkg/index.js:5:1)",
      "    at publishKbOnly (/srv/app/apps/web-platform/server/kb-sync-publish.ts:812:17)",
      "    at syncPush (/srv/app/apps/web-platform/server/session-sync.ts:842:20)",
    ].join("\n");
    publishSpy.mockRejectedValue(err);
    await run();
    const outer = opsOf(reportSilentFallbackSpy, "syncPush");
    expect(outer).toHaveLength(1);
    const [, ctx] = outer[0] as [unknown, { extra?: Record<string, unknown>; tags?: Record<string, string> }];
    expect(ctx.extra).toEqual({ userId: "user-1", errName: "TypeError", frame: "server/kb-sync-publish.ts:812" });
    expect(ctx.tags).toEqual({ reason: "unclassified", push_class: "none" });
    expect(JSON.stringify(outer)).not.toMatch(/github\.com|evil|Cannot read/);
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
