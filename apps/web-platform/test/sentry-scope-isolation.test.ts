import { describe, test, expect, vi, beforeEach } from "vitest";
import { createHmac } from "node:crypto";

// F3 scope-isolation gate — load-bearing test for the `withUserRateLimit`
// HOC `Sentry.setUser` binding (#3710 PR-B deliverable 1).
//
// The custom-server boot path (`apps/web-platform/server/index.ts:51` —
// `http.createServer` delegating to Next's `handle`) bypasses
// `@sentry/nextjs`'s build-time request wrapper, which is the surface that
// normally auto-installs `withIsolationScope` per request. Without an
// explicit `Sentry.withIsolationScope(...)` wrap, a `Sentry.setUser({id: hashA})`
// from request A can leak into a Sentry event captured during request B's
// lifecycle. This test exercises the production placement form (the
// `withIsolationScope`-wrapped HOC) against a Sentry mock that models the
// SDK's save-and-restore semantics.
//
// References:
// - Plan: knowledge-base/project/plans/2026-05-13-feat-sentry-symmetric-userid-pseudonymisation-plan.md
// - ADR-029 (rename-at-boundary userId pseudonymisation)
// - Sentry SDK v10 `withIsolationScope` docs (context7 `/getsentry/sentry-javascript`)

vi.hoisted(() => {
  process.env.SENTRY_USERID_PEPPER = "test-pepper";
});

const TEST_PEPPER = "test-pepper";
const expectedHashFor = (userId: string) =>
  createHmac("sha256", TEST_PEPPER).update(userId).digest("hex");

// Per-test capture arrays + a "current user" pointer that the mocked
// `getCurrentScope().setUser` mutates and `withIsolationScope` saves /
// restores. The SDK docs guarantee that `withIsolationScope` "creates a new
// async context boundary"; the mock below preserves that semantic so
// concurrent-request assertions can prove no cross-promise bleed.
const {
  mockGetUser,
  mockLogRateLimitRejection,
  sentryCaptureExceptionCalls,
  sentryCaptureMessageCalls,
  sentryUserChanges,
  sentryUserStore,
  sentryOuterUser,
} = vi.hoisted(() => {
  // Local require so vi.hoisted runs above the static import (hoisted blocks
  // execute before module top-level imports).
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { AsyncLocalStorage } = require("node:async_hooks") as typeof import("node:async_hooks");
  type UserCell = { current: { id?: string } | null };
  const sentryUserStore = new AsyncLocalStorage<UserCell>();
  const sentryOuterUser: UserCell = { current: null };
  const sentryCaptureExceptionCalls: Array<{
    err: unknown;
    userAtCapture: { id?: string } | null;
  }> = [];
  const sentryCaptureMessageCalls: Array<{
    msg: string;
    userAtCapture: { id?: string } | null;
  }> = [];
  const sentryUserChanges: Array<{ id?: string } | null> = [];
  return {
    mockGetUser: vi.fn(),
    mockLogRateLimitRejection: vi.fn(),
    sentryCaptureExceptionCalls,
    sentryCaptureMessageCalls,
    sentryUserChanges,
    sentryUserStore,
    sentryOuterUser,
  };
});

// Model the SDK's `withIsolationScope` semantics via `AsyncLocalStorage` so
// each isolation scope is bound to its own async context — setUser writes
// into the active store's cell; captureException reads from the same cell.
// Concurrent async branches each have their own cell, so cross-promise bleed
// is structurally impossible. This mirrors the production SDK's
// AsyncContextStrategy implementation.
function currentUserCell(): { current: { id?: string } | null } {
  return sentryUserStore.getStore() ?? sentryOuterUser;
}

vi.mock("@sentry/nextjs", () => {
  const getCurrentScope = () => ({
    setUser: (u: { id?: string } | null) => {
      const cell = currentUserCell();
      cell.current = u;
      sentryUserChanges.push(u);
    },
  });
  return {
    captureException: vi.fn((err: unknown) => {
      sentryCaptureExceptionCalls.push({
        err,
        userAtCapture: currentUserCell().current,
      });
    }),
    captureMessage: vi.fn((msg: string) => {
      sentryCaptureMessageCalls.push({
        msg,
        userAtCapture: currentUserCell().current,
      });
    }),
    withIsolationScope: vi.fn(<T>(fn: () => T): T => {
      const cell = { current: null as { id?: string } | null };
      return sentryUserStore.run(cell, fn);
    }),
    getCurrentScope: vi.fn(getCurrentScope),
  };
});

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
}));

vi.mock("@/server/rate-limiter", async () => {
  const actual =
    await vi.importActual<typeof import("@/server/rate-limiter")>(
      "@/server/rate-limiter",
    );
  return {
    ...actual,
    startPruneInterval: vi.fn(),
    logRateLimitRejection: mockLogRateLimitRejection,
  };
});

async function importHelper() {
  return await import("@/server/with-user-rate-limit");
}

function makeRequest(): Request {
  return new Request("https://app.soleur.ai/api/test", { method: "GET" });
}

function setUserForRequest(userId: string | null) {
  mockGetUser.mockResolvedValueOnce({
    data: { user: userId ? { id: userId } : null },
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.resetModules();
  sentryCaptureExceptionCalls.length = 0;
  sentryCaptureMessageCalls.length = 0;
  sentryUserChanges.length = 0;
  sentryOuterUser.current = null;
});

describe("Sentry scope isolation under withUserRateLimit (#3710 F3)", () => {
  test("sequential request A (authenticated) carries hashed user.id on captured event", async () => {
    const { withUserRateLimit } = await importHelper();
    const Sentry = await import("@sentry/nextjs");

    setUserForRequest("userA-uuid");

    const wrapped = withUserRateLimit(
      async () => {
        Sentry.captureException(new Error("boom-A"));
        return new Response("ok", { status: 200 });
      },
      { perMinute: 60, feature: "test.iso-seq-A" },
    );

    await wrapped(makeRequest());

    expect(sentryCaptureExceptionCalls).toHaveLength(1);
    expect(sentryCaptureExceptionCalls[0].userAtCapture).toEqual({
      id: expectedHashFor("userA-uuid"),
    });
  });

  test("sequential request B (unauthenticated, after A) does NOT carry user from prior request", async () => {
    const { withUserRateLimit } = await importHelper();
    const Sentry = await import("@sentry/nextjs");

    // Request A — authenticated, captures inside the wrap.
    setUserForRequest("userA-uuid");
    const wrappedA = withUserRateLimit(
      async () => {
        Sentry.captureException(new Error("boom-A"));
        return new Response("ok", { status: 200 });
      },
      { perMinute: 60, feature: "test.iso-seq-AB-A" },
    );
    await wrappedA(makeRequest());

    // Request B — unauthenticated. HOC 401s before the inner handler runs.
    // To prove isolation we capture an event from OUTSIDE the wrap so we can
    // assert the outer-scope user remained null (no leak from request A's
    // isolation scope).
    setUserForRequest(null);
    const wrappedB = withUserRateLimit(
      async () => new Response("never", { status: 200 }),
      { perMinute: 60, feature: "test.iso-seq-AB-B" },
    );
    await wrappedB(makeRequest()); // 401

    // Now capture in the outer scope.
    Sentry.captureException(new Error("boom-outer"));

    const outerCapture =
      sentryCaptureExceptionCalls[sentryCaptureExceptionCalls.length - 1];
    expect(outerCapture.userAtCapture).toBeNull();
  });

  test("concurrent requests A and B (interleaved) — each event matches its own request, no cross-promise bleed", async () => {
    const { withUserRateLimit } = await importHelper();
    const Sentry = await import("@sentry/nextjs");

    // Two separate user IDs; two separate captures inside each wrap. With
    // `Sentry.withIsolationScope`, each wrap forks the current scope, so
    // even when request B's setUser fires while request A's body is
    // suspended, A's capture must still see A's hashed id (not B's).
    setUserForRequest("userA-uuid");
    setUserForRequest("userB-uuid");

    const wrapped = (label: string) =>
      withUserRateLimit(
        async () => {
          // Yield twice to interleave with the sibling promise.
          await new Promise((r) => setImmediate(r));
          Sentry.captureException(new Error(`boom-${label}`));
          await new Promise((r) => setImmediate(r));
          return new Response("ok", { status: 200 });
        },
        { perMinute: 60, feature: `test.iso-concurrent-${label}` },
      );

    const wrappedA = wrapped("A");
    const wrappedB = wrapped("B");

    await Promise.all([wrappedA(makeRequest()), wrappedB(makeRequest())]);

    expect(sentryCaptureExceptionCalls).toHaveLength(2);

    // Sort captures by the error message so the test is order-independent
    // — interleaving makes the capture order between A and B variable.
    const byLabel = (label: string) =>
      sentryCaptureExceptionCalls.find(
        (c) => c.err instanceof Error && c.err.message === `boom-${label}`,
      );

    expect(byLabel("A")?.userAtCapture).toEqual({
      id: expectedHashFor("userA-uuid"),
    });
    expect(byLabel("B")?.userAtCapture).toEqual({
      id: expectedHashFor("userB-uuid"),
    });
  });
});
