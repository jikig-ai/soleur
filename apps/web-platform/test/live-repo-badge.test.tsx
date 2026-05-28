import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { LiveRepoBadge } from "@/components/dashboard/live-repo-badge";

function mockActiveRepo(payload: Record<string, unknown>) {
  return vi.fn().mockResolvedValue({
    ok: true,
    json: () => Promise.resolve(payload),
  });
}

describe("LiveRepoBadge", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('renders "Working on: owner/repo" for the active workspace (J6/J4)', async () => {
    vi.stubGlobal(
      "fetch",
      mockActiveRepo({
        workspaceId: "ws-1",
        repoUrl: "https://github.com/bob/team",
        repoName: "bob/team",
        repoStatus: "ready",
        fellBackToSolo: false,
      }),
    );
    render(<LiveRepoBadge />);
    const badge = await screen.findByTestId("live-repo-badge");
    expect(badge).toHaveTextContent("Working on:");
    expect(badge).toHaveTextContent("bob/team");
    // No revocation interstitial on the happy path.
    expect(screen.queryByTestId("revocation-interstitial")).toBeNull();
  });

  it("J5: renders the revocation interstitial when the API reports fellBackToSolo", async () => {
    vi.stubGlobal(
      "fetch",
      mockActiveRepo({
        workspaceId: "solo-1",
        repoUrl: "https://github.com/alice/solo",
        repoName: "alice/solo",
        repoStatus: "ready",
        fellBackToSolo: true,
      }),
    );
    render(<LiveRepoBadge />);
    const interstitial = await screen.findByTestId("revocation-interstitial");
    expect(interstitial).toHaveTextContent(/no longer have access/i);
    expect(interstitial).toHaveTextContent(/personal workspace/i);
    // Still shows the solo repo it fell back to.
    expect(await screen.findByTestId("live-repo-badge")).toHaveTextContent(
      "alice/solo",
    );
  });

  it("re-polls active-repo state on window focus (truthful-at-run-time, not realtime)", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve({
            workspaceId: "ws-1",
            repoUrl: "https://github.com/bob/team",
            repoName: "bob/team",
            repoStatus: "ready",
            fellBackToSolo: false,
          }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve({
            workspaceId: "solo-1",
            repoUrl: "https://github.com/alice/solo",
            repoName: "alice/solo",
            repoStatus: "ready",
            fellBackToSolo: false,
          }),
      });
    vi.stubGlobal("fetch", fetchMock);

    render(<LiveRepoBadge />);
    expect(await screen.findByTestId("live-repo-badge")).toHaveTextContent(
      "bob/team",
    );

    fireEvent.focus(window);

    await vi.waitFor(() => {
      expect(screen.getByTestId("live-repo-badge")).toHaveTextContent(
        "alice/solo",
      );
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock).toHaveBeenCalledWith("/api/workspace/active-repo");
  });

  it("renders nothing until the first poll resolves (no flash for solo users)", () => {
    vi.stubGlobal("fetch", vi.fn(() => new Promise(() => {})));
    const { container } = render(<LiveRepoBadge />);
    expect(container).toBeEmptyDOMElement();
  });
});
