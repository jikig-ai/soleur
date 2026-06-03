import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { LiveRepoBadge } from "@/components/dashboard/live-repo-badge";

// LiveRepoBadge is now INTERSTITIAL-ONLY: the "Working on: owner/repo" string
// moved into the workspace pill subtitle (org-switcher.tsx, fed by the shared
// useActiveRepo hook). This component renders the J5 revocation alert when the
// API reports fellBackToSolo, else nothing.

function mockActiveRepo(payload: Record<string, unknown>) {
  return vi.fn().mockResolvedValue({
    ok: true,
    json: () => Promise.resolve(payload),
  });
}

describe("LiveRepoBadge — J5 revocation interstitial", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("renders NOTHING on the happy path (repo name now lives in the pill, not here)", async () => {
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
    const { container } = render(<LiveRepoBadge />);
    // let the poll resolve, then assert no repo badge + no interstitial
    await vi.waitFor(() => {
      expect(screen.queryByTestId("revocation-interstitial")).toBeNull();
    });
    expect(screen.queryByTestId("live-repo-badge")).toBeNull();
    expect(container).toBeEmptyDOMElement();
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
    // the component no longer surfaces the repo name — that's the pill's job now
    expect(screen.queryByTestId("live-repo-badge")).toBeNull();
  });

  it("dismissing the interstitial hides it", async () => {
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
    fireEvent.click(
      screen.getByRole("button", { name: /dismiss notice/i }),
    );
    expect(interstitial).not.toBeInTheDocument();
  });

  it("renders nothing until the first poll resolves (no flash for solo users)", () => {
    vi.stubGlobal("fetch", vi.fn(() => new Promise(() => {})));
    const { container } = render(<LiveRepoBadge />);
    expect(container).toBeEmptyDOMElement();
  });
});
