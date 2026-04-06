import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

// ---------------------------------------------------------------------------
// ProjectSetupCard tests
// ---------------------------------------------------------------------------

describe("ProjectSetupCard", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders 'Set Up Project' button when not connected", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    render(
      <ProjectSetupCard
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
      />,
    );
    expect(
      screen.getByRole("link", { name: /set up project/i }),
    ).toBeInTheDocument();
  });

  it("links to /connect-repo with return_to param when not connected", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    render(
      <ProjectSetupCard
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
      />,
    );
    const link = screen.getByRole("link", { name: /set up project/i });
    expect(link).toHaveAttribute(
      "href",
      "/connect-repo?return_to=/dashboard/settings",
    );
  });

  it("shows repo name and Connected status when ready", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    render(
      <ProjectSetupCard
        repoUrl="https://github.com/owner/my-repo"
        repoStatus="ready"
        repoLastSyncedAt="2026-04-01T12:00:00Z"
      />,
    );
    expect(screen.getByText("owner/my-repo")).toBeInTheDocument();
    expect(screen.getByText(/connected/i)).toBeInTheDocument();
  });

  it("shows last synced date when ready", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    render(
      <ProjectSetupCard
        repoUrl="https://github.com/owner/my-repo"
        repoStatus="ready"
        repoLastSyncedAt="2026-04-01T12:00:00Z"
      />,
    );
    expect(screen.getByText(/last synced/i)).toBeInTheDocument();
  });

  it("shows error state with retry button when status is error", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    render(
      <ProjectSetupCard
        repoUrl={null}
        repoStatus="error"
        repoLastSyncedAt={null}
      />,
    );
    expect(screen.getByText(/something went wrong/i)).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: /retry setup/i }),
    ).toBeInTheDocument();
  });

  it("shows setting up message when cloning", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    render(
      <ProjectSetupCard
        repoUrl={null}
        repoStatus="cloning"
        repoLastSyncedAt={null}
      />,
    );
    expect(screen.getByText(/setting up/i)).toBeInTheDocument();
  });

  it("renders Project heading", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    const { unmount } = render(
      <ProjectSetupCard
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
      />,
    );
    expect(screen.getByText("Project")).toBeInTheDocument();
    unmount();
  });

  it("shows Disconnect button when repoStatus is ready", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    render(
      <ProjectSetupCard
        repoUrl="https://github.com/owner/my-repo"
        repoStatus="ready"
        repoLastSyncedAt="2026-04-01T12:00:00Z"
      />,
    );
    expect(
      screen.getByRole("button", { name: /disconnect/i }),
    ).toBeInTheDocument();
  });

  it("does NOT show Disconnect button when repoStatus is not_connected", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    render(
      <ProjectSetupCard
        repoUrl={null}
        repoStatus="not_connected"
        repoLastSyncedAt={null}
      />,
    );
    expect(
      screen.queryByRole("button", { name: /disconnect/i }),
    ).not.toBeInTheDocument();
  });
});
