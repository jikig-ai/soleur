import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";

import { FunnelView } from "@/components/crm/funnel-view";
import { SwrTestProvider } from "../helpers/swr-wrapper";

function fetchReturning(res: { ok: boolean; status: number; body: unknown }) {
  return vi.fn(async () => ({
    ok: res.ok,
    status: res.status,
    json: async () => res.body,
  })) as unknown as typeof fetch;
}

function renderFunnel() {
  return render(
    <SwrTestProvider>
      <FunnelView />
    </SwrTestProvider>,
  );
}

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("FunnelView", () => {
  it("renders bars with reached counts, top-of-funnel, and % of prior stage", async () => {
    global.fetch = fetchReturning({
      ok: true,
      status: 200,
      body: {
        stages: [
          { stage: "new", reached: 14, conversionPct: null },
          { stage: "contacted", reached: 10, conversionPct: 71 },
          { stage: "qualified", reached: 7, conversionPct: 70 },
          { stage: "evaluating", reached: 5, conversionPct: 71 },
          { stage: "committed", reached: 3, conversionPct: 60 },
          { stage: "closed_won", reached: 2, conversionPct: 67 },
        ],
        closedLost: 1,
        avgTimeInStageDays: 6.2,
        perTransition: [
          { from: "new", to: "contacted", avgDays: 4 },
          { from: "contacted", to: "qualified", avgDays: 8 },
        ],
      },
    });

    renderFunnel();
    await waitFor(() => expect(screen.getByText("Conversion funnel")).toBeTruthy());
    expect(screen.getByText("Top of funnel")).toBeTruthy();
    expect(screen.getByText("71% of New")).toBeTruthy();
    expect(screen.getByText("14 entered · 2 won")).toBeTruthy();
    // Velocity strip + closed-lost branch.
    expect(screen.getByText("6.2d")).toBeTruthy();
    expect(screen.getByText("Closed Lost")).toBeTruthy();
    expect(screen.getByText(/thin at beta volume/)).toBeTruthy();
  });

  it("suppresses conversionPct as 'insufficient data' at low N (AC4)", async () => {
    global.fetch = fetchReturning({
      ok: true,
      status: 200,
      body: {
        stages: [
          { stage: "new", reached: 2, conversionPct: null },
          { stage: "contacted", reached: 1, conversionPct: null }, // prev < LOW_N
          { stage: "qualified", reached: 0, conversionPct: null },
          { stage: "evaluating", reached: 0, conversionPct: null },
          { stage: "committed", reached: 0, conversionPct: null },
          { stage: "closed_won", reached: 0, conversionPct: null },
        ],
        closedLost: 0,
        avgTimeInStageDays: null,
        perTransition: [],
      },
    });

    renderFunnel();
    await waitFor(() => expect(screen.getByText("Conversion funnel")).toBeTruthy());
    expect(screen.getAllByText("insufficient data").length).toBeGreaterThan(0);
  });

  it("shows an empty state when no contact has entered", async () => {
    global.fetch = fetchReturning({
      ok: true,
      status: 200,
      body: {
        stages: [{ stage: "new", reached: 0, conversionPct: null }],
        closedLost: 0,
        avgTimeInStageDays: null,
        perTransition: [],
      },
    });
    renderFunnel();
    await waitFor(() =>
      expect(screen.getByText(/No contacts have entered the pipeline yet/)).toBeTruthy(),
    );
  });

  it("shows an ErrorCard on failure (toggle-in-parent stays usable)", async () => {
    global.fetch = fetchReturning({ ok: false, status: 502, body: { error: "funnel_query_error" } });
    renderFunnel();
    await waitFor(() => expect(screen.getByText("Couldn't load the funnel")).toBeTruthy());
    expect(screen.queryByText(/funnel_query_error/)).toBeNull();
  });
});
