import { describe, test, expect, vi, beforeEach } from "vitest";

// RED phase for #2510 — withUserRateLimit helper.
//
// Contract (from plan Phase 1):
//   withUserRateLimit(handler, { perMinute, feature }) returns a wrapped handler.
//   - Unauthenticated caller: delegates to inner handler (inner emits 401).
//   - Authenticated + under quota: delegates to inner handler.
//   - Authenticated + at quota boundary (perMinute): delegates to inner handler.
//   - Authenticated + over quota: returns 429 + { error: "Too many requests" } +
//     Retry-After: 60 header; inner handler NOT invoked; one warnSilentFallback
//     call emitted with { feature, op: "rate-limit", extra: { userId } }.
//   - Different userIds get independent counters (per-user isolation).
//   - Different feature strings get independent counters even on the same
//     wrapper call-site pattern (per-feature isolation).

const { mockGetUser, mockWarnSilentFallback } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
}));

vi.mock("@/server/observability", () => ({
  warnSilentFallback: mockWarnSilentFallback,
  reportSilentFallback: vi.fn(),
}));

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

  test("unauthenticated: delegates to inner handler (inner handles 401)", async () => {
    const { withUserRateLimit } = await importHelper();
    setUser(null);
    const inner = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 }),
    );

    const wrapped = withUserRateLimit(inner, {
      perMinute: 60,
      feature: "test.unauth",
    });

    // Even 100 unauthenticated calls must all hit the inner handler — the
    // wrapper does NOT fabricate auth, it just defers to the inner.
    for (let i = 0; i < 100; i++) {
      const res = await wrapped(makeRequest());
      expect(res.status).toBe(401);
    }
    expect(inner).toHaveBeenCalledTimes(100);
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
  });

  test("under quota (request 1 .. perMinute): inner invoked each time", async () => {
    const { withUserRateLimit } = await importHelper();
    setUser("user-a");
    const inner = vi.fn().mockResolvedValue(new Response("ok", { status: 200 }));
    const wrapped = withUserRateLimit(inner, {
      perMinute: 60,
      feature: "test.under",
    });

    for (let i = 0; i < 60; i++) {
      const res = await wrapped(makeRequest());
      expect(res.status).toBe(200);
    }
    expect(inner).toHaveBeenCalledTimes(60);
  });

  test("over quota: 61st call returns 429 + Retry-After: 60; inner NOT invoked", async () => {
    const { withUserRateLimit } = await importHelper();
    setUser("user-a");
    const inner = vi.fn().mockResolvedValue(new Response("ok", { status: 200 }));
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
    // Inner NOT invoked for the over-quota request.
    expect(inner).toHaveBeenCalledTimes(60);
  });

  test("over quota: emits exactly one warnSilentFallback with correct tags", async () => {
    const { withUserRateLimit } = await importHelper();
    setUser("user-a");
    const inner = vi.fn().mockResolvedValue(new Response("ok"));
    const wrapped = withUserRateLimit(inner, {
      perMinute: 2,
      feature: "kb-chat.test",
    });

    await wrapped(makeRequest()); // 1
    await wrapped(makeRequest()); // 2
    mockWarnSilentFallback.mockClear();
    await wrapped(makeRequest()); // 3 (over)

    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
    const [errArg, optsArg] = mockWarnSilentFallback.mock.calls[0];
    expect(errArg).toBeNull();
    expect(optsArg).toMatchObject({
      feature: "kb-chat.test",
      op: "rate-limit",
      extra: { userId: "user-a" },
    });
  });

  test("per-user isolation: user A at quota does not limit user B", async () => {
    const { withUserRateLimit } = await importHelper();
    const inner = vi.fn().mockResolvedValue(new Response("ok", { status: 200 }));
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

  test("per-feature isolation: two wrappers with different features use distinct counters", async () => {
    const { withUserRateLimit } = await importHelper();
    const innerA = vi.fn().mockResolvedValue(new Response("ok", { status: 200 }));
    const innerB = vi.fn().mockResolvedValue(new Response("ok", { status: 200 }));

    const wrappedA = withUserRateLimit(innerA, {
      perMinute: 2,
      feature: "kb-chat.thread-info",
    });
    const wrappedB = withUserRateLimit(innerB, {
      perMinute: 2,
      feature: "kb-chat.conversations",
    });

    setUser("user-a");
    // Exhaust wrapper A's counter for user-a.
    for (let i = 0; i < 2; i++) {
      expect((await wrappedA(makeRequest())).status).toBe(200);
    }
    expect((await wrappedA(makeRequest())).status).toBe(429);

    // Wrapper B is an independent counter — same user is NOT limited there.
    expect((await wrappedB(makeRequest())).status).toBe(200);
  });

  test("only supports two options (perMinute, feature) — type surface is minimal", async () => {
    // This is a compile-time assertion expressed at runtime: the helper's
    // call signature must reject extra keys via TypeScript's excess-property
    // check if the object literal is passed inline. We can't assert that at
    // runtime, but we CAN verify no unexpected keys influence behavior by
    // constructing Options with only the two fields and running the full
    // cycle.
    const { withUserRateLimit } = await importHelper();
    setUser("user-a");
    const inner = vi.fn().mockResolvedValue(new Response("ok"));
    const wrapped = withUserRateLimit(inner, {
      perMinute: 1,
      feature: "test.minimal",
    });
    expect((await wrapped(makeRequest())).status).toBe(200);
    expect((await wrapped(makeRequest())).status).toBe(429);
  });
});
