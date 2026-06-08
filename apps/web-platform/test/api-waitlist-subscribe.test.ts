import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

// POST /api/waitlist — same-origin proxy to Buttondown's embed-subscribe.
//   - Rejects missing / disallowed Origin with 403 (browser-only form)
//   - Honeypot filled → silent 200, no forward
//   - Per-IP rate limit → 429 after threshold (MAX_PER_WINDOW = 5)
//   - Valid email → forwards email+tag+embed urlencoded, returns 200 {ok:true}
//   - Already-subscribed (Buttondown 400 "already…") → 200 {ok:true}
//   - Unexpected Buttondown status / network throw → 502 + warnSilentFallback
//   - Invalid email / invalid JSON → 400

const { mockFetch, warnSilentFallback, logWarn } = vi.hoisted(() => ({
  mockFetch: vi.fn(),
  warnSilentFallback: vi.fn(),
  logWarn: vi.fn(),
}));
vi.stubGlobal("fetch", mockFetch);

vi.mock("@/server/observability", () => ({
  warnSilentFallback,
  reportSilentFallback: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: logWarn, error: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: logWarn,
    debug: vi.fn(),
    error: vi.fn(),
  }),
}));

async function importRoute() {
  return await import("@/app/api/waitlist/route");
}

function makeRequest({
  origin,
  forwardedFor,
  body,
}: {
  origin?: string | null;
  forwardedFor?: string;
  body?: unknown;
}): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (origin !== null && origin !== undefined) headers.set("origin", origin);
  if (forwardedFor) headers.set("x-forwarded-for", forwardedFor);
  return new Request("https://app.soleur.ai/api/waitlist", {
    method: "POST",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

const OK_ORIGIN = "https://app.soleur.ai";

describe("POST /api/waitlist", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockFetch.mockReset();
    warnSilentFallback.mockReset();
    vi.resetModules();
    process.env.APP_URL = OK_ORIGIN;
  });
  afterEach(() => {
    delete process.env.APP_URL;
  });

  test("rejects disallowed Origin with 403", async () => {
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: "https://evil.example", body: { email: "a@b.co" } }),
    );
    expect(res.status).toBe(403);
    expect(mockFetch).not.toHaveBeenCalled();
  });

  test("rejects missing Origin with 403 (browser-only form)", async () => {
    const { POST } = await importRoute();
    const res = await POST(makeRequest({ origin: null, body: { email: "a@b.co" } }));
    expect(res.status).toBe(403);
    expect(mockFetch).not.toHaveBeenCalled();
  });

  test("valid email forwards email+tag+embed and returns 200 {ok:true}", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 200 }));
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "user@company.com" } }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(mockFetch).toHaveBeenCalledTimes(1);
    const [url, init] = mockFetch.mock.calls[0];
    expect(String(url)).toContain("buttondown.com/api/emails/embed-subscribe/soleur");
    const sent = new URLSearchParams(String((init as RequestInit).body));
    expect(sent.get("email")).toBe("user@company.com");
    expect(sent.get("tag")).toBe("pricing-waitlist");
    expect(sent.get("embed")).toBe("1");
  });

  test("already-subscribed (Buttondown 400 'already') is treated as success 200", async () => {
    mockFetch.mockResolvedValue(
      new Response("This email is already subscribed.", { status: 400 }),
    );
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "dup@company.com" } }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  test("filled honeypot returns silent 200 without forwarding", async () => {
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({
        origin: OK_ORIGIN,
        body: { email: "bot@spam.co", url: "http://spam.example" },
      }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(mockFetch).not.toHaveBeenCalled();
  });

  test("invalid email returns 400 without forwarding", async () => {
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "not-an-email" } }),
    );
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "invalid_email" });
    expect(mockFetch).not.toHaveBeenCalled();
  });

  test("invalid JSON returns 400", async () => {
    const { POST } = await importRoute();
    const headers = new Headers({
      origin: OK_ORIGIN,
      "content-type": "application/json",
    });
    const req = new Request("https://app.soleur.ai/api/waitlist", {
      method: "POST",
      headers,
      body: "{not json",
    });
    const res = await POST(req);
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "invalid_json" });
  });

  test("per-IP rate limit returns 429 after 5 allowed", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 200 }));
    const { POST } = await importRoute();
    const ip = "9.9.9.9";
    for (let i = 0; i < 5; i++) {
      const res = await POST(
        makeRequest({ origin: OK_ORIGIN, forwardedFor: ip, body: { email: `u${i}@c.co` } }),
      );
      expect(res.status).toBe(200);
    }
    const limited = await POST(
      makeRequest({ origin: OK_ORIGIN, forwardedFor: ip, body: { email: "u6@c.co" } }),
    );
    expect(limited.status).toBe(429);
    expect(limited.headers.get("Retry-After")).toBe("60");
  });

  test("unexpected Buttondown status → 502 + Sentry mirror", async () => {
    mockFetch.mockResolvedValue(new Response("upstream boom", { status: 503 }));
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "user@company.com" } }),
    );
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "upstream_unavailable" });
    expect(warnSilentFallback).toHaveBeenCalledTimes(1);
    expect(warnSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "waitlist-subscribe",
    });
  });

  test("network throw → 502 + Sentry mirror", async () => {
    mockFetch.mockRejectedValue(new Error("ECONNRESET"));
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "user@company.com" } }),
    );
    expect(res.status).toBe(502);
    expect(warnSilentFallback).toHaveBeenCalledTimes(1);
  });
});
