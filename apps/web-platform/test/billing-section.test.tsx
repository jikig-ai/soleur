import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
}));

import { BillingSection } from "@/components/settings/billing-section";

const BASE_PROPS = {
  subscriptionStatus: null as string | null,
  stripeCustomerId: null as string | null,
  currentPeriodEnd: null as string | null,
  cancelAtPeriodEnd: false,
  conversationCount: 0,
  serviceTokenCount: 0,
  createdAt: new Date("2026-01-10").toISOString(),
};

describe("BillingSection", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-13"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe("active subscriber", () => {
    it("renders plan name, Active badge, period end date, and Manage/Cancel buttons", () => {
      render(
        <BillingSection
          {...BASE_PROPS}
          subscriptionStatus="active"
          stripeCustomerId="cus_123"
          currentPeriodEnd="2026-05-13T00:00:00.000Z"
        />,
      );

      expect(screen.getByText(/Solo/)).toBeInTheDocument();
      expect(screen.getByText(/\$49\/mo/)).toBeInTheDocument();
      expect(screen.getByText("Active")).toBeInTheDocument();
      expect(screen.getByText(/May 13, 2026/)).toBeInTheDocument();
      expect(
        screen.getByRole("button", { name: /manage subscription/i }),
      ).toBeInTheDocument();
      expect(
        screen.getByRole("button", { name: /cancel subscription/i }),
      ).toBeInTheDocument();
    });
  });

  describe("cancelling state", () => {
    it("renders Cancelling badge, warning banner with end date, and Manage button", () => {
      render(
        <BillingSection
          {...BASE_PROPS}
          subscriptionStatus="active"
          stripeCustomerId="cus_123"
          currentPeriodEnd="2026-05-13T00:00:00.000Z"
          cancelAtPeriodEnd={true}
        />,
      );

      expect(screen.getByText("Cancelling")).toBeInTheDocument();
      expect(
        screen.getByText(/your subscription will end on/i),
      ).toBeInTheDocument();
      expect(screen.getByText(/reactivate/i)).toBeInTheDocument();
      expect(
        screen.getByRole("button", { name: /manage subscription/i }),
      ).toBeInTheDocument();
      // No Cancel button in cancelling state
      expect(
        screen.queryByRole("button", { name: /cancel subscription/i }),
      ).not.toBeInTheDocument();
    });
  });

  describe("cancelled / expired", () => {
    it("renders ended message with Resubscribe button", () => {
      render(
        <BillingSection
          {...BASE_PROPS}
          subscriptionStatus="cancelled"
          currentPeriodEnd="2026-03-13T00:00:00.000Z"
        />,
      );

      expect(
        screen.getByText(/your subscription ended/i),
      ).toBeInTheDocument();
      expect(
        screen.getByRole("button", { name: /resubscribe/i }),
      ).toBeInTheDocument();
    });
  });

  describe("no subscription", () => {
    it("renders empty state with Subscribe button", () => {
      render(<BillingSection {...BASE_PROPS} />);

      expect(
        screen.getByText(/no active subscription/i),
      ).toBeInTheDocument();
      expect(
        screen.getByRole("button", { name: /subscribe/i }),
      ).toBeInTheDocument();
      // No manage or cancel buttons
      expect(
        screen.queryByRole("button", { name: /manage/i }),
      ).not.toBeInTheDocument();
    });
  });
});
