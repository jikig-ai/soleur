import { describe, test, expect } from "vitest";
import { buildCspHeader } from "../lib/csp";

function parseCspDirective(csp: string, directive: string): string {
  const match = csp.match(new RegExp(`${directive}\\s+([^;]+)`));
  return match?.[1]?.trim() ?? "";
}

const TEST_NONCE = "dGVzdC1ub25jZQ==";

describe("buildCspHeader", () => {
  const prodCsp = buildCspHeader({
    nonce: TEST_NONCE,
    isDev: false,
    supabaseUrl: "https://abc.supabase.co",
    appHost: "app.soleur.ai",
  });

  const devCsp = buildCspHeader({
    nonce: TEST_NONCE,
    isDev: true,
    supabaseUrl: "https://abc.supabase.co",
    appHost: "localhost:3000",
  });

  test("script-src contains nonce", () => {
    const scriptSrc = parseCspDirective(prodCsp, "script-src");
    expect(scriptSrc).toContain(`'nonce-${TEST_NONCE}'`);
  });

  test("script-src contains strict-dynamic", () => {
    const scriptSrc = parseCspDirective(prodCsp, "script-src");
    expect(scriptSrc).toContain("'strict-dynamic'");
  });

  test("script-src contains unsafe-inline as CSP2 fallback", () => {
    const scriptSrc = parseCspDirective(prodCsp, "script-src");
    expect(scriptSrc).toContain("'unsafe-inline'");
  });

  test("script-src contains https: as CSP1 fallback", () => {
    const scriptSrc = parseCspDirective(prodCsp, "script-src");
    expect(scriptSrc).toContain("https:");
  });

  test("script-src does not include unsafe-eval in production", () => {
    const scriptSrc = parseCspDirective(prodCsp, "script-src");
    expect(scriptSrc).not.toContain("unsafe-eval");
  });

  test("script-src includes unsafe-eval in development", () => {
    const scriptSrc = parseCspDirective(devCsp, "script-src");
    expect(scriptSrc).toContain("'unsafe-eval'");
  });

  test("style-src retains unsafe-inline", () => {
    const styleSrc = parseCspDirective(prodCsp, "style-src");
    expect(styleSrc).toContain("'unsafe-inline'");
  });

  test("connect-src includes Supabase host (https and wss)", () => {
    const connectSrc = parseCspDirective(prodCsp, "connect-src");
    expect(connectSrc).toContain("https://abc.supabase.co");
    expect(connectSrc).toContain("wss://abc.supabase.co");
  });

  // AC8 (#4916): the workspace-logo proxy GET 302-redirects the <img> to a
  // signed URL on the Supabase Storage host. CSP img-src must already allow
  // that host so the image loads — and NO csp.ts edit is needed (TR4 no-op).
  test("img-src includes the Supabase https origin (signed-URL host for workspace logos)", () => {
    const imgSrc = parseCspDirective(prodCsp, "img-src");
    expect(imgSrc).toContain("https://abc.supabase.co");
    expect(imgSrc).toContain("'self'");
  });

  test("connect-src uses http+ws when Supabase URL is http (e2e mock servers)", () => {
    // Regression guard: e2e tests use `http://localhost:<port>` for the
    // mock-supabase server. The CSP's connect-src must include the actual
    // scheme so authenticated e2e tests' fetch calls aren't silently
    // CSP-blocked. See playwright.config.ts MOCK_SUPABASE_URL.
    const csp = buildCspHeader({
      nonce: TEST_NONCE,
      isDev: true,
      supabaseUrl: "http://localhost:54399",
      appHost: "localhost:3100",
    });
    const connectSrc = parseCspDirective(csp, "connect-src");
    expect(connectSrc).toContain("http://localhost:54399");
    expect(connectSrc).toContain("ws://localhost:54399");
    expect(connectSrc).not.toContain("https://localhost:54399");
  });

  test("connect-src falls back to wildcard in dev when URL is empty", () => {
    const csp = buildCspHeader({
      nonce: TEST_NONCE,
      isDev: true,
      supabaseUrl: "",
      appHost: "localhost:3000",
    });
    const connectSrc = parseCspDirective(csp, "connect-src");
    expect(connectSrc).toContain("https://*.supabase.co");
    expect(connectSrc).toContain("wss://*.supabase.co");
  });

  test("throws when Supabase URL is missing in production", () => {
    expect(() =>
      buildCspHeader({ nonce: TEST_NONCE, isDev: false, supabaseUrl: "", appHost: "app.soleur.ai" }),
    ).toThrow("NEXT_PUBLIC_SUPABASE_URL must be set in production builds");
  });

  test("throws when Supabase URL is malformed in production", () => {
    expect(() =>
      buildCspHeader({ nonce: TEST_NONCE, isDev: false, supabaseUrl: "not-a-url", appHost: "app.soleur.ai" }),
    ).toThrow("NEXT_PUBLIC_SUPABASE_URL must be set in production builds");
  });

  test("does not throw on malformed Supabase URL in dev", () => {
    const csp = buildCspHeader({
      nonce: TEST_NONCE,
      isDev: true,
      supabaseUrl: "not-a-url",
      appHost: "localhost:3000",
    });
    expect(csp).toContain("*.supabase.co");
  });

  test("connect-src includes explicit wss:// for app WebSocket origin", () => {
    const connectSrc = parseCspDirective(prodCsp, "connect-src");
    expect(connectSrc).toContain("wss://app.soleur.ai");
  });

  test("connect-src includes ws:// for dev WebSocket origin", () => {
    const connectSrc = parseCspDirective(devCsp, "connect-src");
    expect(connectSrc).toContain("ws://localhost:3000");
  });

  test("connect-src does not use bare wss: scheme", () => {
    const connectSrc = parseCspDirective(prodCsp, "connect-src");
    // Bare 'wss:' (without host) allows connections to ANY wss:// host
    expect(connectSrc).not.toMatch(/\bwss:\s/);
  });

  test("connect-src includes push service endpoints (FCM, Mozilla, Apple)", () => {
    const connectSrc = parseCspDirective(prodCsp, "connect-src");
    expect(connectSrc).toContain("https://fcm.googleapis.com");
    expect(connectSrc).toContain("https://updates.push.services.mozilla.com");
    expect(connectSrc).toContain("https://*.push.apple.com");
  });

  test("connect-src includes push service endpoints in dev mode", () => {
    const connectSrc = parseCspDirective(devCsp, "connect-src");
    expect(connectSrc).toContain("https://fcm.googleapis.com");
    expect(connectSrc).toContain("https://updates.push.services.mozilla.com");
    expect(connectSrc).toContain("https://*.push.apple.com");
  });

  test("connect-src includes Sentry ingest domains (global and EU region)", () => {
    const connectSrc = parseCspDirective(prodCsp, "connect-src");
    expect(connectSrc).toContain("https://*.ingest.sentry.io");
    expect(connectSrc).toContain("https://*.ingest.de.sentry.io");
  });

  test("includes report-uri when sentryReportUri is provided", () => {
    const csp = buildCspHeader({
      nonce: TEST_NONCE,
      isDev: false,
      supabaseUrl: "https://abc.supabase.co",
      appHost: "app.soleur.ai",
      sentryReportUri: "https://o123.ingest.sentry.io/api/456/security/?sentry_key=abc",
    });
    expect(csp).toContain("report-uri https://o123.ingest.sentry.io/api/456/security/?sentry_key=abc");
  });

  test("omits report-uri when sentryReportUri is not provided", () => {
    expect(prodCsp).not.toContain("report-uri");
  });

  test("contains all required directives", () => {
    const requiredDirectives = [
      "default-src",
      "script-src",
      "style-src",
      "img-src",
      "font-src",
      "connect-src",
      "object-src",
      "frame-src",
      "worker-src",
      "base-uri",
      "form-action",
      "frame-ancestors",
      "upgrade-insecure-requests",
    ];
    for (const directive of requiredDirectives) {
      expect(prodCsp).toContain(directive);
    }
  });

  describe("form-action override", () => {
    test("defaults to 'self' when formActionExtra is not provided", () => {
      const formAction = parseCspDirective(prodCsp, "form-action");
      expect(formAction).toBe("'self'");
    });

    test("defaults to 'self' when formActionExtra is empty array", () => {
      const csp = buildCspHeader({
        nonce: TEST_NONCE,
        isDev: false,
        supabaseUrl: "https://abc.supabase.co",
        appHost: "app.soleur.ai",
        formActionExtra: [],
      });
      expect(parseCspDirective(csp, "form-action")).toBe("'self'");
    });

    test("extends form-action with whitelisted github.com origin", () => {
      const csp = buildCspHeader({
        nonce: TEST_NONCE,
        isDev: false,
        supabaseUrl: "https://abc.supabase.co",
        appHost: "app.soleur.ai",
        formActionExtra: ["https://github.com"],
      });
      expect(parseCspDirective(csp, "form-action")).toBe(
        "'self' https://github.com",
      );
    });

    test("deduplicates repeated origins in formActionExtra", () => {
      const csp = buildCspHeader({
        nonce: TEST_NONCE,
        isDev: false,
        supabaseUrl: "https://abc.supabase.co",
        appHost: "app.soleur.ai",
        formActionExtra: ["https://github.com", "https://github.com"],
      });
      expect(parseCspDirective(csp, "form-action")).toBe(
        "'self' https://github.com",
      );
    });

    test("throws when formActionExtra contains an origin not in the allowlist", () => {
      expect(() =>
        buildCspHeader({
          nonce: TEST_NONCE,
          isDev: false,
          supabaseUrl: "https://abc.supabase.co",
          appHost: "app.soleur.ai",
          formActionExtra: ["https://evil.example"],
        }),
      ).toThrow(/not in the allowlist/);
    });

    test("throws when formActionExtra contains a subtly different github origin", () => {
      // Defense-in-depth: github.io, raw.githubusercontent.com, codespaces,
      // and case-variant Github.com must NOT be silently accepted.
      for (const bad of [
        "https://github.io",
        "https://raw.githubusercontent.com",
        "https://Github.com",
        "http://github.com",
      ]) {
        expect(() =>
          buildCspHeader({
            nonce: TEST_NONCE,
            isDev: false,
            supabaseUrl: "https://abc.supabase.co",
            appHost: "app.soleur.ai",
            formActionExtra: [bad],
          }),
        ).toThrow(/not in the allowlist/);
      }
    });
  });
});
