import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { reportSilentFallback } from "@/lib/client-observability";
import {
  PENDING_ENTRY_DELAY_MS,
  PENDING_MIN_VISIBLE_MS,
  NAV_STALL_MS,
  getNavLastLocation,
  getNavPendingSnapshot,
  isSameDocTarget,
  noteNavLocation,
  startNavPending,
  stopNavPending,
  subscribeNavPending,
} from "@/lib/nav-pending-store";

// feat-ui-action-feedback — nav-pending store contract (implementation-brief
// §1): entry delay, min-visible hold, stall termination, start() idempotency
// through the hold, isSameDocTarget hash/relative/UrlObject handling.

// happy-dom's test origin is http://localhost:3000 — pushState must stay
// same-origin, so locations are set with relative URLs throughout.
function setLocation(url: string) {
  window.history.pushState({}, "", url);
  noteNavLocation();
}

function settle() {
  stopNavPending();
  vi.advanceTimersByTime(PENDING_MIN_VISIBLE_MS + 1);
  stopNavPending();
  vi.advanceTimersByTime(NAV_STALL_MS + 1);
  stopNavPending();
}

describe("nav-pending-store", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    setLocation("/dashboard?a=1");
  });

  afterEach(() => {
    settle();
    vi.useRealTimers();
    vi.clearAllMocks();
  });

  it("opens pending at start() but stays invisible through the entry delay (AC2)", () => {
    startNavPending("link");
    expect(getNavPendingSnapshot()).toMatchObject({
      pending: true,
      visible: false,
      trigger: "link",
    });
    vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS - 1);
    expect(getNavPendingSnapshot().visible).toBe(false);
    vi.advanceTimersByTime(1);
    expect(getNavPendingSnapshot().visible).toBe(true);
  });

  it("a commit inside the entry delay produces no visible flash", () => {
    startNavPending("router");
    vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS - 50);
    stopNavPending();
    vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS + 1000);
    const snap = getNavPendingSnapshot();
    expect(snap.visible).toBe(false);
    expect(snap.pending).toBe(false);
  });

  it("holds the bar ~400ms after commit once visible (min-visible, ux #8)", () => {
    startNavPending("link");
    vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS);
    stopNavPending();
    vi.advanceTimersByTime(PENDING_MIN_VISIBLE_MS - 1);
    expect(getNavPendingSnapshot().visible).toBe(true);
    expect(getNavPendingSnapshot().pending).toBe(true);
    vi.advanceTimersByTime(1);
    expect(getNavPendingSnapshot()).toEqual(
      expect.objectContaining({ pending: false, visible: false, trigger: null }),
    );
  });

  it("cancels a visible bar immediately if it was shown long past min-visible", () => {
    startNavPending("link");
    vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS + PENDING_MIN_VISIBLE_MS + 50);
    stopNavPending();
    // holdFor clamps to 0 — the hide timer fires on the next tick.
    vi.advanceTimersByTime(0);
    expect(getNavPendingSnapshot().pending).toBe(false);
  });

  it("start() is idempotent while pending AND through the min-visible hold", () => {
    const listener = vi.fn();
    const unsub = subscribeNavPending(listener);
    startNavPending("link");
    startNavPending("router");
    startNavPending("popstate");
    expect(getNavPendingSnapshot().trigger).toBe("link");
    vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS);
    startNavPending("router");
    expect(getNavPendingSnapshot().trigger).toBe("link");
    stopNavPending();
    startNavPending("router");
    // inside the hold — still a no-op until the bar fully hides
    expect(getNavPendingSnapshot().trigger).toBe("link");
    vi.advanceTimersByTime(PENDING_MIN_VISIBLE_MS);
    expect(getNavPendingSnapshot().pending).toBe(false);
    startNavPending("router");
    expect(getNavPendingSnapshot().trigger).toBe("router");
    unsub();
  });

  it("stop() before the entry delay ends the episode with no double-emit", () => {
    const listener = vi.fn();
    subscribeNavPending(listener);
    startNavPending("link");
    listener.mockClear();
    stopNavPending();
    expect(listener).toHaveBeenCalledTimes(1);
    stopNavPending();
    stopNavPending();
    expect(listener).toHaveBeenCalledTimes(1);
  });

  it("stop() inside the hold is a no-op (already scheduled)", () => {
    startNavPending("link");
    vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS);
    stopNavPending();
    const listener = vi.fn();
    subscribeNavPending(listener);
    stopNavPending();
    expect(listener).not.toHaveBeenCalled();
  });

  it("force-stops and reports to Sentry after the ~30s stall timeout (spec-flow C1)", () => {
    startNavPending("popstate");
    vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS);
    vi.advanceTimersByTime(NAV_STALL_MS - PENDING_ENTRY_DELAY_MS);
    const snap = getNavPendingSnapshot();
    expect(snap.pending).toBe(false);
    expect(snap.visible).toBe(false);
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(vi.mocked(reportSilentFallback).mock.calls[0][1]).toMatchObject({
      feature: "nav-pending",
      op: "stall-timeout",
      extra: expect.objectContaining({ trigger: "popstate" }),
    });
  });

  it("a normal commit before the stall disarms the timeout (no report)", () => {
    startNavPending("link");
    vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS);
    stopNavPending();
    vi.advanceTimersByTime(NAV_STALL_MS + 1000);
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("notifies subscribers on every phase transition", () => {
    const listener = vi.fn();
    const unsub = subscribeNavPending(listener);
    startNavPending("link");
    expect(listener).toHaveBeenCalledTimes(1); // idle -> pending
    vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS);
    expect(listener).toHaveBeenCalledTimes(2); // pending -> visible
    stopNavPending();
    expect(listener).toHaveBeenCalledTimes(3); // visible -> holding
    vi.advanceTimersByTime(PENDING_MIN_VISIBLE_MS);
    expect(listener).toHaveBeenCalledTimes(4); // holding -> idle
    unsub();
    startNavPending("link");
    expect(listener).toHaveBeenCalledTimes(4);
  });
});

describe("isSameDocTarget", () => {
  beforeEach(() => {
    setLocation("/dashboard?a=1");
  });

  it("hash-only hrefs resolve to the current doc (skip-link class)", () => {
    expect(isSameDocTarget("/dashboard?a=1#frag")).toBe(true);
    expect(isSameDocTarget("#main-content")).toBe(true);
  });

  it("same pathname+search is same-doc; different search/pathname is not", () => {
    expect(isSameDocTarget("/dashboard?a=1")).toBe(true);
    expect(isSameDocTarget("/dashboard?a=2")).toBe(false);
    expect(isSameDocTarget("/settings?a=1")).toBe(false);
    expect(isSameDocTarget("/dashboard")).toBe(false);
  });

  it("relative hrefs resolve against the live location", () => {
    expect(isSameDocTarget("?a=1")).toBe(true);
    expect(isSameDocTarget("?a=9")).toBe(false);
    expect(isSameDocTarget("dashboard?a=1")).toBe(true);
  });

  it("absolute same-origin URLs compare on pathname+search", () => {
    expect(isSameDocTarget("http://localhost:3000/dashboard?a=1")).toBe(true);
    expect(isSameDocTarget("http://localhost:3000/dashboard?a=1#x")).toBe(true);
  });

  it("cross-origin absolute URLs differ on pathname+search alone", () => {
    // host is not compared — pathname+search only, per the store contract.
    expect(isSameDocTarget("https://other.example/dashboard?a=1")).toBe(true);
    expect(isSameDocTarget("https://other.example/x")).toBe(false);
  });

  it("UrlObject-like inputs normalize pathname/search/query", () => {
    expect(isSameDocTarget({ pathname: "/dashboard", search: "?a=1" })).toBe(true);
    expect(isSameDocTarget({ pathname: "/dashboard", query: { a: "1" } })).toBe(true);
    expect(isSameDocTarget({ pathname: "/dashboard", query: { a: "2" } })).toBe(false);
    expect(isSameDocTarget({ href: "/dashboard?a=1" })).toBe(true);
    expect(isSameDocTarget({ pathname: "/dashboard", query: "a=1" })).toBe(true);
  });

  it("garbage input never throws", () => {
    // An empty UrlObject resolves "" against the current URL — same doc.
    expect(isSameDocTarget({})).toBe(true);
    expect(isSameDocTarget(":://bad")).toBe(false);
    expect(isSameDocTarget("http://[::1")).toBe(false);
  });
});

describe("last-location tracking", () => {
  it("noteNavLocation keeps pathname+search current for the popstate gate", () => {
    setLocation("/a?x=1");
    expect(getNavLastLocation()).toBe("/a?x=1");
    window.history.pushState({}, "", "/b");
    noteNavLocation();
    expect(getNavLastLocation()).toBe("/b");
    // hash is excluded from the tracked key
    window.history.pushState({}, "", "/b#frag");
    noteNavLocation();
    expect(getNavLastLocation()).toBe("/b");
  });

  it("noteNavLocation reports whether the location moved since the last note", () => {
    setLocation("/a?x=1");
    window.history.pushState({}, "", "/b");
    expect(noteNavLocation()).toBe(true);
    expect(noteNavLocation()).toBe(false);
    // hash-only change is not a move
    window.history.pushState({}, "", "/b#frag");
    expect(noteNavLocation()).toBe(false);
  });
});
