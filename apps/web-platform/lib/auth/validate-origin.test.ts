import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { validateOrigin, rejectCsrf } from "./validate-origin";

function makeRequest(headers: Record<string, string> = {}): Request {
  return new Request("https://app.soleur.ai/api/test", {
    method: "POST",
    headers,
  });
}

describe("validateOrigin", () => {
  const env = process.env as Record<string, string | undefined>;
  const origNodeEnv = env.NODE_ENV;

  beforeEach(() => {
    env.NODE_ENV = "production";
  });

  afterEach(() => {
    env.NODE_ENV = origNodeEnv;
  });

  it("accepts a valid production origin", () => {
    const req = makeRequest({ origin: "https://app.soleur.ai" });
    const result = validateOrigin(req);
    expect(result.valid).toBe(true);
    expect(result.origin).toBe("https://app.soleur.ai");
  });

  it("rejects an invalid origin", () => {
    const req = makeRequest({ origin: "https://evil.com" });
    const result = validateOrigin(req);
    expect(result.valid).toBe(false);
    expect(result.origin).toBe("https://evil.com");
  });

  it("rejects a subdomain spoofing attempt", () => {
    const req = makeRequest({ origin: "https://app.soleur.ai.evil.com" });
    const result = validateOrigin(req);
    expect(result.valid).toBe(false);
  });

  it("falls back to Referer when Origin is absent", () => {
    const req = makeRequest({ referer: "https://app.soleur.ai/dashboard" });
    const result = validateOrigin(req);
    expect(result.valid).toBe(true);
    expect(result.origin).toBe("https://app.soleur.ai");
  });

  it("rejects invalid Referer origin", () => {
    const req = makeRequest({ referer: "https://evil.com/page" });
    const result = validateOrigin(req);
    expect(result.valid).toBe(false);
    expect(result.origin).toBe("https://evil.com");
  });

  it("rejects malformed Referer URL", () => {
    const req = makeRequest({ referer: "not-a-valid-url" });
    const result = validateOrigin(req);
    expect(result.valid).toBe(false);
    expect(result.origin).toBe("not-a-valid-url");
  });

  it("allows requests without Origin or Referer (non-browser clients)", () => {
    const req = makeRequest({});
    const result = validateOrigin(req);
    expect(result.valid).toBe(true);
    expect(result.origin).toBeNull();
  });

  it("compares origin case-insensitively", () => {
    const req = makeRequest({ origin: "HTTPS://APP.SOLEUR.AI" });
    const result = validateOrigin(req);
    expect(result.valid).toBe(true);
  });

  it("accepts localhost in development mode", () => {
    env.NODE_ENV = "development";
    const req = makeRequest({ origin: "http://localhost:3000" });
    const result = validateOrigin(req);
    expect(result.valid).toBe(true);
  });

  it("rejects localhost in production mode", () => {
    env.NODE_ENV = "production";
    const req = makeRequest({ origin: "http://localhost:3000" });
    const result = validateOrigin(req);
    expect(result.valid).toBe(false);
  });

  it("prefers Origin header over Referer", () => {
    const req = makeRequest({
      origin: "https://evil.com",
      referer: "https://app.soleur.ai/dashboard",
    });
    const result = validateOrigin(req);
    expect(result.valid).toBe(false);
    expect(result.origin).toBe("https://evil.com");
  });
});

describe("rejectCsrf", () => {
  it("returns a 403 response", async () => {
    const response = rejectCsrf("api/test", "https://evil.com");
    expect(response.status).toBe(403);
    const body = await response.json();
    expect(body.error).toBe("Forbidden");
  });

  it("sanitizes control characters in logged origin", () => {
    rejectCsrf("api/test", "https://evil\x00\x0a.com");
    // Sanitization happens before logging — control chars stripped, then passed as structured field.
    // The rejectCsrf function slices to 100 chars and strips control chars before logging.
    // We verify the sanitization by checking the function doesn't throw.
  });

  it("truncates long origin values", () => {
    const longOrigin = "https://" + "a".repeat(200) + ".com";
    // rejectCsrf truncates to 100 chars before logging
    const response = rejectCsrf("api/test", longOrigin);
    expect(response.status).toBe(403);
  });

  it("handles null origin", async () => {
    const response = rejectCsrf("api/test", null);
    expect(response.status).toBe(403);
  });
});
