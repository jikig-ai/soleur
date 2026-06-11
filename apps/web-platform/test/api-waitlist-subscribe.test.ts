import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

// POST /api/waitlist — same-origin proxy to Buttondown's authenticated v1 API
//   (POST api.buttondown.com/v1/subscribers, Authorization: Token).
//   - Rejects missing / disallowed Origin with 403 (browser-only form)
//   - Honeypot filled → silent 200, no forward
//   - Per-IP rate limit → 429 after threshold (MAX_PER_WINDOW = 5)
//   - Valid email → POSTs JSON {email_address, tags:["pricing-waitlist"]} (no `type`,
//     so Buttondown's default double opt-in is preserved), returns 200 {ok:true}
//   - Plausible public visitor IP (cf-connecting-ip) → forwarded as `ip_address`
//     so Buttondown firewall-scores the visitor, not the server (survives a
//     re-escalation to aggressive auditing mode); implausible/private/absent →
//     field omitted (fail-safe: today's server-IP-scored behavior)
//   - Already-subscribed (v1 collision 400) → 200 {ok:true}
//   - Unexpected status / network throw / timeout → 502 + warnSilentFallback
//   - Missing BUTTONDOWN_API_KEY → fail-closed 502 before any fetch
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
  cfConnectingIp,
  body,
}: {
  origin?: string | null;
  forwardedFor?: string;
  cfConnectingIp?: string;
  body?: unknown;
}): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (origin !== null && origin !== undefined) headers.set("origin", origin);
  if (forwardedFor) headers.set("x-forwarded-for", forwardedFor);
  if (cfConnectingIp) headers.set("cf-connecting-ip", cfConnectingIp);
  return new Request("https://app.soleur.ai/api/waitlist", {
    method: "POST",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

const OK_ORIGIN = "https://app.soleur.ai";
const TEST_API_KEY = "test-buttondown-key";

describe("POST /api/waitlist", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockFetch.mockReset();
    warnSilentFallback.mockReset();
    vi.resetModules();
    process.env.APP_URL = OK_ORIGIN;
    process.env.BUTTONDOWN_API_KEY = TEST_API_KEY;
  });
  afterEach(() => {
    delete process.env.APP_URL;
    delete process.env.BUTTONDOWN_API_KEY;
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

  test("valid email POSTs v1 subscribers JSON (no type) and returns 200 {ok:true}", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 201 }));
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "user@company.com" } }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(mockFetch).toHaveBeenCalledTimes(1);
    const [url, init] = mockFetch.mock.calls[0];
    expect(String(url)).toContain("api.buttondown.com/v1/subscribers");

    const headers = new Headers((init as RequestInit).headers);
    expect(headers.get("authorization")).toBe(`Token ${TEST_API_KEY}`);
    expect(headers.get("content-type")).toBe("application/json");

    const sent = JSON.parse(String((init as RequestInit).body)) as Record<string, unknown>;
    expect(sent.email_address).toBe("user@company.com");
    expect(sent.tags).toEqual(["pricing-waitlist"]);
    // Double-opt-in preservation guard: never send `type` (would skip the
    // confirmation email + the GDPR Art. 6(1)(a) consent step).
    expect(sent).not.toHaveProperty("type");
    // No cf-connecting-ip header → no ip_address forwarded; exact key set
    // guards against silent body-shape drift in either direction.
    expect(sent).not.toHaveProperty("ip_address");
    expect(Object.keys(sent).sort()).toEqual(["email_address", "tags"]);

    // The abort timeout must be wired so an upstream stall degrades to a JSON 502.
    expect((init as RequestInit).signal).toBeInstanceOf(AbortSignal);
  });

  test("plausible public IPv4 visitor IP is forwarded as ip_address", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 201 }));
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({
        origin: OK_ORIGIN,
        cfConnectingIp: "203.0.113.7",
        body: { email: "user@company.com" },
      }),
    );
    expect(res.status).toBe(200);
    const sent = JSON.parse(
      String((mockFetch.mock.calls[0][1] as RequestInit).body),
    ) as Record<string, unknown>;
    expect(sent.ip_address).toBe("203.0.113.7");
    expect(sent.email_address).toBe("user@company.com");
    expect(sent.tags).toEqual(["pricing-waitlist"]);
    expect(sent).not.toHaveProperty("type");
    expect(Object.keys(sent).sort()).toEqual(["email_address", "ip_address", "tags"]);
  });

  test("plausible public IPv6 visitor IP is forwarded as ip_address", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 201 }));
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({
        origin: OK_ORIGIN,
        cfConnectingIp: "2001:db8::1",
        body: { email: "user@company.com" },
      }),
    );
    expect(res.status).toBe(200);
    const sent = JSON.parse(
      String((mockFetch.mock.calls[0][1] as RequestInit).body),
    ) as Record<string, unknown>;
    expect(sent.ip_address).toBe("2001:db8::1");
  });

  test("private IPv4 (direct-to-origin spoof) is omitted; subscribe still succeeds", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 201 }));
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({
        origin: OK_ORIGIN,
        cfConnectingIp: "10.0.0.1",
        body: { email: "user@company.com" },
      }),
    );
    expect(res.status).toBe(200);
    const sent = JSON.parse(
      String((mockFetch.mock.calls[0][1] as RequestInit).body),
    ) as Record<string, unknown>;
    expect(sent).not.toHaveProperty("ip_address");
    expect(Object.keys(sent).sort()).toEqual(["email_address", "tags"]);
  });

  test("garbage cf-connecting-ip is omitted; subscribe still succeeds (never breaks a signup)", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 201 }));
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({
        origin: OK_ORIGIN,
        cfConnectingIp: "not-an-ip",
        body: { email: "user@company.com" },
      }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    const sent = JSON.parse(
      String((mockFetch.mock.calls[0][1] as RequestInit).body),
    ) as Record<string, unknown>;
    expect(sent).not.toHaveProperty("ip_address");
  });

  test("already-subscribed (v1 collision 400) is treated as success 200", async () => {
    mockFetch.mockResolvedValue(
      new Response(
        JSON.stringify({
          code: "email_already_exists",
          detail: "A subscriber with this email address already exists.",
        }),
        { status: 400, headers: { "content-type": "application/json" } },
      ),
    );
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "dup@company.com" } }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  test("already-subscribed plaintext 400 (legacy body) is treated as success 200", async () => {
    mockFetch.mockResolvedValue(
      new Response("This email is already subscribed.", { status: 400 }),
    );
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "dup2@company.com" } }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  test("non-duplicate validation 400 is NOT swallowed → 502 + Sentry mirror", async () => {
    // A genuine validation error (not a collision) must surface as 502, never a
    // false success — otherwise a real signup is silently dropped.
    mockFetch.mockResolvedValue(
      new Response(
        JSON.stringify({
          code: "invalid_email_address",
          detail: "Enter a valid email address.",
        }),
        { status: 400, headers: { "content-type": "application/json" } },
      ),
    );
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "user@company.com" } }),
    );
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "upstream_unavailable" });
    expect(warnSilentFallback).toHaveBeenCalledTimes(1);
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

  test("per-IP rate limit (keyed on cf-connecting-ip) returns 429 after 5 allowed", async () => {
    mockFetch.mockResolvedValue(new Response("", { status: 201 }));
    const { POST } = await importRoute();
    const ip = "9.9.9.9";
    for (let i = 0; i < 5; i++) {
      const res = await POST(
        makeRequest({ origin: OK_ORIGIN, cfConnectingIp: ip, body: { email: `u${i}@c.co` } }),
      );
      expect(res.status).toBe(200);
    }
    const limited = await POST(
      makeRequest({ origin: OK_ORIGIN, cfConnectingIp: ip, body: { email: "u6@c.co" } }),
    );
    expect(limited.status).toBe(429);
    expect(limited.headers.get("Retry-After")).toBe("60");
  });

  test("rotating x-forwarded-for CANNOT mint fresh buckets (anti-amplification)", async () => {
    // Security: the rate-limit key must NOT trust client-controllable XFF, or an
    // attacker rotates it to spam Buttondown opt-in emails. With no
    // cf-connecting-ip, every request shares the single "unknown" bucket, so a
    // rotated-XFF flood is still capped at 5/window total → 6th is 429.
    mockFetch.mockResolvedValue(new Response("", { status: 201 }));
    const { POST } = await importRoute();
    const statuses: number[] = [];
    for (let i = 0; i < 6; i++) {
      const res = await POST(
        makeRequest({
          origin: OK_ORIGIN,
          forwardedFor: `1.2.3.${i}`, // distinct spoofed XFF each time
          body: { email: `spam${i}@victim.co` },
        }),
      );
      statuses.push(res.status);
    }
    expect(statuses.slice(0, 5)).toEqual([200, 200, 200, 200, 200]);
    expect(statuses[5]).toBe(429);
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

  test("bad key (401) → 502 + Sentry mirror", async () => {
    mockFetch.mockResolvedValue(
      new Response(JSON.stringify({ detail: "Invalid token." }), { status: 401 }),
    );
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "user@company.com" } }),
    );
    expect(res.status).toBe(502);
    expect(warnSilentFallback).toHaveBeenCalledTimes(1);
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

  test("upstream timeout (AbortSignal.timeout → TimeoutError) → 502 + Sentry mirror", async () => {
    mockFetch.mockRejectedValue(
      Object.assign(new Error("The operation was aborted due to timeout"), {
        name: "TimeoutError",
      }),
    );
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "user@company.com" } }),
    );
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "upstream_unavailable" });
    expect(warnSilentFallback).toHaveBeenCalledTimes(1);
  });

  test("missing BUTTONDOWN_API_KEY → fail-closed 502 before any fetch", async () => {
    delete process.env.BUTTONDOWN_API_KEY;
    const { POST } = await importRoute();
    const res = await POST(
      makeRequest({ origin: OK_ORIGIN, body: { email: "user@company.com" } }),
    );
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "upstream_unavailable" });
    expect(warnSilentFallback).toHaveBeenCalledTimes(1);
    // Fail closed: the worker must never reach the upstream call without a key.
    expect(mockFetch).not.toHaveBeenCalled();
  });
});
