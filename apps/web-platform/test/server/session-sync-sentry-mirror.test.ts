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

const { reportSilentFallbackSpy, gitWithInstallationAuthSpy, captureMessageSpy, childLog } = vi.hoisted(() => ({
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

vi.mock("child_process", () => ({
  execFileSync: vi.fn((cmd: string, rawArgs: string[]) => {
    const args = stripHostGitBlock(rawArgs);
    if (args[0] === "remote") {
      return Buffer.from("origin\tgit@github.com:t/t.git (fetch)\n");
    }
    if (args[0] === "rev-list") return Buffer.from("1\n");
    if (args[0] === "status") return Buffer.from("");
    return Buffer.from("");
  }),
}));

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
  readWorkspaceHeadRef: () => ({ sha: "d".repeat(40), refName: "refs/heads/main" }),
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

import { syncPull, syncPush } from "../../server/session-sync";
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
  captureMessageSpy.mockReset();
  childLog.info.mockReset();
  __resetMirrorDebounceForTests();
});

describe("session-sync — Sentry mirror sweep (#4224 Phase 3)", () => {
  test("syncPull catch fires reportSilentFallback{feature:session-sync, op:syncPull}", async () => {
    gitWithInstallationAuthSpy.mockImplementation(async (argv: string[]) => {
      if (argv[0] === "pull") throw new Error("pull broke");
      return Buffer.from("");
    });

    await syncPull("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");

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
