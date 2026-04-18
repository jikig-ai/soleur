import { describe, test, expect, vi, beforeEach } from "vitest";

// Tests for withUserRateLimit (#2510) — per-user rate limit wrapper.
//
// Contract (post-review):
//   withUserRateLimit(handler, { perMinute, feature }) returns a wrapped handler.
//   - Unauthenticated caller: wrapper 401s directly; inner handler NOT invoked.
//   - Authenticated + under quota: inner handler invoked with (req, user).
//   - Authenticated + at quota boundary (perMinute): inner invoked.
//   - Authenticated + over quota: 429 + { error: "Too many requests" } +
//     Retry-After: 60 header; inner NOT invoked; one logRateLimitRejection
//     breadcrumb emitted with the feature tag and userId.
//   - Different userIds: independent counters (per-user isolation).
//   - Different feature strings: independent counters (per-feature isolation).
//
// The rate-limiter module is mocked so `startPruneInterval` is a no-op
// (prevents setInterval leaks across tests) while `SlidingWindowCounter`
// stays real (its behavior is the system-under-test's contract dependency).

const { mockGetUser, mockLogRateLimitRejection } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockLogRateLimitRejection: vi.fn(),
}));

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

function setUser(userId: string | null) {
  mockGetUser.mockResolvedValue({
    data: { user: userId ? { id: userId } : null },
  });
}

describe("withUserRateLimit", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.resetModules();
  });

  test("unauthenticated: wrapper 401s directly; inner NOT invoked", async () => {
    const { withUserRateLimit } = await importHelper();
    setUser(null);
    const inner = vi.fn();
    const wrapped = withUserRateLimit(inner, {
      perMinute: 60,
      feature: "test.unauth",
    });

    const res = await wrapped(makeRequest());
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({ error: "Unauthorized" });
    expect(inner).not.toHaveBeenCalled();
    expect(mockLogRateLimitRejection).not.toHaveBeenCalled();
  });

  test("under quota: inner invoked each time with (req, user)", async () => {
    const { withUserRateLimit } = await importHelper();
    setUser("user-a");
    const inner = vi
      .fn()
      .mockResolvedValue(new Response("ok", { status: 200 }));
    const wrapped = withUserRateLimit(inner, {
      perMinute: 60,
      feature: "test.under",
    });

    for (let i = 0; i < 60; i++) {
      const res = await wrapped(makeRequest());
      expect(res.status).toBe(200);
    }
    expect(inner).toHaveBeenCalledTimes(60);
    // Inner receives the authenticated user as its second argument.
    const [, userArg] = inner.mock.calls[0];
    expect(userArg).toMatchObject({ id: "user-a" });
  });

  test("over quota: 61st call returns 429 + Retry-After: 60; inner NOT invoked", async () => {
    const { withUserRateLimit } = await importHelper();
    setUser("user-a");
    const inner = vi
      .fn()
      .mockResolvedValue(new Response("ok", { status: 200 }));
    const wrapped = withUserRateLimit(inner, {
      perMinute: 60,
      feature: "test.over",
    });

    for (let i = 0; i < 60; i++) {
      await wrapped(makeRequest());
    }
    expect(inner).toHaveBeenCalledTimes(60);

    const res = await wrapped(makeRequest());
    expect(res.status).toBe(429);
    expect(res.headers.get("Retry-After")).toBe("60");
    expect(await res.json()).toEqual({ error: "Too many requests" });
    expect(inner).toHaveBeenCalledTimes(60);
  });

  test("over quota: emits one logRateLimitRejection with feature + userId", async () => {
    const { withUserRateLimit } = await importHelper();
    setUser("user-a");
    const inner = vi.fn().mockResolvedValue(new Response("ok"));
    const wrapped = withUserRateLimit(inner, {
      perMinute: 2,
      feature: "kb-chat.test",
    });

    await wrapped(makeRequest()); // 1
    await wrapped(makeRequest()); // 2
    mockLogRateLimitRejection.mockClear();
    await wrapped(makeRequest()); // 3 (over)

    expect(mockLogRateLimitRejection).toHaveBeenCalledTimes(1);
    expect(mockLogRateLimitRejection).toHaveBeenCalledWith(
      "kb-chat.test",
      "user-a",
    );
  });

  test("per-user isolation: user A at quota does not limit user B", async () => {
    const { withUserRateLimit } = await importHelper();
    const inner = vi
      .fn()
      .mockResolvedValue(new Response("ok", { status: 200 }));
    const wrapped = withUserRateLimit(inner, {
      perMinute: 3,
      feature: "test.iso-user",
    });

    setUser("user-a");
    for (let i = 0; i < 3; i++) {
      const res = await wrapped(makeRequest());
      expect(res.status).toBe(200);
    }
    const overA = await wrapped(makeRequest());
    expect(overA.status).toBe(429);

    setUser("user-b");
    const firstB = await wrapped(makeRequest());
    expect(firstB.status).toBe(200);
  });

  test("per-feature isolation: different features use distinct counters", async () => {
    const { withUserRateLimit } = await importHelper();
    const innerA = vi
      .fn()
      .mockResolvedValue(new Response("ok", { status: 200 }));
    const innerB = vi
      .fn()
      .mockResolvedValue(new Response("ok", { status: 200 }));

    const wrappedA = withUserRateLimit(innerA, {
      perMinute: 2,
      feature: "kb-chat.thread-info",
    });
    const wrappedB = withUserRateLimit(innerB, {
      perMinute: 2,
      feature: "kb-chat.conversations",
    });

    setUser("user-a");
    for (let i = 0; i < 2; i++) {
      expect((await wrappedA(makeRequest())).status).toBe(200);
    }
    expect((await wrappedA(makeRequest())).status).toBe(429);

    expect((await wrappedB(makeRequest())).status).toBe(200);
  });

  test("auth called once per request (no duplicate getUser round-trip)", async () => {
    const { withUserRateLimit } = await importHelper();
    setUser("user-a");
    const inner = vi.fn().mockResolvedValue(new Response("ok"));
    const wrapped = withUserRateLimit(inner, {
      perMinute: 10,
      feature: "test.single-auth",
    });

    await wrapped(makeRequest());
    // Exactly ONE getUser call per request: the wrapper's call. Inner
    // handlers receive `user` as a parameter and must not re-auth.
    expect(mockGetUser).toHaveBeenCalledTimes(1);
  });
});
