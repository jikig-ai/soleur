import { describe, test, expect } from "vitest";
import { buildSecurityHeaders } from "../lib/security-headers";

function findHeader(headers: { key: string; value: string }[], key: string) {
  return headers.find((h) => h.key === key)?.value ?? "";
}

function parseCspDirective(csp: string, directive: string): string {
  const match = csp.match(new RegExp(`${directive}\\s+([^;]+)`));
  return match?.[1]?.trim() ?? "";
}

describe("buildSecurityHeaders", () => {
  const prodHeaders = buildSecurityHeaders({
    isDev: false,
    supabaseUrl: "https://abc.supabase.co",
  });
  const devHeaders = buildSecurityHeaders({
    isDev: true,
    supabaseUrl: "https://abc.supabase.co",
  });
  // Wildcard fallback only allowed in dev mode
  const noUrlHeaders = buildSecurityHeaders({
    isDev: true,
    supabaseUrl: "",
  });
  const badUrlHeaders = buildSecurityHeaders({
    isDev: true,
    supabaseUrl: "not-a-url",
  });

  test("CSP contains frame-ancestors 'none'", () => {
    const csp = findHeader(prodHeaders, "Content-Security-Policy");
    expect(csp).toContain("frame-ancestors 'none'");
  });

  test("CSP does not include unsafe-eval in production", () => {
    const csp = findHeader(prodHeaders, "Content-Security-Policy");
    expect(csp).not.toContain("unsafe-eval");
  });

  test("CSP includes unsafe-eval in development", () => {
    const csp = findHeader(devHeaders, "Content-Security-Policy");
    expect(csp).toContain("unsafe-eval");
  });

  test("connect-src includes Supabase host when URL is provided", () => {
    const csp = findHeader(prodHeaders, "Content-Security-Policy");
    const connectSrc = parseCspDirective(csp, "connect-src");
    expect(connectSrc).toContain("https://abc.supabase.co");
    expect(connectSrc).toContain("wss://abc.supabase.co");
  });

  test("connect-src falls back to wildcard when URL is empty in dev", () => {
    const csp = findHeader(noUrlHeaders, "Content-Security-Policy");
    const connectSrc = parseCspDirective(csp, "connect-src");
    expect(connectSrc).toContain("https://*.supabase.co");
    expect(connectSrc).toContain("wss://*.supabase.co");
  });

  test("throws when Supabase URL is missing in production", () => {
    expect(() =>
      buildSecurityHeaders({ isDev: false, supabaseUrl: "" }),
    ).toThrow("NEXT_PUBLIC_SUPABASE_URL must be set in production");
  });

  test("throws when Supabase URL is malformed in production", () => {
    expect(() =>
      buildSecurityHeaders({ isDev: false, supabaseUrl: "not-a-url" }),
    ).toThrow("NEXT_PUBLIC_SUPABASE_URL must be set in production");
  });

  test("does not throw on malformed Supabase URL in dev", () => {
    expect(badUrlHeaders.length).toBeGreaterThan(0);
    const csp = findHeader(badUrlHeaders, "Content-Security-Policy");
    expect(csp).toContain("*.supabase.co");
    expect(csp).not.toContain("not-a-url");
  });

  test("X-Frame-Options is DENY", () => {
    expect(findHeader(prodHeaders, "X-Frame-Options")).toBe("DENY");
  });

  test("HSTS max-age is 2 years", () => {
    expect(findHeader(prodHeaders, "Strict-Transport-Security")).toContain(
      "max-age=63072000",
    );
  });

  test("X-Content-Type-Options is nosniff", () => {
    expect(findHeader(prodHeaders, "X-Content-Type-Options")).toBe("nosniff");
  });

  test("Referrer-Policy is strict-origin-when-cross-origin", () => {
    expect(findHeader(prodHeaders, "Referrer-Policy")).toBe(
      "strict-origin-when-cross-origin",
    );
  });

  test("X-XSS-Protection is explicitly 0", () => {
    expect(findHeader(prodHeaders, "X-XSS-Protection")).toBe("0");
  });

  test("Permissions-Policy disables dangerous APIs", () => {
    const pp = findHeader(prodHeaders, "Permissions-Policy");
    expect(pp).toContain("camera=()");
    expect(pp).toContain("microphone=()");
    expect(pp).toContain("geolocation=()");
  });

  test("Cross-Origin-Opener-Policy is same-origin", () => {
    expect(findHeader(prodHeaders, "Cross-Origin-Opener-Policy")).toBe(
      "same-origin",
    );
  });

  test("Cross-Origin-Resource-Policy is same-origin", () => {
    expect(findHeader(prodHeaders, "Cross-Origin-Resource-Policy")).toBe(
      "same-origin",
    );
  });

  test("CSP contains frame-src 'none'", () => {
    const csp = findHeader(prodHeaders, "Content-Security-Policy");
    expect(csp).toContain("frame-src 'none'");
  });

  test("CSP contains worker-src 'self'", () => {
    const csp = findHeader(prodHeaders, "Content-Security-Policy");
    expect(csp).toContain("worker-src 'self'");
  });

  test("returns all required headers", () => {
    const keys = prodHeaders.map((h) => h.key);
    expect(keys).toContain("Content-Security-Policy");
    expect(keys).toContain("X-Frame-Options");
    expect(keys).toContain("X-Content-Type-Options");
    expect(keys).toContain("Strict-Transport-Security");
    expect(keys).toContain("Referrer-Policy");
    expect(keys).toContain("Permissions-Policy");
    expect(keys).toContain("Cross-Origin-Opener-Policy");
    expect(keys).toContain("Cross-Origin-Resource-Policy");
    expect(keys).toContain("X-DNS-Prefetch-Control");
    expect(keys).toContain("X-XSS-Protection");
  });

  test("CSP contains all required directives", () => {
    const csp = findHeader(prodHeaders, "Content-Security-Policy");
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
      expect(csp).toContain(directive);
    }
  });
});
