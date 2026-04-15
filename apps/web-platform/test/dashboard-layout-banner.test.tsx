import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

// next/navigation is imported transitively by the layout module. Mock so module
// evaluation doesn't blow up even though PaymentWarningBanner doesn't use it.
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  usePathname: () => "/dashboard",
}));

// Avoid pulling the real supabase browser client (and its env deps) during the
// layout module load.
vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getSession: () =>
        Promise.resolve({ data: { session: null }, error: null }),
      signOut: vi.fn(),
    },
    from: () => ({
      select: () => ({
        eq: () => ({
          single: () => Promise.resolve({ data: null, error: null }),
        }),
      }),
    }),
  }),
}));

// TeamNamesProvider is a simple passthrough during tests.
import { createUseTeamNamesMock } from "./mocks/use-team-names";

vi.mock("@/hooks/use-team-names", () => ({
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
  useTeamNames: () => createUseTeamNamesMock(),
}));

// Import AFTER the mocks. We test the exported PaymentWarningBanner.
import { PaymentWarningBanner } from "@/app/(dashboard)/layout";

const BANNER_DISMISS_KEY = "soleur:past_due_banner_dismissed";

describe("PaymentWarningBanner (sessionStorage-backed dismiss)", () => {
  beforeEach(() => {
    // happy-dom/jsdom leaks sessionStorage across tests — clear defensively.
    sessionStorage.clear();
    vi.restoreAllMocks();
  });

  afterEach(() => {
    sessionStorage.clear();
  });

  it("shows banner when subscription_status is 'past_due' and no sessionStorage key", () => {
    render(<PaymentWarningBanner subscriptionStatus="past_due" />);
    expect(screen.getByText(/Your last payment failed\./i)).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /dismiss payment warning/i }),
    ).toBeInTheDocument();
  });

  it("hides banner when sessionStorage key === '1' before mount", () => {
    sessionStorage.setItem(BANNER_DISMISS_KEY, "1");
    render(<PaymentWarningBanner subscriptionStatus="past_due" />);
    expect(
      screen.queryByText(/Your last payment failed\./i),
    ).not.toBeInTheDocument();
  });

  it("click dismiss sets sessionStorage key AND hides banner", () => {
    render(<PaymentWarningBanner subscriptionStatus="past_due" />);
    const btn = screen.getByRole("button", {
      name: /dismiss payment warning/i,
    });
    fireEvent.click(btn);

    expect(sessionStorage.getItem(BANNER_DISMISS_KEY)).toBe("1");
    expect(
      screen.queryByText(/Your last payment failed\./i),
    ).not.toBeInTheDocument();
  });

  it("sessionStorage.setItem throws — banner still hides in memory", () => {
    const setItemSpy = vi
      .spyOn(Storage.prototype, "setItem")
      .mockImplementation(() => {
        throw new Error("QuotaExceededError");
      });

    // Also watch for uncaught errors bubbling to console.error.
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    render(<PaymentWarningBanner subscriptionStatus="past_due" />);
    const btn = screen.getByRole("button", {
      name: /dismiss payment warning/i,
    });

    // Click must not throw despite sessionStorage write failure.
    expect(() => fireEvent.click(btn)).not.toThrow();

    // Banner hidden via in-memory state even though persistence failed.
    expect(
      screen.queryByText(/Your last payment failed\./i),
    ).not.toBeInTheDocument();

    setItemSpy.mockRestore();
    errorSpy.mockRestore();
  });

  it("renders nothing when subscription_status is not 'past_due'", () => {
    render(<PaymentWarningBanner subscriptionStatus="active" />);
    expect(
      screen.queryByText(/Your last payment failed\./i),
    ).not.toBeInTheDocument();
  });
});
