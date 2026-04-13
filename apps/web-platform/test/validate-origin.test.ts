import { describe, it, expect, vi, afterEach } from "vitest";

describe("validateOrigin", () => {
  afterEach(() => {
    vi.resetModules();
    vi.unstubAllEnvs();
  });

  async function loadModule() {
    return import("@/lib/auth/validate-origin");
  }

  it("allows localhost:3000 in development", async () => {
    vi.stubEnv("NODE_ENV", "development");
    const { validateOrigin } = await loadModule();
    const req = new Request("http://localhost:3000/api/test", {
      headers: { origin: "http://localhost:3000" },
    });
    expect(validateOrigin(req).valid).toBe(true);
  });

  it("rejects unknown port in development without NEXT_PUBLIC_APP_URL", async () => {
    vi.stubEnv("NODE_ENV", "development");
    const { validateOrigin } = await loadModule();
    const req = new Request("http://localhost:3847/api/test", {
      headers: { origin: "http://localhost:3847" },
    });
    expect(validateOrigin(req).valid).toBe(false);
  });

  it("allows custom port via NEXT_PUBLIC_APP_URL in development", async () => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv("NEXT_PUBLIC_APP_URL", "http://localhost:3847");
    const { validateOrigin } = await loadModule();
    const req = new Request("http://localhost:3847/api/test", {
      headers: { origin: "http://localhost:3847" },
    });
    expect(validateOrigin(req).valid).toBe(true);
  });

  it("allows production origin", async () => {
    vi.stubEnv("NODE_ENV", "production");
    const { validateOrigin } = await loadModule();
    const req = new Request("https://app.soleur.ai/api/test", {
      headers: { origin: "https://app.soleur.ai" },
    });
    expect(validateOrigin(req).valid).toBe(true);
  });

  it("rejects unknown origin in production", async () => {
    vi.stubEnv("NODE_ENV", "production");
    const { validateOrigin } = await loadModule();
    const req = new Request("https://evil.com/api/test", {
      headers: { origin: "https://evil.com" },
    });
    expect(validateOrigin(req).valid).toBe(false);
  });

  it("allows requests with no origin or referer (non-browser)", async () => {
    vi.stubEnv("NODE_ENV", "production");
    const { validateOrigin } = await loadModule();
    const req = new Request("https://app.soleur.ai/api/test");
    expect(validateOrigin(req).valid).toBe(true);
    expect(validateOrigin(req).origin).toBeNull();
  });

  it("validates referer when origin is missing", async () => {
    vi.stubEnv("NODE_ENV", "development");
    const { validateOrigin } = await loadModule();
    const req = new Request("http://localhost:3000/api/test", {
      headers: { referer: "http://localhost:3000/dashboard" },
    });
    expect(validateOrigin(req).valid).toBe(true);
  });
});
