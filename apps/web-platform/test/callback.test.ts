import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { resolveOrigin } from "../lib/auth/resolve-origin";

describe("auth callback origin validation", () => {
  let warnSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
  });

  afterEach(() => {
    warnSpy.mockRestore();
  });

  // --- Security: malicious origins are rejected ---

  test("rejects malicious x-forwarded-host", () => {
    expect(resolveOrigin("evil.com", "https", "app.soleur.ai")).toBe(
      "https://app.soleur.ai",
    );
    expect(warnSpy).toHaveBeenCalledWith(
      "[callback] Rejected origin: https://evil.com",
    );
  });

  test("rejects malicious proto + host combination", () => {
    expect(resolveOrigin("evil.com", "http", "app.soleur.ai")).toBe(
      "https://app.soleur.ai",
    );
  });

  test("rejects port variants not in allowlist", () => {
    expect(resolveOrigin("evil.com:3000", null, null)).toBe(
      "https://app.soleur.ai",
    );
  });

  test("rejects subdomain spoofing", () => {
    expect(resolveOrigin("app.soleur.ai.evil.com", "https", null)).toBe(
      "https://app.soleur.ai",
    );
  });

  test("rejects userinfo abuse", () => {
    expect(resolveOrigin("app.soleur.ai@evil.com", "https", null)).toBe(
      "https://app.soleur.ai",
    );
  });

  test("rejects case variation (headers preserve case)", () => {
    expect(resolveOrigin("APP.SOLEUR.AI", "https", null)).toBe(
      "https://app.soleur.ai",
    );
  });

  // --- Functional: legitimate origins are accepted ---

  test("accepts legitimate Cloudflare-proxied request", () => {
    expect(resolveOrigin("app.soleur.ai", "https", null)).toBe(
      "https://app.soleur.ai",
    );
    expect(warnSpy).not.toHaveBeenCalled();
  });

  test("accepts localhost for development", () => {
    expect(resolveOrigin(null, "http", "localhost:3000")).toBe(
      "http://localhost:3000",
    );
  });

  test("falls back to production when no headers present", () => {
    expect(resolveOrigin(null, null, null)).toBe("https://app.soleur.ai");
  });
});
