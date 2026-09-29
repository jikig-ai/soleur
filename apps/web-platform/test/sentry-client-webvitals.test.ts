// #9178 Phase 2 — client field-RUM wiring + transaction/span scrub boundary.
//
// `sentry.client.config.ts` gains `browserTracingIntegration()` (which
// auto-registers webVitalsIntegration — pageload/navigation transactions carry
// LCP/CLS/INP/FCP/TTFB as measurements; the standalone webVitalsIntegration
// cannot emit FCP/TTFB at all) plus a `tracesSampler` armed by a client-side
// sessionStorage marker (a client sampler cannot see the `x-perf-probe` header
// the server sampler reads — the perf probe arms `soleur.perf-probe` via
// page.addInitScript before navigation).
//
// The second gate is the same #3829-class interaction the server suite pins:
// transaction envelopes and span payloads DO NOT flow through `beforeSend` —
// they flow through `beforeSendTransaction` and `beforeSendSpan`. Enabling
// tracing without those sinks would ship un-scrubbed vitals payloads
// (user context, URL query strings in `http.url` span data) to Sentry.

import { describe, it, expect, vi, afterEach } from "vitest";

const { initSpy, browserTracingSpy, fakeBrowserTracing } = vi.hoisted(() => {
  const fakeBrowserTracing = { name: "BrowserTracing" };
  return {
    initSpy: vi.fn(),
    browserTracingSpy: vi.fn(() => fakeBrowserTracing),
    fakeBrowserTracing,
  };
});

vi.mock("@sentry/nextjs", () => ({
  init: initSpy,
  browserTracingIntegration: browserTracingSpy,
}));

// Synthesized fake JWT (3 base64url segments, "eyJ"-prefixed). Same shape used
// by `sentry-client-jwt-scrub.test.ts` fixtures.
const FAKE_JWT =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSJ9.synthesized-signature-for-webvitals-test"; // gitleaks:allow # synthesized
// Opaque (non-JWT-shaped) secret — the shape-driven query/path sanitize is
// what catches it, never the substring scrub.
const OPAQUE_SECRET = "pk_sk_opaque_secret_0123456789abcdef"; // gitleaks:allow # synthesized
const INVITE_TOKEN = "invite-token-AbCdEf012345"; // gitleaks:allow # synthesized

interface ClientInitOptions {
  integrations?: unknown;
  tracesSampleRate?: number;
  tracesSampler?: (ctx: unknown) => number;
  sendDefaultPii?: boolean;
  beforeSend?: (event: unknown) => unknown;
  beforeSendTransaction?: (event: unknown) => unknown;
  beforeSendSpan?: (span: unknown) => unknown;
  beforeBreadcrumb?: (bc: unknown) => unknown;
}

async function loadOptions(): Promise<ClientInitOptions> {
  await import("@/sentry.client.config");
  expect(initSpy).toHaveBeenCalledTimes(1);
  return initSpy.mock.calls[0][0] as ClientInitOptions;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("sentry.client.config web-vitals wiring (#9178)", () => {
  it("registers browserTracingIntegration in init options", async () => {
    const opts = await loadOptions();
    expect(browserTracingSpy).toHaveBeenCalledTimes(1);
    expect(opts.integrations).toContain(fakeBrowserTracing);
  });

  it("samples at 1.0 when the sessionStorage perf-probe marker is armed", async () => {
    const opts = await loadOptions();
    vi.stubGlobal("sessionStorage", {
      getItem: (key: string) => (key === "soleur.perf-probe" ? "1" : null),
    });
    expect(opts.tracesSampler!({ name: "GET /dashboard" })).toBe(1);
  });

  it("applies the 0.1 floor when the marker is absent or wrong-valued", async () => {
    const opts = await loadOptions();
    // Exact-value pin: a silent floor drift multiplies transaction volume —
    // the ceiling comparison would stay green (mirrors the server sampler
    // test's 0.02 pin).
    vi.stubGlobal("sessionStorage", { getItem: () => null });
    expect(opts.tracesSampler!({ name: "GET /dashboard" })).toBe(0.1);
    vi.stubGlobal("sessionStorage", {
      getItem: (key: string) => (key === "soleur.perf-probe" ? "yes" : null),
    });
    expect(opts.tracesSampler!({ name: "GET /dashboard" })).toBe(0.1);
  });

  it("applies the floor when sessionStorage is absent (node/SSR-shaped env)", async () => {
    const opts = await loadOptions();
    // Unit env runs under node with webstorage disabled — `sessionStorage` is
    // simply undefined here; no stub needed.
    expect(opts.tracesSampler!({ name: "GET /dashboard" })).toBe(0.1);
  });

  it("applies the floor when storage access throws", async () => {
    const opts = await loadOptions();
    vi.stubGlobal("sessionStorage", {
      getItem: () => {
        throw new Error("SecurityError: access denied");
      },
    });
    expect(opts.tracesSampler!({ name: "GET /dashboard" })).toBe(0.1);
  });

  it("has no tracesSampleRate fallback above 0.1 and keeps sendDefaultPii unset", async () => {
    const opts = await loadOptions();
    // NFR4: no fallback rate may exceed 0.1 — the key is removed entirely.
    expect(opts.tracesSampleRate).toBeUndefined();
    expect(opts.sendDefaultPii).toBeUndefined();
  });
});

describe("sentry.client.config transaction/span scrub boundary (#9178)", () => {
  function dirtyTransaction() {
    return {
      type: "transaction",
      transaction: `pageload /cb?email=victim@example.com`,
      message: `pageload slow (token: ${FAKE_JWT})`,
      user: {
        id: "u1",
        email: "victim@example.com",
        username: "alice",
        ip_address: "1.2.3.4",
      },
      extra: { userId: "u1", email: "victim@example.com", route: "kept" },
      contexts: { user: { user_id: "u2", role: "kept" } },
      breadcrumbs: [{ data: { userId: "u3", url: "kept" } }],
      request: {
        url: `https://app.soleur.ai/callback?email=victim@example.com`,
        query_string: `token=${FAKE_JWT}`,
        data: `body token=${FAKE_JWT}&opaque=${OPAQUE_SECRET}`,
        headers: {
          referer: `https://x.example/?t=${FAKE_JWT}`,
          host: "app.soleur.ai",
        },
        cookies: { "sb-auth-token": FAKE_JWT },
      },
      spans: [dirtySpan()],
    };
  }

  function dirtySpan() {
    return {
      span_id: "aa",
      trace_id: "bb",
      start_timestamp: 1,
      op: "http.client",
      description: `fetch /api/x?email=victim@example.com`,
      data: {
        user_id: "u4",
        email: "victim@example.com",
        "http.url": `https://api.example/x?code=${FAKE_JWT}`,
        "http.method": "GET",
      },
    };
  }

  it("strips user/PII and scrubs JWT/email substrings in beforeSend (error event)", async () => {
    const opts = await loadOptions();
    expect(typeof opts.beforeSend).toBe("function");
    const event = {
      message: `boom (preview: ${FAKE_JWT})`,
      exception: { values: [{ value: "auth failed for victim@example.com" }] },
      user: {
        id: "u1",
        email: "victim@example.com",
        username: "alice",
        ip_address: "1.2.3.4",
      },
      extra: { userId: "u1", segment: "kept" },
    };
    const out = opts.beforeSend!(event) as {
      message?: string;
      exception?: { values?: Array<{ value?: string }> };
      user?: Record<string, unknown>;
      extra?: Record<string, unknown>;
    };
    expect(out.user?.id).toBeUndefined();
    expect(out.user?.email).toBeUndefined();
    expect(out.user?.username).toBeUndefined();
    expect(out.user?.ip_address).toBeUndefined();
    expect(out.extra?.userId).toBeUndefined();
    expect(out.extra?.segment).toBe("kept");
    expect(out.message).toContain("<jwt-redacted>");
    expect(out.message).not.toContain("eyJ");
    expect(out.exception?.values?.[0]?.value).toContain("<email-redacted>");
    expect(out.exception?.values?.[0]?.value).not.toContain(
      "victim@example.com",
    );
  });

  it("strips user/PII and scrubs JWT/email substrings in beforeSendTransaction", async () => {
    const opts = await loadOptions();
    expect(typeof opts.beforeSendTransaction).toBe("function");
    const out = opts.beforeSendTransaction!(dirtyTransaction()) as {
      transaction?: string;
      message?: string;
      user?: Record<string, unknown>;
      extra?: Record<string, unknown>;
      contexts?: Record<string, Record<string, unknown>>;
      breadcrumbs?: Array<{ data?: Record<string, unknown> }>;
      request?: {
        url?: string;
        query_string?: string;
        data?: string;
        headers?: Record<string, string>;
        cookies?: Record<string, string>;
      };
      spans?: Array<{
        description?: string;
        data?: Record<string, unknown>;
      }>;
    };

    // user context — same four-field zeroing as the error-event sink.
    expect(out.user?.id).toBeUndefined();
    expect(out.user?.email).toBeUndefined();
    expect(out.user?.username).toBeUndefined();
    expect(out.user?.ip_address).toBeUndefined();

    // structured PII keys.
    expect(out.extra?.userId).toBeUndefined();
    expect(out.extra?.email).toBeUndefined();
    expect(out.extra?.route).toBe("kept");
    expect(out.contexts?.user?.user_id).toBeUndefined();
    expect(out.contexts?.user?.role).toBe("kept");
    expect(out.breadcrumbs?.[0]?.data?.userId).toBeUndefined();
    expect(out.breadcrumbs?.[0]?.data?.url).toBe("kept");

    // string fields carrying JWT/email substrings.
    expect(out.transaction).not.toContain("victim@example.com");
    expect(out.transaction).toContain("<email-redacted>");
    expect(out.message).toContain("<jwt-redacted>");
    // request.url's query tail is STRIPPED (shape-driven sanitize — OAuth
    // codes and hash fragments never reach Sentry), not substring-scrubbed.
    expect(out.request?.url).toBe("https://app.soleur.ai/callback");
    expect(out.request?.url).not.toContain("victim@example.com");
    // query_string is deleted outright — per-value substring scrub misses
    // non-JWT-shaped secrets (same contract as server sanitizeRequestForSentry).
    expect(out.request?.query_string).toBeUndefined();
    // A string request.data body still gets substring scrub.
    expect(out.request?.data).toContain("<jwt-redacted>");
    expect(out.request?.data).toContain(OPAQUE_SECRET);
    expect(out.request?.headers?.referer).toContain("<jwt-redacted>");
    expect(out.request?.headers?.host).toBe("app.soleur.ai");
    expect(out.request?.cookies?.["sb-auth-token"]).toContain(
      "<jwt-redacted>",
    );

    // embedded child spans are span payloads — same boundary applies.
    const span = out.spans?.[0];
    expect(span?.data?.user_id).toBeUndefined();
    expect(span?.data?.email).toBeUndefined();
    expect(span?.data?.["http.method"]).toBe("GET");
    expect(String(span?.data?.["http.url"])).toContain("<jwt-redacted>");
    expect(span?.description).not.toContain("victim@example.com");
    expect(span?.description).toContain("<email-redacted>");
  });

  it("strips PII keys and scrubs JWT/email substrings in beforeSendSpan", async () => {
    const opts = await loadOptions();
    expect(typeof opts.beforeSendSpan).toBe("function");
    const out = opts.beforeSendSpan!(dirtySpan()) as {
      description?: string;
      data?: Record<string, unknown>;
    };
    expect(out.data?.user_id).toBeUndefined();
    expect(out.data?.email).toBeUndefined();
    expect(out.data?.["http.method"]).toBe("GET");
    expect(String(out.data?.["http.url"])).toContain("<jwt-redacted>");
    expect(out.description).not.toContain("victim@example.com");
    expect(out.description).toContain("<email-redacted>");
  });

  it("reduces bearer-token path tails and unrouted transaction names (#9180 review P1)", async () => {
    const opts = await loadOptions();
    const out = opts.beforeSendTransaction!({
      type: "transaction",
      transaction: `pageload /invite/${INVITE_TOKEN}`,
      request: {
        url: `https://app.soleur.ai/invite/${INVITE_TOKEN}?code=oauth-callback-secret#access_token=${OPAQUE_SECRET}`,
        query_string: { code: OPAQUE_SECRET },
        headers: {},
        cookies: {},
      },
    }) as {
      transaction?: string;
      request?: { url?: string; query_string?: unknown };
    };

    // The token tail is bearer material valid for days — reduced to <token>
    // in both the URL and the transaction name, no `eyJ` shape required.
    expect(out.request?.url).toBe("https://app.soleur.ai/invite/<token>");
    expect(out.request?.url).not.toContain(INVITE_TOKEN);
    expect(out.request?.url).not.toContain(OPAQUE_SECRET);
    expect(out.transaction).toBe("pageload /invite/<token>");
    expect(out.transaction).not.toContain(INVITE_TOKEN);
    // query_string is deleted outright whatever shape it arrives in.
    expect(out.request?.query_string).toBeUndefined();
  });

  it("scrubs navigation breadcrumbs (from/to URL tails + message)", async () => {
    const opts = await loadOptions();
    expect(typeof opts.beforeBreadcrumb).toBe("function");
    const out = opts.beforeBreadcrumb!({
      category: "navigation",
      message: `nav to /invite/${INVITE_TOKEN} by victim@example.com`,
      data: {
        from: `/invite/${INVITE_TOKEN}`,
        to: `https://app.soleur.ai/shared/${INVITE_TOKEN}`,
        url: "kept-but-scanned",
        // Arbitrary data keys get the same scrub (server parity — a
        // breadcrumb added by app code can carry any payload).
        note: `deeplink /invite/${INVITE_TOKEN} ${OPAQUE_SECRET}`,
        nested: { href: `/api/account/export/${INVITE_TOKEN}` },
        userId: "u1",
      },
    }) as { message?: string; data?: Record<string, unknown> };

    expect(out.message).toContain("<email-redacted>");
    expect(out.message).not.toContain(INVITE_TOKEN);
    expect(out.data?.from).toBe("/invite/<token>");
    expect(out.data?.to).toBe("https://app.soleur.ai/shared/<token>");
    expect(out.data?.url).toBe("kept-but-scanned");
    expect(out.data?.note).not.toContain(INVITE_TOKEN);
    // An opaque (non-JWT/email-shaped) string in an arbitrary field survives —
    // same boundary as the server's key-shape-driven scrub.
    expect(out.data?.note).toContain(OPAQUE_SECRET);
    expect((out.data?.nested as { href?: string })?.href).toBe(
      "/api/account/export/<token>",
    );
    expect(out.data?.userId).toBeUndefined();
  });
});
