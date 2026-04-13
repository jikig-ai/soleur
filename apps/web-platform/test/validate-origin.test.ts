import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

describe("validateOrigin", () => {
  const originalEnv = process.env.NODE_ENV;

  afterEach(() => {
    vi.resetModules();
    process.env.NODE_ENV = originalEnv;
    delete process.env.NEXT_PUBLIC_APP_URL;
  });

  async function loadModule() {
    // Force re-import to pick up env changes
    return import("@/lib/auth/validate-origin");
  }

  it("allows localhost:3000 in development", async () => {
    process.env.NODE_ENV = "development";
    const { validateOrigin } = await loadModule();
    const req = new Request("http://localhost:3000/api/test", {
      headers: { origin: "http://localhost:3000" },
    });
    expect(validateOrigin(req).valid).toBe(true);
  });

  it("rejects unknown port in development without NEXT_PUBLIC_APP_URL", async () => {
    process.env.NODE_ENV = "development";
    const { validateOrigin } = await loadModule();
    const req = new Request("http://localhost:3847/api/test", {
      headers: { origin: "http://localhost:3847" },
    });
    expect(validateOrigin(req).valid).toBe(false);
  });

  it("allows custom port via NEXT_PUBLIC_APP_URL in development", async () => {
    process.env.NODE_ENV = "development";
    process.env.NEXT_PUBLIC_APP_URL = "http://localhost:3847";
    const { validateOrigin } = await loadModule();
    const req = new Request("http://localhost:3847/api/test", {
      headers: { origin: "http://localhost:3847" },
    });
    expect(validateOrigin(req).valid).toBe(true);
  });

  it("allows production origin", async () => {
    process.env.NODE_ENV = "production";
    const { validateOrigin } = await loadModule();
    const req = new Request("https://app.soleur.ai/api/test", {
      headers: { origin: "https://app.soleur.ai" },
    });
    expect(validateOrigin(req).valid).toBe(true);
  });

  it("rejects unknown origin in production", async () => {
    process.env.NODE_ENV = "production";
    const { validateOrigin } = await loadModule();
    const req = new Request("https://evil.com/api/test", {
      headers: { origin: "https://evil.com" },
    });
    expect(validateOrigin(req).valid).toBe(false);
  });

  it("allows requests with no origin or referer (non-browser)", async () => {
    process.env.NODE_ENV = "production";
    const { validateOrigin } = await loadModule();
    const req = new Request("https://app.soleur.ai/api/test");
    expect(validateOrigin(req).valid).toBe(true);
    expect(validateOrigin(req).origin).toBeNull();
  });

  it("validates referer when origin is missing", async () => {
    process.env.NODE_ENV = "development";
    const { validateOrigin } = await loadModule();
    const req = new Request("http://localhost:3000/api/test", {
      headers: { referer: "http://localhost:3000/dashboard" },
    });
    expect(validateOrigin(req).valid).toBe(true);
  });
});
