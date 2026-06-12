import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { LiveRepoBadge } from "@/components/dashboard/live-repo-badge";
import { __resetActiveRepoCoalesceForTests } from "@/hooks/use-active-repo";

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
    __resetActiveRepoCoalesceForTests();
  });

  it("renders NOTHING on the happy path (repo name now lives in the pill, not here)", async () => {
    // Flag when the poll's body settles so the absence assertions below run
    // AFTER the state commit — a bare wait-on-absence passes on the first
    // tick (pre-poll) and proves nothing. Mirrors the regainCommitted
    // pattern in the re-arm test.
    let pollCommitted = false;
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: () =>
          Promise.resolve({
            workspaceId: "ws-1",
            repoUrl: "https://github.com/bob/team",
            repoName: "bob/team",
            repoStatus: "ready",
            fellBackToSolo: false,
          }).finally(() => {
            pollCommitted = true;
          }),
      }),
    );
    const { container } = render(<LiveRepoBadge />);
    // let the poll resolve, then assert no repo badge + no interstitial
    await vi.waitFor(() => expect(pollCommitted).toBe(true), {
      // #5113 — tolerate CPU starvation of the forked worker under
      // full-suite load (vi.waitFor default is 1000ms; see #4128).
      timeout: 10_000,
    });
    expect(screen.queryByTestId("revocation-interstitial")).toBeNull();
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

  it("re-arms the interstitial on a fresh fellBackToSolo transition after dismissal (J5 safety)", async () => {
    const solo = {
      workspaceId: "solo-1",
      repoUrl: "https://github.com/alice/solo",
      repoName: "alice/solo",
      repoStatus: "ready",
      fellBackToSolo: true,
    };
    const team = {
      workspaceId: "team-1",
      repoUrl: "https://github.com/team/repo",
      repoName: "team/repo",
      repoStatus: "ready",
      fellBackToSolo: false,
    };
    let regainCommitted = false;
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({ ok: true, json: () => Promise.resolve(solo) }) // mount: revoked
      .mockResolvedValueOnce({
        ok: true,
        // focus: regained access — flag when its body settles so the next
        // focus fires only AFTER this poll commits (no overlapping in-flight
        // fetches → deterministic ordering despite fetch coalescing).
        json: () =>
          Promise.resolve(team).finally(() => {
            regainCommitted = true;
          }),
      })
      .mockResolvedValueOnce({ ok: true, json: () => Promise.resolve(solo) }); // focus: revoked AGAIN
    vi.stubGlobal("fetch", fetchMock);

    render(<LiveRepoBadge />);
    await screen.findByTestId("revocation-interstitial");

    // user dismisses the notice — dismissal is an async state commit
    // (setDismissed(true) → re-render → return null), so poll until the node
    // is gone rather than asserting on an arbitrary tick (vacuous-absence-wait
    // class, #5234/#5113).
    fireEvent.click(screen.getByRole("button", { name: /dismiss notice/i }));
    await vi.waitFor(
      () => expect(screen.queryByTestId("revocation-interstitial")).toBeNull(),
      { timeout: 10_000 }, // #5113 — tolerate forked-worker CPU starvation
    );

    // regained access (fellBackToSolo:false) — stays hidden, no re-arm.
    // Reset the coalescing latch between simulated focus events: in production
    // distinct focus events are seconds apart so the in-flight latch is always
    // clear; here they fire back-to-back, so reset to force a fresh fetch.
    __resetActiveRepoCoalesceForTests();
    fireEvent.focus(window);
    await vi.waitFor(() => expect(regainCommitted).toBe(true), {
      timeout: 10_000, // #5113 — see first vi.waitFor in this file
    });
    expect(screen.queryByTestId("revocation-interstitial")).toBeNull();

    // a FRESH revocation (false→true transition) must re-surface the alert
    __resetActiveRepoCoalesceForTests();
    fireEvent.focus(window);
    await vi.waitFor(
      () =>
        expect(
          screen.getByTestId("revocation-interstitial"),
        ).toBeInTheDocument(),
      { timeout: 10_000 }, // #5113 — see first vi.waitFor in this file
    );
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
    // prove the interstitial was present before dismissal, then poll until the
    // async dismissal commit removes it — a bare synchronous check races the
    // re-render under load (vacuous-absence-wait class, #5234/#5113).
    await screen.findByTestId("revocation-interstitial");
    fireEvent.click(
      screen.getByRole("button", { name: /dismiss notice/i }),
    );
    await vi.waitFor(
      () => expect(screen.queryByTestId("revocation-interstitial")).toBeNull(),
      { timeout: 10_000 }, // #5113 — tolerate forked-worker CPU starvation
    );
  });

  it("renders nothing until the first poll resolves (no flash for solo users)", () => {
    vi.stubGlobal("fetch", vi.fn(() => new Promise(() => {})));
    const { container } = render(<LiveRepoBadge />);
    expect(container).toBeEmptyDOMElement();
  });
});
