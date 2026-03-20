import { describe, test, expect } from "vitest";
import { buildSecurityHeaders } from "../lib/security-headers";

function findHeader(headers: { key: string; value: string }[], key: string) {
  return headers.find((h) => h.key === key)?.value ?? "";
}

describe("buildSecurityHeaders", () => {
  const headers = buildSecurityHeaders();

  test("does not return Content-Security-Policy (now middleware-owned)", () => {
    const keys = headers.map((h) => h.key);
    expect(keys).not.toContain("Content-Security-Policy");
  });

  test("X-Frame-Options is DENY", () => {
    expect(findHeader(headers, "X-Frame-Options")).toBe("DENY");
  });

  test("HSTS max-age is 2 years", () => {
    expect(findHeader(headers, "Strict-Transport-Security")).toContain(
      "max-age=63072000",
    );
  });

  test("X-Content-Type-Options is nosniff", () => {
    expect(findHeader(headers, "X-Content-Type-Options")).toBe("nosniff");
  });

  test("Referrer-Policy is strict-origin-when-cross-origin", () => {
    expect(findHeader(headers, "Referrer-Policy")).toBe(
      "strict-origin-when-cross-origin",
    );
  });

  test("X-XSS-Protection is explicitly 0", () => {
    expect(findHeader(headers, "X-XSS-Protection")).toBe("0");
  });

  test("Permissions-Policy disables dangerous APIs", () => {
    const pp = findHeader(headers, "Permissions-Policy");
    expect(pp).toContain("camera=()");
    expect(pp).toContain("microphone=()");
    expect(pp).toContain("geolocation=()");
  });

  test("Cross-Origin-Opener-Policy is same-origin", () => {
    expect(findHeader(headers, "Cross-Origin-Opener-Policy")).toBe(
      "same-origin",
    );
  });

  test("Cross-Origin-Resource-Policy is same-origin", () => {
    expect(findHeader(headers, "Cross-Origin-Resource-Policy")).toBe(
      "same-origin",
    );
  });

  test("returns all required non-CSP headers", () => {
    const keys = headers.map((h) => h.key);
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
});
