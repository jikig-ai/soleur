import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Mocks must be declared before the SUT import. `/proc` is mocked at the fs
// layer with fixed-shape responses so assertions pin exact values rather than
// relying on live CI-runner loadavg/memory (would pass on degenerate 0 output).
vi.mock("fs", async () => {
  const actual = await vi.importActual<typeof import("fs")>("fs");
  return {
    ...actual,
    readFileSync: vi.fn((path: string, encoding?: string) => {
      if (path === "/proc/loadavg") return "2.00 1.50 1.00 1/123 4567";
      if (path === "/proc/meminfo") {
        // total=10_000_000 kB, available=2_500_000 kB → (10_000_000-2_500_000)/10_000_000 = 75%
        return "MemTotal:       10000000 kB\nMemFree:          500000 kB\nMemAvailable:    2500000 kB\n";
      }
      return actual.readFileSync(path, encoding as BufferEncoding | undefined);
    }),
  };
});

vi.mock("os", async () => {
  const actual = await vi.importActual<typeof import("os")>("os");
  return {
    ...actual,
    cpus: () => new Array(4).fill({ model: "test", speed: 0, times: { user: 0, nice: 0, sys: 0, idle: 0, irq: 0 } }),
  };
});

vi.mock("../../server/session-metrics", () => ({
  getActiveSessionCount: () => 3,
  getActiveWorkspaceCount: () => 5,
}));

// Import AFTER mocks so the SUT picks up mocked modules and the module-scoped
// CORE_COUNT constant reads the mocked cpus().length of 4.
const { buildHealthResponse, buildInternalMetricsResponse } = await import(
  "../../server/health"
);

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

  it("does NOT expose capacity or session-count fields on public /health", async () => {
    // /health is reachable unauthenticated via CF tunnel; capacity/session
    // fields were moved to /internal/metrics behind a loopback Host gate.
    const response = await buildHealthResponse();
    expect(response).not.toHaveProperty("cpu_load_pct");
    expect(response).not.toHaveProperty("mem_pct");
    expect(response).not.toHaveProperty("load_avg_1m");
    expect(response).not.toHaveProperty("active_sessions");
    expect(response).not.toHaveProperty("active_workspaces");
  });
});

describe("buildInternalMetricsResponse", () => {
  it("includes all base health fields", async () => {
    const response = await buildInternalMetricsResponse();
    expect(response.status).toBe("ok");
    expect(response).toHaveProperty("version");
    expect(response).toHaveProperty("uptime");
    expect(response).toHaveProperty("memory");
  });

  it("pins cpu_load_pct from mocked loadavg=2.00 and nproc=4 (2/4*100 = 50)", async () => {
    const response = await buildInternalMetricsResponse();
    expect(response.cpu_load_pct).toBe(50);
  });

  it("pins mem_pct from mocked meminfo (total=10M, available=2.5M → 75%)", async () => {
    const response = await buildInternalMetricsResponse();
    expect(response.mem_pct).toBe(75);
  });

  it("pins load_avg_1m from mocked /proc/loadavg", async () => {
    const response = await buildInternalMetricsResponse();
    expect(response.load_avg_1m).toBe(2.0);
  });

  it("pins active_sessions from session-metrics", async () => {
    const response = await buildInternalMetricsResponse();
    expect(response.active_sessions).toBe(3);
  });

  it("pins active_workspaces from session-metrics", async () => {
    const response = await buildInternalMetricsResponse();
    expect(response.active_workspaces).toBe(5);
  });
});
