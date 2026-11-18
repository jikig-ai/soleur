import { describe, it, expect, vi, beforeEach } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

// The needs-reconnect variant renders <ReconnectNotice>, which uses the
// reconnect hook. Stub it so no real fetch fires (the hook is covered by
// use-reconnect.test.tsx).
vi.mock("@/components/repo/use-reconnect", () => ({
  useReconnect: () => ({ reconnect: vi.fn(), isPending: false }),
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

  it("shows the 'Updated from GitHub' date line when ready (V2/W5 relabel; no 'Last synced')", async () => {
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
    expect(screen.getByText(/^Updated from GitHub: /)).toBeInTheDocument();
    expect(screen.queryByText(/last synced/i)).not.toBeInTheDocument();
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

  it("renders the reconnect notice only on ready + needsReconnect", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    render(
      <ProjectSetupCard
        repoUrl="https://github.com/owner/my-repo"
        repoStatus="ready"
        repoLastSyncedAt="2026-04-01T12:00:00Z"
        needsReconnect={true}
      />,
    );
    expect(screen.getByText(/can't sync/i)).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /^reconnect$/i }),
    ).toBeInTheDocument();
  });

  it("suppresses the Connected view when needsReconnect is true", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    render(
      <ProjectSetupCard
        repoUrl="https://github.com/owner/my-repo"
        repoStatus="ready"
        repoLastSyncedAt="2026-04-01T12:00:00Z"
        needsReconnect={true}
      />,
    );
    expect(screen.queryByText(/connected/i)).not.toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /disconnect/i }),
    ).not.toBeInTheDocument();
  });

  it("does NOT render the reconnect notice when ready and not needing reconnect", async () => {
    const { ProjectSetupCard } = await import(
      "@/components/settings/project-setup-card"
    );
    render(
      <ProjectSetupCard
        repoUrl="https://github.com/owner/my-repo"
        repoStatus="ready"
        repoLastSyncedAt="2026-04-01T12:00:00Z"
        needsReconnect={false}
      />,
    );
    expect(screen.queryByText(/can't sync/i)).not.toBeInTheDocument();
    expect(screen.getByText(/connected/i)).toBeInTheDocument();
  });
});

// ---------------------------------------------------------------------------
// #12714 held-files notice (V6, D29(8), D31). The strings come from lib/kb-sync-held-copy.ts, whose own test pins them
// verbatim; these rows pin which string each card state renders, and that nothing else renders.
// ---------------------------------------------------------------------------

describe("ProjectSetupCard held-files notice (#12714)", () => {
  const READY = {
    repoUrl: "https://github.com/acme-co/web-platform",
    repoStatus: "ready" as const,
    repoLastSyncedAt: "2026-11-16T12:00:00Z",
  };
  const NOTICE = "kb-sync-held-notice";

  it("Owner, route available, n = 3: the V6 Owner string under the date line, Disconnect unchanged, no new control", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    const { heldOwnerRouteAvailable } = await import("@/lib/kb-sync-held-copy");
    render(<ProjectSetupCard {...READY} heldFiles={3} heldRoute="available" />);
    const notice = screen.getByTestId(NOTICE);
    expect(notice).toHaveTextContent(heldOwnerRouteAvailable(3));
    expect(notice.textContent).toBe(heldOwnerRouteAvailable(3));
    expect(screen.getByText(/^Updated from GitHub: /)).toBeInTheDocument();
    expect(screen.getAllByRole("button")).toHaveLength(1);
    expect(screen.getByRole("button", { name: /disconnect/i })).toBeInTheDocument();
  });

  it("Owner, no route and transient: the V6 no-route and transient strings", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    const copy = await import("@/lib/kb-sync-held-copy");
    const { unmount } = render(<ProjectSetupCard {...READY} heldFiles={1} heldRoute="unavailable" />);
    expect(screen.getByTestId(NOTICE).textContent).toBe(copy.heldOwnerNoRoute(1));
    unmount();
    render(<ProjectSetupCard {...READY} heldFiles={3} heldRoute="unknown" />);
    expect(screen.getByTestId(NOTICE).textContent).toBe(copy.heldOwnerTransient(3));
  });

  it("a missing route state reads as transient, never as the no-route sentence", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    const copy = await import("@/lib/kb-sync-held-copy");
    render(<ProjectSetupCard {...READY} heldFiles={2} />);
    expect(screen.getByTestId(NOTICE).textContent).toBe(copy.heldOwnerTransient(2));
  });

  it("Member, each route state: the V6 member string under the 'managed by' line, no date", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    const copy = await import("@/lib/kb-sync-held-copy");
    const cases = [
      ["available", copy.heldMemberRouteAvailable(3, "Acme Co")],
      ["unavailable", copy.heldMemberNoRoute(3)],
      ["unknown", copy.heldMemberTransient(3)],
    ] as const;
    for (const [route, expected] of cases) {
      const { unmount } = render(
        <ProjectSetupCard {...READY} isOwner={false} ownerLabel="Acme Co" heldFiles={3} heldRoute={route} />,
      );
      expect(screen.getByText("managed by Acme Co")).toBeInTheDocument();
      expect(screen.getByTestId(NOTICE).textContent).toBe(expected);
      expect(screen.queryByText(/Updated from GitHub/)).not.toBeInTheDocument();
      unmount();
    }
  });

  it("Member, no owner label: the 'your workspace owner' fallback", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    render(<ProjectSetupCard {...READY} isOwner={false} ownerLabel={null} heldFiles={3} heldRoute="available" />);
    expect(screen.getByTestId(NOTICE)).toHaveTextContent("then ask your workspace owner to approve the push");
  });

  it("n = 0, null, non-integer or outside 1..10000 renders no held notice (Owner and member)", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    for (const heldFiles of [0, null, undefined, 2.5, -1, 10_001]) {
      for (const isOwner of [true, false]) {
        const { unmount } = render(
          <ProjectSetupCard {...READY} isOwner={isOwner} heldFiles={heldFiles} heldRoute="available" />,
        );
        expect(screen.queryByTestId(NOTICE), `${heldFiles} owner=${isOwner}`).not.toBeInTheDocument();
        expect(screen.queryByText(/changed code file/)).not.toBeInTheDocument();
        unmount();
      }
    }
  });

  it("a repo that is not ready renders no held notice (Owner and member)", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    for (const repoStatus of ["not_connected", "cloning", "error"] as const) {
      for (const isOwner of [true, false]) {
        const { unmount } = render(
          <ProjectSetupCard
            repoUrl="https://github.com/acme-co/web-platform"
            repoStatus={repoStatus}
            repoLastSyncedAt={null}
            isOwner={isOwner}
            heldFiles={3}
            heldRoute="available"
          />,
        );
        expect(screen.queryByTestId(NOTICE), `${repoStatus} owner=${isOwner}`).not.toBeInTheDocument();
        unmount();
      }
    }
  });

  it("Owner with needsReconnect: ReconnectNotice is the only notice (V6(4))", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    render(<ProjectSetupCard {...READY} needsReconnect heldFiles={3} heldRoute="available" />);
    expect(screen.getByText(/can't sync/i)).toBeInTheDocument();
    expect(screen.queryByTestId(NOTICE)).not.toBeInTheDocument();
    expect(screen.queryByText(/changed code file/)).not.toBeInTheDocument();
  });

  it("an owner label carrying markup renders as literal text, never HTML", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    const evil = "<img src=x onerror=alert(1)>";
    const { container } = render(
      <ProjectSetupCard {...READY} isOwner={false} ownerLabel={evil} heldFiles={3} heldRoute="available" />,
    );
    expect(screen.getByTestId(NOTICE)).toHaveTextContent(`then ask ${evil} to approve the push`);
    expect(container.querySelector("img")).toBeNull();
  });

  it("the member notice holds the count only: no path, commit message or tool name", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    render(<ProjectSetupCard {...READY} isOwner={false} ownerLabel="Acme Co" heldFiles={3} heldRoute="available" />);
    const text = screen.getByTestId(NOTICE).textContent ?? "";
    expect(text).not.toMatch(/[\w-]+\/[\w.-]+\.(ts|tsx|js|md)\b/);
    expect(text).not.toMatch(/github_push_branch|commit/i);
  });
  it("V10: role unknown -> the neutral string for any route; the Owner and member steps are never shown", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    const copy = await import("@/lib/kb-sync-held-copy");
    for (const route of ["available", "unavailable", "unknown"] as const) {
      const { unmount } = render(<ProjectSetupCard {...READY} heldAudience="unknown" ownerLabel="Acme Co" heldFiles={3} heldRoute={route} />);
      expect(screen.getByTestId(NOTICE).textContent).toBe(copy.heldRoleUnknown(3));
      unmount();
    }
  });

  it("V10: an explicit audience wins over isOwner (a member audience on an Owner-controls card shows the member string)", async () => {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    const copy = await import("@/lib/kb-sync-held-copy");
    render(<ProjectSetupCard {...READY} heldAudience="member" ownerLabel="Acme Co" heldFiles={3} heldRoute="unavailable" />);
    expect(screen.getByTestId(NOTICE).textContent).toBe(copy.heldMemberNoRoute(3));
  });
});

// #12704 V8: the Disconnect dialog warns about the held count (caution, never a block).
describe("DisconnectRepoDialog held warning (V8)", () => {
  const READY = {
    repoUrl: "https://github.com/acme-co/web-platform",
    repoStatus: "ready" as const,
    repoLastSyncedAt: "2026-11-16T12:00:00Z",
  };
  async function openDialog(props: Record<string, unknown>) {
    const { ProjectSetupCard } = await import("@/components/settings/project-setup-card");
    render(<ProjectSetupCard {...READY} {...props} />);
    fireEvent.click(screen.getByRole("button", { name: /^disconnect$/i }));
  }
  const bodyText = () => screen.getByText(/This will unlink/).textContent;

  it("route available: the warning with the publish step ABOVE the unchanged paragraph; Confirm stays enabled", async () => {
    const copy = await import("@/lib/kb-sync-held-copy");
    await openDialog({ heldFiles: 3, heldRoute: "available" });
    const warning = screen.getByTestId("disconnect-held-warning");
    expect(warning.textContent).toBe(copy.disconnectHeldWarning(3, "available"));
    expect(bodyText()).toBe("This will unlink acme-co/web-platform from your account. Your workspace files will be removed. You can reconnect a repository at any time.");
    // Above the paragraph, a neutral note (not role=alert), and Disconnect is not blocked.
    expect(warning.compareDocumentPosition(screen.getByText(/This will unlink/)) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(warning.getAttribute("role")).toBe("note");
    expect(warning.className).not.toMatch(/red/);
    expect(screen.getByRole("button", { name: /confirm disconnect/i })).toBeEnabled();
  });

  it.each([["unavailable"], ["unknown"]] as const)("route %s: the warning without an instruction", async (route) => {
    const copy = await import("@/lib/kb-sync-held-copy");
    await openDialog({ heldFiles: 1, heldRoute: route });
    expect(screen.getByTestId("disconnect-held-warning").textContent).toBe(copy.disconnectHeldWarning(1, "unknown"));
  });

  it("role unknown: no instruction even when the route is available (V10: the steps are not shown)", async () => {
    const copy = await import("@/lib/kb-sync-held-copy");
    await openDialog({ heldFiles: 2, heldRoute: "available", heldAudience: "unknown" });
    expect(screen.getByTestId("disconnect-held-warning").textContent).toBe(copy.disconnectHeldWarning(2, "unknown"));
  });

  it.each([[null], [0], [10_001]])("count %s: no warning, and the paragraph gains the conditional clause", async (heldFiles) => {
    await openDialog({ heldFiles, heldRoute: "available" });
    expect(screen.queryByTestId("disconnect-held-warning")).not.toBeInTheDocument();
    expect(bodyText()).toBe(
      "This will unlink acme-co/web-platform from your account. Your workspace files will be removed, including any code changes your agent made that are not on your repository's main branch yet. You can reconnect a repository at any time.",
    );
  });
});
