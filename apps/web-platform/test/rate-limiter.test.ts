import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { readFileSync } from "fs";
import { join } from "path";
import {
  SlidingWindowCounter,
  PendingConnectionTracker,
  extractClientIp,
  startPruneInterval,
} from "../server/rate-limiter";
import type { IncomingMessage } from "http";
import type { Socket } from "net";

// ---------------------------------------------------------------------------
// SlidingWindowCounter
// ---------------------------------------------------------------------------

describe("SlidingWindowCounter", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("allows requests under the limit", () => {
    const counter = new SlidingWindowCounter({
      windowMs: 60_000,
      maxRequests: 3,
    });

    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(true);
  });

  test("rejects requests over the limit", () => {
    const counter = new SlidingWindowCounter({
      windowMs: 60_000,
      maxRequests: 3,
    });

    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(false);
  });

  test("allows requests after window expires", () => {
    const counter = new SlidingWindowCounter({
      windowMs: 60_000,
      maxRequests: 2,
    });

    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(false);

    // Advance past window
    vi.advanceTimersByTime(61_000);

    expect(counter.isAllowed("ip1")).toBe(true);
  });

  test("tracks keys independently", () => {
    const counter = new SlidingWindowCounter({
      windowMs: 60_000,
      maxRequests: 1,
    });

    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(false);
    // Different key is unaffected
    expect(counter.isAllowed("ip2")).toBe(true);
  });

  test("prune removes expired entries", () => {
    const counter = new SlidingWindowCounter({
      windowMs: 60_000,
      maxRequests: 5,
    });

    counter.isAllowed("ip1");
    counter.isAllowed("ip2");
    expect(counter.size).toBe(2);

    vi.advanceTimersByTime(61_000);
    counter.prune();

    expect(counter.size).toBe(0);
  });

  test("lazy eviction on isAllowed filters stale entries", () => {
    const counter = new SlidingWindowCounter({
      windowMs: 60_000,
      maxRequests: 2,
    });

    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(false);

    // Advance time so first two entries expire
    vi.advanceTimersByTime(61_000);

    // Should be allowed again (stale entries evicted)
    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(true);
    expect(counter.isAllowed("ip1")).toBe(false);
  });

  test("window tracks attempts, not active connections", () => {
    const counter = new SlidingWindowCounter({
      windowMs: 60_000,
      maxRequests: 20,
    });

    // Use up 19 of 20 allowed
    for (let i = 0; i < 19; i++) {
      expect(counter.isAllowed("ip1")).toBe(true);
    }

    // 20th is still allowed
    expect(counter.isAllowed("ip1")).toBe(true);
    // 21st is rejected (even though connections may have closed)
    expect(counter.isAllowed("ip1")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// PendingConnectionTracker
// ---------------------------------------------------------------------------

describe("PendingConnectionTracker", () => {
  test("allows connections under the limit", () => {
    const tracker = new PendingConnectionTracker(3);

    expect(tracker.add("ip1")).toBe(true);
    expect(tracker.add("ip1")).toBe(true);
    expect(tracker.add("ip1")).toBe(true);
  });

  test("rejects connections at the limit", () => {
    const tracker = new PendingConnectionTracker(2);

    expect(tracker.add("ip1")).toBe(true);
    expect(tracker.add("ip1")).toBe(true);
    expect(tracker.add("ip1")).toBe(false);
  });

  test("decrements on remove", () => {
    const tracker = new PendingConnectionTracker(2);

    tracker.add("ip1");
    tracker.add("ip1");
    expect(tracker.add("ip1")).toBe(false);

    tracker.remove("ip1");
    expect(tracker.add("ip1")).toBe(true);
  });

  test("remove cleans up when count reaches zero", () => {
    const tracker = new PendingConnectionTracker(5);

    tracker.add("ip1");
    expect(tracker.get("ip1")).toBe(1);

    tracker.remove("ip1");
    expect(tracker.get("ip1")).toBe(0);
  });

  test("remove is safe to call with no pending connections", () => {
    const tracker = new PendingConnectionTracker(5);

    // Should not throw
    tracker.remove("ip1");
    expect(tracker.get("ip1")).toBe(0);
  });

  test("tracks IPs independently", () => {
    const tracker = new PendingConnectionTracker(1);

    expect(tracker.add("ip1")).toBe(true);
    expect(tracker.add("ip1")).toBe(false);
    // Different IP is independent
    expect(tracker.add("ip2")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// IP extraction
// ---------------------------------------------------------------------------

function mockRequest(headers: Record<string, string | undefined>, remoteAddress?: string): IncomingMessage {
  return {
    headers,
    socket: { remoteAddress: remoteAddress ?? "127.0.0.1" } as Socket,
  } as IncomingMessage;
}

describe("extractClientIp", () => {
  test("prefers cf-connecting-ip over remoteAddress", () => {
    const req = mockRequest({
      "cf-connecting-ip": "1.2.3.4",
    }, "10.0.0.1");
    expect(extractClientIp(req)).toBe("1.2.3.4");
  });

  test("ignores x-forwarded-for (not trusted — spoofable without Cloudflare)", () => {
    const req = mockRequest({
      "x-forwarded-for": "1.2.3.4, 5.6.7.8",
    }, "10.0.0.1");
    // Should use remoteAddress, not XFF
    expect(extractClientIp(req)).toBe("10.0.0.1");
  });

  test("falls back to remoteAddress when cf-connecting-ip absent", () => {
    const req = mockRequest({}, "10.0.0.1");
    expect(extractClientIp(req)).toBe("10.0.0.1");
  });

  test("returns 'unknown' when no IP source available", () => {
    const req = {
      headers: {},
      socket: { remoteAddress: undefined } as unknown as Socket,
    } as IncomingMessage;
    expect(extractClientIp(req)).toBe("unknown");
  });

  test("handles empty cf-connecting-ip by falling through to remoteAddress", () => {
    const req = mockRequest({
      "cf-connecting-ip": "",
    }, "10.0.0.1");
    expect(extractClientIp(req)).toBe("10.0.0.1");
  });

  test("cf-connecting-ip takes priority even when x-forwarded-for is present", () => {
    const req = mockRequest({
      "cf-connecting-ip": "1.2.3.4",
      "x-forwarded-for": "5.6.7.8",
    });
    expect(extractClientIp(req)).toBe("1.2.3.4");
  });
});

// ---------------------------------------------------------------------------
// startPruneInterval — shared helper for periodic prune wiring
// ---------------------------------------------------------------------------

describe("startPruneInterval", () => {
  test("returns a Node Timeout handle that exposes .unref()", () => {
    const counter = new SlidingWindowCounter({
      windowMs: 60_000,
      maxRequests: 1,
    });
    const handle = startPruneInterval(counter);
    try {
      expect(typeof handle.unref).toBe("function");
    } finally {
      clearInterval(handle);
    }
  });

  test("invokes counter.prune() on each tick at the default 60s cadence", async () => {
    vi.useFakeTimers();
    try {
      const counter = new SlidingWindowCounter({
        windowMs: 60_000,
        maxRequests: 1,
      });
      const spy = vi.spyOn(counter, "prune");
      const handle = startPruneInterval(counter);
      try {
        await vi.advanceTimersByTimeAsync(60_000);
        expect(spy).toHaveBeenCalledTimes(1);
        await vi.advanceTimersByTimeAsync(60_000);
        expect(spy).toHaveBeenCalledTimes(2);
      } finally {
        clearInterval(handle);
      }
    } finally {
      vi.useRealTimers();
    }
  });

  test("accepts a custom interval", async () => {
    vi.useFakeTimers();
    try {
      const counter = new SlidingWindowCounter({
        windowMs: 60_000,
        maxRequests: 1,
      });
      const spy = vi.spyOn(counter, "prune");
      const handle = startPruneInterval(counter, 5_000);
      try {
        await vi.advanceTimersByTimeAsync(4_999);
        expect(spy).toHaveBeenCalledTimes(0);
        await vi.advanceTimersByTimeAsync(1);
        expect(spy).toHaveBeenCalledTimes(1);
        await vi.advanceTimersByTimeAsync(5_000);
        expect(spy).toHaveBeenCalledTimes(2);
      } finally {
        clearInterval(handle);
      }
    } finally {
      vi.useRealTimers();
    }
  });

  test("helper body installs setInterval + prune + unref (Layer-2 invariant)", () => {
    // Negative-space guard per learning 2026-04-15-negative-space-tests-must-
    // follow-extracted-logic: a silent regression that removes .unref() from
    // the helper must fail a test.
    const source = readFileSync(
      join(__dirname, "..", "server", "rate-limiter.ts"),
      "utf-8",
    );
    expect(source).toMatch(
      /export function startPruneInterval[\s\S]*setInterval\([\s\S]*\.prune\(\)[\s\S]*\.unref\(\)/,
    );
  });
});
