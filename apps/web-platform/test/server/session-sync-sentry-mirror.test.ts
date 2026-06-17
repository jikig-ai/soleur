// #4224 Phase 3 — Sentry-mirror sweep. Asserts that each of the three
// session-sync catch sites mirrors to Sentry via `reportSilentFallback`
// with the correct (feature, op, message) triple, per
// cq-silent-fallback-must-mirror-to-sentry.
//
// The kb-route-helpers `syncWorkspace` catch is covered in its own
// dedicated test file (kb-route-helpers-sentry-mirror.test.ts).

import { describe, test, expect, vi, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY ??= "test-service-role-key";

const { reportSilentFallbackSpy, gitWithInstallationAuthSpy } = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
  gitWithInstallationAuthSpy: vi.fn<
    (argv: string[]) => Promise<Buffer>
  >(async () => Buffer.from("")),
}));

// `execFileSync` shape: `git remote -v` returns a remote line so syncPull
// / syncPush proceed past `hasRemote()`. `rev-list` returns 1 so
// `hasLocalCommits()` says yes. Other invocations return empty.
let throwOnPullPush: "pull" | "push" | null = null;

vi.mock("child_process", () => ({
  execFileSync: vi.fn((cmd: string, args: string[]) => {
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

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  hashUserId: (s: string) => `hash-${s}`,
}));

// gitWithInstallationAuth is the throw point we toggle per test to drive
// the catch in syncPull / syncPush.
vi.mock("../../server/git-auth", () => ({
  gitWithInstallationAuth: gitWithInstallationAuthSpy,
}));

vi.mock("../../server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));

import { syncPull, syncPush } from "../../server/session-sync";

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
