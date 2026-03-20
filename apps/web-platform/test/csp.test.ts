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
  });

  const devCsp = buildCspHeader({
    nonce: TEST_NONCE,
    isDev: true,
    supabaseUrl: "https://abc.supabase.co",
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

  test("connect-src falls back to wildcard in dev when URL is empty", () => {
    const csp = buildCspHeader({
      nonce: TEST_NONCE,
      isDev: true,
      supabaseUrl: "",
    });
    const connectSrc = parseCspDirective(csp, "connect-src");
    expect(connectSrc).toContain("https://*.supabase.co");
    expect(connectSrc).toContain("wss://*.supabase.co");
  });

  test("throws when Supabase URL is missing in production", () => {
    expect(() =>
      buildCspHeader({ nonce: TEST_NONCE, isDev: false, supabaseUrl: "" }),
    ).toThrow("NEXT_PUBLIC_SUPABASE_URL must be set in production builds");
  });

  test("throws when Supabase URL is malformed in production", () => {
    expect(() =>
      buildCspHeader({ nonce: TEST_NONCE, isDev: false, supabaseUrl: "not-a-url" }),
    ).toThrow("NEXT_PUBLIC_SUPABASE_URL must be set in production builds");
  });

  test("does not throw on malformed Supabase URL in dev", () => {
    const csp = buildCspHeader({
      nonce: TEST_NONCE,
      isDev: true,
      supabaseUrl: "not-a-url",
    });
    expect(csp).toContain("*.supabase.co");
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
});
