import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

// Phase 5.1/5.2: POST /api/analytics/track
//   - Rejects missing / disallowed Origin with 403
//   - Per-IP rate limit returns 429 after threshold
//   - Forwards goal + props to Plausible Events API
//   - Never forwards user_id (strips it if present)
//   - HTTP 402 from Plausible: graceful 204 (no error to client)
//   - Non-JSON Plausible response is tolerated (no crash, 204)
//   - GET returns 405
//   - Missing PLAUSIBLE_* env: graceful 204 skip

const { mockFetch } = vi.hoisted(() => ({
  mockFetch: vi.fn(),
}));
vi.stubGlobal("fetch", mockFetch);

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));

async function importRoute() {
  return await import("@/app/api/analytics/track/route");
}

function makeRequest(
  url: string,
  {
    origin,
    forwardedFor,
    body,
  }: { origin?: string | null; forwardedFor?: string; body?: unknown },
): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (origin !== null && origin !== undefined) headers.set("origin", origin);
  if (forwardedFor) headers.set("x-forwarded-for", forwardedFor);
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
});
