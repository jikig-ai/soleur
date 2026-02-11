import { describe, test, expect, afterEach } from "bun:test";
import { createHealthServer, type HealthState } from "../src/health";

let server: ReturnType<typeof createHealthServer> | null = null;

afterEach(() => {
  if (server) {
    server.stop(true);
    server = null;
  }
});

function startServer(overrides: Partial<HealthState> = {}) {
  const state: HealthState = {
    cliProcess: {},
    cliState: "ready",
    messageQueue: { length: 0 },
    startTime: Date.now(),
    messagesProcessed: 0,
    ...overrides,
  };
  server = createHealthServer(0, state); // port 0 = OS-assigned
  return `http://127.0.0.1:${server.port}`;
}

describe("health endpoint", () => {
  test("returns 200 when CLI is ready", async () => {
    const base = startServer({ cliState: "ready", cliProcess: {} });
    const res = await fetch(`${base}/health`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("ok");
    expect(body.cli).toBe("ready");
  });

  test("P2-013 regression: returns 503 when CLI not ready", async () => {
    const base = startServer({ cliState: "connecting", cliProcess: null });
    const res = await fetch(`${base}/health`);
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.status).toBe("degraded");
    expect(body.cli).toBe("connecting");
  });

  test("returns 503 when CLI in error state", async () => {
    const base = startServer({ cliState: "error", cliProcess: null });
    const res = await fetch(`${base}/health`);
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.status).toBe("degraded");
  });

  test("returns 503 when cliProcess is null even if state is ready", async () => {
    const base = startServer({ cliState: "ready", cliProcess: null });
    const res = await fetch(`${base}/health`);
    expect(res.status).toBe(503);
  });

  test("includes queue length in response", async () => {
    const base = startServer({ messageQueue: { length: 3 } });
    const res = await fetch(`${base}/health`);
    const body = await res.json();
    expect(body.queue).toBe(3);
  });

  test("includes uptime in response", async () => {
    const base = startServer({ startTime: Date.now() - 60_000 });
    const res = await fetch(`${base}/health`);
    const body = await res.json();
    expect(body.uptime).toBeGreaterThanOrEqual(59);
  });

  test("returns 404 for unknown paths", async () => {
    const base = startServer();
    const res = await fetch(`${base}/unknown`);
    expect(res.status).toBe(404);
  });

  test("returns 404 for non-GET methods", async () => {
    const base = startServer();
    const res = await fetch(`${base}/health`, { method: "POST" });
    expect(res.status).toBe(404);
  });
});
