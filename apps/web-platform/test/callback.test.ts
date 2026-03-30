import { describe, test, expect } from "vitest";
import { resolveOrigin } from "../lib/auth/resolve-origin";

describe("auth callback origin validation", () => {
  // --- Security: malicious origins are rejected ---

  test("rejects malicious x-forwarded-host", () => {
    expect(resolveOrigin("evil.com", "https", "app.soleur.ai")).toBe(
      "https://app.soleur.ai",
    );
    // Rejection is logged via Pino (structured) — verified by return value
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

  // --- Functional: legitimate origins are accepted ---

  test("normalizes uppercase host to match allowlist", () => {
    expect(resolveOrigin("APP.SOLEUR.AI", "https", null)).toBe(
      "https://app.soleur.ai",
    );
  });

  test("accepts legitimate Cloudflare-proxied request", () => {
    expect(resolveOrigin("app.soleur.ai", "https", null)).toBe(
      "https://app.soleur.ai",
    );
  });

  test("rejects localhost outside development", () => {
    expect(resolveOrigin(null, "http", "localhost:3000")).toBe(
      "https://app.soleur.ai",
    );
  });

  test("accepts localhost for development", () => {
    const env = process.env as Record<string, string | undefined>;
    const origEnv = env.NODE_ENV;
    env.NODE_ENV = "development";
    try {
      expect(resolveOrigin(null, "http", "localhost:3000")).toBe(
        "http://localhost:3000",
      );
    } finally {
      env.NODE_ENV = origEnv;
    }
  });

  test("falls back to production when no headers present", () => {
    expect(resolveOrigin(null, null, null)).toBe("https://app.soleur.ai");
  });
});
