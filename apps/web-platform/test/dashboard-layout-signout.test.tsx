import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { ThemeProvider } from "@/components/theme/theme-provider";

const stubMatchMedia = () => ({
  matches: false,
  addEventListener: () => {},
  removeEventListener: () => {},
});

function Wrap({ children }: { children: React.ReactNode }) {
  return <ThemeProvider>{children}</ThemeProvider>;
}

const {
  pushMock,
  signOutMock,
  removeAllChannelsMock,
  reportSilentFallbackMock,
} = vi.hoisted(() => ({
  pushMock: vi.fn(),
  signOutMock: vi.fn(() => Promise.resolve({ error: null })),
  removeAllChannelsMock: vi.fn(() => Promise.resolve(["ok"])),
  reportSilentFallbackMock: vi.fn(),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, refresh: vi.fn() }),
  usePathname: () => "/dashboard",
  useParams: () => ({}),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getSession: () =>
        Promise.resolve({ data: { session: null }, error: null }),
      getUser: () => Promise.resolve({ data: { user: null }, error: null }),
      signOut: signOutMock,
    },
    from: () => ({
      select: () => ({
        eq: () => ({
          single: () => Promise.resolve({ data: null, error: null }),
          maybeSingle: () => Promise.resolve({ data: null, error: null }),
        }),
      }),
    }),
    channel: () => ({
      on: vi.fn().mockReturnThis(),
      subscribe: vi.fn().mockReturnThis(),
    }),
    removeChannel: vi.fn(),
    removeAllChannels: removeAllChannelsMock,
  }),
}));

vi.mock("@/hooks/use-team-names", () => ({
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
  useTeamNames: () => createUseTeamNamesMock(),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: reportSilentFallbackMock,
}));

const fetchMock = vi.fn(() =>
  Promise.resolve({
    ok: true,
    json: () => Promise.resolve({ isAdmin: false }),
  } as Response),
);

beforeEach(() => {
  vi.stubGlobal("fetch", fetchMock);
  vi.stubGlobal("matchMedia", stubMatchMedia);
  fetchMock.mockClear();
  pushMock.mockClear();
  signOutMock.mockClear();
  removeAllChannelsMock.mockClear();
  reportSilentFallbackMock.mockClear();
  signOutMock.mockImplementation(() => Promise.resolve({ error: null }));
  removeAllChannelsMock.mockImplementation(() => Promise.resolve(["ok"]));
});

afterEach(() => {
  vi.unstubAllGlobals();
  cleanup();
});

describe("DashboardLayout — Sign out confirmation modal", () => {
  it("does not render the modal until the sidebar Sign out button is clicked", async () => {
    const { default: DashboardLayout } = await import(
      "@/app/(dashboard)/layout"
    );

    render(
      <Wrap>
        <DashboardLayout>
          <div data-testid="page">page</div>
        </DashboardLayout>
      </Wrap>,
    );

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("opens the confirmation modal when the sidebar Sign out button is clicked", async () => {
    const { default: DashboardLayout } = await import(
      "@/app/(dashboard)/layout"
    );

    render(
      <Wrap>
        <DashboardLayout>
          <div data-testid="page">page</div>
        </DashboardLayout>
      </Wrap>,
    );

    const signOutButtons = screen.getAllByRole("button", { name: /sign out/i });
    fireEvent.click(signOutButtons[0]);

    expect(screen.getByRole("dialog")).toBeInTheDocument();
    expect(signOutMock).not.toHaveBeenCalled();
    expect(removeAllChannelsMock).not.toHaveBeenCalled();
  });

  it("Cancel inside the modal closes it without signing out", async () => {
    const { default: DashboardLayout } = await import(
      "@/app/(dashboard)/layout"
    );

    render(
      <Wrap>
        <DashboardLayout>
          <div data-testid="page">page</div>
        </DashboardLayout>
      </Wrap>,
    );

    const signOutButtons = screen.getAllByRole("button", { name: /sign out/i });
    fireEvent.click(signOutButtons[0]);

    const cancelButton = screen.getByRole("button", { name: /cancel/i });
    fireEvent.click(cancelButton);

    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(signOutMock).not.toHaveBeenCalled();
    expect(removeAllChannelsMock).not.toHaveBeenCalled();
    expect(pushMock).not.toHaveBeenCalled();
  });

  it("Confirm inside the modal runs the teardown contract and redirects to /login", async () => {
    const { default: DashboardLayout } = await import(
      "@/app/(dashboard)/layout"
    );

    render(
      <Wrap>
        <DashboardLayout>
          <div data-testid="page">page</div>
        </DashboardLayout>
      </Wrap>,
    );

    const sidebarSignOut = screen.getAllByRole("button", { name: /sign out/i })[0];
    fireEvent.click(sidebarSignOut);

    const confirmInModal = screen
      .getAllByRole("button", { name: /^sign out$/i })
      .find((btn) => btn !== sidebarSignOut);
    expect(confirmInModal).toBeDefined();
    fireEvent.click(confirmInModal!);

    await waitFor(() => {
      expect(signOutMock).toHaveBeenCalledTimes(1);
    });
    expect(removeAllChannelsMock).toHaveBeenCalledTimes(1);
    expect(pushMock).toHaveBeenCalledWith("/login");
  });

  it("still redirects when removeAllChannels rejects, and mirrors the error to Sentry", async () => {
    removeAllChannelsMock.mockImplementationOnce(() =>
      Promise.reject(new Error("phx_leave timeout")),
    );

    const { default: DashboardLayout } = await import(
      "@/app/(dashboard)/layout"
    );

    render(
      <Wrap>
        <DashboardLayout>
          <div data-testid="page">page</div>
        </DashboardLayout>
      </Wrap>,
    );

    const sidebarSignOut = screen.getAllByRole("button", { name: /sign out/i })[0];
    fireEvent.click(sidebarSignOut);

    const confirmInModal = screen
      .getAllByRole("button", { name: /^sign out$/i })
      .find((btn) => btn !== sidebarSignOut);
    fireEvent.click(confirmInModal!);

    await waitFor(() => {
      expect(pushMock).toHaveBeenCalledWith("/login");
    });

    expect(signOutMock).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackMock).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "auth", op: "signOut" }),
    );
  });

  it("mirrors a signOut throw to Sentry with feature:auth op:signOut and still pushes /login", async () => {
    signOutMock.mockImplementationOnce(() =>
      Promise.reject(new Error("network failure")),
    );

    const { default: DashboardLayout } = await import(
      "@/app/(dashboard)/layout"
    );

    render(
      <Wrap>
        <DashboardLayout>
          <div data-testid="page">page</div>
        </DashboardLayout>
      </Wrap>,
    );

    const sidebarSignOut = screen.getAllByRole("button", { name: /sign out/i })[0];
    fireEvent.click(sidebarSignOut);

    const confirmInModal = screen
      .getAllByRole("button", { name: /^sign out$/i })
      .find((btn) => btn !== sidebarSignOut);
    fireEvent.click(confirmInModal!);

    await waitFor(() => {
      expect(pushMock).toHaveBeenCalledWith("/login");
    });

    expect(reportSilentFallbackMock).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "auth", op: "signOut" }),
    );
  });
});
