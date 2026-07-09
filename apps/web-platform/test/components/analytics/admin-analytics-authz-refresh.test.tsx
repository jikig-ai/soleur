import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, cleanup } from "@testing-library/react";

// GAP H (ADR-067 staleTimes amendment): the admin-analytics page bakes ALL-tenant
// data into a cacheable RSC gated only by a server-side ADMIN_USER_IDS env check.
// AdminAnalyticsAuthzRefresh calls router.refresh() on mount so every entry —
// including a warm Router-Cache restore — forces a fresh server render that
// re-runs the isAdmin gate (a de-provisioned admin is redirected instead of
// riding the cached all-tenant RSC).

const { refreshMock } = vi.hoisted(() => ({ refreshMock: vi.fn() }));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: refreshMock }),
}));

import { AdminAnalyticsAuthzRefresh } from "@/components/analytics/admin-analytics-authz-refresh";

beforeEach(() => refreshMock.mockClear());
afterEach(() => cleanup());

describe("AdminAnalyticsAuthzRefresh (GAP H)", () => {
  it("calls router.refresh() exactly once on mount", () => {
    render(<AdminAnalyticsAuthzRefresh />);
    expect(refreshMock).toHaveBeenCalledTimes(1);
  });

  it("renders nothing (side-effect-only component)", () => {
    const { container } = render(<AdminAnalyticsAuthzRefresh />);
    expect(container).toBeEmptyDOMElement();
  });
});
