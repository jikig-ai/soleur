import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { validateOrigin, rejectCsrf } from "./validate-origin";

function makeRequest(headers: Record<string, string> = {}): Request {
  return new Request("https://app.soleur.ai/api/test", {
    method: "POST",
    headers,
  });
}

describe("validateOrigin", () => {
  const origNodeEnv = process.env.NODE_ENV;

  beforeEach(() => {
    process.env.NODE_ENV = "production";
  });

  afterEach(() => {
    process.env.NODE_ENV = origNodeEnv;
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

  it("rejects when neither Origin nor Referer is present (fail-closed)", () => {
    const req = makeRequest({});
    const result = validateOrigin(req);
    expect(result.valid).toBe(false);
    expect(result.origin).toBeNull();
  });

  it("compares origin case-insensitively", () => {
    const req = makeRequest({ origin: "HTTPS://APP.SOLEUR.AI" });
    const result = validateOrigin(req);
    expect(result.valid).toBe(true);
  });

  it("accepts localhost in development mode", () => {
    process.env.NODE_ENV = "development";
    const req = makeRequest({ origin: "http://localhost:3000" });
    const result = validateOrigin(req);
    expect(result.valid).toBe(true);
  });

  it("rejects localhost in production mode", () => {
    process.env.NODE_ENV = "production";
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
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    rejectCsrf("api/test", "https://evil\x00\x0a.com");
    expect(warnSpy).toHaveBeenCalledWith(
      "[api/test] CSRF: rejected origin https://evil.com",
    );
    warnSpy.mockRestore();
  });

  it("truncates long origin values in logs", () => {
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    const longOrigin = "https://" + "a".repeat(200) + ".com";
    rejectCsrf("api/test", longOrigin);
    const loggedMessage = warnSpy.mock.calls[0][0] as string;
    const originPart = loggedMessage.split("rejected origin ")[1];
    expect(originPart.length).toBeLessThanOrEqual(100);
    warnSpy.mockRestore();
  });

  it("handles null origin", async () => {
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    const response = rejectCsrf("api/test", null);
    expect(response.status).toBe(403);
    expect(warnSpy).toHaveBeenCalledWith(
      "[api/test] CSRF: rejected origin none",
    );
    warnSpy.mockRestore();
  });
});
