import { beforeEach, describe, expect, it, vi } from "vitest";

// #12288 — bounded deny reporting for the relay. At most DENY_MAX_EVENTS Sentry events per
// reason per window, an exact counter, one summary event for a window that suppressed
// anything, and one closed-grammar `relay_hello_window` pino line per window (the only
// off-host positive signal for a signed round trip: the serve-gate probe sends no hello).

const { mockWarn, mockInfo, mockError } = vi.hoisted(() => ({
  mockWarn: vi.fn(),
  mockInfo: vi.fn(),
  mockError: vi.fn(),
}));

vi.mock("@/server/logger", () => {
  const child = () => ({ info: mockInfo, warn: mockWarn, error: mockError, debug: vi.fn() });
  return { default: child(), createChildLogger: child };
});
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));

import {
  DENY_MAX_EVENTS,
  DENY_WINDOW_MS,
  createDenyReporter,
  type DenyReason,
} from "@/server/proxy-deny-report";

type Timer = { fn: () => void; ms: number };

function harness() {
  let clock = 1_000_000;
  const timers: Timer[] = [];
  const reports: Array<{ err: Error; opts: { feature: string; op: string; extra?: Record<string, unknown> } }> = [];
  const reporter = createDenyReporter({
    now: () => clock,
    setTimer: (fn, ms) => {
      timers.push({ fn, ms });
    },
    report: (err, opts) => {
      reports.push({ err: err as Error, opts: opts as never });
    },
  });
  return {
    reporter,
    reports,
    timers,
    advance: (ms: number) => {
      clock += ms;
    },
    fireTimers: () => {
      const due = timers.splice(0);
      for (const t of due) t.fn();
    },
  };
}

const windowLines = () => mockWarn.mock.calls.map((c) => String(c[1])).filter((l) => l.startsWith("relay_hello_window"));

beforeEach(() => {
  vi.clearAllMocks();
});

describe("constants", () => {
  it("fixes the cap at 5 events per 60 s", () => {
    expect(DENY_MAX_EVENTS).toBe(5);
    expect(DENY_WINDOW_MS).toBe(60_000);
  });
});

describe("per-reason cap and exact counter", () => {
  it("reports the first 5 denies of a reason and suppresses the rest; counter is exact", () => {
    const h = harness();
    for (let i = 0; i < 200; i++) h.reporter.record("peer", { peer: "10.0.1.99" });
    const peerReports = h.reports.filter((r) => r.opts.op === "createProxyServer.peer-deny");
    expect(peerReports).toHaveLength(5);
    expect(h.reporter.counters("peer")).toEqual({ denied: 200, reported: 5, suppressed: 195 });
  });

  it("a burst of exactly 5 emits no summary even after the window ends", () => {
    const h = harness();
    for (let i = 0; i < 5; i++) h.reporter.record("mac");
    h.advance(DENY_WINDOW_MS + 1);
    h.fireTimers();
    expect(h.reports).toHaveLength(5);
    expect(h.reports.some((r) => r.opts.op.endsWith("-summary"))).toBe(false);
  });

  it("a burst of 6 yields 5 reports plus exactly one summary carrying {reason, denied, suppressed}", () => {
    const h = harness();
    for (let i = 0; i < 6; i++) h.reporter.record("shape");
    expect(h.reports).toHaveLength(5);
    h.advance(DENY_WINDOW_MS + 1);
    h.fireTimers();
    const summaries = h.reports.filter((r) => r.opts.op.endsWith("-summary"));
    expect(summaries).toHaveLength(1);
    expect(summaries[0].opts.extra).toEqual({ reason: "shape", denied: 6, suppressed: 1 });
  });

  it("reasons have independent buckets: a second reason is not starved by the first", () => {
    const h = harness();
    for (let i = 0; i < 50; i++) h.reporter.record("peer", { peer: "10.0.1.99" });
    for (let i = 0; i < 3; i++) h.reporter.record("skew");
    expect(h.reports.filter((r) => r.opts.extra?.reason === "skew")).toHaveLength(3);
  });

  it("the window rolls: after 60 s the next deny reports again", () => {
    const h = harness();
    for (let i = 0; i < 20; i++) h.reporter.record("replay");
    expect(h.reports).toHaveLength(5);
    h.advance(DENY_WINDOW_MS + 1);
    h.reporter.record("replay");
    // 5 + summary for the rolled window + 1 fresh report
    expect(h.reports.filter((r) => r.opts.op.endsWith("-summary"))).toHaveLength(1);
    expect(h.reports.filter((r) => !r.opts.op.endsWith("-summary"))).toHaveLength(6);
  });
});

describe("report shape", () => {
  const ops: Array<[DenyReason, string]> = [
    ["peer", "createProxyServer.peer-deny"],
    ["membership", "createProxyServer.ap2-deny"],
    ["mac", "createProxyServer.hello-deny"],
    ["size", "createProxyServer.hello-deny"],
    ["shape", "createProxyServer.hello-deny"],
    ["skew", "createProxyServer.hello-deny"],
    ["replay", "createProxyServer.hello-deny"],
    ["full", "createProxyServer.hello-deny"],
  ];
  it.each(ops)("reason %s reports op %s with the reason enum in extra", (reason, op) => {
    const h = harness();
    h.reporter.record(reason);
    expect(h.reports[0].opts.op).toBe(op);
    expect(h.reports[0].opts.feature).toBe("control_plane_route");
    expect(h.reports[0].opts.extra?.reason).toBe(reason);
  });

  it("extras carry only the enum, counts and the supplied peer/ids; nothing else leaks in", () => {
    const h = harness();
    h.reporter.record("peer", { peer: "10.0.1.99" });
    h.reporter.record("membership", { userId: "u", workspaceId: "w" });
    expect(h.reports[0].opts.extra).toEqual({ reason: "peer", peer: "10.0.1.99" });
    expect(h.reports[1].opts.extra).toEqual({ reason: "membership", userId: "u", workspaceId: "w" });
  });
});

describe("relay_hello_window line", () => {
  it("emits one closed-grammar warn line per window with counts only", () => {
    const h = harness();
    h.reporter.recordAccepted();
    h.reporter.recordAccepted();
    for (let i = 0; i < 8; i++) h.reporter.record("mac");
    expect(windowLines()).toEqual([]);
    h.advance(DENY_WINDOW_MS + 1);
    h.fireTimers();
    expect(windowLines()).toEqual(["relay_hello_window accepted=2 denied=8 suppressed=3"]);
    expect(windowLines()[0]).toMatch(/^relay_hello_window accepted=\d+ denied=\d+ suppressed=\d+$/);
  });

  it("emits nothing for a window with no accepted and no denied hellos", () => {
    const h = harness();
    h.advance(DENY_WINDOW_MS + 1);
    h.fireTimers();
    expect(windowLines()).toEqual([]);
  });

  it("the line never matches the relay_probe / relay_peer_probe alert filters", () => {
    const h = harness();
    h.reporter.recordAccepted();
    h.advance(DENY_WINDOW_MS + 1);
    h.fireTimers();
    const line = windowLines()[0];
    expect(line).not.toContain("relay_probe proxy_state=");
    expect(line).not.toContain("relay_peer_probe peer=");
  });
});

describe("module singleton", () => {
  it("exports a default reporter and a reset for tests", async () => {
    const mod = await import("@/server/proxy-deny-report");
    expect(typeof mod.denyReporter.record).toBe("function");
    mod.denyReporter.record("peer", { peer: "10.0.1.99" });
    expect(mod.denyReporter.counters("peer").denied).toBe(1);
    mod.__resetDenyReporterForTests();
    expect(mod.denyReporter.counters("peer").denied).toBe(0);
  });
});
