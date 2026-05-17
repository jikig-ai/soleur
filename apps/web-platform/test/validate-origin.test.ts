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

  // PR-A (#2939): NEXT_PUBLIC_DEV_EXTRA_ORIGINS lets Playwright run multiple
  // dev-mode origins simultaneously (ports 3099 + 3100).
  it("accepts every origin in NEXT_PUBLIC_DEV_EXTRA_ORIGINS comma list in development", async () => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv(
      "NEXT_PUBLIC_DEV_EXTRA_ORIGINS",
      "http://localhost:3099,http://localhost:3100",
    );
    const { validateOrigin } = await loadModule();
    const req3099 = new Request("http://localhost:3099/api/test", {
      headers: { origin: "http://localhost:3099" },
    });
    const req3100 = new Request("http://localhost:3100/api/test", {
      headers: { origin: "http://localhost:3100" },
    });
    expect(validateOrigin(req3099).valid).toBe(true);
    expect(validateOrigin(req3100).valid).toBe(true);
  });

  it("regression guard: empty NEXT_PUBLIC_DEV_EXTRA_ORIGINS leaves legacy dev origins intact", async () => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv("NEXT_PUBLIC_DEV_EXTRA_ORIGINS", "");
    const { validateOrigin } = await loadModule();
    const okLocal = new Request("http://localhost:3000/api/test", {
      headers: { origin: "http://localhost:3000" },
    });
    const okProd = new Request("https://app.soleur.ai/api/test", {
      headers: { origin: "https://app.soleur.ai" },
    });
    const rejected = new Request("http://localhost:3099/api/test", {
      headers: { origin: "http://localhost:3099" },
    });
    expect(validateOrigin(okLocal).valid).toBe(true);
    expect(validateOrigin(okProd).valid).toBe(true);
    expect(validateOrigin(rejected).valid).toBe(false);
  });

  it("ignores NEXT_PUBLIC_DEV_EXTRA_ORIGINS in production", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("NEXT_PUBLIC_DEV_EXTRA_ORIGINS", "http://localhost:3099");
    const { validateOrigin } = await loadModule();
    const req = new Request("http://localhost:3099/api/test", {
      headers: { origin: "http://localhost:3099" },
    });
    expect(validateOrigin(req).valid).toBe(false);
  });
});
