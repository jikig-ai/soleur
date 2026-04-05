import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { buildHealthResponse } from "../../server/health";

describe("buildHealthResponse", () => {
  const originalEnv = process.env;

  beforeEach(() => {
    process.env = { ...originalEnv };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it("reports sentry as configured when SENTRY_DSN is set", async () => {
    process.env.SENTRY_DSN = "https://key@sentry.io/123";
    const response = await buildHealthResponse();
    expect(response.sentry).toBe("configured");
  });

  it("reports sentry as not-configured when SENTRY_DSN is absent", async () => {
    delete process.env.SENTRY_DSN;
    const response = await buildHealthResponse();
    expect(response.sentry).toBe("not-configured");
  });

  it("includes standard health fields", async () => {
    const response = await buildHealthResponse();
    expect(response.status).toBe("ok");
    expect(response).toHaveProperty("version");
    expect(response).toHaveProperty("uptime");
    expect(response).toHaveProperty("memory");
  });

  it("reports supabase status", async () => {
    const response = await buildHealthResponse();
    expect(["connected", "error"]).toContain(response.supabase);
  });
});
