import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor, cleanup } from "@testing-library/react";
import { SWRConfig } from "swr";

// GAP H (ADR-067 staleTimes amendment): the client loader fetches all-tenant
// analytics from the admin-gated route so nothing sensitive is ever baked into a
// cacheable RSC. On a de-provisioned admin (fresh 403) it bounces WITHOUT
// rendering any data; on session revocation it hard-navs to /login.

vi.mock("@/components/analytics/analytics-dashboard", () => ({
  AnalyticsDashboard: ({ metrics }: { metrics: unknown[] }) => (
    <div data-testid="dashboard">rows:{metrics.length}</div>
  ),
}));

import { AnalyticsDashboardLoader } from "@/components/analytics/analytics-dashboard-loader";

const assignMock = vi.fn();
let originalLocation: Location;
const fetchMock = vi.fn();

function renderLoader() {
  return render(
    <SWRConfig value={{ provider: () => new Map(), dedupingInterval: 0 }}>
      <AnalyticsDashboardLoader />
    </SWRConfig>,
  );
}

beforeEach(() => {
  assignMock.mockReset();
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
  originalLocation = window.location;
  Object.defineProperty(window, "location", {
    configurable: true,
    writable: true,
    value: { assign: assignMock, pathname: "/dashboard/admin/analytics" } as unknown as Location,
  });
});

afterEach(() => {
  Object.defineProperty(window, "location", {
    configurable: true,
    writable: true,
    value: originalLocation,
  });
  vi.unstubAllGlobals();
  cleanup();
});

describe("AnalyticsDashboardLoader (GAP H)", () => {
  it("renders the loading skeleton before data arrives, then the dashboard", async () => {
    fetchMock.mockResolvedValue({
      status: 200,
      ok: true,
      redirected: false,
      url: "https://app/api/admin/analytics",
      json: () => Promise.resolve({ metrics: [{ userId: "u1" }], funnel: {} }),
    });
    renderLoader();
    expect(screen.getByTestId("analytics-loading")).toBeInTheDocument();
    await waitFor(() => expect(screen.getByTestId("dashboard")).toBeInTheDocument());
    expect(screen.getByTestId("dashboard")).toHaveTextContent("rows:1");
  });

  it("bounces a de-provisioned admin (403) to /dashboard WITHOUT rendering data", async () => {
    fetchMock.mockResolvedValue({
      status: 403,
      ok: false,
      redirected: false,
      url: "https://app/api/admin/analytics",
      json: () => Promise.resolve({ error: "forbidden" }),
    });
    renderLoader();
    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/dashboard"));
    expect(screen.queryByTestId("dashboard")).not.toBeInTheDocument();
  });

  it("hard-navs to /login on a revocation bounce (302→/login followed to 200)", async () => {
    fetchMock.mockResolvedValue({
      status: 200,
      ok: true,
      redirected: true,
      url: "https://app/login",
      json: () => Promise.resolve({}),
    });
    renderLoader();
    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/login"));
    expect(screen.queryByTestId("dashboard")).not.toBeInTheDocument();
  });

  it("shows a retry affordance on a 500", async () => {
    fetchMock.mockResolvedValue({
      status: 500,
      ok: false,
      redirected: false,
      url: "https://app/api/admin/analytics",
      json: () => Promise.resolve({ error: "query_failed" }),
    });
    renderLoader();
    await waitFor(() =>
      expect(screen.getByText(/failed to load analytics/i)).toBeInTheDocument(),
    );
    expect(assignMock).not.toHaveBeenCalled();
  });
});
