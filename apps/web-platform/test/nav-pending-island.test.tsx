import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { act, render, screen } from "@testing-library/react";
import React from "react";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
}));

const nav = vi.hoisted(() => ({
  pathname: "/dashboard",
  search: "?a=1",
}));

vi.mock("next/navigation", () => ({
  usePathname: () => nav.pathname,
  useSearchParams: () => new URLSearchParams(nav.search),
}));

import {
  PENDING_ENTRY_DELAY_MS,
  PENDING_MIN_VISIBLE_MS,
  getNavPendingSnapshot,
  noteNavLocation,
  startNavPending,
  stopNavPending,
} from "@/lib/nav-pending-store";
import { NavPendingIsland } from "@/components/nav/nav-pending-island";

// feat-ui-action-feedback — the island is the ONE mount of the route-pending
// bar (brief §1/§2): useSyncExternalStore on the module store, a completion
// watcher on usePathname+useSearchParams, a popstate listener gated on
// pathname+search deltas, and a persistent sr-only live region that announces
// "Loading" only while the bar is visible (§6, ux #5).

function setLocation(url: string) {
  window.history.pushState({}, "", url);
  noteNavLocation();
}

function settle() {
  stopNavPending();
  vi.advanceTimersByTime(PENDING_MIN_VISIBLE_MS + 1);
  stopNavPending();
  vi.advanceTimersByTime(60_000);
  stopNavPending();
}

describe("NavPendingIsland", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    nav.pathname = "/dashboard";
    nav.search = "?a=1";
    setLocation("/dashboard?a=1");
  });

  afterEach(() => {
    settle();
    vi.useRealTimers();
  });

  it("renders the 2px bar only after the entry delay, with a live-region announcement", () => {
    render(<NavPendingIsland />);
    act(() => startNavPending("link"));
    expect(screen.queryByTestId("nav-pending-bar")).toBeNull();
    act(() => vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS - 1));
    expect(screen.queryByTestId("nav-pending-bar")).toBeNull();
    // The region mounts with the bar — an always-on empty status would
    // collide with other pages' global role="status" assertions.
    expect(screen.queryByRole("status")).toBeNull();
    act(() => vi.advanceTimersByTime(1));
    const bar = screen.getByTestId("nav-pending-bar");
    expect(bar).toHaveAttribute("aria-hidden", "true");
    expect(bar.className).toContain("fixed");
    expect(bar.className).toContain("z-50");
    expect(screen.getByRole("status")).toHaveTextContent("Loading");
  });

  it("clears the bar on route commit (pathname delta) honoring min-visible", () => {
    const { rerender } = render(<NavPendingIsland />);
    act(() => startNavPending("link"));
    act(() => vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS));
    expect(screen.getByTestId("nav-pending-bar")).toBeTruthy();

    nav.pathname = "/inbox";
    nav.search = "";
    rerender(<NavPendingIsland />);
    act(() => vi.advanceTimersByTime(0));
    // min-visible hold keeps the bar up past the commit
    expect(screen.getByTestId("nav-pending-bar")).toBeTruthy();
    act(() => vi.advanceTimersByTime(PENDING_MIN_VISIBLE_MS));
    expect(screen.queryByTestId("nav-pending-bar")).toBeNull();
    expect(getNavPendingSnapshot().pending).toBe(false);
  });

  it("clears on a same-path searchParams commit (workstream?issue= class)", () => {
    const { rerender } = render(<NavPendingIsland />);
    act(() => startNavPending("link"));
    act(() => vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS));

    nav.search = "?issue=42";
    rerender(<NavPendingIsland />);
    act(() => vi.advanceTimersByTime(0));
    // episode committed (holding) even though the bar is still on screen
    act(() => vi.advanceTimersByTime(PENDING_MIN_VISIBLE_MS));
    expect(getNavPendingSnapshot().pending).toBe(false);
    expect(screen.queryByTestId("nav-pending-bar")).toBeNull();
  });

  it("popstate to a different pathname+search starts a popstate episode", () => {
    render(<NavPendingIsland />);
    // Island's commit watcher seeded lastLocation to /dashboard?a=1 at mount.
    act(() => {
      window.history.pushState({}, "", "/inbox?x=9");
      window.dispatchEvent(new PopStateEvent("popstate"));
    });
    expect(getNavPendingSnapshot()).toMatchObject({
      pending: true,
      trigger: "popstate",
    });
    act(() => vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS));
    expect(screen.getByTestId("nav-pending-bar")).toBeTruthy();
  });

  it("hash-only popstate (skip-link class) never fires the bar (kieran #4)", () => {
    render(<NavPendingIsland />);
    act(() => {
      window.history.pushState({}, "", "/dashboard?a=1#main-content");
      window.dispatchEvent(new PopStateEvent("popstate"));
    });
    expect(getNavPendingSnapshot().pending).toBe(false);
    act(() => vi.advanceTimersByTime(PENDING_ENTRY_DELAY_MS + 100));
    expect(screen.queryByTestId("nav-pending-bar")).toBeNull();
  });
});
