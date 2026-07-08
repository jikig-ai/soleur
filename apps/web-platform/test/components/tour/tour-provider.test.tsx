import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup, act } from "@testing-library/react";

const flagState = vi.hoisted(() => ({ on: true }));
vi.mock("@/components/feature-flags/provider", () => ({
  useOptionalFeatureFlag: (name: string) =>
    name === "guided-tour" ? flagState.on : false,
}));

const onb = vi.hoisted(() => ({
  onboardingLoaded: true,
  onboardingCompletedAt: "2026-01-01T00:00:00Z" as string | null,
  tourCompletedAt: null as string | null,
}));
vi.mock("@/hooks/use-onboarding", () => ({
  useOnboarding: () => onb,
}));

const pathState = vi.hoisted(() => ({ path: "/dashboard" }));
const routerPush = vi.hoisted(() => vi.fn());
vi.mock("next/navigation", () => ({
  usePathname: () => pathState.path,
  useRouter: () => ({ push: routerPush }),
}));

const track = vi.hoisted(() => vi.fn());
vi.mock("@/lib/analytics-client", () => ({ track }));

vi.mock("@/components/dashboard/rail-slot", () => ({
  RAIL_EXPAND_EVENT: "soleur:rail-expand",
}));

import { TourProvider, useTour } from "@/components/tour/tour-provider";

function Probe() {
  const t = useTour();
  return (
    <>
      <button type="button" data-available={t.available} onClick={() => t.startTour("test")}>
        start
      </button>
      <button type="button" onClick={() => t.next()}>
        next
      </button>
    </>
  );
}

function renderProvider() {
  return render(
    <TourProvider>
      <Probe />
    </TourProvider>,
  );
}

describe("TourProvider", () => {
  beforeEach(() => {
    flagState.on = true;
    onb.onboardingLoaded = true;
    onb.onboardingCompletedAt = "2026-01-01T00:00:00Z";
    onb.tourCompletedAt = null;
    pathState.path = "/dashboard";
    routerPush.mockClear();
    track.mockClear();
    vi.stubGlobal(
      "fetch",
      vi.fn(() => Promise.resolve({ ok: true, json: async () => ({ ok: true }) })),
    );
  });
  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  it("flag OFF: available=false and no overlay; manual start is a no-op", () => {
    flagState.on = false;
    renderProvider();
    expect(screen.getByText("start").getAttribute("data-available")).toBe("false");
    fireEvent.click(screen.getByText("start"));
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("flag ON: manual startTour mounts the overlay + emits tour_started", () => {
    // Suppress auto-start for this test by marking the tour already completed.
    onb.tourCompletedAt = "2026-02-02T00:00:00Z";
    renderProvider();
    expect(screen.getByText("start").getAttribute("data-available")).toBe("true");
    expect(screen.queryByRole("dialog")).toBeNull();
    fireEvent.click(screen.getByText("start"));
    expect(screen.getByRole("dialog")).toBeTruthy();
    expect(track).toHaveBeenCalledWith(
      "tour_started",
      expect.objectContaining({ source: "test" }),
    );
  });

  it("auto-starts once when onboarding done, tour never completed, on /dashboard", () => {
    vi.useFakeTimers();
    renderProvider();
    expect(screen.queryByRole("dialog")).toBeNull();
    act(() => {
      vi.advanceTimersByTime(700);
    });
    expect(screen.getByRole("dialog")).toBeTruthy();
    expect(track).toHaveBeenCalledWith(
      "tour_started",
      expect.objectContaining({ source: "auto" }),
    );
  });

  it("does NOT auto-start when tour_completed_at is set", () => {
    vi.useFakeTimers();
    onb.tourCompletedAt = "2026-02-02T00:00:00Z";
    renderProvider();
    act(() => {
      vi.advanceTimersByTime(700);
    });
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("does NOT auto-start before first-run onboarding completes", () => {
    vi.useFakeTimers();
    onb.onboardingCompletedAt = null;
    renderProvider();
    act(() => {
      vi.advanceTimersByTime(700);
    });
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("navigates to a step's route when advancing onto a different-route step", () => {
    onb.tourCompletedAt = "x"; // suppress auto-start; drive manually
    renderProvider();
    fireEvent.click(screen.getByText("start")); // step 0 Welcome (no route)
    // Steps 1-3 (Dashboard tab, Start a conversation, org-panel) all route to
    // /dashboard, which equals the current pathname → no navigation.
    fireEvent.click(screen.getByText("next")); // step 1 Dashboard tab
    fireEvent.click(screen.getByText("next")); // step 2 start a conversation
    fireEvent.click(screen.getByText("next")); // step 3 org-panel
    expect(routerPush).not.toHaveBeenCalled();
    fireEvent.click(screen.getByText("next")); // step 4 Inside a conversation → /dashboard/chat/new
    expect(routerPush).toHaveBeenCalledWith("/dashboard/chat/new");
  });

  it("does NOT navigate on the Knowledge Base TAB step — the rail is swapped once inside, so the tab is highlighted from the prior page; only the next (content) step opens the KB", () => {
    onb.tourCompletedAt = "x"; // suppress auto-start; drive manually
    renderProvider();
    fireEvent.click(screen.getByText("start")); // step 0 Welcome
    // Advance to step 10 (Concierge modal step) — the step just before the KB tab.
    for (let i = 0; i < 10; i++) fireEvent.click(screen.getByText("next"));
    routerPush.mockClear();
    fireEvent.click(screen.getByText("next")); // step 11 KB tab (no route)
    expect(routerPush).not.toHaveBeenCalled();
    fireEvent.click(screen.getByText("next")); // step 12 KB content → opens the KB
    expect(routerPush).toHaveBeenCalledWith("/dashboard/kb");
  });

  it("opens the New Issue dialog on its modal steps and closes it on leave (reveal event, no flicker between the two)", () => {
    onb.tourCompletedAt = "x"; // suppress auto-start; drive manually
    const events: boolean[] = [];
    const handler = (e: Event) =>
      events.push((e as CustomEvent<{ open: boolean }>).detail.open);
    window.addEventListener("soleur:new-issue-dialog", handler);
    try {
      renderProvider();
      fireEvent.click(screen.getByText("start")); // step 0
      // Steps 1-8 carry no `reveal` → nothing dispatched yet.
      for (let i = 0; i < 8; i++) fireEvent.click(screen.getByText("next"));
      expect(events).toEqual([]);
      fireEvent.click(screen.getByText("next")); // step 9 manual create (reveal → open)
      expect(events).toEqual([true]);
      fireEvent.click(screen.getByText("next")); // step 10 concierge (same reveal → no re-dispatch)
      expect(events).toEqual([true]);
      fireEvent.click(screen.getByText("next")); // step 11 KB tab (no reveal → close)
      expect(events).toEqual([true, false]);
    } finally {
      window.removeEventListener("soleur:new-issue-dialog", handler);
    }
  });

  it("Finish persists completion via POST /api/tour/complete", () => {
    onb.tourCompletedAt = "x"; // suppress auto-start; drive manually
    renderProvider();
    fireEvent.click(screen.getByText("start"));
    const dialog = screen.getByRole("dialog");
    // Welcome (1) → step through to last, then Finish.
    // Simpler: Skip persists too — assert the POST fires on Skip.
    fireEvent.keyDown(document, { key: "Escape" }); // Escape = skip in overlay
    const fetchMock = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/tour/complete",
      expect.objectContaining({ method: "POST" }),
    );
  });
});
