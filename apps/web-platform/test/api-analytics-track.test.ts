import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  describe,
  test,
  expect,
  vi,
  beforeEach,
  afterEach,
} from "vitest";

// Phase 5.1/5.2: POST /api/analytics/track
//   - Rejects missing / disallowed Origin with 403
//   - Per-IP rate limit returns 429 after threshold
//   - Forwards goal + props to Plausible Events API
//   - Never forwards user_id (strips it if present)
//   - HTTP 402 from Plausible: graceful 204 (no error to client)
//   - Non-JSON Plausible response is tolerated (no crash, 204)
//   - GET returns 405
//   - Missing PLAUSIBLE_* env: graceful 204 skip
//
// Hardening bundle (#2383):
//   T1 — cf-connecting-ip beats rotating x-forwarded-for for rate-limit keying
//   T2 — throttle pruner reduces .size after window and module installs
//        setInterval(..., 60_000) calling analyticsTrackThrottle.prune()
//   T3 — allowlist strips non-path prop keys (email, sessionId, fingerprint, ...)
//   T4 — truncates prop string values at 200 chars
//   T5 — sanitizeForLog strips C0 control characters from goal + err

const { mockFetch, logWarn, logInfo, logDebug } = vi.hoisted(() => ({
  mockFetch: vi.fn(),
  logWarn: vi.fn(),
  logInfo: vi.fn(),
  logDebug: vi.fn(),
}));
vi.stubGlobal("fetch", mockFetch);

vi.mock("@/server/logger", () => ({
  default: { info: logInfo, warn: logWarn, error: vi.fn() },
  createChildLogger: () => ({
    info: logInfo,
    warn: logWarn,
    debug: logDebug,
    error: vi.fn(),
  }),
}));

async function importRoute() {
  return await import("@/app/api/analytics/track/route");
}

function makeRequest(
  url: string,
  {
    origin,
    forwardedFor,
    cfConnectingIp,
    body,
  }: {
    origin?: string | null;
    forwardedFor?: string;
    cfConnectingIp?: string;
    body?: unknown;
  },
): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (origin !== null && origin !== undefined) headers.set("origin", origin);
  if (forwardedFor) headers.set("x-forwarded-for", forwardedFor);
  if (cfConnectingIp) headers.set("cf-connecting-ip", cfConnectingIp);
  return new Request(url, {
    method: "POST",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

describe("POST /api/analytics/track", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockFetch.mockReset();
    logWarn.mockReset();
    logInfo.mockReset();
    logDebug.mockReset();
    vi.resetModules();
    process.env.PLAUSIBLE_SITE_ID = "soleur.test";
    process.env.PLAUSIBLE_EVENTS_URL = "https://plausible.io/api/event";
    process.env.APP_URL = "https://app.soleur.ai";
    process.env.ANALYTICS_TRACK_RATE_PER_MIN = "3";
  });
  afterEach(() => {
    delete process.env.PLAUSIBLE_SITE_ID;
    delete process.env.PLAUSIBLE_EVENTS_URL;
    delete process.env.APP_URL;
    delete process.env.ANALYTICS_TRACK_RATE_PER_MIN;
  });

  test("rejects disallowed Origin with 403", async () => {
    const { POST } = await importRoute();
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://evil.example",
      body: { goal: "kb.chat.opened", props: { path: "x" } },
    });
    const res = await POST(req);
    expect(res.status).toBe(403);
    expect(mockFetch).not.toHaveBeenCalled();
  });

  test("rejects missing Origin with 403", async () => {
    const { POST } = await importRoute();
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: null,
      body: { goal: "kb.chat.opened" },
    });
    const res = await POST(req);
    expect(res.status).toBe(403);
  });

  test("forwards goal + props to Plausible and returns 204", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 202 }));
    const { POST } = await importRoute();
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      forwardedFor: "1.2.3.4",
      body: { goal: "kb.chat.opened", props: { path: "knowledge-base/x.md" } },
    });
    const res = await POST(req);
    expect(res.status).toBe(204);
    expect(mockFetch).toHaveBeenCalledTimes(1);
    const [url, init] = mockFetch.mock.calls[0];
    expect(url).toBe("https://plausible.io/api/event");
    const init_ = init as RequestInit;
    const payload = JSON.parse(String(init_.body));
    expect(payload.name).toBe("kb.chat.opened");
    expect(payload.domain).toBe("soleur.test");
    expect(payload.props).toEqual({ path: "knowledge-base/x.md" });
  });

  test("strips user_id from forwarded props", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 202 }));
    const { POST } = await importRoute();
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: {
        goal: "kb.chat.opened",
        props: { path: "x", user_id: "abc", userId: "abc" },
      },
    });
    await POST(req);
    const [, init] = mockFetch.mock.calls[0];
    const payload = JSON.parse(String((init as RequestInit).body));
    expect(payload.props.user_id).toBeUndefined();
    expect(payload.props.userId).toBeUndefined();
    expect(payload.props.path).toBe("x");
  });

  test("HTTP 402 from Plausible is a graceful 204 skip", async () => {
    mockFetch.mockResolvedValue(new Response("{}", { status: 402 }));
    const { POST } = await importRoute();
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: { goal: "kb.chat.opened" },
    });
    const res = await POST(req);
    expect(res.status).toBe(204);
  });

  test("non-JSON / plaintext Plausible response does not crash (returns 204)", async () => {
    mockFetch.mockResolvedValue(
      new Response("rate limited, please try later", {
        status: 200,
        headers: { "content-type": "text/plain" },
      }),
    );
    const { POST } = await importRoute();
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: { goal: "kb.chat.opened" },
    });
    const res = await POST(req);
    expect(res.status).toBe(204);
  });

  test("per-IP rate limit returns 429 after threshold", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 202 }));
    const { POST } = await importRoute();
    const ip = "9.9.9.9";
    for (let i = 0; i < 3; i++) {
      const res = await POST(
        makeRequest("https://app.soleur.ai/api/analytics/track", {
          origin: "https://app.soleur.ai",
          forwardedFor: ip,
          body: { goal: "kb.chat.opened" },
        }),
      );
      expect(res.status).toBe(204);
    }
    const limited = await POST(
      makeRequest("https://app.soleur.ai/api/analytics/track", {
        origin: "https://app.soleur.ai",
        forwardedFor: ip,
        body: { goal: "kb.chat.opened" },
      }),
    );
    expect(limited.status).toBe(429);
  });

  test("GET method returns 405", async () => {
    const { GET } = await importRoute();
    const res = await GET();
    expect(res.status).toBe(405);
  });

  test("missing PLAUSIBLE_SITE_ID returns 204 without forwarding (graceful skip)", async () => {
    delete process.env.PLAUSIBLE_SITE_ID;
    const { POST } = await importRoute();
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: { goal: "kb.chat.opened" },
    });
    const res = await POST(req);
    expect(res.status).toBe(204);
    expect(mockFetch).not.toHaveBeenCalled();
  });

  test("invalid body (not JSON / missing goal) returns 400", async () => {
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest("https://app.soleur.ai/api/analytics/track", {
        origin: "https://app.soleur.ai",
        body: { notAGoal: "x" },
      }),
    );
    expect(res.status).toBe(400);
  });

  // -------------------------------------------------------------------------
  // #2383 hardening — T1..T5
  // -------------------------------------------------------------------------

  test("T1: prefers cf-connecting-ip over rotating x-forwarded-for for rate-limit keying", async () => {
    // Guard against silent coupling: the rate cap is read at module-load in
    // throttle.ts. If this env var is missing or resetModules gets dropped,
    // the test silently runs against the 120/min default and only fails at
    // 121 requests. Assert the contract explicitly.
    expect(process.env.ANALYTICS_TRACK_RATE_PER_MIN).toBe("3");

    mockFetch.mockResolvedValue(new Response("", { status: 202 }));
    const { POST } = await importRoute();
    const cfIp = "7.7.7.7";
    const xffRotation = ["1.1.1.1", "2.2.2.2", "3.3.3.3", "4.4.4.4"];
    const statuses: number[] = [];
    for (const xff of xffRotation) {
      const res = await POST(
        makeRequest("https://app.soleur.ai/api/analytics/track", {
          origin: "https://app.soleur.ai",
          cfConnectingIp: cfIp,
          forwardedFor: xff,
          body: { goal: "kb.chat.opened" },
        }),
      );
      statuses.push(res.status);
    }
    // First three requests allowed, fourth blocked. Pre-fix: route keys on
    // x-forwarded-for first; all four return 204.
    expect(statuses.slice(0, 3)).toEqual([204, 204, 204]);
    expect(statuses[3]).toBe(429);
  });

  test("T2a: analyticsTrackThrottle.prune() reclaims entries expired past the window", async () => {
    const { analyticsTrackThrottle, __resetAnalyticsTrackThrottleForTest } =
      await import("@/app/api/analytics/track/throttle");
    __resetAnalyticsTrackThrottleForTest();
    expect(analyticsTrackThrottle.size).toBe(0);

    expect(analyticsTrackThrottle.isAllowed("a")).toBe(true);
    expect(analyticsTrackThrottle.isAllowed("b")).toBe(true);
    expect(analyticsTrackThrottle.size).toBe(2);

    vi.useFakeTimers({ now: Date.now() });
    try {
      vi.advanceTimersByTime(61_000);
      analyticsTrackThrottle.prune();
      expect(analyticsTrackThrottle.size).toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });

  test("T2b: throttle module source installs a periodic prune interval", () => {
    // Negative-space guard: behavioral tests in T2a can still pass after a
    // refactor that removes the interval while leaving .prune() intact. The
    // source-grep pins the wiring. Style: csrf-coverage.test.ts and learning
    // 2026-04-15-negative-space-tests-must-follow-extracted-logic.
    const throttlePath = join(
      __dirname,
      "..",
      "app",
      "api",
      "analytics",
      "track",
      "throttle.ts",
    );
    const throttleSource = readFileSync(throttlePath, "utf-8");
    expect(throttleSource).toMatch(
      /setInterval\([\s\S]*analyticsTrackThrottle\.prune\(\)[\s\S]*60_?000/,
    );
    expect(throttleSource).toMatch(/\.unref\(\)/);
  });

  test("T3: drops non-allowlisted prop keys (email, sessionId, fingerprint, deviceId, ip)", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 202 }));
    const { POST } = await importRoute();
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: {
        goal: "kb.chat.opened",
        props: {
          path: "x",
          email: "a@b.example",
          sessionId: "s",
          session_id: "s",
          fingerprint: "f",
          deviceId: "d",
          device_id: "d",
          ip: "1.1.1.1",
          user_id: "u",
          userId: "u",
        },
      },
    });
    await POST(req);
    const [, init] = mockFetch.mock.calls[0];
    const payload = JSON.parse(String((init as RequestInit).body));
    expect(payload.props).toEqual({ path: "x" });
  });

  test("T4: truncates prop string values at 200 chars", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 202 }));
    const { POST } = await importRoute();
    const longPath = "a".repeat(500);
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: { goal: "kb.chat.opened", props: { path: longPath } },
    });
    await POST(req);
    const [, init] = mockFetch.mock.calls[0];
    const payload = JSON.parse(String((init as RequestInit).body));
    expect(payload.props.path).toHaveLength(200);
    expect(payload.props.path).toBe("a".repeat(200));
  });

  test("T5a: strips control characters from goal before logging (402 branch)", async () => {
    mockFetch.mockResolvedValue(new Response("{}", { status: 402 }));
    const { POST } = await importRoute();
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: { goal: "kb.chat.opened\n[FAKE] fake-event" },
    });
    await POST(req);
    // toMatchObject + .find tolerate future context-field additions (e.g.,
    // adding `status: 402`) and additional log lines; they still fail if the
    // goal is not stripped.
    const warnCall = logWarn.mock.calls.find(([, msg]) =>
      typeof msg === "string" && msg.includes("402"),
    );
    expect(warnCall).toBeDefined();
    const [ctx] = warnCall!;
    expect(ctx).toMatchObject({ goal: "kb.chat.opened[FAKE] fake-event" });
    expect(ctx.goal).not.toMatch(/[\x00-\x1f]/);
  });

  test("T5b: strips control characters from goal and err before logging (catch branch)", async () => {
    mockFetch.mockRejectedValue(new Error("network down\nINJECTED"));
    const { POST } = await importRoute();
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: { goal: "kb.opened\r\nLINE2" },
    });
    await POST(req);
    const warnCall = logWarn.mock.calls.find(([, msg]) =>
      typeof msg === "string" && msg.includes("forward failed"),
    );
    expect(warnCall).toBeDefined();
    const [ctx] = warnCall!;
    expect(typeof ctx.err).toBe("string");
    expect(ctx.err).not.toMatch(/[\x00-\x1f]/);
    expect(ctx.goal).toBe("kb.openedLINE2");
    expect(ctx.err).toContain("network downINJECTED");
  });

  test("T5c: strips Unicode line separators U+2028/U+2029 and DEL from logged goal", async () => {
    mockFetch.mockResolvedValue(new Response("{}", { status: 402 }));
    const { POST } = await importRoute();
    // U+2028 (line separator), U+2029 (paragraph separator), and DEL (0x7f)
    // are passed through by JSON loggers but rendered as line breaks by many
    // downstream log viewers — re-enabling log injection.
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: { goal: "kb\u2028.open\u2029ed\x7f[INJECTED]" },
    });
    await POST(req);
    const warnCall = logWarn.mock.calls.find(([, msg]) =>
      typeof msg === "string" && msg.includes("402"),
    );
    expect(warnCall).toBeDefined();
    const [ctx] = warnCall!;
    expect(ctx.goal).toBe("kb.opened[INJECTED]");
    expect(ctx.goal).not.toMatch(/[\u2028\u2029\x7f]/);
  });

  test("T6: non-string prop values for allowlisted keys are forwarded untouched (but counted as 1 key)", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 202 }));
    const { POST } = await importRoute();
    // The allowlist cap is applied per-key; the value type is not mutated for
    // non-strings. Document the current behavior so a future regression
    // accidentally coercing non-strings is caught.
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: { goal: "kb.chat.opened", props: { path: 42 } },
    });
    const res = await POST(req);
    expect(res.status).toBe(204);
    const [, init] = mockFetch.mock.calls[0];
    const payload = JSON.parse(String((init as RequestInit).body));
    expect(payload.props).toEqual({ path: 42 });
  });

  test("T8: logs scrub pattern names at debug when path contains PII (never raw value)", async () => {
    // #2462 — sanitizeProps scrubs PII tokens from the `path` value and the
    // route mirrors the existing `dropped` log pattern to emit a debug line
    // with the pattern names only. The raw value must never appear in any
    // debug context field.
    mockFetch.mockResolvedValue(new Response("", { status: 202 }));
    const { POST } = await importRoute();
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: {
        goal: "kb.chat.opened",
        props: { path: "/users/alice@example.com/settings" },
      },
    });
    await POST(req);

    // Forwarded payload is scrubbed.
    const [, init] = mockFetch.mock.calls[0];
    const payload = JSON.parse(String((init as RequestInit).body));
    expect(payload.props.path).toBe("/users/[email]/settings");

    // Debug log fires with pattern NAMES only — never the raw value.
    const scrubCall = logDebug.mock.calls.find(([, msg]) =>
      typeof msg === "string" && msg.includes("scrubbed"),
    );
    expect(scrubCall).toBeDefined();
    const [ctx] = scrubCall!;
    expect(ctx).toMatchObject({ scrubbed: ["email"] });
    // The raw value (pre-scrub) must never appear in ANY debug ctx field.
    const allDebugCtx = JSON.stringify(logDebug.mock.calls);
    expect(allDebugCtx).not.toContain("alice@example.com");
  });

  test("T7: rejects body with more than MAX_PROP_KEYS (20) props with 400", async () => {
    const { POST } = await importRoute();
    const tooManyProps: Record<string, unknown> = {};
    for (let i = 0; i < 25; i++) tooManyProps[`k${i}`] = "v";
    const req = makeRequest("https://app.soleur.ai/api/analytics/track", {
      origin: "https://app.soleur.ai",
      body: { goal: "kb.chat.opened", props: tooManyProps },
    });
    const res = await POST(req);
    expect(res.status).toBe(400);
    expect(mockFetch).not.toHaveBeenCalled();
  });
});
