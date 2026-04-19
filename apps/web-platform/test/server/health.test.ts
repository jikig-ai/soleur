import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { buildHealthResponse } from "../../server/health";

vi.mock("../../server/session-metrics", () => ({
  getActiveSessionCount: () => 3,
  getActiveWorkspaceCount: () => 5,
}));

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

  it("includes host CPU utilization percentage", async () => {
    const response = await buildHealthResponse();
    expect(response).toHaveProperty("cpu_pct_1m");
    expect(typeof response.cpu_pct_1m).toBe("number");
    expect(response.cpu_pct_1m).toBeGreaterThanOrEqual(0);
    expect(response.cpu_pct_1m).toBeLessThanOrEqual(100);
  });

  it("includes host memory utilization percentage", async () => {
    const response = await buildHealthResponse();
    expect(response).toHaveProperty("mem_pct");
    expect(typeof response.mem_pct).toBe("number");
    expect(response.mem_pct).toBeGreaterThanOrEqual(0);
    expect(response.mem_pct).toBeLessThanOrEqual(100);
  });

  it("includes 1-minute load average", async () => {
    const response = await buildHealthResponse();
    expect(response).toHaveProperty("load_avg_1m");
    expect(typeof response.load_avg_1m).toBe("number");
    expect(response.load_avg_1m).toBeGreaterThanOrEqual(0);
  });

  it("pins active_sessions from session-metrics", async () => {
    const response = await buildHealthResponse();
    expect(response.active_sessions).toBe(3);
  });

  it("pins active_workspaces from session-metrics", async () => {
    const response = await buildHealthResponse();
    expect(response.active_workspaces).toBe(5);
  });
});
