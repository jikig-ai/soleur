import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen } from "@testing-library/react";

// Stable module-level pathname mock — a fresh object each render would refire
// effects (learning 2026-04-07-userouter-mock-instability). One mutable string.
let mockPathname = "/dashboard";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  usePathname: () => mockPathname,
  useParams: () => ({}),
}));

vi.mock("@/hooks/use-conversations", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/hooks/use-conversations")>();
  return {
    ...actual,
    useConversations: () => ({
      conversations: [],
      loading: false,
      error: null,
      refetch: vi.fn(),
      archiveConversation: vi.fn(),
      unarchiveConversation: vi.fn(),
      updateStatus: vi.fn(),
    }),
  };
});

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getSession: () =>
        Promise.resolve({ data: { session: null }, error: null }),
      getUser: () => Promise.resolve({ data: { user: null }, error: null }),
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

import { createUseTeamNamesMock } from "./mocks/use-team-names";

vi.mock("@/hooks/use-team-names", () => ({
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
  useTeamNames: () => createUseTeamNamesMock(),
}));

import DashboardLayout from "@/app/(dashboard)/layout";
import { ThemeProvider } from "@/components/theme/theme-provider";
import { RailSlotPortal } from "@/components/dashboard/rail-slot";

const stubMatchMedia = () => ({
  matches: false,
  addEventListener: () => {},
  removeEventListener: () => {},
});

function Wrap({ children }: { children: React.ReactNode }) {
  return <ThemeProvider>{children}</ThemeProvider>;
}

describe("Single nav rail — URL-derived drill swap (AC3/AC4c)", () => {
  beforeEach(() => {
    mockPathname = "/dashboard";
    localStorage.clear();
    vi.stubGlobal("matchMedia", stubMatchMedia);
  });
  afterEach(() => {
    localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("shows the PRIMARY nav (and no secondary slot) at the top level", () => {
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    expect(
      screen.getByRole("link", { name: "Knowledge Base" }),
    ).toBeInTheDocument();
    expect(screen.queryByTestId("rail-secondary-slot")).not.toBeInTheDocument();
  });

  it("KEEPS the primary nav on /dashboard/admin/analytics (allowlist, RQ6)", () => {
    mockPathname = "/dashboard/admin/analytics";
    render(
      <Wrap>
        <DashboardLayout>
          <div>content</div>
        </DashboardLayout>
      </Wrap>,
    );
    expect(
      screen.getByRole("link", { name: "Knowledge Base" }),
    ).toBeInTheDocument();
    expect(screen.queryByTestId("rail-secondary-slot")).not.toBeInTheDocument();
  });

  it.each(["/dashboard/kb", "/dashboard/settings/members", "/dashboard/chat/x"])(
    "swaps to the secondary slot (primary nav gone) when drilled: %s",
    (pathname) => {
      mockPathname = pathname;
      render(
        <Wrap>
          <DashboardLayout>
            <div>content</div>
          </DashboardLayout>
        </Wrap>,
      );
      expect(screen.getByTestId("rail-secondary-slot")).toBeInTheDocument();
      // primary nav items are replaced by the section's secondary nav
      expect(
        screen.queryByRole("link", { name: "Knowledge Base" }),
      ).not.toBeInTheDocument();
    },
  );

  it("routes children through RailSlotProvider — a section can portal into the slot when drilled", () => {
    mockPathname = "/dashboard/settings";
    render(
      <Wrap>
        <DashboardLayout>
          <RailSlotPortal>
            <div data-testid="portaled-nav">section nav</div>
          </RailSlotPortal>
        </DashboardLayout>
      </Wrap>,
    );
    expect(screen.getByTestId("portaled-nav")).toBeInTheDocument();
    // and it lands inside the slot, not loose in the content
    const slot = screen.getByTestId("rail-secondary-slot");
    expect(slot).toContainElement(screen.getByTestId("portaled-nav"));
  });

  it("does NOT render portal content at the top level (slot absent)", () => {
    mockPathname = "/dashboard";
    render(
      <Wrap>
        <DashboardLayout>
          <RailSlotPortal>
            <div data-testid="portaled-nav">section nav</div>
          </RailSlotPortal>
        </DashboardLayout>
      </Wrap>,
    );
    expect(screen.queryByTestId("portaled-nav")).not.toBeInTheDocument();
  });
});
