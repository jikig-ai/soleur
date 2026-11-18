// #4224 Phase 3 — Sentry-mirror sweep. Asserts that each of the three
// session-sync catch sites mirrors to Sentry via `reportSilentFallback`
// with the correct (feature, op, message) triple, per
// cq-silent-fallback-must-mirror-to-sentry.
//
// The kb-route-helpers `syncWorkspace` catch is covered in its own
// dedicated test file (kb-route-helpers-sentry-mirror.test.ts).

import { describe, test, expect, vi, beforeEach } from "vitest";
import { stripHostGitBlock } from "../helpers/host-git-block";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY ??= "test-service-role-key";

const { reportSilentFallbackSpy, gitWithInstallationAuthSpy, captureMessageSpy, childLog, headThrows } = vi.hoisted(() => ({
  /** #12718: the pull's outer catch is driven by a throw inside its try (the HEAD read), never by a git error. */
  headThrows: { value: false },
  reportSilentFallbackSpy: vi.fn(),
  captureMessageSpy: vi.fn(),
  childLog: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  gitWithInstallationAuthSpy: vi.fn<
    (argv: string[]) => Promise<Buffer>
  >(async () => Buffer.from("")),
}));

// `execFileSync` shape: `git remote -v` returns a remote line so syncPull
// / syncPush proceed past `hasRemote()`. `rev-list` returns 1 so
// `hasLocalCommits()` says yes. Other invocations return empty.
let throwOnPullPush: "pull" | "push" | null = null;

vi.mock("child_process", async () => {
  // D38(1): the connected-repo runner is async; the sync stub drives `execFile` through the adapter.
  const { execFileFromSync } = await import("../helpers/exec-file-from-sync");
  const execFileSync = vi.fn((cmd: string, rawArgs: string[]) => {
    const args = stripHostGitBlock(rawArgs);
    if (args[0] === "remote") {
      return Buffer.from("origin\tgit@github.com:t/t.git (fetch)\n");
    }
    if (args[0] === "rev-list") return Buffer.from("1\n");
    if (args[0] === "status") return Buffer.from("");
    return Buffer.from("");
  });
  return { execFileSync, execFile: vi.fn(execFileFromSync(execFileSync)) };
});

vi.mock("fs", () => ({
  readdirSync: vi.fn(() => []),
  lstatSync: vi.fn(() => {
    throw Object.assign(new Error("ENOENT"), { code: "ENOENT" }); // host-git shape guard: the fake workspace has no .git
  }),
}));

vi.mock("@supabase/supabase-js", () => ({ createClient: vi.fn() }));

// Recursive tenant client — every `.from(...)` / chained method returns
// a chain that resolves to `{ data: null, error: null }`.
vi.mock("@/lib/supabase/tenant", () => {
  class FakeRuntimeAuthError extends Error {}
  const fakeRow = {
    id: "user-1",
    kb_sync_history: [],
    github_installation_id: 42,
  };
  const eqChain: Record<string, unknown> = {};
  eqChain.eq = () => eqChain;
  eqChain.single = async () => ({ data: fakeRow, error: null });
  eqChain.maybeSingle = async () => ({ data: fakeRow, error: null });
  eqChain.then = (resolve: (v: unknown) => void) => resolve({ error: null });
  const fromChain = {
    select: () => ({ eq: () => eqChain }),
    update: () => ({ eq: () => eqChain }),
  };
  return {
    getFreshTenantClient: vi.fn(async () => ({ from: () => fromChain })),
    RuntimeAuthError: FakeRuntimeAuthError,
  };
});

// #12600 AC5: the REAL warn path and debounce (`mirrorWarnWithDebounce` -> `warnSilentFallback` -> Sentry), observed at
// the Sentry SDK; `reportSilentFallback` stays a spy for the catch-site rows.
vi.mock("@sentry/nextjs", () => ({ captureMessage: captureMessageSpy, captureException: vi.fn() }));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: reportSilentFallbackSpy,
  hashUserId: (s: string) => `hash-${s}`,
}));
// The KB sync reaches its isolated directory only through a resolvable repo URL and a readable HEAD.
vi.mock("../../server/current-repo-url", () => ({ getCurrentRepoUrl: async () => "https://github.com/acme/widget" }));
vi.mock("../../server/resolve-installation-id", () => ({ resolveInstallationId: async () => 42 }));
vi.mock("../../server/approval/workspace-head", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../server/approval/workspace-head")>()),
  readWorkspaceHeadRef: () => {
    if (headThrows.value) throw new Error(`HEAD unreadable at https://github.com/acme/widget ${"e".repeat(40)}`);
    return { sha: "d".repeat(40), refName: "refs/heads/main" };
  },
}));

// gitWithInstallationAuth is the throw point we toggle per test to drive
// the catch in syncPull / syncPush.
vi.mock("../../server/git-auth", () => ({
  gitWithInstallationAuth: gitWithInstallationAuthSpy,
}));

vi.mock("../../server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  createChildLogger: () => childLog,
}));

import { reportPullHeld, syncPull, syncPush } from "../../server/session-sync";
import { reportPushHeld } from "../../server/kb-sync-publish";
import { __resetMirrorDebounceForTests } from "../../server/observability";

// ADR-044 PR-B: syncPull/syncPush take an injected service client + resolved
// workspace id. These tests force the catch path; a minimal stub suffices.
const STUB_SERVICE = {
  from: () => ({
    update: () => ({
      eq: () => ({
        select: () => Promise.resolve({ data: [{ id: "user-1" }], error: null }),
      }),
    }),
  }),
} as never;

beforeEach(() => {
  reportSilentFallbackSpy.mockReset();
  gitWithInstallationAuthSpy.mockReset();
  gitWithInstallationAuthSpy.mockResolvedValue(Buffer.from(""));
  throwOnPullPush = null;
  headThrows.value = false;
  captureMessageSpy.mockReset();
  childLog.info.mockReset();
  childLog.warn.mockReset();
  __resetMirrorDebounceForTests();
});

describe("session-sync — Sentry mirror sweep (#4224 Phase 3)", () => {
  test("syncPull catch fires reportSilentFallback{feature:session-sync, op:syncPull}", async () => {
    // #12718: no legacy token pull is left to throw; an unexpected throw inside the pull's try is the catch's input.
    headThrows.value = true;

    // R2-B (obs F3, verify-coverage P3-17): the outer catch-all is a closed reason too, with its one pull-held line
    await expect(syncPull("user-1", "/tmp/workspace", STUB_SERVICE, "user-1")).resolves.toEqual({ heldFiles: null, onRecovered: null, pullReason: "pull_unexpected", checkedAt: null });
    const pullHeld = childLog.info.mock.calls.filter(([o]) => (o as { op?: string } | undefined)?.op === "kb-sync.pull-held");
    expect(pullHeld).toEqual([[expect.objectContaining({ reason: "pull_unexpected", errName: "Error" }), expect.any(String)]]);
    expect(JSON.stringify(pullHeld)).not.toMatch(/github\.com|[0-9a-f]{40}/);

    const matching = reportSilentFallbackSpy.mock.calls.filter(
      ([, ctx]) =>
        (ctx as { feature: string; op?: string }).feature === "session-sync" &&
        (ctx as { feature: string; op?: string }).op === "syncPull",
    );
    expect(matching).toHaveLength(1);
    const [, ctx] = matching[0];
    expect(ctx).toEqual(
      expect.objectContaining({
        feature: "session-sync",
        op: "syncPull",
        message: expect.stringMatching(/sync pull failed/i),
      }),
    );
    // D25(7): no raw error reaches Sentry: a null error, the class name and an app frame only, never the URL or a sha
    const [err, full] = matching[0] as [unknown, { extra: Record<string, unknown> }];
    expect(err).toBeNull();
    expect(full.extra).toEqual(expect.objectContaining({ userId: "user-1", errName: "Error" }));
    expect(Object.keys(full.extra).filter((k) => !["userId", "errName", "frame"].includes(k))).toEqual([]);
    expect(JSON.stringify(full)).not.toMatch(/github\.com|[0-9a-f]{40}/);
    expect(gitWithInstallationAuthSpy).not.toHaveBeenCalled();
  });

  test("syncPush outer catch fires reportSilentFallback{feature:session-sync, op:syncPush}", async () => {
    gitWithInstallationAuthSpy.mockImplementation(async (argv: string[]) => {
      if (argv[0] === "push") throw new Error("push broke");
      return Buffer.from("");
    });

    await syncPush("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");

    // #12600 AC5: a closed reason tag, a static message, and an error that names no URL or sha.
    const outer = reportSilentFallbackSpy.mock.calls.filter(([, ctx]) => (ctx as { op?: string }).op === "syncPush");
    expect(outer).toHaveLength(1);
    const [outerErr, outerCtx] = outer[0] as [unknown, { tags?: Record<string, string>; message?: string }];
    // the fake workspace is not on disk, so the isolated directory refuses: a closed reason, never "unclassified"
    expect(outerCtx.tags?.reason).toBe("isolated_refused");
    // D21: the refusal's closed reason rides along as a tag, never a path. D23: the exact value (the workspace root does not
    // exist on disk, which createIsolatedPushDir reports as the server's own state)
    expect(outerCtx.tags?.isolated_reason).toBe("setup_failed");
    for (const text of [String((outerErr as Error)?.message ?? outerErr), outerCtx.message ?? ""]) {
      expect(text).not.toMatch(/github\.com|https?:\/\/|[0-9a-f]{40}/);
    }

    const matching = reportSilentFallbackSpy.mock.calls.filter(
      ([, ctx]) =>
        (ctx as { feature: string; op?: string }).feature === "session-sync" &&
        (ctx as { feature: string; op?: string }).op === "syncPush",
    );
    expect(matching).toHaveLength(1);
    expect(matching[0][1]).toEqual(
      expect.objectContaining({
        feature: "session-sync",
        op: "syncPush",
        message: expect.stringMatching(/sync push failed/i),
      }),
    );
    // pattern P3-16, gdpr: the pino line carries the class name and the closed reason, never the raw error (its message
    // is git's argv: the URL, the refspec, tenant paths)
    const pushLine = childLog.warn.mock.calls.find(([, msg]) => /Sync push failed/.test(String(msg)));
    expect(pushLine?.[0]).toEqual({ userId: "user-1", errName: "KbSyncError", reason: "isolated_refused" });
    for (const [o] of childLog.warn.mock.calls) expect(Object.keys((o as object) ?? {})).not.toContain("err");
  });
});

describe("kb-sync.pull-held observability (#12718, D25(6))", () => {
  const pullLines = () =>
    childLog.info.mock.calls.filter(([o]) => (o as { op?: string } | undefined)?.op === "kb-sync.pull-held");

  test("a workspace that is not on disk: one pull-held line (isolated_refused), one Sentry warning, no catch report, never throws", async () => {
    await expect(syncPull("user-1", "/tmp/workspace", STUB_SERVICE, "ws-1")).resolves.toEqual({
      heldFiles: null,
      onRecovered: null,
      pullReason: "isolated_refused",
      checkedAt: null,
    });
    expect(pullLines()).toHaveLength(1);
    // obs F4: the refusal's closed reason rides on the line and the warning as `isolated_reason`
    expect(pullLines()[0][0]).toEqual({ op: "kb-sync.pull-held", reason: "isolated_refused", isolated_reason: "setup_failed", workspaceId: "ws-1" });
    expect(captureMessageSpy).toHaveBeenCalledTimes(1);
    const [, payload] = captureMessageSpy.mock.calls[0] as [string, { level: string; tags: Record<string, string> }];
    expect(payload.level).toBe("warning");
    expect(payload.tags).toEqual({ feature: "session-sync", op: "kb-sync.pull-held", reason: "isolated_refused", isolated_reason: "setup_failed" });
    expect(reportSilentFallbackSpy.mock.calls.filter(([, c]) => (c as { op?: string }).op === "syncPull")).toEqual([]);
    expect(gitWithInstallationAuthSpy).not.toHaveBeenCalled(); // refused before any token-bearing read
  });

  test("an info reason (up_to_date, merged, side_linked) is a pino line only; a fetch-stage reason tags which fetch", () => {
    for (const r of ["up_to_date", "merged", "side_linked", "non_default_branch"] as const) reportPullHeld(r, { userId: "user-1", workspaceId: "ws-1" });
    expect(captureMessageSpy).not.toHaveBeenCalled();
    expect(pullLines()).toHaveLength(4);
    reportPullHeld("fetch_failed", { userId: "user-1", workspaceId: "ws-2" }, "side");
    expect(pullLines()[4][0]).toEqual({ op: "kb-sync.pull-held", reason: "fetch_failed", ref: "side", workspaceId: "ws-2" });
    const [, payload] = captureMessageSpy.mock.calls[0] as [string, { tags: Record<string, string>; extra: Record<string, unknown> }];
    expect(payload.tags).toEqual({ feature: "session-sync", op: "kb-sync.pull-held", reason: "fetch_failed", ref: "side" });
    expect(Object.keys(payload.extra).filter((k) => k !== "err")).toEqual(["userIdHash"]);
  });

  test("the same warning reason twice for one workspace is debounced to one Sentry warning; the info line is per run", async () => {
    await syncPull("user-1", "/tmp/workspace", STUB_SERVICE, "ws-1");
    await syncPull("user-1", "/tmp/workspace", STUB_SERVICE, "ws-1");
    expect(pullLines()).toHaveLength(2);
    expect(captureMessageSpy).toHaveBeenCalledTimes(1);
  });
});

describe("kb-sync.push-held observability (#12600 AC5)", () => {
  const ctx = { userId: "user-1", workspaceId: "ws-1" };
  const heldLines = () =>
    childLog.info.mock.calls.filter(([o]) => (o as { op?: string } | undefined)?.op === "kb-sync.push-held");

  test("a warning reason emits one Sentry warning: tags reason + outcome, extra carries the hashed user id only", () => {
    reportPushHeld("head_moved", "held", ctx);
    expect(captureMessageSpy).toHaveBeenCalledTimes(1);
    const [message, payload] = captureMessageSpy.mock.calls[0] as [string, { level: string; tags: Record<string, string>; extra: Record<string, unknown> }];
    expect(payload.level).toBe("warning");
    expect(payload.tags).toEqual({ feature: "session-sync", op: "kb-sync.push-held", reason: "head_moved", outcome: "held" });
    expect(Object.keys(payload.extra).filter((k) => k !== "err")).toEqual(["userIdHash"]);
    expect(payload.extra.userIdHash).not.toBe("user-1");
    expect(JSON.stringify(payload)).not.toContain("user-1");
    expect(message).not.toMatch(/https?:\/\/|[0-9a-f]{40}|refs\//);
  });

  test("two different reasons in one window both emit; a repeat is debounced; every outcome still writes its info line", () => {
    reportPushHeld("head_moved", "held", ctx);
    reportPushHeld("head_moved", "held", ctx);
    reportPushHeld("unpack_failed", "held", ctx);
    expect(captureMessageSpy.mock.calls.map(([, p]) => (p as { tags: Record<string, string> }).tags.reason)).toEqual([
      "head_moved",
      "unpack_failed",
    ]);
    expect(heldLines().map(([o]) => (o as { reason: string }).reason)).toEqual(["head_moved", "head_moved", "unpack_failed"]);
  });

  test("the expected outcomes are info only: no Sentry event", () => {
    for (const reason of ["synthetic_pushed", "held_foreign", "remote_ahead", "remote_unknown_tip", "side_pending", "side_declined"] as const) {
      reportPushHeld(reason, reason === "synthetic_pushed" ? "pushed" : "held", ctx);
    }
    expect(captureMessageSpy).not.toHaveBeenCalled();
    expect(heldLines()).toHaveLength(6);
    // D21: the info line names the workspace (the Sentry warning keys on it too), never a path, sha or branch
    expect(heldLines().map(([o]) => (o as { workspaceId?: string }).workspaceId)).toEqual(Array(6).fill("ws-1"));
  });
});
